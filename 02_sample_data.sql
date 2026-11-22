-- 02_sample_data.sql : small dataset used by the test script
USE retail_db;

INSERT INTO customers (full_name, email, city) VALUES
  ('Aarav Sharma', 'aarav@example.com', 'Delhi'),
  ('Priya Nair',   'priya@example.com', 'Kochi'),
  ('Rohan Mehta',  'rohan@example.com', 'Mumbai');

INSERT INTO products
  (sku, product_name, category, unit_price, stock_qty, reorder_level, reorder_qty)
VALUES
  ('ELE-001', 'Wireless Mouse',    'Electronics', 799.00, 12, 10,  50),
  ('ELE-002', 'USB-C Cable',       'Electronics', 299.00, 80, 20, 100),
  ('GRO-001', 'Basmati Rice 5kg',  'Grocery',     649.00, 40, 15,  60),
  ('STA-001', 'A4 Notebook Pack',  'Stationery',  199.00, 25, 10,  40);
