-- Run once by the postgres entrypoint, on the first start with an empty pgdata volume.
CREATE TABLE products (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL,
  price NUMERIC(10,2) NOT NULL,
  stock INT NOT NULL DEFAULT 0
);

CREATE TABLE orders (
  id         SERIAL PRIMARY KEY,
  product_id INT NOT NULL REFERENCES products(id),
  quantity   INT NOT NULL,
  status     TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO products (name, price, stock) VALUES
  ('Clavier mécanique', 89.90, 12),
  ('Écran 27"', 249.00, 4),
  ('Souris sans fil', 29.50, 40);
