# Exercice Docker #1

Réaliser une image de conteneur compatible avec NGINX (serveur web):

Pour cela, suivre les étapes suivantes:

- Créer un conteneur Ubuntu
- Entrer dans le conteneur Ubuntu
- Mettre à jour les paquets dans le conteneur
- Installer NGINX dans le conteneur
- Sortir du conteneur
- Sauvegarder l'état actuel du conteneur en tant que nouvelle image nommée par exemple "ubuntu-nginx"

## SOLUTION :

```bash
docker run -it --name ubuntu-exo01 ubuntu:22.04 bash
apt-get update
apt-get install -y nginx
exit
docker commit ubuntu-exo01 ubuntu-nginx
docker images ubuntu-nginx
```
