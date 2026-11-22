-- =====================================================================
-- 01_schema.sql  |  Retail automation database (MySQL 8.0.16+)
-- =====================================================================
CREATE DATABASE IF NOT EXISTS retail_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE retail_db;

-- ---------- Core business tables ----------
CREATE TABLE customers (
  customer_id INT AUTO_INCREMENT PRIMARY KEY,
  full_name   VARCHAR(100) NOT NULL,
  email       VARCHAR(120) UNIQUE,
  city        VARCHAR(60),
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE products (
  product_id    INT AUTO_INCREMENT PRIMARY KEY,
  sku           VARCHAR(30)  NOT NULL UNIQUE,
  product_name  VARCHAR(120) NOT NULL,
  category      VARCHAR(50)  NOT NULL,
  unit_price    DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
  stock_qty     INT NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
  reorder_level INT NOT NULL DEFAULT 10,   -- alert when stock <= this
  reorder_qty   INT NOT NULL DEFAULT 50,   -- how many to order
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE orders (
  order_id     INT AUTO_INCREMENT PRIMARY KEY,
  customer_id  INT NOT NULL,
  order_date   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status       ENUM('PLACED','SHIPPED','DELIVERED','CANCELLED')
               NOT NULL DEFAULT 'PLACED',
  total_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id)
    REFERENCES customers(customer_id),
  INDEX idx_orders_date        (order_date),
  INDEX idx_orders_status_date (status, order_date)
) ENGINE=InnoDB;

CREATE TABLE order_items (
  item_id    INT AUTO_INCREMENT PRIMARY KEY,
  order_id   INT NOT NULL,
  product_id INT NOT NULL,
  quantity   INT NOT NULL CHECK (quantity > 0),
  unit_price DECIMAL(10,2) NOT NULL,       -- price frozen at sale time
  CONSTRAINT fk_items_order   FOREIGN KEY (order_id)
    REFERENCES orders(order_id),
  CONSTRAINT fk_items_product FOREIGN KEY (product_id)
    REFERENCES products(product_id)
) ENGINE=InnoDB;

-- ---------- Automation support tables ----------
CREATE TABLE stock_movements (            -- audit trail of every stock change
  movement_id INT AUTO_INCREMENT PRIMARY KEY,
  product_id  INT NOT NULL,
  change_qty  INT NOT NULL,               -- negative = stock out
  reason      ENUM('SALE','CANCEL_RESTOCK','RESTOCK') NOT NULL,
  ref_id      INT NULL,                   -- order_id or purchase request id
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_mov_product (product_id, created_at)
) ENGINE=InnoDB;

CREATE TABLE low_stock_alerts (
  alert_id       INT AUTO_INCREMENT PRIMARY KEY,
  product_id     INT NOT NULL,
  stock_at_alert INT NOT NULL,
  reorder_level  INT NOT NULL,
  status         ENUM('OPEN','ORDERED','RESOLVED') NOT NULL DEFAULT 'OPEN',
  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_alert_product_status (product_id, status)
) ENGINE=InnoDB;

CREATE TABLE purchase_requests (
  request_id INT AUTO_INCREMENT PRIMARY KEY,
  product_id INT NOT NULL,
  alert_id   INT NULL,
  qty        INT NOT NULL,
  status     ENUM('PENDING','RECEIVED','CANCELLED') NOT NULL DEFAULT 'PENDING',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  received_at DATETIME NULL
) ENGINE=InnoDB;

CREATE TABLE price_audit (
  audit_id   INT AUTO_INCREMENT PRIMARY KEY,
  product_id INT NOT NULL,
  old_price  DECIMAL(10,2) NOT NULL,
  new_price  DECIMAL(10,2) NOT NULL,
  changed_by VARCHAR(100) NOT NULL DEFAULT (USER()),
  changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE job_log (                    -- one row per automated job run
  log_id        INT AUTO_INCREMENT PRIMARY KEY,
  job_name      VARCHAR(60) NOT NULL,
  status        ENUM('STARTED','SUCCESS','FAILED') NOT NULL DEFAULT 'STARTED',
  rows_affected INT NOT NULL DEFAULT 0,
  message       TEXT NULL,
  started_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at   DATETIME NULL,
  INDEX idx_job_name_time (job_name, started_at)
) ENGINE=InnoDB;

-- ---------- Archive tables (same structure + archived_at) ----------
CREATE TABLE orders_archive      LIKE orders;
CREATE TABLE order_items_archive LIKE order_items;
ALTER TABLE orders_archive
  ADD COLUMN archived_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE order_items_archive
  ADD COLUMN archived_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- ---------- Reporting layer table (filled by a scheduled job) ----------
CREATE TABLE daily_sales_summary (
  summary_date DATE NOT NULL,
  category     VARCHAR(50) NOT NULL,
  orders_count INT NOT NULL,
  units_sold   INT NOT NULL,
  revenue      DECIMAL(14,2) NOT NULL,
  refreshed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (summary_date, category)
) ENGINE=InnoDB;
