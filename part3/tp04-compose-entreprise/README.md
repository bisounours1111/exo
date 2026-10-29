# TP04 — Une stack Compose d'entreprise : du poste du dev à la prod


## Contexte

La stack *Shop SAS* (API, worker, PostgreSQL, Redis) est aujourd'hui décrite par un `docker-compose.yml`
« qui marche sur le poste du dev » (`starter/`). On vous demande d'en faire la **référence d'exécution**
utilisée à la fois par les développeurs, la CI (TP09) et le serveur de prod. Exigences de l'équipe :

- un **même fichier de base** pour tous les environnements, avec des surcharges dev et prod ;
- **zéro secret en clair** dans les fichiers versionnés ;
- la base et Redis **inaccessibles depuis l'extérieur et depuis Internet** ; seul le reverse proxy expose le port 80 ;
- un démarrage **ordonné et fiable** (pas de `sleep 10`), des healthchecks partout, `docker compose up --wait` qui ne rend la main qu'avec une stack saine ;
- des outils (admin BDD, migrations) disponibles **à la demande** sans tourner en permanence ;
- en prod : limites de ressources, rotation des logs, redémarrage automatique, plusieurs réplicas de l'API derrière le proxy.

## Étapes

### 1. Critique du compose existant 

Listez les problèmes de `starter/docker-compose.yml` (au moins 8). Indices : `version`, `links`,
images non épinglées, ports exposés, mots de passe, `sleep`, réseau unique, pas de healthcheck,
pas de volumes nommés, `restart` incohérent, pas de limites.

### 2. Fichier de base `compose.yml` 

- `name: shop` (nom de projet stable, indépendant du dossier) ;
- deux réseaux : `front` (proxy ↔ api) et `back` (`internal: true` : api/worker ↔ db/redis) ;
- images épinglées (`postgres:16.4-alpine`, `redis:7.4-alpine`, `traefik:v3.1`) ;
- **healthchecks** sur tous les services, factorisés via une **ancre YAML** (`x-healthcheck-defaults`) ;
- `depends_on` avec `condition: service_healthy` ;
- mot de passe PostgreSQL via **`secrets:`** (fichier `./secrets/db_password.txt` gitignored),
  `POSTGRES_PASSWORD_FILE` côté base. Côté API et worker, l'application ne lit que `DATABASE_URL` :
  trouvez un moyen de construire cette URL à partir du secret **sans modifier le code** ;
- volumes nommés `pgdata`, `redisdata`, script d'initialisation `db/init.sql` ;
- reverse proxy **Traefik** piloté par labels : `api.localhost` → API, healthcheck de backend ;
- rotation des logs (`x-logging`), `restart: unless-stopped` ;
- profils : `tools` (adminer sur `adminer.localhost`) et `ops` (service `migrate` à usage unique :
  `MIGRATION=002-add-sku.sql docker compose run --rm migrate`).

Vérifiez avec `docker compose config` (le fichier résolu) et `docker compose up -d --wait && docker compose ps`.

### 3. Surcharge dev `compose.override.yml` 

Appliquée automatiquement : bind mount du code source avec rechargement (`node --watch`), ports de
debug (3000, 5432, dashboard Traefik 8080), `LOG_LEVEL=debug`. Modifiez `server.js`, observez le reload.

### 4. Surcharge prod `compose.prod.yml` 

`docker compose -f compose.yml -f compose.prod.yml config` puis `up -d --wait` :

- pas de `build` (images tirées du registre du TP03 : `REGISTRY`/`VERSION` depuis `.env`) — cherchez
  comment **supprimer** une clé héritée (`!reset`) ;
- `deploy.replicas: 2` pour l'API : vérifiez avec `docker compose ps` et plusieurs `curl` que Traefik
  répartit la charge (ajoutez l'`id` du conteneur dans la réponse ? non : regardez les logs d'accès) ;
- limites CPU/mémoire, `read_only: true` + `tmpfs`, `cap_drop: [ALL]`, `no-new-privileges` ;
- aucun port de debug, pas de dashboard.

Testez `docker compose up -d --scale api=3` puis `docker compose up -d` : que se passe-t-il ?

### 5. Outillage d'équipe 

`Makefile` (ou `justfile`) : `make up`, `make prod-up`, `make migrate M=002-add-sku.sql`, `make test`
(script `smoke-test.sh` : `/ready`, `/products` avec cache HIT, création d'une commande, vérification
qu'elle est passée `confirmed` par le worker).

> **Livrables** : `compose.yml`, `compose.override.yml`, `compose.prod.yml`, `.env.example`, `Makefile`,
> `smoke-test.sh`, et la liste de l'étape 1.

## Bonus

- **B1** : `docker compose watch` (section `develop.watch`) à la place du bind mount : `sync` vs `rebuild`.
- **B2** : TLS local sur Traefik avec `mkcert` et redirection 80 → 443.
- **B3** : `docker compose --profile tools up` lance adminer sur le réseau `back` qui est `internal` :
  adminer peut-il quand même être joint via Traefik ? Pourquoi (deux réseaux) ?
- **B4** : variables obligatoires : `${REGISTRY:?REGISTRY doit être défini}` en prod. Testez l'erreur.
- **B5** : `docker compose alpha publish` / `include:` pour découper le compose en plusieurs fichiers partagés entre équipes.

