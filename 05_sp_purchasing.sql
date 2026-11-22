-- 05_sp_purchasing.sql : alert -> purchase request -> restock
USE retail_db;
DROP PROCEDURE IF EXISTS sp_create_purchase_requests;
DROP PROCEDURE IF EXISTS sp_receive_purchase;
DELIMITER $$

-- Turns every OPEN low-stock alert into a PENDING purchase request.
-- Scheduled hourly. Safe to re-run: it only touches alerts that are OPEN.
CREATE PROCEDURE sp_create_purchase_requests ()
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

  INSERT INTO job_log (job_name) VALUES ('sp_create_purchase_requests');
  SET v_log_id = LAST_INSERT_ID();

  START TRANSACTION;

  -- Snapshot the alerts first so alerts raised mid-run are not half-processed
  DROP TEMPORARY TABLE IF EXISTS tmp_open_alerts;
  CREATE TEMPORARY TABLE tmp_open_alerts AS
    SELECT alert_id, product_id
      FROM low_stock_alerts
     WHERE status = 'OPEN';

  INSERT INTO purchase_requests (product_id, alert_id, qty)
  SELECT t.product_id, t.alert_id, p.reorder_qty
    FROM tmp_open_alerts t
    JOIN products p ON p.product_id = t.product_id;
  SET v_rows = ROW_COUNT();

  UPDATE low_stock_alerts a
    JOIN tmp_open_alerts t ON t.alert_id = a.alert_id
     SET a.status = 'ORDERED';

  COMMIT;
  DROP TEMPORARY TABLE IF EXISTS tmp_open_alerts;

  UPDATE job_log
     SET status = 'SUCCESS', rows_affected = v_rows, finished_at = NOW()
   WHERE log_id = v_log_id;
END$$

-- Called when the supplier delivers: adds stock, closes the request
CREATE PROCEDURE sp_receive_purchase (IN p_request_id INT)
BEGIN
  DECLARE v_product INT DEFAULT NULL;
  DECLARE v_alert   INT;
  DECLARE v_qty     INT;
  DECLARE v_msg     TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
    ROLLBACK;
    INSERT INTO job_log (job_name, status, message, finished_at)
    VALUES ('sp_receive_purchase', 'FAILED', v_msg, NOW());
    RESIGNAL;
  END;

  START TRANSACTION;

  SELECT product_id, alert_id, qty INTO v_product, v_alert, v_qty
    FROM purchase_requests
   WHERE request_id = p_request_id AND status = 'PENDING'
     FOR UPDATE;

  IF v_product IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Purchase request not found or already received';
  END IF;

  -- Close the alert FIRST. Then the stock update fires trigger T3, which
  -- either leaves it closed (stock healthy) or opens a NEW alert (delivery
  -- was too small to get above the reorder level).
  UPDATE low_stock_alerts SET status = 'RESOLVED'
   WHERE alert_id = v_alert AND status = 'ORDERED';

  UPDATE products SET stock_qty = stock_qty + v_qty
   WHERE product_id = v_product;

  INSERT INTO stock_movements (product_id, change_qty, reason, ref_id)
  VALUES (v_product, v_qty, 'RESTOCK', p_request_id);

  UPDATE purchase_requests
     SET status = 'RECEIVED', received_at = NOW()
   WHERE request_id = p_request_id;

  COMMIT;
END$$

DELIMITER ;
