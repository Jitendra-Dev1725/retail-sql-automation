-- 08_scheduled_events.sql : MySQL Event Scheduler (the "cron" of MySQL)
USE retail_db;

-- Needs the SYSTEM_VARIABLES_ADMIN (or SUPER) privilege. To keep it after a
-- server restart also add  event_scheduler=ON  under [mysqld] in my.cnf
SET GLOBAL event_scheduler = ON;

DROP EVENT IF EXISTS ev_daily_sales_summary;
DROP EVENT IF EXISTS ev_hourly_purchase_requests;
DROP EVENT IF EXISTS ev_monthly_archive;
DROP EVENT IF EXISTS ev_weekly_log_cleanup;

-- Every night at 01:00 - summarise YESTERDAY (all sales are final by then)
CREATE EVENT ev_daily_sales_summary
  ON SCHEDULE EVERY 1 DAY
  STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 1 HOUR)
  COMMENT 'Refresh daily_sales_summary for yesterday'
  DO CALL sp_refresh_daily_sales_summary(CURRENT_DATE - INTERVAL 1 DAY);

-- Every hour - convert new low-stock alerts into purchase requests
-- Starts at xx:30 so it never collides with the 01:00 / 02:00 / 03:00 jobs
CREATE EVENT ev_hourly_purchase_requests
  ON SCHEDULE EVERY 1 HOUR
  STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 30 MINUTE)
  COMMENT 'Create purchase requests for OPEN low-stock alerts'
  DO CALL sp_create_purchase_requests();

-- 1st of every month at 02:00 - archive orders older than 12 months
CREATE EVENT ev_monthly_archive
  ON SCHEDULE EVERY 1 MONTH
  STARTS TIMESTAMP(DATE_FORMAT(NOW() + INTERVAL 1 MONTH, '%Y-%m-01 02:00:00'))
  COMMENT 'Move finished orders older than 12 months to archive tables'
  DO CALL sp_archive_old_orders(12, 1000);

-- Weekly - keep job_log small (90 days of history)
CREATE EVENT ev_weekly_log_cleanup
  ON SCHEDULE EVERY 1 WEEK
  STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 3 HOUR)
  COMMENT 'Delete job_log rows older than 90 days'
  DO DELETE FROM job_log WHERE started_at < NOW() - INTERVAL 90 DAY;

-- Check what is scheduled
SELECT event_name, interval_value, interval_field, starts, last_executed, status
  FROM information_schema.events
 WHERE event_schema = 'retail_db';

-- ---------------------------------------------------------------------
-- Alternative schedulers (when the Event Scheduler is not allowed)
-- ---------------------------------------------------------------------
-- Linux cron  (crontab -e):
-- 0 1 * * *  mysql --defaults-extra-file=/etc/retail/.my.cnf retail_db \
--   -e "CALL sp_refresh_daily_sales_summary(CURDATE() - INTERVAL 1 DAY);" \
--   >> /var/log/retail_jobs.log 2>&1
--
-- Windows Task Scheduler:
-- schtasks /create /tn "RetailDailySummary" /sc daily /st 01:00 /tr ^
--   "mysql -u retail_job -p*** retail_db -e \"CALL sp_refresh_daily_sales_summary(CURDATE()-INTERVAL 1 DAY)\""
--
-- PostgreSQL (pg_cron extension):
-- SELECT cron.schedule('daily-summary', '0 1 * * *',
--        $$CALL refresh_daily_sales_summary(CURRENT_DATE - 1)$$);
--
-- SQL Server: create a SQL Server Agent job, step type T-SQL,
--   command  EXEC dbo.usp_refresh_daily_sales_summary @d = ...; schedule daily 01:00.
