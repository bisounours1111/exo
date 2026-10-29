# TP01 — Rapport : image `shopapi` conforme

Fichiers livrés dans `starter/shopapi/` :

| Fichier | Rôle |
|---------|------|
| `Dockerfile` | Image finale multi-stage `base` → `deps` → `test` → `runtime` |
| `.dockerignore` | Liste blanche : seuls `package.json`, `package-lock.json`, `src/` et `test/` entrent dans le contexte |
| `package-lock.json` | Généré avec `npm install --package-lock-only` dans `node:20.20.2-alpine3.23`, requis par `npm ci` |
| `Dockerfile.legacy` | Copie du Dockerfile d'origine, conservée pour les mesures avant/après |
| `Dockerfile.legacy.dockerignore` | Garde au build legacy son contexte d'origine (BuildKit lit `<Dockerfile>.dockerignore` en priorité) |
| `Dockerfile.distroless` | Bonus B1 |

Le code applicatif (`src/`, `test/`, `package.json`) n'a pas été modifié.

## Commandes de vérification

```bash
cd starter/shopapi
docker run --rm -i hadolint/hadolint:v2.15.1 < Dockerfile          # aucune sortie
docker build --target test -t shopapi:test .                       # lint + tests
docker build --build-arg APP_VERSION=1.4.2 --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t shopapi:1.4.2 .
docker image ls shopapi
docker run --rm shopapi:1.4.2 id
docker run --rm shopapi:1.4.2 ls -la /app
docker inspect shopapi:1.4.2 --format '{{json .Config.Labels}}'
docker run -d --name api -p 3000:3000 shopapi:1.4.2
sleep 6 && docker inspect api --format '{{.State.Health.Status}}'
curl -s localhost:3000/products
time docker stop api
```

Sous Git Bash (Windows), préfixer par `MSYS_NO_PATHCONV=1` les commandes qui passent un chemin absolu au
conteneur (`ls /app`), sinon Git Bash le convertit en chemin Windows. Si le port 3000 est déjà pris sur le
poste, utiliser `-p 3001:3000`.

## Résultats de conformité

```text
$ hadolint Dockerfile
(aucune sortie, exit 0)

$ docker run --rm shopapi:1.4.2 id
uid=1000(node) gid=1000(node) groups=1000(node)

$ docker run --rm shopapi:1.4.2 ls -la /app
drwxr-xr-x  114 root     root          4096 node_modules
-rwxr-xr-x    1 root     root           569 package.json
drwxr-xr-x    2 root     root          4096 src
                                     # ni .env, ni *.sql, ni Dockerfile, ni test/
$ docker run --rm shopapi:1.4.2 touch /app/x
touch: /app/x: Permission denied     # le code appartient à root, node ne peut que le lire

$ docker inspect shopapi:1.4.2 --format '{{json .Config.Labels}}'
{"org.opencontainers.image.base.name":"docker.io/library/node:20.20.2-alpine3.23",
 "org.opencontainers.image.description":"API catalogue produits Shop SAS",
 "org.opencontainers.image.revision":"cd7bc56",
 "org.opencontainers.image.source":"https://github.com/bisounours1111/exo",
 "org.opencontainers.image.title":"shopapi",
 "org.opencontainers.image.vendor":"Shop SAS",
 "org.opencontainers.image.version":"1.4.2"}

$ docker inspect api --format '{{.State.Health.Status}}'
healthy
$ curl -s localhost:3000/products
[{"id":1,"name":"Clavier mécanique","price":89.9,"stock":12},{"id":2,"name":"Écran 27\"","price":249,"stock":4},{"id":3,"name":"Souris sans fil","price":29.5,"stock":40}]
$ curl -s localhost:3000/
{"service":"shopapi","version":"1.4.2"}

$ docker top api
UID    PID     PPID    CMD
1000   43471   43448   node src/server.js           # un seul processus, PID 1 dans le conteneur

$ docker stop api        # 0,41 s, exit code 0
$ docker logs api | tail -1
{"level":30,...,"pid":1,"signal":"SIGTERM","msg":"arrêt demandé"}
```

Un test cassé bloque bien l'image finale (fichier `test/zz-fail.test.js` ajouté puis supprimé) :

```text
$ docker build -t shopapi:should-fail .
ERROR: failed to solve: process "/bin/sh -c npm run lint  && npm test  && touch /tmp/tests.ok" did not complete successfully: exit code: 1
```

## Tableau avant / après

| Critère | `shopapi:legacy` | `shopapi:1.4.2` |
|---------|------------------|-----------------|
| Base | `ubuntu:22.04` + NodeSource | `node:20.20.2-alpine3.23@sha256:fb4c…` |
| Taille affichée par `docker image ls` | 1,09 Go | 211 Mo |
| Taille décompressée (`du -sxh /` dans le conteneur) | 747 Mo | 153 Mo |
| Taille compressée, celle stockée dans le registre (`docker image inspect --format '{{.Size}}'`) | 286 Mo | 51 Mo |
| Nombre de couches | 9 (1 de base + 8) | 9 (4 de base + 5 propres) |
| Rebuild après `echo "// commentaire" >> src/server.js` | 10,4 s, `npm install` rejoué | 4,4 s, `npm ci` `CACHED` (les tests sont rejoués, c'est voulu) |
| Utilisateur | `root` (uid 0) | `node` (uid 1000) |
| Arrêt (`docker stop`) | 9,6 s, exit 137 (SIGKILL) | 0,41 s, exit 0 |
| Secrets dans l'image | `ENV DATABASE_URL` + `.env` (clé AWS) | aucun |
| Fichiers inutiles | `.env`, dump SQL, `Dockerfile`, `.gitignore`, devDependencies, `nodemon` global | aucun |
| `HEALTHCHECK` | absent | `wget` sur `/health`, `healthy` au contrôle à 6 s |
| Labels OCI | `version=22.04` hérité d'Ubuntu (faux) | version, révision, source, titre, base |
| hadolint | 6 warnings, 4 infos | aucune sortie |

**Taille** : le système de fichiers de l'image fait 153 Mo et le registre en stocke 51 Mo. Avec le
*containerd image store* de Docker Desktop, `docker image ls` additionne les couches décompressées et les
blobs compressés, d'où les 211 Mo affichés.

## Pourquoi l'arrêt passe de 10 s à 0,4 s

Avec `CMD npm start` (forme shell), Docker lance `/bin/sh -c "npm start"` : **PID 1 est `sh`**. Le noyau
n'applique aucun comportement par défaut aux signaux reçus par le PID 1 d'un namespace : un `SIGTERM` sans
handler est simplement ignoré, et `sh` ne le relaie pas à ses enfants (`npm`, puis encore un `sh`, puis
`node`). Le handler `shutdown()` de `server.js` ne s'exécute jamais. `docker stop` attend son délai de
10 s, puis envoie `SIGKILL` : d'où l'exit code 137 (128 + 9), des requêtes coupées net et des connexions
PostgreSQL et Redis jamais fermées.

Avec `CMD ["node", "src/server.js"]` (forme exec), **`node` est le PID 1** et reçoit `SIGTERM` directement.
Comme le code installe un handler, le signal est traité : `server.close()` termine les requêtes en cours,
ferme les pools, puis `process.exit(0)`. Le log `"signal":"SIGTERM","msg":"arrêt demandé"` le prouve.

Si l'application n'avait pas de handler, il faudrait un init minimal (`docker run --init`, ou `tini` en
`ENTRYPOINT`) pour relayer les signaux et récupérer les processus zombies.

## Choix techniques

- **`node:20-alpine` plutôt que `slim`** : 153 Mo contre environ 200 Mo, et aucune dépendance native dans
  `package.json` (`pg` est en pur JavaScript), donc pas de risque lié à musl.
- **Tag exact + digest** : `node:20.20.2-alpine3.23` dit ce qu'on attend, le digest garantit qu'on
  l'obtient même si le tag est réécrit.
- **`npm ci --omit=dev`** dans `deps`, et `npm ci` complet uniquement dans `test` : eslint et nodemon ne
  quittent jamais l'étape de test.
- **Cache mount `/root/.npm`** sur les deux `npm ci` (voir B2).
- **`COPY --from=test /tmp/tests.ok`** : BuildKit ne construit que les étapes dont la cible a besoin. Sans
  cette ligne, `docker build` sans `--target` ignorerait l'étape `test`. Le fichier vide rend les tests
  obligatoires pour produire l'image.
- **Fichiers possédés par root, `USER 1000:1000`** : le processus ne peut pas réécrire son propre code. L'UID
  est numérique pour que `runAsNonRoot` de Kubernetes puisse le vérifier (hadolint DL3066).
- **`ARG`/`LABEL` en fin de Dockerfile** : changer `GIT_SHA` ne crée que des couches de métadonnées et
  n'invalide ni `npm ci` ni `COPY src/`.
- **`HEALTHCHECK ... --start-interval=1s`** : sonde rapide pendant la phase de démarrage, puis toutes les
  10 s. Cette option demande Docker Engine ≥ 25 et hadolint ≥ 2.13.
- **Runtime sans gestionnaire de paquets** : npm, npx, corepack et yarn sont retirés de l'étape `runtime`,
  et OpenSSL est mis à jour en `3.5.9-r0`. Trivy ne relève aucune vulnérabilité HIGH/CRITICAL
  corrigeable.

## Bonus

### B1 — distroless (`Dockerfile.distroless`)

```text
$ docker build -f Dockerfile.distroless --build-arg APP_VERSION=1.4.2 --build-arg GIT_SHA=cd7bc56 -t shopapi:1.4.2-distroless .
$ docker image ls shopapi:1.4.2-distroless        # 188 Mo affichés, 47 Mo compressés
$ docker inspect apid --format '{{.State.Health.Status}}'
healthy
$ docker exec apid sh -c id
exec: "sh": executable file not found in $PATH
$ docker stop apid                                # 0,48 s, exit 0
```

- **Gain** : pas de shell, pas de `apk`, pas de `wget`, pas de busybox. Un attaquant qui obtient une
  exécution de code ne dispose que de `node`. Moins de paquets signifie aussi moins de CVE remontées par
  les scanners. L'utilisateur `nonroot` (uid 65532) est fourni par l'image.
- **Coût** : impossible de faire `docker exec ... sh` pour déboguer. Il faut passer par
  `docker debug`, un conteneur éphémère (`kubectl debug --image=busybox --target=...`), ou le tag `:debug`
  de distroless qui ajoute busybox. Les dépendances doivent être installées sur une base glibc
  (`node:20-bookworm-slim`), pas sur alpine (musl), sinon un module natif casserait au runtime.
- **Healthcheck sans `wget`** : on utilise le seul binaire disponible, node, avec un client HTTP en une
  ligne en forme exec :
  `["/nodejs/bin/node", "-e", "require('http').get('http://127.0.0.1:3000/health', (r) => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"]`.
  Autre option : un petit binaire statique de healthcheck copié depuis une étape de build. En Kubernetes,
  on n'en a pas besoin : les sondes `httpGet` sont exécutées par le kubelet, hors du conteneur.

### B2 — `--no-cache` vs cache mount `/root/.npm`

Mesures sur un builder dédié (`docker buildx create --name tp01-bench --driver docker-container`) pour
pouvoir vider uniquement ses caches. Durée de l'étape `npm ci --omit=dev`, la couche étant invalidée par un
`--build-arg` différent à chaque build :

| Scénario | Run 1 | Run 2 | Run 3 | Run 4 |
|----------|-------|-------|-------|-------|
| Cache mount vidé avant chaque build (`buildx prune --filter type=exec.cachemount`) | 2,3 s | 2,3 s | 2,3 s | 2,2 s |
| Cache mount conservé | 1,3 s | 1,5 s | 1,4 s | 1,3 s |
| Cache de couches valide (rien n'a changé) | `CACHED` | | | |

- Le cache mount fait gagner environ 40 % sur `npm ci` : les tarballs sont lus depuis `/root/.npm` au lieu
  d'être téléchargés. Ici le réseau est rapide et les dépendances pèsent 15 Mo (5 Mo de cache npm) ; en
  CI derrière un proxy, ou avec des centaines de dépendances, l'écart se compte en minutes.
- Le cache mount **n'est pas une couche** : il n'apparaît pas dans l'image et ne pèse rien au push.
- Il complète le cache de couches : quand `package*.json` n'a pas bougé, l'étape n'est même pas
  exécutée.

### B3 — build reproductible

```bash
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
docker buildx build --no-cache --provenance=false --build-arg SOURCE_DATE_EPOCH \
  --build-arg APP_VERSION=1.4.2 --build-arg GIT_SHA=cd7bc56 \
  --metadata-file meta.json --output type=oci,dest=shopapi.tar,rewrite-timestamp=true .
```

| Build | Digest |
|-------|--------|
| Reproductible, 1er build | `sha256:4365dc99c373a46e0240e7a2ea52c2d825ebee6e36e5600454f63beb0d498f42` |
| Reproductible, 2e build | `sha256:4365dc99c373a46e0240e7a2ea52c2d825ebee6e36e5600454f63beb0d498f42` |
| Classique, 1er build | `sha256:3d114b5e1444588f4e0131259212c1685a3be5fcdbfcf8559120ea0f69c6205d` |
| Classique, 2e build | `sha256:1075bc83fb9a20438822ab8bd3b55f75a315d684c40931178410d1cac650a66c` |

Ce qui empêche la reproductibilité, et comment chaque point est traité :

- **Horodatages** : date de création dans la config de l'image et dans l'historique, `mtime` des fichiers
  écrits par `npm ci` ou `touch`. `SOURCE_DATE_EPOCH` fixe les dates de la config ;
  `rewrite-timestamp=true` ramène à cette date tous les fichiers plus récents dans les couches.
- **Attestation de provenance** : elle contient l'heure et l'identifiant du build, donc change à chaque
  fois. `--provenance=false` pour la comparaison, ou comparer seulement le manifeste de l'image.
- **Entrées mutables** : un tag de base qui bouge, `npm install` sans lockfile. Le digest dans `FROM` et
  `npm ci` sur un lockfile versionné les figent.
- **Ce qui reste hors de contrôle** : `apk add` ou `apt-get install` sans version épinglée (le miroir
  évolue), les scripts `postinstall` qui téléchargent ou compilent, et les `ARG` comme `GIT_SHA` qui
  changent volontairement le résultat.
