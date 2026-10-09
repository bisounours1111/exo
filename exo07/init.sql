SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS kennelDB;
USE kennelDB;

CREATE TABLE client (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nom VARCHAR(50) NOT NULL,
  prenom VARCHAR(50) NOT NULL,
  date_naissance DATE,
  pseudonyme VARCHAR(50) UNIQUE
);

CREATE TABLE adresse (
  id INT AUTO_INCREMENT PRIMARY KEY,
  numero VARCHAR(10),
  rue VARCHAR(100) NOT NULL,
  code_postal VARCHAR(10) NOT NULL,
  commune VARCHAR(50) NOT NULL
);

CREATE TABLE client_adresse (
  client_id INT,
  adresse_id INT,
  PRIMARY KEY (client_id, adresse_id),
  FOREIGN KEY (client_id) REFERENCES client(id),
  FOREIGN KEY (adresse_id) REFERENCES adresse(id)
);

CREATE TABLE chien (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nom VARCHAR(50) NOT NULL,
  date_naissance DATE,
  race VARCHAR(50),
  sterilise BOOLEAN DEFAULT FALSE,
  client_id INT,
  FOREIGN KEY (client_id) REFERENCES client(id)
);

CREATE TABLE chat (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nom VARCHAR(50) NOT NULL,
  date_naissance DATE,
  race VARCHAR(50),
  sterilise BOOLEAN DEFAULT FALSE,
  client_id INT,
  FOREIGN KEY (client_id) REFERENCES client(id)
);

INSERT INTO client (nom, prenom, date_naissance, pseudonyme) VALUES
  ('Dupont', 'Marie', '1990-04-12', 'mdupont'),
  ('Martin', 'Lucas', '1985-11-03', 'lucasm'),
  ('Bernard', 'Emma', '2000-07-25', 'emmab');

INSERT INTO adresse (numero, rue, code_postal, commune) VALUES
  ('12', 'rue de la Paix', '75002', 'Paris'),
  ('5', 'avenue Jean Jaurès', '69007', 'Lyon'),
  ('8', 'boulevard Victor Hugo', '06000', 'Nice');

INSERT INTO client_adresse (client_id, adresse_id) VALUES
  (1, 1), (2, 2), (3, 2), (3, 3);

INSERT INTO chien (nom, date_naissance, race, sterilise, client_id) VALUES
  ('Rex', '2019-03-10', 'Berger allemand', TRUE, 1),
  ('Max', '2021-06-22', 'Labrador', FALSE, 2);

INSERT INTO chat (nom, date_naissance, race, sterilise, client_id) VALUES
  ('Minou', '2018-09-14', 'Siamois', TRUE, 1),
  ('Félix', '2022-01-30', 'Maine Coon', FALSE, 3);
