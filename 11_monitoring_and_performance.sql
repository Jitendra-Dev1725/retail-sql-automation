-- 11_monitoring_and_performance.sql : health checks and query-plan checks
USE retail_db;

-- M1: jobs that FAILED in the last 24 hours (run this every morning)
SELECT log_id, job_name, message, started_at
  FROM job_log
 WHERE status = 'FAILED'
   AND started_at >= NOW() - INTERVAL 1 DAY
 ORDER BY started_at DESC;

-- M2: jobs stuck in STARTED for more than 30 minutes (crashed or blocked)
SELECT log_id, job_name, started_at
  FROM job_log
 WHERE status = 'STARTED'
   AND started_at < NOW() - INTERVAL 30 MINUTE;

-- M3: did last night's summary run? (expect 1 SUCCESS row for each night)
SELECT DATE(started_at) AS run_date, status, rows_affected
  FROM job_log
 WHERE job_name = 'sp_refresh_daily_sales_summary'
 ORDER BY started_at DESC
 LIMIT 7;

-- M4: average and longest run time per job over the last 30 days
SELECT job_name,
       COUNT(*)                                          AS runs,
       ROUND(AVG(TIMESTAMPDIFF(SECOND, started_at, finished_at)), 2) AS avg_seconds,
       MAX(TIMESTAMPDIFF(SECOND, started_at, finished_at))           AS max_seconds
  FROM job_log
 WHERE status = 'SUCCESS'
   AND started_at >= NOW() - INTERVAL 30 DAY
 GROUP BY job_name;

-- M5: scheduler status (ENABLED / DISABLED) and last execution time
SELECT event_name, status, last_executed
  FROM information_schema.events
 WHERE event_schema = 'retail_db';

-- M6: products that are on order for too long (request PENDING > 7 days)
SELECT pr.request_id, p.product_name, pr.qty, pr.created_at
  FROM purchase_requests pr
  JOIN products p ON p.product_id = pr.product_id
 WHERE pr.status = 'PENDING'
   AND pr.created_at < NOW() - INTERVAL 7 DAY;

-- ---------------------------------------------------------------------
-- Query-plan checks: run EXPLAIN and confirm the index is used.
-- Good: type = range / ref, key = idx_orders_date or idx_orders_status_date
-- Bad : type = ALL (full table scan)  -> add or fix an index
-- ---------------------------------------------------------------------
EXPLAIN
SELECT p.category, COUNT(DISTINCT o.order_id), SUM(oi.quantity),
       SUM(oi.quantity * oi.unit_price)
  FROM orders o
  JOIN order_items oi ON oi.order_id  = o.order_id
  JOIN products    p  ON p.product_id = oi.product_id
 WHERE o.order_date >= '2026-11-20'
   AND o.order_date <  '2026-11-21'
   AND o.status <> 'CANCELLED'
 GROUP BY p.category;

-- Anti-pattern (do NOT write this): wrapping the column in a function
-- stops MySQL from using idx_orders_date and forces a full scan.
-- EXPLAIN SELECT ... WHERE DATE(o.order_date) = '2026-11-20';

-- MySQL 8.0.18+ : real execution time per plan step
EXPLAIN ANALYZE
SELECT product_id, SUM(quantity) FROM order_items GROUP BY product_id;
