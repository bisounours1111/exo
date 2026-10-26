# TP02 — Rapport : BuildKit avancé

Fichiers livrés :

| Fichier | Rôle |
|---------|------|
| `starter/shop-worker/Dockerfile` | Image finale `base` → `builder` → `test` → `runtime`, secret mount + cache mount par architecture |
| `starter/shop-worker/.dockerignore` | Liste blanche : `requirements*.txt`, `worker/`, `tests/` |
| `starter/shop-worker/.gitignore` | Exclut `pip.conf` (identifiants) |
| `starter/shop-worker/pip.conf` | **Local, non commité** : `index-url = https://pypi.org/simple` pour la formation |
| `starter/shop-worker/Dockerfile.leak` (+ `.dockerignore`) | Dockerfile d'origine, gardé pour la démonstration de l'étape 1 |
| `docker-bake.hcl` | Construction de la stack (API du TP01 + worker) |
| `starter/shop-worker/Dockerfile.offline` | Bonus B1 |
| `starter/shop-worker/Dockerfile.uv` | Bonus B3 |

Environnement de mesure : Docker Desktop 28.5.1 (Windows, WSL2, amd64), buildx 0.29.1, builder
`docker-container` BuildKit v0.33.1, registre `registry:2` du TP03 sur `localhost:5000`.

Le `pip.conf` n'est pas versionné : pour rejouer les commandes, le recréer avec :

```ini
[global]
index-url = https://pypi.org/simple
```

## 1. Prouver la fuite

```text
$ docker build --build-arg PIP_INDEX_URL=https://svc-ci:Tr3sS3cret@pypi.internal.example.com/simple -t worker:leak .
ERROR: Could not find a version that satisfies the requirement redis==5.0.8 (from versions: none)
```

Pour obtenir une image à inspecter, on rejoue le même build avec les mêmes identifiants sur l'index public
(PyPI ignore l'authentification) : `--build-arg PIP_INDEX_URL=https://svc-ci:Tr3sS3cret@pypi.org/simple`.

On recherche la valeur elle-même (`grep Tr3sS3cret`). Le secret est visible à au moins quatre endroits :

**a) L'historique de l'image** : BuildKit écrit les `ARG` utilisés par un `RUN` dans la commande enregistrée.

```text
$ docker history --no-trunc --format '{{.CreatedBy}}' worker:leak
CMD ["python" "-m" "worker.main"]
RUN |1 PIP_INDEX_URL=https://svc-ci:Tr3sS3cret@pypi.org/simple /bin/sh -c pip install -r requirements-dev.txt # buildkit
ARG PIP_INDEX_URL=https://svc-ci:Tr3sS3cret@pypi.org/simple
COPY . . # buildkit
```

**b) La configuration de l'image** (ce que `docker inspect` et le registre servent). `docker image inspect`
n'affiche pas le champ `history`, et `Config.Env` est propre puisque c'est un `ARG`, pas un `ENV`. Mais le
blob de configuration JSON poussé dans le registre contient l'historique ci-dessus :

```text
$ docker save worker:leak -o leak.tar && tar -xf leak.tar && grep -rl Tr3sS3cret blobs
blobs/sha256/a1da2a2771a8...: {"architecture":"amd64","config":{"Env":[...
```

N'importe qui peut donc le lire avec un simple pull, même sans lancer l'image. Le même contenu est
enregistré dans l'historique des builds du daemon (`docker buildx history inspect <id>` affiche
`BUILD ARG  PIP_INDEX_URL  https://svc-ci:Tr3sS3cret@pypi.org/simple`) et dans l'attestation de
provenance (voir B2 : les `build-arg` y sont listés en clair).

**c) Une couche intermédiaire** : `COPY . .` sans `.dockerignore` copie `pip.conf.example`, qui contient
le même identifiant, et copierait le `pip.conf` réel d'un développeur s'il était présent dans le dossier.
Supprimer le fichier dans un `RUN` suivant ne servirait à rien : il resterait dans la couche du `COPY`.

```text
$ docker run --rm worker:leak cat /app/pip.conf.example
index-url = https://svc-ci:Tr3sS3cret@pypi.internal.example.com/simple
```

**d) À noter** : les logs de build sont relativement protégés, pip masque le mot de passe
(`Looking in indexes: https://svc-ci:****@pypi.org/simple`). C'est ce qui donne une fausse impression de
sécurité : les logs CI sont propres, mais l'image ne l'est pas.

## 2. Secret mount

```dockerfile
RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf,required=true \
    --mount=type=cache,target=/root/.cache/pip,id=pip-${TARGETARCH},sharing=locked \
    python -m venv /opt/venv \
 && pip install -r requirements.txt
```

```text
$ docker build --secret id=pipconf,src=pip.conf -t worker:1.0 .
$ docker history --no-trunc worker:1.0 | grep -cE 'Tr3sS3cret|pypi|pip.conf|index-url'
0
$ docker run --rm worker:1.0 cat /etc/pip.conf
cat: /etc/pip.conf: No such file or directory
$ docker run --rm worker:1.0 ls -la /app
drwxr-xr-x 2 root root 4096 worker        # ni pip.conf, ni Dockerfile, ni tests/
$ docker run --rm worker:1.0 id
uid=10001(worker) gid=10001(worker) groups=10001(worker)
```

Le secret est monté en `tmpfs` le temps du seul `RUN` qui le demande, et n'est écrit dans aucune couche.
Il n'apparaît ni dans l'historique, ni dans la config, ni dans la provenance (qui ne garde que l'`id`, voir B2).

`required=true` fait échouer le build si le secret manque, au lieu de partir silencieusement sur l'index
public, ce qui serait une porte ouverte au *dependency confusion* :

```text
$ docker build --no-cache -t worker:nosecret .
ERROR: failed to solve: secret pipconf: not found
```

Attention : **le secret ne fait pas partie de la clé de cache**. Sans `--no-cache`, ce même build sans
secret a réussi, car l'étape `pip install` était déjà en cache. Changer de mot de passe ne déclenche donc
pas de réinstallation ; c'est voulu (la valeur ne fuit pas via le cache), mais il faut le savoir.

Autres durcissements de l'image finale :

- virtualenv `/opt/venv` construit dans `builder`, seul copié dans `runtime` : pytest et ruff restent dans
  l'étape `test` ;
- l'étape `test` exécute `ruff check` puis `pytest`, et `runtime` en dépend via `COPY --from=test /tmp/tests.ok` ;
- utilisateur `worker` (uid/gid 10001), code possédé par root ;
- base `python:3.12.16-slim-bookworm` épinglée par digest ;
- `HEALTHCHECK` sur le endpoint Prometheus `:9100/metrics` ;
- labels OCI alimentés par `VERSION` et `GIT_SHA` ;
- `hadolint` : aucune sortie.

```text
$ docker run -d --name w1 worker:1.0 && sleep 4 && docker inspect w1 --format '{{.State.Health.Status}}'
healthy
$ docker stop w1                    # 0,42 s, exit 0
{"level":"INFO","msg":"signal 15 reçu, arrêt en cours"}
{"level":"INFO","msg":"worker arrêté proprement"}
```

| | `worker:leak` | `worker:1.0` |
|---|---|---|
| Taille (`docker image ls`, containerd store) | 1,71 Go | 218 Mo |
| Taille compressée (registre) | 446 Mo | 53 Mo |
| Utilisateur | root | worker (10001) |
| Dépendances de dev (pytest, ruff) | oui | non |
| Secret dans l'image | oui (history, config, fichier) | non |

### Alternatives au secret fichier

- **`--mount=type=ssh`** : pour une dépendance dans un dépôt git privé
  (`git+ssh://git@github.com/shop/lib.git` dans `requirements.txt`). On lance le build avec `--ssh default`
  ; BuildKit relaie l'agent SSH de l'hôte pendant le `RUN`. La clé privée ne quitte jamais l'hôte et
  n'est même pas copiée dans le conteneur de build.
- **`--secret id=TOKEN,env=TOKEN`** côté CLI, `--mount=type=secret,id=TOKEN,env=TOKEN` côté Dockerfile
  (syntaxe 1.10+) : le secret est exposé comme variable d'environnement du seul `RUN`. Pratique en CI où
  le token est déjà dans une variable masquée, et pour les outils qui ne lisent pas de fichier de
  configuration. C'est ce qu'utilise la variante `uv` (B3), car uv ignore `pip.conf`.

## 3. Cache mount

Mesures sur le builder `shop` (`docker-container`), plateforme amd64 :

| # | Scénario | Durée totale | Téléchargements pip |
|---|----------|--------------|---------------------|
| 1 | Build à froid | 23,0 s | 16 `Downloading` |
| 2 | Rebuild sans changement | 6,6 s | 0 (tout `CACHED`) |
| 3 | `docker buildx prune -f` puis `requests==2.32.3` ajouté | 19,0 s | **26 `Downloading`** |
| 4 | `requests==2.32.3` ajouté, sans prune | 11,8 s | 0, 26 `Using cached` |

Durée de l'étape `pip install`, avec la couche invalidée par une modification de `requirements.txt` :

| Scénario | `builder` (prod) | `test` (dev) | pip |
|----------|------------------|--------------|-----|
| Cache mount chaud | 4,0 s | 1,8 s | 26 `Using cached` |
| `buildx prune --filter type=regular` (couches seules) | 4,0 s | — | 26 `Using cached` |
| `buildx prune -f` (tout) | 6,9 s | 4,5 s | 26 `Downloading` |
| `--no-cache` | 6,1 s | 3,8 s | 26 `Downloading` |

**Cache de couches** : BuildKit associe à chaque instruction une clé calculée à partir de l'instruction,
des fichiers copiés et de la couche parente. Si la clé est connue, le résultat (la couche) est réutilisé
tel quel et l'étape n'est pas exécutée : c'est tout ou rien. Dès que `requirements.txt` change, la clé de
`pip install` change, et sans autre mécanisme tout est retéléchargé.

**Cache mount** : un répertoire persistant du builder, monté pendant l'exécution d'un `RUN`. Il ne fait
pas partie de l'image et n'entre pas dans la clé de cache. Quand l'étape doit être rejouée, pip retrouve
dans `/root/.cache/pip` les wheels déjà téléchargées : seul le delta (`requests` et ses dépendances) est
récupéré. Il complète le cache de couches, il ne le remplace pas.

**Vider les caches** : sur BuildKit v0.33, `docker buildx prune -f` vide le cache de couches et les
cache mounts (scénario 3). `docker buildx prune --filter type=regular` ne vide que le cache de couches.
`--no-cache` rejoue toutes les étapes et garantit un build depuis les sources.

## 4. Multi-architecture

Émulation arm64 (QEMU) installée dans la VM Docker, puis builder dédié :

```bash
docker run --privileged --rm tonistiigi/binfmt:qemu-v9.2.2 --install arm64
docker buildx create --name shop --driver docker-container --driver-opt network=host
docker buildx inspect shop --bootstrap      # Platforms: linux/amd64, ..., linux/arm64, linux/386
```

`network=host` permet au conteneur BuildKit de joindre le registre `localhost:5000` de l'hôte. Le builder
n'est pas mis par défaut (`--use` absent) : on le passe avec `--builder shop` ou `BUILDX_BUILDER=shop`.

```text
$ docker buildx build --builder shop --platform linux/amd64,linux/arm64 --secret id=pipconf,src=pip.conf \
    -t localhost:5000/shop-worker:1.0 --push .                                   # 65 s
$ docker buildx imagetools inspect localhost:5000/shop-worker:1.0
MediaType: application/vnd.oci.image.index.v1+json
Digest:    sha256:9020839c7449ac9c327d805a4cc9112cf126740fb92b04f4b1e541221a3a8284
Manifests:
  Name: ...@sha256:eb152ded...   Platform: linux/amd64
  Name: ...@sha256:ae563106...   Platform: linux/arm64
  Name: ...@sha256:eb0c7ec2...   Platform: unknown/unknown   vnd.docker.reference.type: attestation-manifest
  Name: ...@sha256:6a1a0840...   Platform: unknown/unknown   vnd.docker.reference.type: attestation-manifest
$ docker run --rm --platform linux/amd64 localhost:5000/shop-worker:1.0 python -c "import platform, psycopg2; print(platform.machine(), psycopg2.__version__)"
x86_64 2.9.9 (dt dec pq3 ext lo64)
$ docker run --rm --platform linux/arm64 localhost:5000/shop-worker:1.0 python -c "..."
aarch64 2.9.9 (dt dec pq3 ext lo64)
```

| Étape | amd64 (natif) | arm64 (QEMU) | Rapport |
|-------|---------------|--------------|---------|
| `builder` : venv + `pip install` | 4,0 s | 33,5 s | ×8 |
| `test` : `pip install -r requirements-dev.txt` | 2,8 s | 14,3 s | ×5 |
| `test` : ruff + pytest | 0,6 s | 5,5 s | ×9 |

**Pourquoi `--push` ou `-o` est obligatoire** : le résultat d'un build multi-plateforme est un *index*
qui référence plusieurs images. L'image store classique de Docker (`overlay2`) ne sait stocker qu'une
image par tag et par plateforme, donc `--load` refuse. Il faut exporter l'ensemble vers un registre
(`--push`) ou dans une archive OCI (`-o type=oci,dest=worker.tar`). Le containerd image store sait stocker
des index ; en CI on pousse de toute façon.

**Contenu du manifest list** (index OCI) : une liste d'entrées `{mediaType, digest, size, platform}`.
Il y en a une par image (linux/amd64, linux/arm64), avec chacune son propre manifeste, sa config et ses
couches, plus ici une entrée `unknown/unknown` par plateforme : le manifeste d'attestation (provenance),
lié à son image par l'annotation `vnd.docker.reference.digest`. Au `docker pull`, le client lit l'index et
choisit l'entrée correspondant à son architecture : un seul tag pour toutes les machines.

**`TARGETARCH` pour isoler le cache pip** : BuildKit définit automatiquement `TARGETPLATFORM`, `TARGETOS`,
`TARGETARCH` (`amd64`, `arm64`) pour chaque plateforme ciblée. Après `ARG TARGETARCH` dans l'étape, on
l'utilise dans l'`id` du cache mount : `id=pip-${TARGETARCH}`. Les logs le confirment (`id=pip-amd64` et
`id=pip-arm64`). Sans ça, les deux builds parallèles partageraient le même répertoire : risque de
corruption en écriture concurrente, et une wheel `manylinux_x86_64` ne sert à rien pour arm64.
`sharing=locked` sérialise en plus deux builds de la même architecture.

**Pourquoi arm64 est plus lent sur amd64** : chaque instruction arm64 de chaque `RUN` (python, pip, pytest)
est traduite à la volée par QEMU en mode utilisateur, d'où un facteur 5 à 9 mesuré ici, et bien plus pour
de la compilation (wheels sans binaire, `npm` avec modules natifs). Alternatives :

- **builders natifs** : un seul builder avec un nœud par architecture,
  `docker buildx create --name shop --platform linux/amd64 ssh://runner-amd64` puis
  `docker buildx create --append --name shop --platform linux/arm64 ssh://runner-graviton`. BuildKit
  envoie chaque plateforme sur le nœud natif et assemble l'index (Docker Build Cloud fait la même chose
  en service managé) ;
- **compilation croisée** : `FROM --platform=$BUILDPLATFORM` pour les étapes de build, qui s'exécutent
  alors nativement et produisent des artefacts pour `$TARGETPLATFORM` (Go `GOARCH`,
  `pip download --platform manylinux2014_aarch64 --only-binary=:all:`). Seule l'étape finale est par
  plateforme et elle ne contient idéalement aucun `RUN`.

## 5. Cache distant

```bash
docker buildx build --builder shop --platform linux/amd64,linux/arm64 --secret id=pipconf,src=pip.conf \
  --cache-to type=registry,ref=localhost:5000/cache:worker-max,mode=max \
  --cache-from type=registry,ref=localhost:5000/cache:worker-max \
  -t localhost:5000/shop-worker:1.0 --push .
```

Chaque mesure d'import est faite sur un builder **neuf** (`buildx rm` + `create`), donc sans cache local,
comme un nouveau runner CI :

| Scénario | `mode=max` | `mode=min` |
|----------|-----------|-----------|
| Export (builder neuf, build complet) | 70 s | 77 s |
| Import, aucun changement | 7 s | 16 s |
| Import, `worker/main.py` modifié | **18 s**, `pip install` `CACHED` | **70 s**, `pip install` rejoué (3,7 s amd64, 33,9 s arm64) |

- **`mode=min`** (défaut) : n'exporte que les couches de l'image finale. Tant que rien ne change, c'est
  suffisant. Mais les étapes intermédiaires (`builder`, `test`) ne sont pas dans le cache : dès qu'un
  fichier source change, `pip install` est rejoué, sous QEMU qui plus est.
- **`mode=max`** : exporte les couches de **toutes** les étapes, y compris celles qui ne finissent pas dans
  l'image. Cache plus gros et export plus long, mais c'est celui qu'il faut pour du multi-stage en CI.
- Le cache est poussé dans un tag dédié (`localhost:5000/cache:worker-max`), séparé de l'image, et ne
  contient aucun secret puisque celui-ci n'est dans aucune couche.

Variantes CI :

- **`type=gha`** (GitHub Actions) : `--cache-to type=gha,mode=max,scope=worker --cache-from type=gha,scope=worker`.
  Utilise le cache GitHub Actions (10 Go par dépôt, éviction LRU) ; `scope` sépare les images.
  Demande l'action `docker/setup-buildx-action`, qui expose le jeton d'API du cache.
- **`type=s3`** : `--cache-to type=s3,region=eu-west-3,bucket=shop-buildcache,name=worker,mode=max`.
  Pratique pour des runners auto-hébergés ou pour partager le cache entre plusieurs CI. Les credentials
  AWS viennent de l'environnement du builder.

## 6. `docker buildx bake`

`docker-bake.hcl` (dans `part2/tp02-buildkit-avance/`, à lancer depuis ce dossier) :

- variables `REGISTRY` (défaut `localhost:5000`), `VERSION`, `GIT_SHA` surchargeables par variables
  d'environnement ;
- `_common` (abstraite) : plateformes amd64 + arm64, labels OCI, `cache-from` sur le cache de toute la
  stack ;
- `api` (contexte `../tp01-optimisation-image/starter/shopapi`) et `worker`, chacune avec son `cache-to`.
  Une même référence de cache écrite par deux cibles en parallèle serait écrasée, d'où une référence par
  image ;
- `worker` passe le secret : `secret = ["id=pipconf,src=starter/shop-worker/pip.conf"]` ;
- `worker-test` hérite de `worker`, cible l'étape `test`, `output = ["type=cacheonly"]` : on exécute les
  tests sur les deux architectures sans produire ni pousser d'image ;
- groupe `default` = `api` + `worker`.

```text
$ export BUILDX_BUILDER=shop
$ docker buildx bake --print                     # plan JSON résolu, sans rien construire
$ VERSION=1.0 GIT_SHA=$(git rev-parse --short HEAD) docker buildx bake worker-test      # 8 s
#28 0.216 All checks passed!          (amd64)
#28 0.711 2 passed in 0.09s
#27 0.762 All checks passed!          (arm64)
#27 6.505 2 passed in 0.87s
$ VERSION=1.0 docker buildx bake --set '*.platform=linux/amd64' --load                  # 48 s
$ docker image ls
localhost:5000/shopapi:1.0       211MB
localhost:5000/shop-worker:1.0   218MB
$ VERSION=1.0 GIT_SHA=$(git rev-parse --short HEAD) docker buildx bake --push           # 56 s, 2 images × 2 archis
$ VERSION=1.0 GIT_SHA=$(git rev-parse --short HEAD) docker buildx bake --push           # 5 s, 47 étapes CACHED
```

Au premier lancement, les lignes `ERROR: failed to configure registry cache importer: ... not found`
sont normales : le cache n'existe pas encore dans le registre. BuildKit les ignore et le build réussit.

Sous Git Bash, mettre `'*.platform=linux/amd64'` entre quotes. Sinon le shell développe `*` avec les noms
de fichiers du dossier.

## Bonus

### B1 — build sans Internet (`Dockerfile.offline`)

Le principe : une étape `prefetch`, la seule qui a besoin du réseau, fait `pip download` dans un cache mount
`/wheels` (un par architecture). Toutes les autres étapes portent `RUN --network=none` et installent avec
`pip install --no-index --find-links /wheels`. `builder` ne dépend pas de `prefetch`, donc un build normal
ne l'exécute pas.

```text
$ docker buildx build -f Dockerfile.offline --network=none -t worker:offline --load .     # cache vide
ERROR: Could not find a version that satisfies the requirement redis==5.0.8 (from versions: none)

$ docker buildx build -f Dockerfile.offline --secret id=pipconf,src=pip.conf --target prefetch .   # en ligne, une fois

$ docker buildx build -f Dockerfile.offline --network=none -t worker:offline --load .     # hors ligne
Successfully installed prometheus-client-0.20.0 psycopg2-binary-2.9.9 redis-5.0.8
Successfully installed iniconfig-2.3.1 packaging-26.3 pluggy-1.7.0 pytest-8.3.2 ruff-0.6.3
2 passed in 0.07s
$ docker run --rm worker:offline python -c "import redis, psycopg2, prometheus_client; print('deps ok')"
deps ok
```

Pip seul ne sait pas installer hors ligne depuis son cache HTTP (il veut toujours interroger l'index) :
c'est pour ça qu'on télécharge les wheels avec `pip download` et qu'on installe avec `--no-index`.

Contextes d'entreprise : zones **air-gapped** (défense, santé, OIV, industrie) où les runners n'ont pas
Internet ; **supply chain** maîtrisée (on prouve que le build n'a rien téléchargé d'autre que ce qui a été
pré-approuvé et scanné) ; **builds hermétiques et reproductibles** (même entrée, même sortie, sans
dépendance à la disponibilité de PyPI) ; et protection contre un `setup.py` ou un test malveillant qui
voudrait exfiltrer des données pendant le build.

### B2 — attestations de provenance et SBOM

```bash
docker buildx build --builder shop --platform linux/amd64,linux/arm64 --secret id=pipconf,src=pip.conf \
  --provenance=mode=max --sbom=true -t localhost:5000/shop-worker:1.0-attest --push .
docker buildx imagetools inspect localhost:5000/shop-worker:1.0-attest --format '{{json .Provenance}}'
docker buildx imagetools inspect localhost:5000/shop-worker:1.0-attest --format '{{json .SBOM}}'
```

Extrait de la provenance SLSA v1 (linux/amd64) :

```text
buildType: https://github.com/moby/buildkit/blob/master/docs/attestations/slsa-definitions.md
externalParameters.request.args: {'build-arg:GIT_SHA': 'cd7bc56', 'build-arg:VERSION': '1.0',
                                  'source': 'docker/dockerfile:1.7'}
externalParameters.request.secrets: [{'id': 'pipconf'}]          # l'id seulement, jamais la valeur
resolvedDependencies:
  pkg:docker/python@3.12.16-slim-bookworm?digest=sha256:e697c818...  # base épinglée et tracée
  pkg:docker/docker/dockerfile@1.7
  pkg:docker/docker/buildkit-syft-scanner@stable-1
```

SBOM SPDX généré par Syft : 124 paquets, dont les paquets Debian de la base et les 4 paquets Python
`pip==25.0.1`, `prometheus-client==0.20.0`, `psycopg2-binary==2.9.9`, `redis==5.0.8`. pytest et ruff
n'y sont pas, ce qui confirme qu'ils ne sont pas dans l'image finale.

Lien avec l'étape 1 et le TP03 : la provenance enregistre **tous les build-args en clair**. Un identifiant
passé en `ARG` fuit donc aussi par ce canal, alors que le secret mount n'y laisse que son `id`. Côté TP03,
ces attestations sont exactement ce qu'un *release gate* vérifie : provenance (qui a construit, à partir de
quoi) et SBOM (à scanner pour les CVE, à signer avec cosign).

### B3 — uv au lieu de pip (`Dockerfile.uv`)

Changements :

- binaire `uv` copié depuis `ghcr.io/astral-sh/uv:0.9.5` (épinglé par digest), uniquement dans `builder` ;
- cache mount `/root/.cache/uv` (id `uv-${TARGETARCH}`) et `UV_LINK_MODE=copy`, car le cache et
  `/opt/venv` sont sur des systèmes de fichiers différents et les liens physiques sont impossibles ;
- uv ne lit pas `pip.conf` : l'index est passé en secret exposé en variable d'environnement,
  `--mount=type=secret,id=uv_index,env=UV_INDEX_URL` (syntaxe 1.10),
  `docker build --secret id=uv_index,env=UV_INDEX_URL`.

Durée des étapes d'installation, couche invalidée, deux séries :

| | `builder` série 1 | `builder` série 2 | `test` série 1 | `test` série 2 |
|---|---|---|---|---|
| pip, cache mount vide | 5,4 s | 5,1 s | 3,9 s | 3,8 s |
| pip, cache mount chaud | 4,6 s | 3,6 s | 2,9 s | 1,8 s |
| uv, cache mount vide | 1,4 s | 0,7 s | < 1 s | 1,0 s |
| uv, cache mount chaud | 0,8 s | 0,2 s | 0,6 s | 0,4 s |

uv est 4 à 18 fois plus rapide que pip : résolution et téléchargements en parallèle, et installation depuis
le cache par simple copie, sans retraitement des wheels. Même à froid, uv fait mieux que pip à chaud.
L'image `worker:uv` fait 198 Mo contre 218 Mo, car le virtualenv créé par uv ne contient pas pip.

## Nettoyage

```bash
docker compose -p tp02-registry -f ../tp03-registry-supply-chain/starter/registry/compose.yml down
docker buildx rm shop
docker run --privileged --rm tonistiigi/binfmt:qemu-v9.2.2 --uninstall qemu-aarch64   # ou redémarrer Docker Desktop
```
