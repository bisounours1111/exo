# TP09 — CI/CD : de la pull request au déploiement sans interruption


## Contexte

*Shop SAS* déploie encore « à la main » : un ops se connecte en SSH, fait `git pull`, `docker compose up -d
--build` et croise les doigts. Résultat : 30 à 60 s d'indisponibilité à chaque mise en production, des
images jamais scannées, et personne ne sait quelle version tourne. Vous devez livrer :

1. un **pipeline** (GitHub Actions ou GitLab CI, au choix) qui construit, teste, scanne, signe et publie
   les images avec la politique de tags du TP03 ;
2. un **déploiement sans interruption** sur un hôte Docker distant via `docker context` ;
3. la **preuve mesurée** qu'il n'y a plus d'interruption.

## Étapes

### 1. Le dépôt 

Assemblez le dépôt `shop` (voir `starter/README-starter.md`) : applications, compose, release gate.

### 2. Le pipeline 

Sur **pull request** : hadolint, `docker compose config`, build de l'étape `test`, build de l'image (sans push).
Sur **main** : + push `sha-<sha>` sur le registre (GHCR ou GitLab Registry), scan trivy bloquant, signature
cosign **keyless** (OIDC), déploiement préprod automatique.
Sur **tag `v*`** : tags semver, déploiement prod avec **approbation manuelle** (`environment`), après
**vérification de la signature** côté déploiement.

Points techniques imposés : `docker/metadata-action` pour les tags et labels OCI ; cache `type=gha`
(ou registre) ; build **multi-arch** ; matrice api/worker ; secret de build pour le worker (pip.conf) ;
`provenance` + `sbom` activés.

Pas de compte GitHub/GitLab ? Utilisez `ci-local.sh` qui rejoue les mêmes étapes en local contre le
registre du TP03, et `act` (`nektos/act`) pour exécuter le workflow GitHub en conteneur.

### 3. Déploiement distant 

```bash
docker context create preprod --docker "host=ssh://deploy@preprod.local"
docker --context preprod ps
DOCKER_CONTEXT=preprod docker compose -f compose.yml -f compose.prod.yml up -d --wait
```

Pour le TP, l'« hôte distant » est une seconde VM, un collègue (clé SSH), ou… votre propre machine via
`ssh://localhost`. Quels prérequis côté serveur (utilisateur `deploy` dans le groupe docker, clé, `docker` installé,
`.env` et `secrets/` **présents sur le serveur** et non dans git) ? Comment les secrets arrivent-ils en prod ?

### 4. Zéro interruption 

Lancez `deploy/measure-downtime.sh` dans un terminal (100 req/s sur `/health`), puis dans un autre un
déploiement naïf : `docker compose up -d --force-recreate api`. Combien d'échecs ?

Écrivez `deploy/rolling-update.sh` : réplicas ≥ 2, Traefik ne route que vers les conteneurs **healthy**
(label `healthcheck` + `HEALTHCHECK` image + `start_period`), recréation **un réplica à la fois**, arrêt
propre (`stop -t 15`, l'API gère SIGTERM depuis le TP01). Mesurez à nouveau : objectif **0 échec**.

Expliquez le rôle de chaque brique : healthcheck image, `--wait`, `start_period`, SIGTERM, `stop_grace_period`,
réplicas, proxy. Que se passe-t-il si on retire l'une d'elles ?

### 5. Rollback 

`VERSION=<ancien sha> ./deploy/rolling-update.sh` : combien de temps ? Qu'est-ce qui rend le rollback
possible (tags immuables, images conservées sur l'hôte, base compatible) ? Et une migration de schéma
non rétro-compatible ?

> **Livrables** : workflow CI, `rolling-update.sh`, `measure-downtime.sh`, captures : pipeline vert,
> signature vérifiée, mesure naïve vs rolling (nombre d'échecs), rollback.

## Bonus

- **B1** : **Docker Swarm** (`compose.swarm.yml`) : `update_config` natif `start-first`, `rollback_config`.
  Comparez effort/robustesse avec le script. (Pas Kubernetes : Swarm est intégré au moteur Docker.)
- **B2** : déploiement **GitOps pull** : un conteneur `watchtower` ou un cron `compose pull && up -d`
  côté serveur. Avantages (pas d'accès SSH entrant) et risques (`latest`, pas de gate).
- **B3** : `docker compose publish` / artefact OCI du compose : versionner la stack elle-même dans le registre.
- **B4** : tests d'intégration en CI avec `docker compose up --wait` + `smoke-test.sh` + `compose down -v`
  dans le job, et Testcontainers côté code.
