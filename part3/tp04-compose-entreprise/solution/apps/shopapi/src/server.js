'use strict';
const express = require('express');
const pino = require('pino');
const pinoHttp = require('pino-http');
const client = require('prom-client');
const { Pool } = require('pg');
const Redis = require('ioredis');

const log = pino({ level: process.env.LOG_LEVEL || 'info' });
const app = express();
app.use(express.json());
app.use(pinoHttp({ logger: log }));

// ---- Métriques Prometheus ----
client.collectDefaultMetrics();
const httpDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Durée des requêtes HTTP',
  labelNames: ['method', 'route', 'status'],
});
app.use((req, res, next) => {
  const end = httpDuration.startTimer();
  res.on('finish', () => end({ method: req.method, route: req.route ? req.route.path : req.path, status: res.statusCode }));
  next();
});

// ---- Connexions optionnelles (l'API fonctionne seule si pas de DATABASE_URL / REDIS_URL) ----
const pool = process.env.DATABASE_URL ? new Pool({ connectionString: process.env.DATABASE_URL }) : null;
const redis = process.env.REDIS_URL ? new Redis(process.env.REDIS_URL, { lazyConnect: true, maxRetriesPerRequest: 1 }) : null;
if (redis) redis.connect().catch((e) => log.warn({ err: e.message }, 'redis indisponible au démarrage'));

const memoryProducts = [
  { id: 1, name: 'Clavier mécanique', price: 89.9, stock: 12 },
  { id: 2, name: 'Écran 27"', price: 249.0, stock: 4 },
  { id: 3, name: 'Souris sans fil', price: 29.5, stock: 40 },
];

async function listProducts() {
  if (!pool) return memoryProducts;
  const { rows } = await pool.query('SELECT id, name, price, stock FROM products ORDER BY id');
  return rows;
}

// ---- Routes ----
app.get('/', (_req, res) => res.json({ service: 'shopapi', version: process.env.APP_VERSION || 'dev' }));

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.get('/ready', async (_req, res) => {
  const checks = { db: 'skipped', redis: 'skipped' };
  try {
    if (pool) { await pool.query('SELECT 1'); checks.db = 'ok'; }
    if (redis) { await redis.ping(); checks.redis = 'ok'; }
    res.json({ status: 'ready', checks });
  } catch (e) {
    checks.error = e.message;
    res.status(503).json({ status: 'not ready', checks });
  }
});

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

app.get('/products', async (req, res, next) => {
  try {
    if (redis) {
      const cached = await redis.get('products').catch(() => null);
      if (cached) return res.set('X-Cache', 'HIT').json(JSON.parse(cached));
    }
    const products = await listProducts();
    if (redis) await redis.set('products', JSON.stringify(products), 'EX', 30).catch(() => {});
    res.set('X-Cache', 'MISS').json(products);
  } catch (e) { next(e); }
});

app.post('/orders', async (req, res, next) => {
  try {
    const { productId, quantity } = req.body || {};
    if (!productId || !quantity) return res.status(400).json({ error: 'productId et quantity requis' });
    const order = { id: Date.now(), productId, quantity, status: 'pending', createdAt: new Date().toISOString() };
    if (pool) {
      await pool.query('INSERT INTO orders(product_id, quantity, status) VALUES ($1,$2,$3)', [productId, quantity, 'pending']);
    }
    if (redis) await redis.lpush('orders:queue', JSON.stringify(order)).catch(() => {});
    res.status(201).json(order);
  } catch (e) { next(e); }
});

app.use((err, req, res, _next) => {
  req.log.error({ err }, 'erreur non gérée');
  res.status(500).json({ error: 'internal error' });
});

const port = process.env.PORT || 3000;
const server = app.listen(port, () => log.info({ port }, 'shopapi démarré'));

// Arrêt propre : indispensable pour les rolling updates
function shutdown(signal) {
  log.info({ signal }, 'arrêt demandé');
  server.close(async () => {
    if (pool) await pool.end().catch(() => {});
    if (redis) redis.disconnect();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
