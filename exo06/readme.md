# Exercice Docker #6

Via Docker, créer un conteneur utilitaire basé sur une image d'un serveur web.

Ce conteneur aura pour but de permettre le développement d'un site internet sans avoir à installer localement de dépendances ou de librairies.

Il sera possible, via un dossier placé sur notre ordinateur, de coder directement un site web desservi par NGINX (qui lui sera exécuté dans un conteneur).

Pour cela, il vous faudra utiliser un type de volume (via l'option de lancement `-v`).

## SOLUTION :

```bash
docker compose up -d
```

Ouvrir http://localhost:8080, modifier `site/index.html`, puis rafraîchir la page.
