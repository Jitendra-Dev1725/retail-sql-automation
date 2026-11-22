-- 09_test_script.sql : run top to bottom on a fresh database
USE retail_db;

-- TEST 1: successful order (trigger deducts stock, low-stock alert fires)
CALL sp_place_order(1, 1, 5, @order_id);
SELECT @order_id AS order_id;
SELECT product_id, stock_qty FROM products WHERE product_id = 1;
SELECT alert_id, product_id, stock_at_alert, reorder_level, status FROM low_stock_alerts;

-- TEST 2: business-rule failure (insufficient stock) - must roll back and log
CALL sp_place_order(2, 1, 20, @order_id);
SELECT product_id, stock_qty FROM products WHERE product_id = 1;   -- unchanged
SELECT job_name, status, message FROM job_log WHERE status = 'FAILED';

-- TEST 3: more sales, then build the summary for today
CALL sp_place_order(2, 2, 3, @o2);
CALL sp_place_order(3, 3, 2, @o3);
CALL sp_refresh_daily_sales_summary(CURDATE());
SELECT * FROM daily_sales_summary;

-- TEST 4: dynamic reports (same procedure, different parameters)
CALL sp_dynamic_sales_report('CATEGORY', CURDATE(), CURDATE(), NULL);
CALL sp_dynamic_sales_report('CATEGORY', CURDATE(), CURDATE(), 'Grocery');
CALL sp_dynamic_sales_report('WEEKLY',   CURDATE(), CURDATE(), NULL);   -- rejected
CALL sp_top_products(CURDATE(), CURDATE(), 3);

-- TEST 5: alert -> purchase request -> receive stock
CALL sp_create_purchase_requests();
SELECT request_id, product_id, qty, status FROM purchase_requests;
SELECT alert_id, status FROM low_stock_alerts;
CALL sp_receive_purchase(1);
SELECT stock_qty FROM products WHERE product_id = 1;
SELECT alert_id, status FROM low_stock_alerts;

-- TEST 6: cancel order 1 -> stock restored, summary corrected on re-run
UPDATE orders SET status = 'CANCELLED' WHERE order_id = 1;
SELECT stock_qty FROM products WHERE product_id = 1;
CALL sp_refresh_daily_sales_summary(CURDATE());
SELECT * FROM daily_sales_summary;

-- TEST 7: price audit trigger
UPDATE products SET unit_price = 849.00 WHERE product_id = 1;
SELECT product_id, old_price, new_price FROM price_audit;

-- TEST 8: archive (insert one old delivered order first)
INSERT INTO orders (customer_id, order_date, status, total_amount)
VALUES (3, '2025-01-15 10:00:00', 'DELIVERED', 649.00);
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (LAST_INSERT_ID(), 3, 1, 649.00);
CALL sp_archive_old_orders(12, 1000);
SELECT COUNT(*) AS archived_orders FROM orders_archive;

-- Monitoring query: how did every job run?
SELECT log_id, job_name, status, rows_affected, started_at, finished_at
  FROM job_log ORDER BY log_id;
