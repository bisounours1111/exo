# TP05 — Données : persistance, sauvegarde, restauration, montée de version


## Contexte

L'incident du mois dernier chez *Shop SAS* : un `docker compose down -v` lancé « pour nettoyer » sur le
serveur de préprod a effacé la base. Aucune sauvegarde testée n'existait. La DSI exige désormais :

1. de **comprendre précisément** où vivent les données de chaque conteneur ;
2. une **procédure de sauvegarde/restauration** scriptée et **testée** (une sauvegarde non restaurée n'existe pas) ;
3. la **montée de version majeure** PostgreSQL 14 → 16 sur la base legacy, **sans perte** et avec retour arrière possible.

## Étapes

### 1. Anatomie du stockage 

Avec la stack du TP04 démarrée :

```bash
docker inspect $(docker compose ps -q db) --format '{{json .Mounts}}' | jq
docker volume inspect shop_pgdata
docker system df -v | head -40
```

Répondez, preuves à l'appui :

- Où sont écrites les données des couches du conteneur (writable layer) vs du volume ? Montrez avec
  `docker exec db touch /tmp/x` puis `docker diff`.
- Que se passe-t-il pour `pgdata` lors de `docker compose down` ? `down -v` ? `docker compose rm` ?
  `docker volume prune` ? Testez chaque cas (sur une copie de la stack !).
- Volume **anonyme** : lancez `docker run -d postgres:16-alpine` sans `-v`. Où sont les données ? Que
  devient le volume au `docker rm` ? Et avec `docker rm -v` ? Pourquoi est-ce un piège classique ?
- Bind mount vs volume nommé vs `tmpfs` : quand utiliser chacun ? Performances sur Docker Desktop (macOS/Windows) ?
- Pourquoi `db/init.sql` n'est-il **pas rejoué** au redémarrage ? Comment forcer une ré-initialisation ?

### 2. Sauvegarde et restauration 

Écrivez `backup.sh` (sans client `psql` sur l'hôte : tout via conteneurs) :

- dump logique `pg_dump -Fc` horodaté ;
- sauvegarde **brute** du volume via un conteneur `alpine` + `tar` (`-v vol:/data:ro`). Dans quel cas la
  sauvegarde brute est-elle incohérente ? Comment la rendre cohérente (arrêt, `pg_backup_start`) ?
- rétention des 7 derniers.

Écrivez `restore.sh` et **prouvez** la restauration : seedez (`starter/seed.sh`, ≈ 100 000 lignes), notez
le checksum affiché, sauvegardez, détruisez (`down -v`), recréez, restaurez, comparez le checksum.

Ajoutez à la stack du TP04 un sidecar de sauvegarde planifiée (`compose.backup.yml`,
image `prodrigestivill/postgres-backup-local`) : vérifiez qu'un dump apparaît (`SCHEDULE: "@every 1m"` pour le test).

### 3. Montée de version majeure PostgreSQL 

`starter/compose.yml` fait tourner PostgreSQL 14. Changer simplement le tag en `16` ne marche pas : constatez-le
(`docker compose up` → lisez l'erreur dans les logs). Pourquoi ?

Écrivez `upgrade-pg.sh` : checksum avant → `pg_dumpall` + `pg_dump -Fc` → arrêt PG14 (volume conservé) →
PG16 sur **nouveau volume** → `pg_restore` → checksum après → verdict. Documentez le retour arrière.

Questions : différence `pg_dumpall` / `pg_dump` ? Pourquoi un **nouveau** volume plutôt qu'écraser ?
Temps d'indisponibilité : comment le réduire (réplication logique, `pg_upgrade --link` dans un conteneur
contenant les deux binaires, ex. `tianon/postgres-upgrade`) ?

### 4. Redis 

`redis-server --save 60 1` vs `--appendonly yes` : quelle perte maximale de données dans chaque cas ?
Dans notre stack, que contient Redis (cache + file) et quel niveau de persistance est justifié ?

> **Livrables** : réponses de l'étape 1 avec preuves, `backup.sh`, `restore.sh`, `upgrade-pg.sh`,
> transcript (copie du terminal) de la restauration et de la montée de version avec les checksums.

## Bonus

- **B1** : testez `pg_upgrade --link` avec `tianon/postgres-upgrade:14-to-16` et comparez la durée.
- **B2** : chiffrez le dump (`age` ou `gpg`) et poussez-le vers un bucket S3 compatible (MinIO en conteneur).
- **B3** : volume sur un driver distant : NFS (`driver_opts: type: nfs`) ou un plugin (rexray, local-persist).
  Qu'est-ce qui change pour la sauvegarde et la haute disponibilité ?
- **B4** : *Point-in-time recovery* : archivage WAL vers un volume et restauration à T-5 min.

