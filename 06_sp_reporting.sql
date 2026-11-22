-- 06_sp_reporting.sql : the dynamic reporting layer
USE retail_db;
DROP PROCEDURE IF EXISTS sp_refresh_daily_sales_summary;
DROP PROCEDURE IF EXISTS sp_dynamic_sales_report;
DROP PROCEDURE IF EXISTS sp_top_products;
DROP VIEW IF EXISTS v_inventory_status;
DELIMITER $$

-- Rebuilds ONE day of the summary table. Idempotent: delete + insert in a
-- single transaction, so re-running (or back-filling) never double counts.
CREATE PROCEDURE sp_refresh_daily_sales_summary (IN p_date DATE)
BEGIN
  DECLARE v_log_id INT;
  DECLARE v_rows   INT DEFAULT 0;
  DECLARE v_msg    TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
    ROLLBACK;
    UPDATE job_log
       SET status = 'FAILED', message = v_msg, finished_at = NOW()
     WHERE log_id = v_log_id;
  END;

  INSERT INTO job_log (job_name) VALUES ('sp_refresh_daily_sales_summary');
  SET v_log_id = LAST_INSERT_ID();

  START TRANSACTION;

  DELETE FROM daily_sales_summary WHERE summary_date = p_date;

  INSERT INTO daily_sales_summary
         (summary_date, category, orders_count, units_sold, revenue)
  SELECT p_date,
         p.category,
         COUNT(DISTINCT o.order_id),
         SUM(oi.quantity),
         SUM(oi.quantity * oi.unit_price)
    FROM orders o
    JOIN order_items oi ON oi.order_id   = o.order_id
    JOIN products    p  ON p.product_id  = oi.product_id
   WHERE o.order_date >= p_date                          -- range scan, uses index
     AND o.order_date <  DATE_ADD(p_date, INTERVAL 1 DAY)
     AND o.status <> 'CANCELLED'
   GROUP BY p.category;
  SET v_rows = ROW_COUNT();

  COMMIT;

  UPDATE job_log
     SET status = 'SUCCESS', rows_affected = v_rows, finished_at = NOW()
   WHERE log_id = v_log_id;
END$$

-- Dynamic report: the caller chooses grouping, date range and category.
-- Only a whitelisted expression is concatenated; user values are bound with
-- placeholders, so the dynamic SQL cannot be injected.
CREATE PROCEDURE sp_dynamic_sales_report (
  IN p_group_by VARCHAR(20),      -- DAY | MONTH | CATEGORY
  IN p_start    DATE,
  IN p_end      DATE,
  IN p_category VARCHAR(50)       -- NULL = all categories
)
BEGIN
  DECLARE v_expr VARCHAR(60);

  IF p_start IS NULL OR p_end IS NULL OR p_start > p_end THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid date range';
  END IF;

  CASE UPPER(TRIM(p_group_by))
    WHEN 'DAY'      THEN SET v_expr = 'summary_date';
    WHEN 'MONTH'    THEN SET v_expr = "DATE_FORMAT(summary_date, '%Y-%m')";
    WHEN 'CATEGORY' THEN SET v_expr = 'category';
    ELSE SIGNAL SQLSTATE '45000'
           SET MESSAGE_TEXT = 'group_by must be DAY, MONTH or CATEGORY';
  END CASE;

  SET @sql = CONCAT(
    'SELECT ', v_expr, ' AS period, ',
    'SUM(orders_count) AS orders, SUM(units_sold) AS units, ',
    'SUM(revenue) AS revenue ',
    'FROM daily_sales_summary ',
    'WHERE summary_date BETWEEN ? AND ? AND (? IS NULL OR category = ?) ',
    'GROUP BY 1 ORDER BY 1');

  PREPARE stmt FROM @sql;
  SET @p_start = p_start, @p_end = p_end, @p_cat = p_category;
  EXECUTE stmt USING @p_start, @p_end, @p_cat, @p_cat;
  DEALLOCATE PREPARE stmt;
END$$

-- Parameterised "top N products" report straight from live tables
CREATE PROCEDURE sp_top_products (IN p_start DATE, IN p_end DATE, IN p_limit INT)
BEGIN
  SELECT p.product_name,
         SUM(oi.quantity)                AS units_sold,
         SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id  = o.order_id
    JOIN products    p  ON p.product_id = oi.product_id
   WHERE o.order_date >= p_start
     AND o.order_date <  DATE_ADD(p_end, INTERVAL 1 DAY)
     AND o.status <> 'CANCELLED'
   GROUP BY p.product_id, p.product_name
   ORDER BY revenue DESC
   LIMIT p_limit;
END$$

DELIMITER ;

-- Ready-made view for dashboards: current stock health per product
CREATE VIEW v_inventory_status AS
SELECT product_id, product_name, category, stock_qty, reorder_level,
       CASE WHEN stock_qty = 0                THEN 'OUT OF STOCK'
            WHEN stock_qty <= reorder_level   THEN 'LOW'
            WHEN stock_qty <= reorder_level*2 THEN 'WATCH'
            ELSE 'HEALTHY' END AS stock_status
  FROM products;
