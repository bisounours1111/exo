# Exercice Docker #7

Via Docker, créer un conteneur de base de données (de type MySQL) possédant déjà plusieurs tables et données à son lancement.

- Ce conteneur devra être initialisé via un script de type sql contenant l'initialisation de la base de données
- Ce conteneur devra être instancié via une image construite par vos soins

Concernant le contenu de la base de données, celle-ci devra se nommer kennelDB et comporter:

- Des clients (nom, prénom, date de naissance, pseudonymme)
- Des adresses (numéro, rue, code postal, commune)
- Des associations clients-adresses
- Des chiens (nom, date de naissance, race, statut de stérilisation)
- Des chats (nom, date de naissance, race, statut de stérilisation)


## SOLUTION :

Fichiers : `init.sql` (tables + données), `Dockerfile` (image MySQL + script) et `compose.yaml`.

```bash
docker build -t kennel-db .
docker compose up -d
docker compose exec mysql mysql -uroot -proot kennelDB -e "SHOW TABLES; SELECT * FROM client;"
```
