# TP01 — Reprendre en main une image « historique »

**Niveau** : intermédiaire → avancé · **Travail** : individuel

## Contexte

Vous rejoignez l'équipe plateforme de *Shop SAS*. L'API catalogue `shopapi` (Node.js) est conteneurisée
depuis 2021 avec un Dockerfile que « personne n'ose toucher ». Le lead ops vous remonte les problèmes suivants :

- l'image pèse plus d'1 Go et le registre d'entreprise sature ;
- chaque commit, même un changement de README, relance un `npm install` complet dans la CI (≈ 4 min) ;
- l'audit sécurité a signalé que le conteneur tourne en **root** et que des **secrets** sont dans l'image ;
- en production les rolling updates prennent 30 s : le conteneur ne s'arrête pas proprement sur `SIGTERM`.

Votre mission : livrer une image conforme aux standards de l'entreprise **sans modifier le code applicatif**.

## Standards d'image Shop SAS (extrait du référentiel interne)

1. Image finale < 200 Mo, basée sur une image officielle à version épinglée.
2. Processus non-root, forme exec pour `CMD`/`ENTRYPOINT`.
3. Aucun secret, aucun fichier inutile (`.env`, dumps, `.git`, `node_modules` locaux) dans l'image.
4. Build reproductible et **cache-friendly** : un changement de code source ne réinstalle pas les dépendances.
5. `HEALTHCHECK` défini, labels OCI (`org.opencontainers.image.*`) renseignés : version, révision git, source.
6. Pas de dépendances de dev dans l'image finale ; les tests s'exécutent **dans le build** (étape dédiée).
7. Zéro avertissement `hadolint` de niveau error/warning.

## Étapes

### 1. Diagnostic 

Dans `starter/shopapi` :

```bash
docker build -t shopapi:legacy .
docker image ls shopapi:legacy
docker history shopapi:legacy
docker run --rm shopapi:legacy env | grep -i -E 'secret|database'
docker run --rm shopapi:legacy id
docker run --rm shopapi:legacy ls -la /app
```

Installez puis utilisez `dive` (`dive shopapi:legacy`) et `hadolint` (`hadolint Dockerfile`).

> **Livrable 1** : un fichier `DIAGNOSTIC.md` listant **au moins 10 problèmes** classés en 3 catégories :
> taille/performance, sécurité, exploitabilité. Pour chacun : la preuve (commande + sortie) et l'impact.

### 2. Mesurer l'invalidation du cache (10 min)

```bash
time docker build -t shopapi:legacy .
echo "// commentaire" >> src/server.js
time docker build -t shopapi:legacy .
```

Expliquez pourquoi `npm install` est rejoué. Dessinez l'ordre des couches idéal.

### 3. Réécrire le Dockerfile

Contraintes : multi-stage, `node:20-alpine` (ou `node:20-slim` si vous justifiez), `.dockerignore`,
étape `test` exécutant `npm test` et `npm run lint`, utilisateur `node`, `HEALTHCHECK`, labels OCI
alimentés par des `ARG` (`APP_VERSION`, `GIT_SHA`), `CMD` en forme exec.

```bash
docker build --build-arg APP_VERSION=1.4.2 --build-arg GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo local) -t shopapi:1.4.2 .
docker build --target test -t shopapi:test .          # les tests doivent passer
```

### 4. Vérifier la conformité

```bash
docker image ls shopapi                                # < 200 Mo
docker run --rm shopapi:1.4.2 id                       # uid=1000(node)
docker run --rm shopapi:1.4.2 ls /app                  # pas de .env ni de *.sql
docker inspect shopapi:1.4.2 --format '{{json .Config.Labels}}' | jq
docker run -d --name api -p 3000:3000 shopapi:1.4.2
sleep 6 && docker inspect api --format '{{.State.Health.Status}}'   # healthy
curl -s localhost:3000/products | jq
time docker stop api                                   # < 1 s (SIGTERM géré)
```

Comparez avec `time docker stop` sur l'image legacy (10 s : timeout puis SIGKILL). Expliquez.

### 5. Rapport

> **Livrable 2** : tableau avant/après (taille, nombre de couches, temps de rebuild après changement de code,
> utilisateur, temps d'arrêt) + le Dockerfile final + la sortie `hadolint` vide.

## Bonus

- **B1** : produisez une variante `distroless` (`gcr.io/distroless/nodejs20-debian12`). Quel compromis
  (debug, shell, healthcheck) ? Comment faire le healthcheck sans `wget` ?
- **B2** : `docker build --no-cache` vs cache mount `--mount=type=cache,target=/root/.npm` : mesurez.
- **B3** : rendez l'image **reproductible** : deux builds successifs donnent le même digest
  (`SOURCE_DATE_EPOCH`, `--output type=oci,rewrite-timestamp=true`). Qu'est-ce qui empêche la reproductibilité ?


