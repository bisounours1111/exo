# GestStock — procédure d'installation serveur (document hérité, 2017, mis à jour 2021)

Serveur : Debian 10, 1 vCPU, 2 Go. Tout est installé **à la main** :

1. `apt install apache2 php7.3 php7.3-mysql php7.3-gd mariadb-server postfix cron`
2. Copier le code dans `/var/www/geststock`, DocumentRoot Apache → `/var/www/geststock/public`
3. `mysql < sql/schema.sql` ; créer l'utilisateur `geststock` avec le mot de passe de `lib/config.php`
4. `mkdir -p /var/www/html/uploads /var/log/geststock && chown www-data` (les photos sont servies par Apache
   via l'alias `/uploads` → `/var/www/html/uploads`)
5. Cron : `0 6 * * * www-data php /var/www/geststock/bin/rapport.php` (mail via postfix relais)
6. Rotation des logs : `logrotate` sur `/var/log/geststock/app.log`
7. Sauvegarde : `mysqldump` dans un cron à 2h vers `/backup` (le disque est plein depuis mars)
8. `php.ini` : `upload_max_filesize = 20M`, `post_max_size = 25M`, `display_errors = On` (pour « débugger en prod »)

Problèmes connus : un seul serveur, pas de préprod, mises à jour PHP impossibles (7.3 en fin de vie),
redémarrage du serveur = 10 min d'indisponibilité, personne ne sait reconstruire la machine.
