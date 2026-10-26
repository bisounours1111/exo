# TP03 — Registre privé et chaîne d'approvisionnement (supply chain)

**Niveau** : avancé · **Travail** : binôme

## Contexte

*Shop SAS* ne veut plus dépendre de Docker Hub : rate limits en CI, images publiques non maîtrisées,
et un incident récent (une image `latest` réécrite a cassé la prod un vendredi soir). La direction
sécurité exige en plus, pour toute image déployée : un **inventaire des composants (SBOM)**, un **scan de
vulnérabilités** bloquant et une **signature** vérifiable.

Vous devez livrer un registre privé **prêt pour l'entreprise** et la **porte de release** (`release-gate.sh`)
qui sera appelée par la CI (...dans un prochain TP).

## Étapes

### 1. Registre sécurisé 

Partez de `starter/registry/compose.yml` (un `registry:2` en HTTP sans auth). Faites-en un registre :

- **TLS** : CA interne + certificat serveur avec SAN `registry.local` (script `openssl`), déclaré côté
  client dans `/etc/docker/certs.d/registry.local:5000/ca.crt` (+ entrée `/etc/hosts`) ;
- **authentification** `htpasswd` (bcrypt) avec deux comptes : `ci` (push) et `dev` (pull) ;
- **persistance** dans un volume nommé, **suppression** activée (`storage.delete.enabled`) ;
- `healthcheck`, `restart: unless-stopped`, configuration via `config.yml` monté (pas 15 variables d'env) ;
- une **UI** de consultation (`joxit/docker-registry-ui`) ;
- un **mirror** Docker Hub (pull-through cache) sur le port 5001, et le daemon configuré pour l'utiliser
  (`"registry-mirrors": ["http://localhost:5001"]` dans `daemon.json`).

Validation :

```bash
curl -k https://registry.local:5000/v2/                         # 401
curl -k -u dev:dev-pull-2024 https://registry.local:5000/v2/_catalog
docker login registry.local:5000 -u ci
docker tag shopapi:1.4.2 registry.local:5000/shopapi:1.4.2 && docker push registry.local:5000/shopapi:1.4.2
docker pull alpine:3.20 && docker pull alpine:3.20            # 2e pull servi par le mirror : vérifiez les logs
```

> Question : `htpasswd` suffit-il en entreprise ? Que change un registre comme Harbor, Nexus, Artifactory,
> ECR/ACR/GAR (RBAC, scan intégré, réplication, quotas, immutabilité des tags) ?

### 2. Parler à l'API du registre

Sans client Docker, uniquement avec `curl` + `jq` :

- lister les dépôts, les tags d'un dépôt ;
- récupérer le **digest** d'un tag (en-tête `Docker-Content-Digest` sur un `HEAD /manifests/<tag>`,
  avec le bon `Accept`) ;
- supprimer un tag par digest, puis exécuter le `garbage-collect`. Que se passe-t-il si deux tags pointent
  sur le même manifeste ?
- écrivez `retention.sh` : garde les N tags les plus récents hors semver.

### 3. Politique de tags

Rédigez `TAGGING.md` : quels tags, lesquels sont immuables, pourquoi `latest` est interdit en prod,
comment référencer une image par **digest** dans un `compose.yml`. Retaguez sans pull avec
`skopeo copy` ou `crane tag` (depuis un conteneur si l'outil n'est pas installé).

### 4. SBOM, scan, signature

Installez ou utilisez en conteneur : `syft` (anchore/syft), `trivy` (aquasec/trivy), `cosign`
(ghcr.io/sigstore/cosign/cosign).

```bash
syft shopapi:1.4.2 -o spdx-json > sbom.json ; jq '.packages | length' sbom.json
trivy image --severity HIGH,CRITICAL --ignore-unfixed shopapi:1.4.2
trivy image --scanners secret shopapi:legacy                        # retrouve la clé AWS du TP01 ?
cosign generate-key-pair                                             # mot de passe vide pour le TP
cosign sign --key cosign.key registry.local:5000/shopapi:1.4.2
cosign verify --key cosign.pub registry.local:5000/shopapi:1.4.2 | jq
cosign attest --key cosign.key --type spdxjson --predicate sbom.json registry.local:5000/shopapi:1.4.2
```

Observez dans le registre ce que la signature a créé (`_catalog`, tags `sha256-...sig`).
Que se passe-t-il si vous retaguez puis re-pushez une image modifiée sous le même tag ? La signature
suit-elle le tag ou le digest ?

### 5. La porte de release

Complétez `release-gate.sh IMAGE [--push REGISTRY_IMAGE]` pour qu'il échoue (code ≠ 0) si :
labels OCI version/revision/source absents, utilisateur root, pas de `HEALTHCHECK`, CVE HIGH/CRITICAL
corrigeable, secret détecté. S'il passe : push, signature, attestation SBOM. Testez-le sur `shopapi:legacy`
(doit refuser) et `shopapi:1.4.2` (doit accepter).

## Bonus

- **B1** : scan **continu** : `trivy image --download-db-only` puis `trivy server` partagé par l'équipe.
- **B2** : signature **keyless** (Fulcio/Rekor) avec un compte GitHub : avantages/inconvénients vs clé.
- **B3** : *policy as code* : exigez la signature au `docker run` avec un plugin d'autorisation ou, plus
  simplement, un wrapper `verified-run.sh` qui appelle `cosign verify` avant `docker run`.
- **B4** : `trivy sbom sbom.json` : scanner le SBOM au lieu de l'image. Intérêt pour une CVE publiée
  6 mois après le build ?

