# TP04 — Stack Compose d'entreprise

## 1. Critique de `starter/docker-compose.yml`

| # | Problème | Conséquence |
|---|----------|-------------|
| 1 | `version: '3'` | Clé obsolète, ignorée par Compose v2 (avertissement) |
| 2 | `links` | Mécanisme legacy : le DNS d'un réseau utilisateur suffit |
| 3 | `postgres`, `redis` sans tag | Version imprévisible, une mise à jour majeure de PostgreSQL rend le volume illisible |
| 4 | Ports 5432 et 6379 publiés sur `0.0.0.0` | Base et cache joignables depuis le réseau, Redis sans mot de passe |
| 5 | Mot de passe `postgres` en clair, répété trois fois | Secret versionné, visible dans `docker inspect` |
| 6 | Utilisateur `postgres` et base `postgres` | Compte superutilisateur utilisé par l'application |
| 7 | `sleep 10 && node ...` | Démarrage non fiable (trop court ou trop long), `sh` en PID 1 qui ne relaie pas `SIGTERM` |
| 8 | Un seul réseau par défaut | L'API, le worker, la base et Redis se voient tous, pas d'isolation |
| 9 | Aucun healthcheck, `depends_on` absent | Impossible d'ordonner le démarrage ou d'utiliser `up --wait` |
| 10 | Pas de volumes nommés | Données dans des volumes anonymes, perdues ou orphelines au `down` |
| 11 | `restart: always` sur le worker uniquement | Politique incohérente, l'API et la base ne redémarrent pas |
| 12 | Pas de limites CPU/mémoire ni de rotation des logs | Un conteneur peut saturer l'hôte ou remplir le disque |
| 13 | Pas de reverse proxy, l'API publie 3000 directement | Pas de point d'entrée unique, pas de répartition de charge |
| 14 | Pas de nom de projet | Noms des réseaux et volumes dépendants du dossier |

## `--scale api=3` puis `up -d`

Le premier crée `shop-api-3`, que Traefik ajoute
automatiquement. Le second ramène l'API à `deploy.replicas: 2` et supprime `shop-api-3` : le fichier
reste la source de vérité, un `--scale` manuel n'est pas persistant.
