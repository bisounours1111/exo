# TP06 — Réseau Docker et dépannage : incident P1 en préprod


## Contexte

Il est 9h12. La préprod *Shop SAS* ne répond plus depuis qu'un collègue a « rangé le compose » avant de
partir en congé. Vous êtes d'astreinte. Le `compose.yml` et la conf nginx sont dans `starter/`.
Règles du jeu :

- vous **ne modifiez pas le code applicatif** ni l'image ;
- vous remplissez le **rapport d'incident** (`INCIDENT-TEMPLATE.md`) au fil de l'eau : chaque hypothèse,
  la commande qui l'a confirmée ou infirmée ;
- la stack contient **au moins 10 anomalies**. Objectif : `curl localhost:8081/products` renvoie le catalogue
  avec `X-Cache: HIT` au second appel, et `docker compose ps` affiche tout `healthy`.

## Partie 1 — Rappels express réseau 

```bash
docker network ls ; docker network inspect bridge
docker run -d --name a alpine sleep 1d ; docker run -d --name b alpine sleep 1d
docker exec a ping -c1 b        # échoue : pas de DNS sur le bridge par défaut
docker network create demo && docker network connect demo a && docker network connect demo b
docker exec a ping -c1 b        # OK : DNS embarqué (127.0.0.11)
docker exec a cat /etc/resolv.conf
docker run --rm --network container:a nicolaka/netshoot ss -tlnp     # partager la pile réseau d'un conteneur
```

Notions à maîtriser : bridge par défaut vs réseau utilisateur, DNS embarqué et alias, `internal`, `host`,
`none`, `container:` ; publication de port (`-p`) = règle DNAT côté hôte ; `expose` n'ouvre rien.

## Partie 2 — Résolution de l'incident 

Boîte à outils recommandée :

| Besoin | Commande |
|--------|----------|
| État et santé | `docker compose ps`, `docker inspect X --format '{{json .State.Health}}' \| jq` |
| Logs | `docker compose logs -f --tail 50 api`, `docker events --since 5m` |
| Config résolue | `docker compose config` (variables interpolées, erreurs de schéma) |
| Réseau d'un conteneur | `docker inspect X --format '{{json .NetworkSettings.Networks}}' \| jq` |
| Qui est sur un réseau | `docker network inspect incident_backend --format '{{range .Containers}}{{.Name}} {{end}}'` |
| DNS depuis un conteneur | `docker exec X getent hosts db` / `nslookup db 127.0.0.11` |
| Ports écoutés | `docker exec X ss -tlnp` (ou `netstat -tln`) |
| Sidecar de debug (sans rien installer dans l'image) | `docker run --rm -it --network container:X nicolaka/netshoot` puis `curl`, `tcpdump -i eth0 port 5432`, `dig`, `ss` |
| Processus / fichiers | `docker top X`, `docker diff X`, `docker exec X ls -la /etc/nginx/conf.d` |

Marche à suivre conseillée : partir du **symptôme utilisateur** (le port 8081) et remonter la chaîne
front → api → db/redis, une couche à la fois. À chaque étape : *qu'est-ce que j'attends ? qu'est-ce que j'observe ?*

## Partie 3 — Post-mortem 

Complétez le rapport : classez les anomalies (réseau / configuration / cycle de vie / stockage / sécurité),
puis proposez **3 garde-fous** qui auraient évité l'incident (ex. : `docker compose config` + smoke test
en CI, revue de code du compose, healthchecks + `--wait`, lint de compose).

> **Livrables** : `compose.yml` et `default.conf` corrigés, rapport d'incident complété.

## Bonus

- **B1** : capturez avec `tcpdump` (netshoot, `--network container:api`) l'échange API → PostgreSQL et
  montrez la requête `SELECT` en clair. Conclusion sur le chiffrement intra-réseau ?
- **B2** : ajoutez un alias réseau (`networks: backend: aliases: [database]`) et faites pointer l'API dessus.
  Intérêt pour une bascule de base sans toucher l'application ?
- **B3** : `driver_opts` du bridge : `com.docker.network.bridge.enable_icc=false`. Que se passe-t-il ?
- **B4** : reproduisez un conflit de sous-réseau avec le VPN d'entreprise (`default-address-pools` dans `daemon.json`).

