# TP01 — Diagnostic de l'image `shopapi:legacy`

Image construite depuis `starter/shopapi/Dockerfile.legacy` (copie du Dockerfile historique) :

```bash
docker build -t shopapi:legacy -f Dockerfile.legacy .     # build à froid : 2 min 11 s
```

## Preuves collectées

```text
$ docker image ls shopapi:legacy
REPOSITORY   TAG       IMAGE ID       CREATED          SIZE
shopapi      legacy    c5d4fd736ba4   27 seconds ago   1.09GB

$ docker history --no-trunc shopapi:legacy
SIZE      CREATED BY
0B        CMD ["/bin/sh" "-c" "npm start"]
0B        EXPOSE [3000/tcp]
0B        ENV DATABASE_URL=postgres://shop:S3cret!@db.internal:5432/shop
0B        ENV NODE_ENV=development
63.5MB    RUN /bin/sh -c npm install # buildkit
53.2kB    COPY . /app # buildkit
8.19kB    WORKDIR /app
7.56MB    RUN /bin/sh -c npm install -g nodemon # buildkit
173MB     RUN /bin/sh -c apt-get install -y nodejs # buildkit
999kB     RUN /bin/sh -c curl -fsSL https://deb.nodesource.com/setup_20.x | bash - # buildkit
393MB     RUN /bin/sh -c apt-get install -y curl wget vim git build-essential python3 # buildkit
81.5MB    RUN /bin/sh -c apt-get update # buildkit
0B        ENV DEBIAN_FRONTEND=noninteractive
87.7MB    ADD file:ba52f9ee... in /                       # ubuntu:22.04
0B        LABEL org.opencontainers.image.version=22.04    # hérité d'ubuntu

$ docker run --rm shopapi:legacy env | grep -i -E 'secret|database|node_env'
NODE_ENV=development
DATABASE_URL=postgres://shop:S3cret!@db.internal:5432/shop

$ docker run --rm shopapi:legacy id
uid=0(root) gid=0(root) groups=0(root)

$ docker run --rm shopapi:legacy ls -la /app
-rwxr-xr-x   1 root root   183 .env
-rwxr-xr-x   1 root root    22 .gitignore
-rwxr-xr-x   1 root root   520 Dockerfile
-rwxr-xr-x   1 root root    48 dump-prod-2024.sql
drwxr-xr-x 199 root root  4096 node_modules
-rw-r--r--   1 root root 99341 package-lock.json      # généré au build, absent du repo
-rwxr-xr-x   1 root root   569 package.json
drwxr-xr-x   2 root root  4096 src
drwxr-xr-x   2 root root  4096 test

$ docker run --rm shopapi:legacy cat /app/.env
DATABASE_URL=postgres://shop:S3cret!@localhost:5432/shop
REDIS_URL=redis://localhost:6379
AWS_SECRET_ACCESS_KEY=AKIAFAKEFAKEFAKEFAKE

$ docker run --rm shopapi:legacy sh -c 'ls /app/node_modules | grep -E "^(eslint|nodemon)$"; which vim git gcc curl wget'
eslint
nodemon
/usr/bin/vim
/usr/bin/git
/usr/bin/gcc
/usr/bin/curl
/usr/bin/wget

$ docker top <conteneur>
UID   PID     PPID    CMD
root  34225   34202   /bin/sh -c npm start
root  34239   34225   npm start
root  34250   34239   sh -c node src/server.js
root  34251   34250   node src/server.js

$ docker inspect shopapi:legacy --format 'Healthcheck={{json .Config.Healthcheck}} User={{json .Config.User}} Cmd={{json .Config.Cmd}}'
Healthcheck=null User="" Cmd=["/bin/sh","-c","npm start"]

$ Measure-Command { docker stop -t 10 legacy-stop }      # PowerShell
elapsed: 9.59 s
$ docker inspect legacy-stop --format '{{.State.ExitCode}}'
137                                                       # 128 + 9 = SIGKILL

$ hadolint Dockerfile.legacy        # docker run --rm -i hadolint/hadolint:v2.12.0 < Dockerfile.legacy
-:3 DL3009 info: Delete the apt-get lists after installing something
-:4 DL3008 warning: Pin versions in apt get install.
-:4 DL3015 info: Avoid additional packages by specifying `--no-install-recommends`
-:4 DL3059 info: Multiple consecutive `RUN` instructions. Consider consolidation.
-:5 DL4006 warning: Set the SHELL option -o pipefail before RUN with a pipe in it.
-:6 DL3008 warning: Pin versions in apt get install.
-:6 DL3015 info: Avoid additional packages by specifying `--no-install-recommends`
-:7 DL3059 info: Multiple consecutive `RUN` instructions. Consider consolidation.
-:7 DL3016 warning: Pin versions in npm.
-:14 DL3025 warning: Use arguments JSON notation for CMD and ENTRYPOINT arguments
```

`dive shopapi:legacy` confirme la répartition : 87,7 Mo de base Ubuntu, 393 Mo de chaîne de compilation,
173 Mo pour Node via NodeSource, 81,5 Mo de listes apt jamais nettoyées. L'application et ses dépendances
représentent moins de 70 Mo, soit **moins de 7 % de l'image**.

## Problèmes identifiés

### Taille / performance

| # | Problème | Preuve | Impact |
|---|----------|--------|--------|
| 1 | Image de 1,09 Go sur une base généraliste `ubuntu:22.04` | `docker image ls` : 1.09GB | Registre saturé, pull lent à chaque déploiement et chaque nouveau nœud |
| 2 | Chaîne de compilation et outils dans l'image finale (`build-essential`, `python3`, `vim`, `git`, `curl`, `wget`) | `history` : couche de 393 Mo ; `which vim git gcc curl wget` | 36 % de l'image ne sert à rien à l'exécution |
| 3 | `apt-get update` dans sa propre couche, listes apt jamais supprimées | `history` : 81,5 Mo ; hadolint DL3009 | Poids mort, et la couche `update` reste en cache pendant que l'`install` évolue : paquets obsolètes |
| 4 | `COPY . /app` placé avant `npm install` | Après `echo "// commentaire" >> src/server.js`, le build rejoue `[9/9] RUN npm install` (non `CACHED`) | Toute modification du contexte, même un README, réinstalle les dépendances (≈ 4 min en CI) |
| 5 | `npm install` sans lockfile versionné au lieu de `npm ci` | `package-lock.json` absent du repo mais présent dans `/app` | Build non reproductible : deux builds peuvent embarquer des versions différentes |
| 6 | Dépendances de dev dans l'image (`eslint`, `nodemon` local et `nodemon` global) | `ls node_modules` liste `eslint` et `nodemon` ; couche `npm install -g nodemon` de 7,56 Mo | Poids inutile et code non destiné à la prod exécutable dans le conteneur |
| 7 | Pas de multi-stage, 7 instructions `RUN`/`COPY` empilées | `docker image inspect --format '{{len .RootFS.Layers}}'` : 9 couches | Impossible de séparer build, tests et runtime ; chaque couche conserve ses fichiers même s'ils sont supprimés plus tard |

### Sécurité

| # | Problème | Preuve | Impact |
|---|----------|--------|--------|
| 8 | Le processus tourne en **root** | `id` : `uid=0(root)` ; `docker top` : tous les processus en root | Une RCE dans l'API donne root dans le conteneur, et facilite une évasion |
| 9 | Mot de passe de la base dans `ENV DATABASE_URL` | `env` et `docker history` affichent `postgres://shop:S3cret!@db.internal` | Secret lisible par quiconque peut pull l'image, gravé dans les métadonnées |
| 10 | `.env` du développeur copié dans l'image (clé AWS, URL de base) | `cat /app/.env` | Fuite de credentials, aucun `.dockerignore` |
| 11 | Dump de production `dump-prod-2024.sql` copié | `ls -la /app` | Fuite potentielle de données clients (RGPD) et 50 Mo en vrai |
| 12 | `Dockerfile` et `.gitignore` copiés dans `/app` | `ls -la /app` | Divulgue la recette de build et l'infra (`db.internal`) |
| 13 | `curl ... | bash -` depuis NodeSource, sans `pipefail` | `history` ; hadolint DL4006 | Exécution d'un script distant non vérifié ; une erreur de `curl` passe inaperçue |
| 14 | Rien n'est épinglé : tag `ubuntu:22.04` mutable, paquets apt et `nodemon` sans version | hadolint DL3008, DL3016 | Builds non reproductibles, impossible d'auditer ce qui tourne en prod |
| 15 | Surface d'attaque large : shell, `vim`, `git`, `gcc`, `curl`, `wget` | `which ...` | Un attaquant dispose de tout pour télécharger et compiler des outils |

### Exploitabilité

| # | Problème | Preuve | Impact |
|---|----------|--------|--------|
| 16 | `CMD` en forme shell : PID 1 = `/bin/sh -c npm start` | `inspect` : `Cmd=["/bin/sh","-c","npm start"]` ; hadolint DL3025 ; `docker top` | `sh` en PID 1 ne relaie pas `SIGTERM` à Node : le handler `shutdown()` du code ne s'exécute jamais |
| 17 | Arrêt en 9,6 s terminé par `SIGKILL` | `docker stop` : 9,59 s, exit code 137 | Rolling updates de 30 s, requêtes en cours coupées, connexions DB non fermées |
| 18 | 4 processus en chaîne (`sh` → `npm` → `sh` → `node`) | `docker top` | Signaux perdus, mémoire gaspillée, logs npm parasites |
| 19 | `NODE_ENV=development` en production | `env` | Express désactive ses optimisations (cache des vues, messages d'erreur détaillés) |
| 20 | Aucun `HEALTHCHECK` | `inspect` : `Healthcheck=null` | L'orchestrateur ne détecte pas une API figée ; `/health` existe pourtant |
| 21 | Aucun label OCI, et un label trompeur hérité d'Ubuntu | `history` : `org.opencontainers.image.version=22.04` | Impossible de relier l'image à une version, un commit ou un dépôt ; l'image annonce la version 22.04 |
| 22 | 6 avertissements hadolint de niveau warning | sortie ci-dessus | Non conforme au standard n° 7 |

## Étape 2 — invalidation du cache

```text
$ time docker build -t shopapi:legacy -f Dockerfile.legacy .     # rien n'a changé
real    0m8.112s
$ echo "// commentaire" >> src/server.js
$ time docker build --progress=plain -t shopapi:legacy -f Dockerfile.legacy .
#6..#11 CACHED              # apt, nodesource, nodejs, nodemon global
#12 [8/9] COPY . /app       DONE 0.1s
#13 [9/9] RUN npm install   DONE 4.9s   <- rejoué
real    0m8.111s
```

**Pourquoi `npm install` est rejoué** : BuildKit calcule la clé de cache d'un `COPY` à partir du contenu
des fichiers copiés. `COPY . /app` prend tout le contexte, donc la moindre modification (code, README,
`.env`) change cette clé. La couche `COPY` est invalidée, et avec elle **toutes les couches suivantes**,
dont `npm install`, alors que `package.json` n'a pas bougé. En local le réseau est rapide (4,9 s) ; en CI
sans cache de couches ni proxy npm, c'est l'essentiel des 4 minutes.

**Ordre des couches idéal** (du plus stable au plus volatil) :

```text
┌────────────────────────────────────────────┐  change : rarement (montée de version Node)
│ FROM node:20.x-alpine (version épinglée)   │
├────────────────────────────────────────────┤
│ WORKDIR /app, ENV NODE_ENV=production      │
├────────────────────────────────────────────┤  change : à chaque ajout/màj de dépendance
│ COPY package.json package-lock.json        │
│ RUN npm ci --omit=dev                      │
├────────────────────────────────────────────┤  change : à chaque commit
│ COPY src/                                  │
├────────────────────────────────────────────┤  change : à chaque build (métadonnées, 0 octet)
│ ARG APP_VERSION / GIT_SHA, LABEL, USER,    │
│ HEALTHCHECK, CMD ["node", "src/server.js"] │
└────────────────────────────────────────────┘
```

Un changement de code n'invalide plus que la couche `COPY src/` et les métadonnées : `npm ci` reste en cache.
