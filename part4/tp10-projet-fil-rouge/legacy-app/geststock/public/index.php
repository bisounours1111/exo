<?php
require_once __DIR__ . '/../lib/db.php';

$message = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $name = trim($_POST['name'] ?? '');
    $qty = (int)($_POST['qty'] ?? 0);
    $photo = null;
    if (!empty($_FILES['photo']['tmp_name'])) {
        $ext = strtolower(pathinfo($_FILES['photo']['name'], PATHINFO_EXTENSION));
        if (in_array($ext, ['jpg', 'jpeg', 'png'], true)) {
            $photo = uniqid('p_', true) . '.' . $ext;
            move_uploaded_file($_FILES['photo']['tmp_name'], UPLOAD_DIR . $photo);
        }
    }
    if ($name !== '') {
        db()->prepare('INSERT INTO items(name, qty, photo) VALUES (?, ?, ?)')->execute([$name, $qty, $photo]);
        app_log('info', "article ajouté: $name ($qty)");
        $message = 'Article ajouté.';
    }
}
if (isset($_GET['delete'])) {
    db()->prepare('DELETE FROM items WHERE id = ?')->execute([(int)$_GET['delete']]);
    app_log('info', 'article supprimé: ' . (int)$_GET['delete']);
    header('Location: /'); exit;
}
if (isset($_GET['health'])) {
    try { db()->query('SELECT 1'); echo 'OK'; } catch (Throwable $e) { http_response_code(503); echo 'DB KO'; }
    exit;
}
$items = db()->query('SELECT * FROM items ORDER BY id DESC')->fetchAll();
?>
<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><title>GestStock</title>
<style>body{font-family:sans-serif;max-width:800px;margin:2em auto}table{width:100%;border-collapse:collapse}td,th{border:1px solid #ccc;padding:.4em}img{height:40px}</style>
</head><body>
<h1>GestStock — inventaire (<?= count($items) ?> articles)</h1>
<?php if ($message): ?><p><strong><?= htmlspecialchars($message) ?></strong></p><?php endif; ?>
<form method="post" enctype="multipart/form-data">
  <input name="name" placeholder="Nom" required> <input name="qty" type="number" value="1" min="0">
  <input name="photo" type="file" accept="image/*"> <button>Ajouter</button>
</form>
<table><tr><th>ID</th><th>Nom</th><th>Qté</th><th>Photo</th><th></th></tr>
<?php foreach ($items as $it): ?>
<tr><td><?= $it['id'] ?></td><td><?= htmlspecialchars($it['name']) ?></td><td><?= $it['qty'] ?></td>
<td><?php if ($it['photo']): ?><img src="/uploads/<?= htmlspecialchars($it['photo']) ?>" alt=""><?php endif; ?></td>
<td><a href="?delete=<?= $it['id'] ?>">supprimer</a></td></tr>
<?php endforeach; ?>
</table>
<p><small>GestStock v2.3 — serveur <?= gethostname() ?> — PHP <?= PHP_VERSION ?></small></p>
</body></html>
