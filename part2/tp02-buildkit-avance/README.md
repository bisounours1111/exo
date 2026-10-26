# TP02 — BuildKit avancé : cache, secrets, multi-architecture, bake

**Niveau** : avancé · **Travail** : individuel ou binôme

## Contexte

Le second composant de la stack *Shop SAS*, `shop-worker` (Python), consomme la file de commandes Redis.
Son Dockerfile a trois défauts bloquants pour la CI d'entreprise :

1. le **registre PyPI interne** exige une authentification et l'équipe passe les identifiants en `ARG`.
   L'audit a montré qu'ils sont lisibles avec `docker history` ;
2. la CI tourne sur des runners **amd64** mais la prod migre sur des nœuds **arm64** (Graviton) et les
   développeurs ont des Mac M-series : il faut des images **multi-architecture** ;
3. chaque build re-télécharge toutes les dépendances : la CI veut un **cache partagé** entre runners.

Enfin, l'équipe veut une **commande unique** pour construire toute la stack (API + worker) : `docker buildx bake`.

## Étapes

### 1. Prouver la fuite

```bash
cd starter/shop-worker
docker build --build-arg PIP_INDEX_URL=https://svc-ci:Tr3sS3cret@pypi.internal.example.com/simple -t worker:leak . || true
docker history --no-trunc worker:leak | grep -i secret
```

L'image ne build pas (le registre interne n'existe pas), mais même si elle buildait, où le secret serait-il
visible ? Trois endroits au moins (history, `docker inspect`, couche intermédiaire). Documentez.

### 2. Secret mount

Réécrivez le Dockerfile en multi-stage (`builder` → `test` → `runtime`) avec :

- `RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf pip install ...`
- un fichier local `pip.conf` (gitignored) pointant pour la formation vers `https://pypi.org/simple` ;
- build : `docker build --secret id=pipconf,src=pip.conf -t worker:1.0 .`

Vérifiez : `docker history worker:1.0` et `docker run --rm worker:1.0 cat /etc/pip.conf` → le secret
n'existe nulle part. Discutez des alternatives : `--mount=type=ssh` pour les dépendances git privées,
variables d'environnement `--secret id=TOKEN,env=TOKEN`.

### 3. Cache mount

Ajoutez `--mount=type=cache,target=/root/.cache/pip`. Mesurez :

```bash
time docker build --secret id=pipconf,src=pip.conf -t worker:1.0 .
docker builder prune -f                     # vide le cache de couches, PAS le cache mount
echo "requests==2.32.3" >> requirements.txt
time docker build --secret id=pipconf,src=pip.conf -t worker:1.0 .
```

Expliquez la différence entre cache de couches et cache mount. Que se passe-t-il avec `--no-cache` ?

### 4. Multi-architecture

```bash
docker buildx create --name shop --driver docker-container --use
docker buildx inspect --bootstrap
docker buildx build --platform linux/amd64,linux/arm64 \
  --secret id=pipconf,src=pip.conf -t localhost:5000/shop-worker:1.0 --push .     # registre du TP03, ou -o type=oci,dest=worker.tar
docker buildx imagetools inspect localhost:5000/shop-worker:1.0
```

Questions : pourquoi `--push` ou `-o` est-il obligatoire avec plusieurs plateformes ? Que contient le
*manifest list* ? Comment utilisez-vous `TARGETARCH` dans le Dockerfile pour isoler le cache pip par
architecture ? Pourquoi le build arm64 est-il plus lent sur une machine amd64 (QEMU) et quelle est
l'alternative (builders natifs distants, `--platform` par nœud du builder) ?

### 5. Cache distant

```bash
docker buildx build --cache-to type=registry,ref=localhost:5000/cache:worker,mode=max \
                    --cache-from type=registry,ref=localhost:5000/cache:worker ...
```

Variante CI : `type=gha` (GitHub Actions), `type=s3`. Différence `mode=min` / `mode=max` ?

### 6. `docker buildx bake`

Écrivez `docker-bake.hcl` avec un groupe `default` (api du TP01 + worker), une cible abstraite `_common`
(labels, plateformes, cache), des variables `VERSION`, `GIT_SHA`, `REGISTRY`, et une cible `worker-test`
qui exécute uniquement l'étape `test`.

```bash
docker buildx bake --print                 # plan sans builder
VERSION=1.0 GIT_SHA=$(git rev-parse --short HEAD) docker buildx bake worker-test
VERSION=1.0 docker buildx bake --set *.platform=linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') --load
```

> **Livrables** : Dockerfile final, `docker-bake.hcl`, un `RAPPORT.md` avec les mesures des étapes 3 et 4
> et les réponses aux questions.

## Bonus

- **B1** : build de l'image **sans accès Internet** au moment du build (`--network=none`) grâce au cache
  mount pré-rempli. Dans quel contexte d'entreprise est-ce utile ?
- **B2** : ajoutez les attestations `--provenance=true --sbom=true` et inspectez-les avec
  `docker buildx imagetools inspect --format '{{json .Provenance}}'` (fait le lien avec le TP03).
- **B3** : `uv` au lieu de `pip` : adaptez le cache mount et comparez les temps.


