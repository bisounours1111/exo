Point de départ : un dépôt git contenant `apps/shopapi`, `apps/shop-worker` (TP01/02), la stack compose
(TP04) et `release-gate.sh` (TP03). Créez-le :

    mkdir shop && cd shop && git init
    cp -r ../../jour2-run/tp04-compose-entreprise/solution/* .
    cp ../../jour1-images/tp03-registry-supply-chain/solution/scripts/release-gate.sh .
    git add -A && git commit -m "import"

Puis poussez-le sur GitHub (ou GitLab) pour la partie CI, ou utilisez `ci-local.sh` pour simuler le pipeline.
