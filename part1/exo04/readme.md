# Exercice Docker #4

Réaliser, via Docker, le déploiement de deux conteneurs pouvant communiquer entre eux:

- Pour cela, vous créerez dans un premier temps un réseau qui sera utilisé par les deux conteneurs
- Vous créerez ensuite un conteneur sur lequel vous devrez installer la commande servant à la réalisation du ping
- Sauvegardez ensuite l'image issue de cette installation pour pouvoir créer un second conteneur directement pourvu de ping
- Vérifier / connecter les deux conteneurs au même réseau virtuel
- Dans chacun des conteneur, vérifier la capacité de communiquer avec son voisin via le nom du conteneur (tester la résolution DNS interne à Docker)

## SOLUTION :

```bash
docker compose up --build
```
