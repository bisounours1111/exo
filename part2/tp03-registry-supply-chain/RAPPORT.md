# TP03 — Réponses aux questions

Réalisé :

- **registre** `registry:3.1.2` derrière une gateway nginx : TLS (CA interne, SAN `registry.local`),
  authentification bcrypt et droits par compte (`ci` pousse, `dev` ne fait que `GET`/`HEAD`). S'y
  ajoutent un volume persistant, la suppression activée, des healthchecks, l'UI joxit et un mirror
  Docker Hub sur le port 5001 ;
- **`retention.sh`**, **`TAGGING.md`**, **`release-gate.sh`** et les bonus B1 à B4 ;
- **image `shopapi`** : npm et yarn sont retirés de l'étape `runtime` et OpenSSL est mis à jour, ce qui
  donne 0 CVE HIGH/CRITICAL corrigeable.

## 1. `htpasswd` suffit-il en entreprise ?

Non :
- il n'y a pas d'autorisation par dépôt : tout compte valide peut pousser ou supprimer ;
- il n'y a ni SSO, ni LDAP, ni MFA ;
- il n'y a pas d'audit ;
- les mots de passe sont statiques et partagés.

Harbor, Nexus, Artifactory et ECR/ACR/GAR apportent le RBAC par projet, le SSO, le scan intégré (avec
blocage du pull), la réplication, les quotas, l'immutabilité des tags et la rétention planifiée.

## 2. Deux tags sur le même manifeste

Un tag n'est qu'un pointeur vers un digest. Supprimer par digest supprime le manifeste, donc **tous** les
tags qui pointent dessus : `release-a` et `release-b` disparaissent ensemble.

Le `DELETE` ne libère aucun espace : c'est le `garbage-collect` qui supprime ensuite les blobs orphelins.
`registry:3` permet aussi de supprimer un tag seul (`DELETE /manifests/<tag>`), et c'est ce
qu'utilise `retention.sh`.

## 4. La signature suit-elle le tag ou le digest ?

Le **digest**. La signature est stockée sous le tag `sha256-<digest>.sig`, l'attestation sous `.att`, et
aucun nouveau dépôt n'apparaît dans `_catalog`. Si on re-pousse une image modifiée sous le même tag,
`cosign verify` sur ce tag répond `no signatures found`, alors que l'ancien digest reste vérifiable.

Le scan de secrets de trivy retrouve la clé AWS de `/app/.env` dans `shopapi:legacy`.

## Bonus

- **B1** : `starter/scanner/compose.yml` télécharge la base une fois, puis lance un `trivy server`
  protégé par token. Toute l'équipe utilise la même base à jour, et les runners n'ont plus à la
  télécharger.
- **B2 (clé ou keyless)** :
  - avantages du keyless : aucune clé à protéger, on vérifie une identité (workflow, dépôt, tag) et la
    signature est inscrite dans un journal public horodaté ;
  - inconvénients : il faut que Fulcio, Rekor et le fournisseur d'identité soient joignables, et le nom et
    le digest de l'image sont publiés, ce qui gêne pour un registre interne.
- **B3** : `verified-run.sh` vérifie la signature avec `cosign.pub`, puis lance l'image par digest. Une
  image non signée ou re-poussée est refusée. En production, cette règle se place dans un contrôleur
  d'admission (Kyverno, policy-controller).
- **B4** : le SBOM est l'inventaire figé de ce qui a été livré. Pour une CVE publiée 6 mois plus tard, on
  le rescanne contre la base du jour en une seconde, sans retirer l'image. Il faut le générer au format
  lu par le scanner : un SBOM produit par trivy est relu sans perte par `trivy sbom`.
