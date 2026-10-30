# TP08 — Durcir les conteneurs pour la production


## Contexte

L'équipe sécurité de *Shop SAS* a passé la stack au **CIS Docker Benchmark** : 23 écarts. Trois sont
jugés critiques : des conteneurs applicatifs en root, la socket Docker montée dans Traefik (équivalent
root sur l'hôte), aucune limite de ressources. Vous devez livrer une configuration durcie **qui
fonctionne** (une mesure qui casse l'app sera désactivée par l'astreinte et ne reviendra jamais), et un
outil d'audit rejouable.

## Étapes

### 1. Mesurer 

Écrivez `audit.sh` : pour chaque conteneur en cours d'exécution, affiche utilisateur, `Privileged`,
capabilities ajoutées/retirées, rootfs read-only, limite mémoire, `PidsLimit`, `no-new-privileges`,
montage de la socket. Code retour ≠ 0 si écart. Lancez-le sur la stack du TP04 : combien d'écarts ?

Lancez aussi la référence du marché :

```bash
docker run --rm --net host --pid host --userns host --cap-add audit_control \
  -v /etc:/etc:ro -v /var/lib:/var/lib:ro -v /var/run/docker.sock:/var/run/docker.sock:ro \
  docker/docker-bench-security
```

Notez le score et les 5 `WARN` qui vous semblent prioritaires. (Sous Docker Desktop, certaines sections
ne s'appliquent pas : la VM n'est pas votre hôte.)

### 2. Comprendre chaque mesure 

Pour chacune, faites une **expérience** qui montre ce qu'elle change, sur un conteneur `alpine` jetable :

| Mesure | Expérience |
|--------|-----------|
| `--read-only` | `touch /x` échoue ; `--tmpfs /tmp` → `touch /tmp/x` OK |
| `--cap-drop ALL` | `ping 1.1.1.1` (NET_RAW), `chown` (CHOWN), `apk add` : que faut-il réajouter et pourquoi ? |
| `--security-opt no-new-privileges` | `docker run --rm alpine ls -l /bin/busybox` puis un binaire setuid : `passwd` ne peut plus élever |
| `--pids-limit 50` | `sh -c 'for i in $(seq 100); do sleep 60 & done; sleep 1; ps \| wc -l'` |
| `--memory 32m` | `python -c "x='a'*100_000_000"` → `OOMKilled: true` |
| `--user 1000` | `docker run --user 1000 alpine id` ; conséquence sur les volumes montés (droits) |
| seccomp | `docker run --rm alpine unshare --user` vs `--security-opt seccomp=unconfined` : combien de syscalls le profil par défaut bloque-t-il ? |

### 3. Durcir la stack 

Écrivez `compose.hardened.yml` (surcharge de la stack TP04) : `read_only` + `tmpfs` ciblés,
`cap_drop: [ALL]` + `cap_add` **minimal justifié** par service (PostgreSQL et Traefik en ont besoin : lesquels ?
trouvez-les par essai/erreur et lecture des logs), `no-new-privileges`, `pids_limit`, limites CPU/mémoire,
Redis en utilisateur non-root, et surtout : **retirez la socket Docker de Traefik** au profit d'un
**proxy de socket** (`tecnativa/docker-socket-proxy`) en lecture seule sur un réseau `internal`.

Validez : `docker compose -f compose.yml -f compose.hardened.yml up -d --wait`, smoke test du TP04 **vert**,
`audit.sh` **sans écart** sur les services applicatifs.

### 4. Côté daemon 

Proposez un `daemon.json` : `no-new-privileges`, `icc: false`, `live-restore`, logs rotatifs, `userns-remap`
ou **rootless**. Quels effets de bord d'`icc: false` sur la stack (réseau bridge par défaut uniquement) et de
`userns-remap` sur les volumes existants (propriétaire des fichiers) ?

> **Livrables** : `audit.sh`, `compose.hardened.yml` commenté (menace réduite par directive), tableau des
> expériences, `daemon.json` justifié, sortie `audit.sh` avant/après.

## Bonus

- **B1** : profil **seccomp personnalisé** pour l'API : partez du profil par défaut, générez la liste des
  syscalls réellement utilisés (`strace -f -c` dans un conteneur de test, ou `docker-slim`), restreignez.
- **B2** : exécutez la stack en **Docker rootless** (ou podman rootless) : qu'est-ce qui ne marche plus
  (ports < 1024, cAdvisor, performances réseau) et comment contourner ?
- **B3** : image `distroless` pour l'API (lien TP01) + `docker scout cves` / `docker scout recommendations`.
- **B4** : AppArmor : profil `docker-default` vs profil dédié qui interdit l'écriture hors `/tmp`.

