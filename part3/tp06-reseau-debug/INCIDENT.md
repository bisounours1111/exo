# Rapport d'incident — préprod Shop SAS

**Heure de début** : 10h22 · **Heure de résolution** : 10h27 · **Impact** : préprod indisponible

Fichiers corrigés : `starter/compose.yml`, `starter/nginx/default.conf`. Code applicatif et image inchangés.

## Chronologie du diagnostic

| Heure | Symptôme observé | Commande / preuve | Hypothèse | Résultat |
|-------|------------------|-------------------|-----------|----------|
| 10h22 | La stack ne démarre pas | `docker compose config` : `can't set container_name and api as container name must be unique` | `container_name` fixe incompatible avec `replicas: 2` | Confirmé, `container_name` retiré |
| 10h23 | `front` reste `Created` | `docker compose up` : `Are you trying to mount a directory onto a file (or vice-versa)?` | Le dossier `./nginx` est monté sur le fichier `default.conf` | Confirmé, montage du fichier `./nginx/default.conf` |
| 10h23 | Les deux `api` en `Exited (1)` | `docker compose logs api` : `Cannot find module '/app/server.js'` ; `docker run --entrypoint ls incident-api /app/src` → `server.js` ; CMD de l'image `["node","src/server.js"]` | `command` écrase la CMD de l'image avec un mauvais chemin | Confirmé, `command` retiré |
| 10h24 | `curl localhost:8081` → code 000 | `docker compose ps` : `80/tcp` sans publication ; `docker network inspect incident_public` → `internal=true` | Un réseau `internal` ne publie aucun port | Confirmé, `public` n'est plus `internal` |
| 10h24 | `api` en `health: starting` puis `unhealthy` | `docker inspect ... .State.Health` : `can't connect to remote host (127.0.0.1): Connection refused` ; logs `"port":"8080"` | `PORT: 8080` alors que le healthcheck de l'image et nginx attendent 3000 | Confirmé, `PORT` retiré |
| 10h24 | `curl :8081/products` → 502 | `docker compose logs front` : `upstream: "http://127.0.0.1:3000/"` | `localhost` dans nginx désigne le conteneur nginx lui-même | Confirmé, `proxy_pass http://api:3000` (`getent hosts api` → 172.31.0.3) |
| 10h25 | 500 `internal error` | `docker compose logs api` : `getaddrinfo ENOTFOUND databse` | Faute de frappe dans `DATABASE_URL` | Confirmé, hôte `db` |
| 10h25 | `getent hosts db` sans réponse depuis `api` | `docker inspect incident-api-1 ... Networks` → `incident_public` seulement | L'API n'est pas sur le réseau de la base | Confirmé, `api` ajouté à `backend` |
| 10h25 | `getaddrinfo ENOTFOUND redis` | `docker inspect incident-redis-1` → `network_mode=host` | Redis en réseau `host` : pas de nom DNS sur les réseaux du projet | Confirmé, Redis sur `backend` |
| 10h26 | `X-Cache: MISS` à chaque appel | `docker compose logs api` : `NOAUTH Authentication required.` | `--requirepass r3dis` côté Redis, pas de mot de passe dans `REDIS_URL` | Confirmé, `redis://:r3dis@redis:6379` → `X-Cache: HIT` |
| 10h26 | Erreurs répétées dans les logs de la base | `docker compose logs db` : `FATAL: role "postgres" does not exist` toutes les 5 s | Healthcheck avec le mauvais utilisateur | Confirmé, `pg_isready -U shop -d shop` (0 FATAL ensuite) |
| 10h27 | `front` et `redis` sans état de santé | `docker compose ps` : pas de `(healthy)` | Pas de healthcheck, `depends_on` sans condition | Healthchecks ajoutés, `depends_on: condition: service_healthy` |
| 10h27 | Vérification finale | `docker compose up -d --wait` ; `curl -D - localhost:8081/products` ×2 | — | 5 conteneurs `healthy`, `X-Cache: MISS` puis `HIT` |

État final :

```text
NAME               STATUS                    PORTS
incident-api-1     Up 8 seconds (healthy)    3000/tcp
incident-api-2     Up 8 seconds (healthy)    3000/tcp
incident-db-1      Up 13 seconds (healthy)
incident-front-1   Up 6 seconds (healthy)    0.0.0.0:8081->80/tcp, [::]:8081->80/tcp
incident-redis-1   Up 13 seconds (healthy)

$ curl -s -D - localhost:8081/products        # 2e appel
HTTP/1.1 200 OK
X-Cache: HIT
[{"id":1,"name":"Clavier mécanique","price":"89.90","stock":12},{"id":2,"name":"Écran 27\"","price":"249.00","stock":4},{"id":3,"name":"Souris sans fil","price":"29.50","stock":40}]
```

## Anomalies trouvées

| # | Fichier / service | Anomalie | Correction | Catégorie |
|---|-------------------|----------|------------|-----------|
| 1 | compose / api | `container_name: api` avec `replicas: 2` | Supprimé | config |
| 2 | compose / front | Dossier `./nginx` monté sur le fichier `default.conf` | `./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro` | stockage |
| 3 | compose / api | `command: node server.js` (fichier inexistant) | Supprimé, la CMD de l'image s'applique | config |
| 4 | compose / réseaux | `public` en `internal: true` : port 8081 non publié | `public` normal | réseau |
| 5 | compose / api | `PORT: 8080`, healthcheck et proxy sur 3000 | Supprimé (3000 par défaut) | config |
| 6 | default.conf | `proxy_pass http://localhost:3000` | `proxy_pass http://api:3000` | réseau |
| 7 | compose / api | `DATABASE_URL` vers `databse` | `db` | config |
| 8 | compose / api | API absente du réseau `backend` | `networks: [public, backend]` | réseau |
| 9 | compose / redis | `network_mode: host` | Réseau `backend` | réseau |
| 10 | compose / api | `REDIS_URL` sans le mot de passe de `--requirepass` | `redis://:r3dis@redis:6379` | config |
| 11 | compose / db | `pg_isready -U postgres` (rôle inexistant) | `pg_isready -U shop -d shop` | cycle de vie |
| 12 | compose / front, redis | Pas de healthcheck, `depends_on` sans condition, API démarrée sans attendre Redis | Healthchecks, `condition: service_healthy` | cycle de vie |
| 13 | compose / réseaux | `backend` non `internal` : base et Redis ont accès à Internet | `backend: internal: true` | sécurité |

## Pourquoi ça n'a pas été détecté avant ?

Le compose a été modifié directement sur la préprod, sans revue ni validation automatique. L'erreur n° 1
est remontée par `docker compose config`, que personne n'a lancé. Les autres ne se voient qu'à
l'exécution : sans healthcheck sur le front et Redis, sans `--wait` et sans smoke test, `docker compose up`
rendait la main sans erreur alors que le service était cassé.

## Actions de prévention

1. **CI sur le dépôt du compose** : `docker compose config --quiet` et un lint (`dclint`) à chaque merge
   request ; aucune modification directe sur un serveur.
2. **Démarrage vérifié** : healthchecks sur tous les services, déploiement par
   `docker compose up -d --wait`, suivi d'un smoke test (`curl /products` deux fois, `X-Cache: HIT`) ; le
   déploiement échoue sinon.
3. **Revue de code obligatoire** sur les fichiers d'infrastructure, avec une liste de contrôle : réseaux
   `internal`, ports publiés, URL de connexion, `network_mode`, `container_name`.
