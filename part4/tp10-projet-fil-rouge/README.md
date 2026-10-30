# TP10 — Projet fil rouge : conteneuriser et industrialiser un monolithe legacy


## Contexte

*Shop SAS* a racheté un petit concurrent qui gère son inventaire avec **GestStock**, une application PHP
installée à la main sur un serveur Debian unique depuis 2017 (voir `legacy-app/INSTALL-LEGACY.md` et le code dans
`legacy-app/geststock`). Le serveur doit être décommissionné dans un mois. Votre mission : **livrer GestStock
sous forme de stack conteneurisée prête pour la production**, en appliquant tout ce que vous avez vu pendant
les trois jours.

Contraintes métier :

- le code PHP peut être **modifié à la marge** (configuration par variables d'environnement, logs), mais pas réécrit ;
- les photos déjà uploadées et la base existante doivent être **migrées** (on vous fournit `schema.sql` ; simulez
  des données existantes) ;
- le rapport quotidien doit continuer à partir (et on doit pouvoir le **tester** sans attendre 6h du matin) ;
- l'appli doit passer de PHP 7.3 à **PHP 8.3** ;
- **zéro mot de passe dans git**, **zéro root**, **zéro interruption** lors des mises à jour.

## Livrables attendus

Un dépôt git `geststock-docker` contenant :

| # | Livrable | Compétences mobilisées |
|---|----------|------------------------|
| 1 | `Dockerfile` de l'application : multi-stage (si composer/assets), image officielle `php:8.3-apache` ou `php-fpm` + nginx, non-root, `HEALTHCHECK` (endpoint `?health`), labels OCI, config PHP de prod (`display_errors=Off`, limites d'upload), `.dockerignore` | TP01, TP02 |
| 2 | Gestion des **logs** : l'application doit logger sur **stdout/stderr** (adapter `app_log`) et Apache aussi | TP07 |
| 3 | **Configuration par environnement** : `config.php` lit `getenv()` avec valeurs par défaut ; mot de passe BDD via **secret fichier** (`DB_PASS_FILE`) | TP04 |
| 4 | `compose.yml` + `compose.override.yml` (dev) + `compose.prod.yml` : MariaDB/MySQL épinglé avec volume + init `schema.sql`, volume **uploads** partagé, réseaux segmentés, healthchecks, `depends_on` conditionnel, reverse proxy Traefik, limites, logs rotatifs | TP04 |
| 5 | **Cron** : le rapport quotidien tourne dans un conteneur dédié (image `supercronic` ou un service `ofelia`, ou `docker compose run rapport` déclenché par un cron hôte) ; l'envoi de mail passe par un conteneur **MailHog/Mailpit** en dev (variable `SMTP_HOST`) ; le rapport est **testable à la demande** | TP04 |
| 6 | **Données** : script de **migration** depuis le legacy (import dump SQL + copie des uploads dans le volume), `backup.sh` / `restore.sh` testés, procédure de **restauration** documentée | TP05 |
| 7 | **Observabilité** : la stack rejoint l'observabilité du TP07 (logs dans Loki, métriques cAdvisor) ; bonus : exporter MySQL | TP07 |
| 8 | **Sécurité** : `compose.hardened.yml` (read-only, cap_drop, no-new-privileges, limites), `audit.sh` sans écart, image qui passe `release-gate.sh` (scan + SBOM + signature) | TP03, TP08 |
| 9 | **CI/CD** : pipeline (GitHub/GitLab ou `ci-local.sh`) build → test (au moins un test : `php -l` + un `curl` sur la stack démarrée en CI) → gate → push → déploiement rolling | TP09 |
| 10 | `RUNBOOK.md` : démarrer, mettre à jour, revenir en arrière, sauvegarder/restaurer, diagnostiquer (où sont les logs, les métriques), rotation des secrets | TP06 |



## Ce qui est volontairement laissé à votre jugement

- Apache intégré (`php:8.3-apache`) vs nginx + php-fpm (deux conteneurs) : argumentez.
- Cron : `supercronic` dans un conteneur dédié avec la même image, `ofelia` pilotant par labels, ou cron hôte :
  argumentez (simplicité, observabilité, sécurité).
- Où mettre le volume uploads en prod (volume local, NFS, S3 via proxy) : argumentez.
