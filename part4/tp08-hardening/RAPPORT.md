# TP08 — Durcissement

Livrables : `audit.sh`, `compose.hardened.yml` (surcharge de la stack du TP04), `daemon.json`.

```bash
cd part3/tp04-compose-entreprise/solution
docker compose -f compose.yml -f ../../../part4/tp08-hardening/compose.hardened.yml up -d --wait
./smoke-test.sh
../../../part4/tp08-hardening/audit.sh '^shop-(api|worker|db|redis|traefik)-'
```

## 1. Mesure

`audit.sh` sur la stack du TP04 (`compose.yml` + `compose.prod.yml`) : **14 écarts**, code retour 1.

```text
CONTAINER                  USER         PRIV  CAP_DROP       CAP_ADD   RO    MEM       PIDS  NNP    SOCKET
shop-api-1                 1000:1000    false ALL            -         true  256M      none  yes    no
    ! no pids limit
shop-api-2                 1000:1000    false ALL            -         true  256M      none  yes    no
    ! no pids limit
shop-db-1                  root         false -              -         false 512M      none  yes    no
    ! runs as root
    ! capabilities not dropped
    ! writable rootfs
    ! no pids limit
shop-redis-1               root         false -              -         false 128M      none  yes    no
    ! runs as root
    ! capabilities not dropped
    ! writable rootfs
    ! no pids limit
shop-traefik-1             root         false ALL            -         true  128M      none  yes    yes
    ! runs as root
    ! no pids limit
    ! docker socket mounted
shop-worker-1              10001:10001  false ALL            -         true  128M      none  yes    no
    ! no pids limit
deviations: 14
```

`docker/docker-bench-security` : **Checks: 105, Score: 1** (toute la VM Docker Desktop est auditée, y
compris les conteneurs d'autres projets). Les 5 `WARN` prioritaires :

| Contrôle | Pourquoi |
|----------|----------|
| 5.31 Docker socket mounted (`shop-traefik-1`, `observability-promtail-1`) | La socket donne le contrôle root de l'hôte |
| 5.12 Root filesystem not read only | Un attaquant peut modifier binaires et configuration |
| 5.28 PIDs cgroup limit | Une fork bomb peut saturer l'hôte |
| 5.10 Memory usage not limited | Un conteneur peut provoquer l'OOM de l'hôte |
| 2.18 / 5.25 No new privileges | Un binaire setuid permet de redevenir root |

## 2. Expériences

| Mesure | Expérience | Résultat |
|--------|-----------|----------|
| `--read-only` | `touch /x` | `touch: /x: Read-only file system` (exit 1) |
| `--read-only --tmpfs /tmp` | `touch /tmp/x` | OK |
| `--cap-drop ALL` | `ping -c1 1.1.1.1` | OK : Docker autorise les sockets ICMP non privilégiés (`net.ipv4.ping_group_range`), `NET_RAW` n'est pas nécessaire |
| `--cap-drop ALL` | `chown 1000 /tmp` | `Operation not permitted` ; OK avec `--cap-add CHOWN` |
| `--cap-drop ALL` | `apk add curl` | OK : les fichiers installés restent à root, aucun `chown` n'est nécessaire. Un paquet qui crée un utilisateur ou change un propriétaire demande `CHOWN`, `FOWNER`, `DAC_OVERRIDE` |
| `no-new-privileges` | copie setuid de `id` lancée en uid 1000 | sans : `uid=1000 gid=1000 euid=0(root)` ; avec : `uid=1000 gid=1000` |
| `--pids-limit 50` | 100 `sleep &` | `sh: can't fork: Resource temporarily unavailable` |
| `--memory 32m` | `python -c "x='a'*100_000_000"` | `OOMKilled: true exit=137` |
| `--user 1000` | `id` | `uid=1000 gid=0(root)` |
| `--user 1000` + volume | écriture dans un fichier créé par root | `can't create /data/f: Permission denied` : les fichiers du volume doivent appartenir à l'uid du conteneur |
| seccomp par défaut | `unshare --user id` | `unshare(0x10000000): Operation not permitted` ; avec `seccomp=unconfined` : OK. Le profil par défaut bloque environ 44 appels système sur plus de 300 |

Capacités de PostgreSQL, trouvées par essai et lecture des logs (`--cap-drop ALL` puis ajouts) :

| Démarrage | Résultat |
|-----------|----------|
| root, aucune capacité | `chmod: /var/lib/postgresql/data: Operation not permitted`, arrêt |
| root + `CHOWN SETUID SETGID` | démarre, `chmod ... Operation not permitted` dans les logs |
| root + `CHOWN SETUID SETGID FOWNER DAC_OVERRIDE` | `ready to accept connections` |
| `user: 70:70`, aucune capacité, `read_only` | `ready to accept connections` |

Démarré directement avec l'utilisateur `postgres`, l'entrypoint n'a plus besoin de changer les
propriétaires ni de quitter root : aucune capacité. Même principe pour Traefik : sans la socket, il tourne
en `nobody` sans capacité. Le port 80 reste accessible car Docker fixe `ip_unprivileged_port_start=0` dans
le namespace réseau du conteneur (sinon `NET_BIND_SERVICE`).

## 3. Stack durcie

`compose.hardened.yml` : `read_only` + `tmpfs`, `cap_drop: [ALL]` sans `cap_add`, `no-new-privileges`,
limites CPU/mémoire/PIDs, PostgreSQL (uid 70), Redis (uid 999) et Traefik (uid 65534) non-root. Traefik
lit l'API Docker via `tecnativa/docker-socket-proxy` (GET sur `containers`, `events`, `version`, `ping`
uniquement), sur le réseau `internal` `socket` : le proxy est le seul conteneur qui monte la socket.

```text
$ docker compose -f compose.yml -f compose.hardened.yml up -d --wait && ./smoke-test.sh
X-Cache: HIT
status: confirmed
OK

$ ./audit.sh '^shop-(api|worker|db|redis|traefik)-'
CONTAINER                  USER         PRIV  CAP_DROP       CAP_ADD   RO    MEM       PIDS  NNP    SOCKET
shop-api-1                 1000:1000    false ALL            -         true  256M      100   yes    no
shop-db-1                  70:70        false ALL            -         true  512M      100   yes    no
shop-redis-1               999:1000     false ALL            -         true  128M      50    yes    no
shop-traefik-1             65534:65534  false ALL            -         true  128M      100   yes    no
shop-worker-1              10001:10001  false ALL            -         true  128M      50    yes    no
deviations: 0
```

## 4. `daemon.json`

| Option | Effet |
|--------|-------|
| `no-new-privileges` | Appliqué à tous les conteneurs, même ceux lancés sans l'option |
| `icc: false` | Les conteneurs du bridge par défaut ne communiquent plus entre eux |
| `live-restore` | Les conteneurs continuent de tourner pendant un redémarrage ou une mise à jour du daemon |
| `userland-proxy: false` | Publication des ports par iptables, sans processus `docker-proxy` par port |
| `log-opts` | Rotation des logs par défaut (30 Mo max par conteneur) |
| `userns-remap: default` | root dans le conteneur correspond à un uid non privilégié de l'hôte (utilisateur `dockremap`) |

- **`icc: false`** ne concerne que le bridge par défaut (`docker0`). Les réseaux créés par Compose
  (`shop_front`, `shop_back`) ne sont pas affectés : la stack continue de fonctionner. Les conteneurs
  lancés par `docker run` sans `--network` ne peuvent plus se joindre, sauf par ports publiés.
- **`userns-remap`** décale tous les uid : les fichiers des volumes existants, créés par l'uid 70 ou 999
  de l'hôte, apparaissent comme `nobody` dans les conteneurs, qui ne peuvent plus y écrire. Il faut
  migrer les volumes (`chown` vers la plage subordonnée, ex. 100070) ou les recréer depuis une
  sauvegarde. Les images et conteneurs existants sont aussi masqués (nouveau répertoire
  `/var/lib/docker/<uid>.<gid>`), et `--privileged` ou `--pid host` demandent `--userns=host`.
