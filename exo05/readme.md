# Exercice Docker #5 — MySQL et Adminer

## Objectif

Déployer une base de données MySQL et une interface d'administration web (Adminer) à l'aide de Docker, en utilisant deux conteneurs distincts.

## Travail demandé

1. Créer un réseau Docker dédié à l'exercice.
2. Déployer un conteneur **MySQL** avec une base de données et un utilisateur dédiés.
3. Déployer un conteneur **Adminer** permettant d'administrer MySQL depuis un navigateur.
4. Faire communiquer les deux conteneurs via le réseau Docker.
5. Se connecter à MySQL depuis Adminer, créer une table et y insérer quelques enregistrements.

## Contraintes

- Les conteneurs doivent communiquer par leur nom, sans adresse IP fixe.
- Les données MySQL doivent être conservées même après la suppression et la recréation du conteneur.
- Les conteneurs doivent redémarrer automatiquement en cas d'arrêt inattendu ou de redémarrage de Docker.
- Seule l'interface Adminer doit être accessible depuis la machine hôte.

## Vérifications

- Consulter les enregistrements depuis Adminer.
- Supprimer puis recréer le conteneur MySQL.
- Vérifier que la table et ses enregistrements sont toujours présents.
- Simuler une panne d'un conteneur et vérifier son redémarrage automatique.

## Bonus

Reproduire le déploiement à l'aide d'un fichier `compose.yaml` pour démarrer les deux services avec une seule commande.

## SOLUTION :

```bash
docker compose up -d
```

http://localhost:8080

cred :

- Serveur : `mysql`
- Utilisateur : `user`
- Mot de passe : `password`
- Base de données : `exo05`
