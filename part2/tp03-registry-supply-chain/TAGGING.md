# Politique de tags Shop SAS

S'applique à toutes les images poussées sur `registry.local:5000`. Le tag sert aux humains ; ce qu'on
déploie, c'est un **digest**.

## Tags produits

| Tag | Exemple | Produit par | Mutable ? | Usage |
|-----|---------|-------------|-----------|-------|
| `X.Y.Z` (semver) | `1.4.2` | CI, sur un tag git `vX.Y.Z` après `release-gate.sh` | **Non, jamais réécrit** | Releases, référence pour la prod |
| `X.Y.Z-<sha>` | `1.4.2-c8a8df5` | CI, même build que `X.Y.Z` | **Non** | Lien direct version ↔ commit |
| `sha-<sha>` | `sha-c8a8df5` | CI, chaque commit sur `main` | **Non** | Tester un commit précis en recette |
| `X.Y`, `X` | `1.4`, `1` | CI, à chaque release | Oui, suit la dernière patch ou mineure | Environnements de dev, jamais en prod |
| `main` | `main` | CI, chaque commit sur `main` | Oui | Environnement d'intégration |
| `pr-<n>` | `pr-12` | CI, chaque push sur une PR | Oui | Environnements éphémères de revue |
| `latest` | — | **Interdit** | — | Refusé par `release-gate.sh` |

Règles :

- **Semver strict** : `MAJOR.MINOR.PATCH` avec un pré-release optionnel (`2.0.0-rc.1`). La version vient
  du tag git, et le label OCI `org.opencontainers.image.version` doit avoir la même valeur.
- **Immuable** veut dire : une fois poussé, le tag ne pointe jamais vers un autre digest. Une correction
  donne une nouvelle version (`1.4.3`), jamais un re-push de `1.4.2`.
- **Rétention** : les tags semver sont gardés indéfiniment. `main`, `sha-*` et `pr-*` sont purgés par
  `retention.sh <repo> <N> --apply`, qui garde les N plus récents, puis par le garbage-collect du
  registre.

## Comment l'immutabilité est garantie ici

`registry:3` n'a pas de notion de tag immuable : tout compte qui peut pousser peut réécrire un tag.
Dans ce TP :

1. seul le compte `ci` peut pousser (règle RBAC de la gateway nginx ; `dev` reçoit un 403) ;
2. `release-gate.sh` refuse de pousser un tag semver qui existe déjà dans le registre (`HEAD` sur le
   manifeste avant le push).

Un registre d'entreprise le fait côté serveur, quel que soit le client : règles d'immutabilité de Harbor,
`imageTagMutability: IMMUTABLE` sur ECR, verrouillage des tags sur ACR (`az acr repository update
--write-enabled false`), *immutable tags* sur GAR.

## Pourquoi `latest` est interdit en production

- **Il ne veut rien dire** : `latest` est seulement le tag par défaut quand on n'en précise pas. Ce n'est
  pas « la dernière version stable », c'est le dernier `docker push` sans tag, quel qu'il soit.
- **Il change sous vos pieds** : deux nœuds qui tirent `latest` à une heure d'écart peuvent exécuter deux
  versions différentes. C'est l'incident du vendredi soir : l'image a été réécrite et les nœuds qui ont
  redémarré ont pris la nouvelle.
- **Pas de retour arrière** : pour revenir à « l'ancien `latest` », il faut connaître son digest, que
  personne n'a noté.
- **Caches incohérents** : avec `imagePullPolicy: IfNotPresent`, un nœud garde l'ancien `latest` en cache
  pendant qu'un autre tire le nouveau. Kubernetes passe d'ailleurs par défaut en `Always` quand le tag est
  `latest`, signe que ce tag n'est pas fiable.
- **Aucune traçabilité** : impossible de répondre à « quelle version tourne en prod ? » ou « ce correctif
  CVE est-il déployé ? ».

## Référencer une image par digest dans `compose.yml`

```yaml
services:
  api:
    # Le tag est purement indicatif ; Docker tire le digest, et rien d'autre.
    image: registry.local:5000/shopapi:1.4.2@sha256:ededab27c481e207fded7f033864e40e9520ce5f7c9ca89e3a7df8c8bf048e62
```

- Pour une image multi-architecture, utiliser le digest de l'**index** (celui que renvoie
  `crane digest` ou l'en-tête `Docker-Content-Digest`), pas celui d'une plateforme : chaque nœud choisit
  ensuite son architecture.
- Récupérer le digest sans tirer l'image :
  `crane digest registry.local:5000/shopapi:1.4.2` ou
  `docker buildx imagetools inspect registry.local:5000/shopapi:1.4.2 --format '{{json .Manifest.Digest}}'`.
- Attention : quand un digest est présent, **le tag est ignoré**. Testé :
  `docker pull localhost:5000/shopapi:9.9.9@sha256:ededab…` réussit alors que `9.9.9` n'existe pas. Le tag
  peut donc mentir ; la CI doit écrire le couple tag + digest à partir d'une seule source (la sortie de
  `release-gate.sh`).
- Un digest inconnu échoue franchement : `failed to resolve reference ... not found`.
- Mettre à jour une version, c'est changer le digest dans un commit : la montée de version est revue,
  versionnée et réversible avec `git revert`.

## Retaguer sans pull

Un retag n'est qu'un nouveau `PUT` du même manifeste sous un autre nom ; les couches ne transitent pas.

```bash
. ./tools.sh                                   # crane / skopeo en conteneur si non installés
crane tag  registry.local:5000/shopapi:1.4.2 1.4
crane tag  registry.local:5000/shopapi:1.4.2 1
skopeo copy --all --preserve-digests \
  docker://registry.local:5000/shopapi:1.4.2 docker://registry.local:5000/shopapi:1.4.2-c8a8df5
crane digest registry.local:5000/shopapi:1.4      # même digest que 1.4.2
```

Résultat mesuré dans les logs de la gateway : uniquement des `HEAD` sur les blobs (vérification de
présence), des `GET` du manifeste et de la config, et un `PUT /v2/shopapi/manifests/<tag>` par nouveau
tag. Aucun `POST` ni `PATCH` d'upload de couche.

Même principe pour une **promotion** entre registres (recette → prod) :
`crane copy registry.local:5000/shopapi@sha256:… prod-registry:5000/shopapi:1.4.2`. On copie le digest
qui a été validé, pas un tag qui aurait pu bouger entre-temps.
