-- 07_sp_archive.sql : batch archiving of old finished orders
USE retail_db;
DROP PROCEDURE IF EXISTS sp_archive_old_orders;
DELIMITER $$

CREATE PROCEDURE sp_archive_old_orders (IN p_months INT, IN p_batch_size INT)
BEGIN
  DECLARE v_cutoff DATETIME;
  DECLARE v_log_id INT;
  DECLARE v_batch  INT DEFAULT 1;
  DECLARE v_moved  INT DEFAULT 0;
  DECLARE v_msg    TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
    ROLLBACK;                       -- only the current batch is undone
    UPDATE job_log
       SET status = 'FAILED', rows_affected = v_moved,
           message = v_msg, finished_at = NOW()
     WHERE log_id = v_log_id;
  END;

  INSERT INTO job_log (job_name) VALUES ('sp_archive_old_orders');
  SET v_log_id = LAST_INSERT_ID();
  SET v_cutoff = DATE_SUB(CURDATE(), INTERVAL p_months MONTH);

  DROP TEMPORARY TABLE IF EXISTS tmp_batch_ids;
  CREATE TEMPORARY TABLE tmp_batch_ids (order_id INT PRIMARY KEY);

  WHILE v_batch > 0 DO
    START TRANSACTION;

    DELETE FROM tmp_batch_ids;
    INSERT INTO tmp_batch_ids
    SELECT order_id
      FROM orders
     WHERE order_date < v_cutoff
       AND status IN ('DELIVERED','CANCELLED')
     ORDER BY order_id
     LIMIT p_batch_size;
    SET v_batch = ROW_COUNT();

    IF v_batch > 0 THEN
      INSERT INTO orders_archive
             (order_id, customer_id, order_date, status, total_amount)
      SELECT o.order_id, o.customer_id, o.order_date, o.status, o.total_amount
        FROM orders o JOIN tmp_batch_ids t ON t.order_id = o.order_id;

      INSERT INTO order_items_archive
             (item_id, order_id, product_id, quantity, unit_price)
      SELECT oi.item_id, oi.order_id, oi.product_id, oi.quantity, oi.unit_price
        FROM order_items oi JOIN tmp_batch_ids t ON t.order_id = oi.order_id;

      DELETE oi FROM order_items oi JOIN tmp_batch_ids t ON t.order_id = oi.order_id;
      DELETE o  FROM orders o       JOIN tmp_batch_ids t ON t.order_id = o.order_id;

      SET v_moved = v_moved + v_batch;
    END IF;

    COMMIT;                         -- short transactions = short locks
  END WHILE;

  DROP TEMPORARY TABLE IF EXISTS tmp_batch_ids;

  UPDATE job_log
     SET status = 'SUCCESS', rows_affected = v_moved, finished_at = NOW()
   WHERE log_id = v_log_id;
END$$

DELIMITER ;
