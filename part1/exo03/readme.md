# Exercice Docker #3

Réaliser le déploiement d'un site web customisé via Docker:

- Ce site web doit être desservi via le serveur web NGINX
- Ce site web doit avoir une page d'accueil personnalisée (contenant par exemple un message du style "Hello World" ou "Exercice 03")
- Le site web doit être accessible dans l'ordinateur hôte via une adresse telle que http://localhost:8080 (par exemple)

## SOLUTION :

Fichier : `index.html` (page d'accueil personnalisée).

```bash
docker pull nginx
docker run -d --name site-exo03 -p 8080:80 -v "$(pwd)/index.html:/usr/share/nginx/html/index.html" nginx
docker ps
```

Puis ouvrir http://localhost:8080 dans le navigateur.
