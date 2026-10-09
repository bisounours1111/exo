# Exercice Docker #2

Déployer, au moyen de Docker, une image du jeu 2048:

- Trouver dans le registre d'images de conteneur public DockerHub, une image compatible du jeu 2048
- Récupérer l'image localement
- Lancer un conteneur basé sur l'image de l'application (faire en sorte que celle-ci soit disponible au port hôte 8080, ou 8090 si non disponible)
- Naviguer, via le navigateur de l'ordinateur (pas via le conteneur) vers http://localhost:8080 et faire en sorte de voir l'application

## SOLUTION :

```bash
docker search 2048
docker pull evilroot/docker-2048
docker run -d --name jeu-2048 -p 8080:80 evilroot/docker-2048
docker ps
```
