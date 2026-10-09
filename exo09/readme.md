# Exercice Docker #9

Réaliser deux APIs en Java (via Spring Boot) et les conteneuriser.

## API Logs

L'objectif de cette API est de permettre le stockage et la récupération de logs dans un fichier / une base de données.

Elle possèdera plusieurs endpoints tels que:

- `GET /api/v1/logs`: Récupération de l'ensemble des logs
- `POST /api/v1/logs`: Ajout d'un nouveau log à notre listing

Un log sera constitué de la sorte:

```json
{
  "message": "string",
  "source": "string",
  "timestamp": "string",
  "level": "string"
}
```

- Le message sera l'erreur retournée par l'API du CRUD
- La source sera une chaine de caractère de type `[CrudAPI] GET /api/v1/chemin/appelle`
- Le timestamp sera l'indicatif de temps du moment où le message d'erreur à été levé par l'API
- Le niveau sera un énum de type `INFO | WARN | ERR` permettant de savoir s'il s'agit d'une erreur ou d'un simple appel ayant retourné un 200

## API CRUD

Cette API devra permettre la réalisation d'un CRUD de base sur une entité de votre choix (pour l'exemple, cela sera des chiens).

Elle offrira plusieurs endpoints, de type:

- `GET /api/v1/dogs`: Listing des chiens
- `GET /api/v1/dogs/{dogId}`: Récupération d'un chien et de ses détails
- `POST /api/v1/dogs`: Ajout d'un nouveau chien à notre base de données
- `PUT /api/v1/dogs/{dogId}`: Edition d'un chien via son ID
- `DELETE /api/v1/dogs/{dogId}`: Suppression d'un chien via son ID

Pour fonctionner, l'API utilisera Hibernate et sera connectée à une base de données de type MySQL / PostgresSQL.

Lors de l'interaction de l'utilisateur avec cette API, des logs seront générés et seront transmis à l'API de logging via un client HTTP (de type RestTemplate en Java donc).

La base de données sera également conteneurisée, de sorte à ne pas avoir à installer le moindre SGBD en local.

## SOLUTION :

Dossiers : `crud-api` (copie de l'exo 8 + envoi des logs) et `logs-api` (stockage des logs dans MySQL).

```bash
docker compose up -d --build
```
