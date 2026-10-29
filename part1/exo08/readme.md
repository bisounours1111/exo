# Exercice Docker #8

Réaliser une API en Java (via Spring Boot) conteneurisée.

Cette API devra permettre la réalisation d'un CRUD de base sur une entité de votre choix (pour l'exemple, cela sera des chiens).

Elle offrira plusieurs endpoints, de type:

- `GET /api/v1/dogs`: Listing des chiens
- `GET /api/v1/dogs/{dogId}`: Récupération d'un chien et de ses détails
- `POST /api/v1/dogs`: Ajout d'un nouveau chien à notre base de données
- `PUT /api/v1/dogs/{dogId}`: Edition d'un chien via son ID
- `DELETE /api/v1/dogs/{dogId}`: Suppression d'un chien via son ID

Pour fonctionner, l'API utilisera Hibernate et sera connectée à une base de données de type MySQL / PostgresSQL.

La base de données sera également conteneurisée, de sorte à ne pas avoir à installer le moindre SGBD en local.


## SOLUTION :

Fichiers : projet Spring Boot (`pom.xml`, `src/`), `Dockerfile` (build Maven + image Java) et `compose.yaml` (MySQL + API).

```bash
docker compose up -d --build
```

### Tester l'API

```bash
curl -X POST localhost:8080/api/v1/dogs -H "Content-Type: application/json" -d '{"name":"Rex","breed":"Berger allemand","birthDate":"2019-03-10","sterilized":true}'
curl localhost:8080/api/v1/dogs
curl localhost:8080/api/v1/dogs/1
curl -X PUT localhost:8080/api/v1/dogs/1 -H "Content-Type: application/json" -d '{"name":"Rex","breed":"Berger allemand","birthDate":"2019-03-10","sterilized":false}'
curl -X DELETE localhost:8080/api/v1/dogs/1
```
