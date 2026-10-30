<?php
// Rapport quotidien lancé par cron à 6h : /etc/cron.d/geststock → 0 6 * * * www-data php /var/www/geststock/bin/rapport.php
require_once __DIR__ . '/../lib/db.php';
$rows = db()->query('SELECT count(*) n, coalesce(sum(qty),0) total FROM items')->fetch();
$low = db()->query('SELECT name, qty FROM items WHERE qty < 5 ORDER BY qty')->fetchAll();
$body = "Articles: {$rows['n']}, quantité totale: {$rows['total']}\nStock bas:\n";
foreach ($low as $l) { $body .= " - {$l['name']}: {$l['qty']}\n"; }
app_log('info', 'rapport généré');
// Envoi par mail via sendmail local (postfix configuré en relais vers SMTP_HOST)
@mail(REPORT_TO, 'Rapport stock ' . date('Y-m-d'), $body);
echo $body;
