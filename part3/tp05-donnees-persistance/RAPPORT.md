# TP05 — Persistance, sauvegarde, restauration, montée de version

Livrables : `backup.sh`, `restore.sh`, `upgrade-pg.sh` (+ `compose.pg16.yml`), `compose.backup.yml` (sidecar
de sauvegarde pour la stack du TP04). Les sauvegardes sont écrites dans `backups/` (gitignored).

## 1. Anatomie du stockage

Stack du TP04 démarrée :

```text
$ docker inspect shop-db-1 --format '{{json .Mounts}}' | jq -c '.[] | {Type, Name, Source, Destination, RW}'
{"Type":"volume","Name":"shop_pgdata","Source":"/var/lib/docker/volumes/shop_pgdata/_data","Destination":"/var/lib/postgresql/data","RW":true}
{"Type":"bind","Name":null,"Source":"/run/desktop/mnt/host/c/Users/yanda/exo/part3/tp04-compose-entreprise/solution/db/init.sql","Destination":"/docker-entrypoint-initdb.d/init.sql","RW":false}
{"Type":"bind","Name":null,"Source":"C:\\Users\\yanda\\exo\\part3\\tp04-compose-entreprise\\solution\\secrets\\db_password.txt","Destination":"/run/secrets/db_password","RW":false}

$ docker volume inspect shop_pgdata
{"Name":"shop_pgdata","Driver":"local","Mountpoint":"/var/lib/docker/volumes/shop_pgdata/_data",
 "Labels":{"com.docker.compose.project":"shop","com.docker.compose.volume":"pgdata", ...}}

$ docker system df -v
VOLUME NAME        LINKS     SIZE
shop_pgdata        1         48.23MB
shop_redisdata     1         1.222kB
```

**Couche du conteneur vs volume** :

```text
$ docker exec shop-db-1 touch /tmp/x && docker diff shop-db-1
C /tmp
A /tmp/x
C /run/postgresql
A /run/postgresql/.s.PGSQL.5432
```

`/tmp/x` est écrit dans la couche inscriptible du conteneur (snapshot containerd, détruit avec le
conteneur). Les fichiers de la base (`/var/lib/postgresql/data`) n'apparaissent pas dans `docker diff` :
ils sont dans le volume `shop_pgdata`, un répertoire de la VM Docker
(`/var/lib/docker/volumes/shop_pgdata/_data`, qui contient `PG_VERSION`, `base`, `global`...),
indépendant du cycle de vie du conteneur.

**Cycle de vie de `pgdata`**, testé sur une copie (`docker compose -p shopcopy -f starter/compose.yml`,
une table `t` avec une ligne) :

| Commande | Volume | Données |
|----------|--------|---------|
| `docker compose down` | conservé | ligne retrouvée après `up` |
| `docker compose rm` | conservé | ligne retrouvée après `up` |
| `docker volume prune` | conservé : depuis Docker 23, `prune` ne supprime que les volumes **anonymes** | — |
| `docker volume prune -a` (volume non utilisé) | supprimé | perdues |
| `docker compose down -v` | supprimé (`Volume shopcopy_pgdata Removed`) | perdues |

**Volume anonyme** :

```text
$ docker run -d --name anon-pg -e POSTGRES_PASSWORD=x postgres:16.4-alpine
$ docker inspect anon-pg --format '{{range .Mounts}}{{.Type}} {{.Name}} -> {{.Destination}}{{end}}'
volume 2e1dd422f1a8...b819f0 -> /var/lib/postgresql/data
$ docker rm -f anon-pg        -> le volume 2e1dd422... existe toujours
$ docker rm -v anon-pg        -> le volume est supprimé
```

L'image déclare `VOLUME /var/lib/postgresql/data` : sans `-v`, Docker crée un volume au nom aléatoire.
C'est un piège dans les deux sens : après un `docker rm`, le volume reste orphelin, et un nouveau
conteneur ne le réutilise pas (base vide, données « perdues » mais qui occupent le disque). Un
`docker volume prune` ou un `rm -v` les supprime ensuite définitivement.

**Bind mount, volume nommé, `tmpfs`** :

| Type | Usage | 2 000 petits fichiers écrits (Docker Desktop, Windows) |
|------|-------|------------------------------------------------------|
| bind mount | code source en dev, fichiers de config, certificats | 3,69 s |
| volume nommé | données (bases, files), tout ce qui doit survivre au conteneur | 0,07 s |
| `tmpfs` | données temporaires ou sensibles en mémoire, `/tmp` d'un conteneur `read_only` | 0,01 s |

Sur Docker Desktop, un bind mount traverse la frontière entre l'hôte et la VM Linux à chaque accès
fichier : c'est environ 50 fois plus lent qu'un volume, qui vit sur le disque ext4 de la VM. Les
données de base de données vont toujours dans un volume nommé.

**`db/init.sql` n'est pas rejoué** :

```text
$ docker compose restart db && docker compose logs db
PostgreSQL Database directory appears to contain a database; Skipping initialization
```

L'entrypoint de l'image n'exécute `/docker-entrypoint-initdb.d/` que si le répertoire de données est
vide. Pour forcer une ré-initialisation, il faut un volume vide : `docker compose down -v` (ou
`docker volume rm shop_pgdata`) puis `up`, après avoir sauvegardé.

## 2. Sauvegarde et restauration

`backup.sh` produit un dump logique `pg_dump -Fc` et une copie brute du volume par `tar` dans un conteneur
`alpine`, puis garde les 7 plus récents de chaque type (`KEEP`).

La copie brute est **incohérente si PostgreSQL tourne** : les fichiers sont copiés à des instants
différents pendant que le serveur écrit, et le WAL n'est pas forcément en accord avec les fichiers de
données. Pour la rendre cohérente : arrêter la base pendant la copie (ce que fait `backup.sh`), ou
encadrer la copie par `pg_backup_start()` / `pg_backup_stop()` en copiant aussi les WAL produits
pendant ce temps (c'est ce que fait `pg_basebackup`). Le dump logique est cohérent base démarrée (un
seul snapshot transactionnel).

Transcript de la restauration :

```text
$ cd starter && docker compose up -d --wait && ./seed.sh
 orders |             checksum
--------+----------------------------------
 100000 | eef45ba1f45b4b7ed8cf0307983c5f57

$ ./backup.sh
dump: backups/shop-20261030-101253.dump (1593932 bytes)
 Container shopdata-db-1  Stopped
 Container shopdata-db-1  Started
raw:  backups/shopdata_pgdata-20261030-101253.tar.gz (volume shopdata_pgdata)

$ cd starter && docker compose down -v
 Container shopdata-db-1  Removed
 Volume shopdata_pgdata  Removed

$ cd starter && docker compose up -d --wait
 Container shopdata-db-1  Healthy
orders table present: 0

$ ./restore.sh backups/shop-20261030-101253.dump
restored: backups/shop-20261030-101253.dump
 orders |             checksum
--------+----------------------------------
 100000 | eef45ba1f45b4b7ed8cf0307983c5f57
```

Rétention (`KEEP=2 ./backup.sh`, deux fois) :

```text
pruned: backups/shop-20261030-101253.dump
pruned: backups/shopdata_pgdata-20261030-101253.tar.gz
```

**Sidecar planifié** (`compose.backup.yml`, depuis `part3/tp04-compose-entreprise/solution`) :

```text
$ BACKUP_SCHEDULE="@every 1m" docker compose -f compose.yml -f compose.prod.yml \
    -f ../../tp05-donnees-persistance/compose.backup.yml up -d --wait backup
 Container shop-backup-1  Healthy
$ docker exec shop-backup-1 ls -l /backups/last
shop-20261030-091655.sql.gz
shop-20261030-091755.sql.gz
shop-20261030-091940.sql.gz
shop-latest.sql.gz -> shop-20261030-091940.sql.gz
```

## 3. Montée de version PostgreSQL 14 → 16

```text
$ # image postgres:16.4-alpine sur le volume de PostgreSQL 14
FATAL:  database files are incompatible with server
DETAIL:  The data directory was initialized by PostgreSQL version 14, which is not compatible with this version 16.4.
```

Le format des fichiers de données change à chaque version majeure. PostgreSQL 16 ne sait pas lire un
répertoire initialisé par la 14 : il faut un dump/restore ou `pg_upgrade`.

```text
$ ./upgrade-pg.sh
== 1. checksum on postgres (PostgreSQL) 14.13
before: 100000 eef45ba1f45b4b7ed8cf0307983c5f57
== 2. dumps
backups/upgrade-20261030-102033.dump           1593916
backups/upgrade-20261030-102033.dumpall.sql    5097472
== 3. stop PostgreSQL 14 (volume pgdata kept)
 Container shopdata-db-1  Stopped
== 4. PostgreSQL 16 on the new volume pgdata16
 Volume shopdata_pgdata16  Created
 Container shopdata-db-1  Healthy
postgres (PostgreSQL) 16.4
== 5. restore
== 6. checksum on PostgreSQL 16
after:  100000 eef45ba1f45b4b7ed8cf0307983c5f57
VERDICT: OK, identical data on PostgreSQL 16

$ docker volume ls | grep shopdata
shopdata_pgdata
shopdata_pgdata16
```

**Retour arrière** : le volume de PostgreSQL 14 n'a pas été modifié. Il suffit de relancer la stack sans la
surcharge (le script le fait seul si les checksums diffèrent) :

```text
$ docker compose -f starter/compose.yml up -d --wait
postgres (PostgreSQL) 14.13
100000 eef45ba1f45b4b7ed8cf0307983c5f57
```

Pour valider définitivement la 16 : mettre l'image et le volume `pgdata16` dans `starter/compose.yml`,
puis supprimer `shopdata_pgdata` après une période d'observation.

- **`pg_dumpall` / `pg_dump`** : `pg_dumpall` exporte tout le cluster en SQL, y compris les objets
  globaux (rôles, mots de passe, tablespaces) et toutes les bases. `pg_dump` exporte une seule base, au
  format custom `-Fc` compressé, restaurable sélectivement et en parallèle avec `pg_restore`, mais sans
  les rôles. Le script garde les deux : `-Fc` pour la restauration, `dumpall` pour les rôles.
- **Nouveau volume** : écraser l'ancien supprimerait le seul retour arrière. Avec deux volumes, la 14
  reste intacte et redémarrable en une commande tant que la 16 n'est pas validée.
- **Réduire l'indisponibilité** : ici, la base est indisponible de l'arrêt de la 14 à la fin du
  `pg_restore`, une durée proportionnelle au volume de données.
  - `pg_upgrade --link` dans un conteneur qui contient les deux binaires (`tianon/postgres-upgrade:14-to-16`)
    convertit le catalogue et crée des liens physiques vers les fichiers existants : quelques secondes
    quelle que soit la taille, mais sans retour arrière une fois la 16 démarrée (il faut donc copier le
    volume avant).
  - La réplication logique (publication sur la 14, abonnement sur la 16) synchronise la 16 pendant que la
    14 sert le trafic. La coupure se limite à la bascule de l'application.

## 4. Redis

- **`--save 60 1`** (RDB) : un snapshot complet au plus toutes les 60 s s'il y a eu au moins une
  écriture. En cas de crash, on perd jusqu'à 60 s d'écritures (plus la durée du snapshot en cours).
- **`--appendonly yes`** (AOF) : chaque écriture est ajoutée au journal, synchronisé sur disque toutes les
  secondes par défaut (`appendfsync everysec`). Perte maximale : environ 1 s d'écritures.

Dans la stack, Redis contient le **cache** `products` (TTL de 30 s, reconstruit depuis PostgreSQL) et la
**file** `orders:queue`. Le cache n'a pas besoin de persistance. La file en a besoin : une commande
enregistrée en base mais perdue dans Redis ne serait jamais confirmée par le worker. D'où
`--appendonly yes` dans le TP04, sur le volume `redisdata`.
