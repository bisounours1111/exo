"""shop-worker : consomme la file `orders:queue` (Redis), valide et persiste les commandes."""
import json
import logging
import os
import signal
import sys
import time

from prometheus_client import Counter, start_http_server

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}')
log = logging.getLogger("shop-worker")

PROCESSED = Counter("orders_processed_total", "Commandes traitées", ["status"])
RUNNING = True


def _stop(signum, _frame):
    global RUNNING
    log.info("signal %s reçu, arrêt en cours", signum)
    RUNNING = False


signal.signal(signal.SIGTERM, _stop)
signal.signal(signal.SIGINT, _stop)


def sleep_interruptible(seconds: float):
    """time.sleep n'est pas interrompu par un signal (PEP 475) : on dort par petits pas."""
    end = time.monotonic() + seconds
    while RUNNING and time.monotonic() < end:
        time.sleep(0.1)


def get_redis():
    url = os.getenv("REDIS_URL")
    if not url:
        return None
    import redis  # import tardif : le worker démarre même sans Redis (mode démo)
    return redis.Redis.from_url(url, socket_connect_timeout=2)


def get_db():
    url = os.getenv("DATABASE_URL")
    if not url:
        return None
    import psycopg2
    return psycopg2.connect(url)


def process(order: dict, db) -> str:
    status = "rejected" if order.get("quantity", 0) > 100 else "confirmed"
    if db:
        with db, db.cursor() as cur:
            cur.execute("UPDATE orders SET status=%s WHERE product_id=%s AND status='pending'", (status, order["productId"]))
    PROCESSED.labels(status=status).inc()
    log.info("commande %s -> %s", order.get("id"), status)
    return status


def main():
    start_http_server(int(os.getenv("METRICS_PORT", "9100")))
    r = get_redis()
    db = None
    while RUNNING:
        try:
            if db is None and os.getenv("DATABASE_URL"):
                db = get_db()
            if r is None:
                log.info("mode démo (pas de REDIS_URL) : rien à consommer")
                sleep_interruptible(5)
                continue
            item = r.brpop("orders:queue", timeout=2)
            if item:
                process(json.loads(item[1]), db)
        except Exception as exc:  # noqa: BLE001
            log.error("erreur: %s", exc)
            db = None
            sleep_interruptible(2)
    log.info("worker arrêté proprement")
    sys.exit(0)


if __name__ == "__main__":
    main()
