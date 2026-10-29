# TP07 — Observabilité : logs, métriques, alertes

## Contexte

Après l'incident du TP06, le post-mortem a conclu : « nous n'avons aucune visibilité ». Direction :
mettre en place pour la stack *Shop SAS* une observabilité **standard de marché**, en conteneurs, sans
toucher au code (l'API expose déjà `/metrics` et le worker `:9100`, et les deux loggent en JSON).

## Étapes

### 1. Les logs côté Docker 

Avec la stack du TP04 démarrée :

```bash
docker logs --since 5m --timestamps shop-api-1 | jq            # logs JSON structurés
docker inspect shop-api-1 --format '{{.HostConfig.LogConfig}}' # driver + options (rotation du TP04)
sudo ls -la /var/lib/docker/containers/$(docker inspect shop-api-1 -f '{{.Id}}')/   # le fichier json-file
docker run --rm --log-driver none alpine echo "pas loggé"     # et donc invisible à `docker logs`
```

Questions : que se passe-t-il **sans** `max-size` sur un serveur qui tourne 6 mois ? Pourquoi un conteneur
doit-il écrire sur stdout/stderr et pas dans un fichier ? Différence `json-file` / `local` / `journald` /
`fluentd` / `awslogs` ; `mode: non-blocking` et `max-buffer-size` : quel compromis ?

### 2. Métriques côté Docker 

`docker stats`, `docker system df -v`, `docker events --filter type=container --since 10m`,
`docker inspect --format '{{.State.OOMKilled}}'`. Limitez l'API à 64 Mo et chargez-la (`load.sh`) :
observez l'OOMKill et le redémarrage.

### 3. Stack d'observabilité 

Complétez `compose.observability.yml` (projet séparé, qui **rejoint** les réseaux `shop_front` / `shop_back`
déclarés `external`) avec :

- **Prometheus** : scrape de cAdvisor, de l'API via **découverte DNS** (`dns_sd_configs` sur `api` pour voir
  tous les réplicas), du worker. Pourquoi ne pas utiliser `docker_sd_configs` ? (indice : `docker exec prometheus id`) ;
- **cAdvisor** : métriques CPU/mémoire/réseau/IO par conteneur ;
- **Loki + Promtail** : collecte de **tous** les logs via la socket (`docker_sd_configs`), labels
  `service`/`project` à partir des labels compose, extraction du champ `level` du JSON ;
- **Grafana** : datasources et dashboard **provisionnés par fichiers** (aucun clic : reproductible),
  port 3001 ;
- **alertes** Prometheus : API down, > 5 % de 5xx, p95 > 500 ms, conteneur qui redémarre, mémoire > 90 % de la limite.

```bash
docker compose -f compose.observability.yml up -d
./load.sh 1000
open http://localhost:9090/targets  http://localhost:3001   (admin/admin)
```

Dans Grafana → Explore → Loki : `{service="api"} | json | level="50"` (erreurs pino) ;
`{service="worker"} |= "rejected"`. Dans Prometheus : `sum(rate(http_request_duration_seconds_count[1m])) by (status)`.

### 4. Exercice de corrélation

Le formateur injecte une panne (Redis arrêté, mot de passe BDD changé, limite mémoire abaissée…).
Trouvez-la en **moins de 5 minutes** uniquement avec Grafana (métriques + logs), puis vérifiez avec `docker`.

> **Livrables** : `compose.observability.yml`, configs Prometheus/Promtail, dashboard JSON, captures
> d'écran du dashboard sous charge et des alertes en état `firing`.

## Bonus

- **B1** : remplacez le json-file par le **driver Loki** (`docker plugin install grafana/loki-docker-driver`)
  ou par `fluent-bit` : avantages/inconvénients vs Promtail + socket.
- **B2** : ajoutez **Alertmanager** et une notification vers un webhook local (`docker run -p 8085 mendhak/http-https-echo`).
- **B3** : traces : instrumentez l'API avec OpenTelemetry (variables `OTEL_*`, auto-instrumentation Node)
  vers **Tempo** ou **Jaeger** en conteneur. Sans changer le code ? (`NODE_OPTIONS=--require @opentelemetry/auto-instrumentations-node/register`)
- **B4** : `docker compose top` et `docker stats --format` dans un script d'alerte minimal sans Prometheus.

