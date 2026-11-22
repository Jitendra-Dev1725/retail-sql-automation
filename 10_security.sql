-- 10_security.sql : least-privilege accounts for the automation layer
USE retail_db;

-- Application account: may only CALL procedures and read reporting objects
CREATE USER IF NOT EXISTS 'retail_app'@'%' IDENTIFIED BY 'ChangeMe_#2026';
GRANT EXECUTE ON retail_db.* TO 'retail_app'@'%';
GRANT SELECT  ON retail_db.v_inventory_status   TO 'retail_app'@'%';
GRANT SELECT  ON retail_db.daily_sales_summary  TO 'retail_app'@'%';

-- Dashboard / BI account: read-only on the reporting layer
CREATE USER IF NOT EXISTS 'retail_bi'@'%' IDENTIFIED BY 'ChangeMe_#2026';
GRANT SELECT ON retail_db.daily_sales_summary TO 'retail_bi'@'%';
GRANT SELECT ON retail_db.v_inventory_status  TO 'retail_bi'@'%';
GRANT EXECUTE ON PROCEDURE retail_db.sp_dynamic_sales_report TO 'retail_bi'@'%';
GRANT EXECUTE ON PROCEDURE retail_db.sp_top_products         TO 'retail_bi'@'%';

-- Job account for cron / Task Scheduler (not needed for the Event Scheduler)
CREATE USER IF NOT EXISTS 'retail_job'@'localhost' IDENTIFIED BY 'ChangeMe_#2026';
GRANT EXECUTE ON retail_db.* TO 'retail_job'@'localhost';
