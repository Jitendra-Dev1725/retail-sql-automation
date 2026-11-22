-- 03_sp_place_order.sql : transactional order entry with error handling
USE retail_db;
DROP PROCEDURE IF EXISTS sp_place_order;
DELIMITER $$

CREATE PROCEDURE sp_place_order (
  IN  p_customer_id INT,
  IN  p_product_id  INT,
  IN  p_qty         INT,
  OUT p_order_id    INT
)
BEGIN
  DECLARE v_price DECIMAL(10,2) DEFAULT NULL;
  DECLARE v_stock INT DEFAULT NULL;
  DECLARE v_msg   TEXT;

  -- Any SQL error: capture the message, undo everything, log, re-raise
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
    ROLLBACK;
    INSERT INTO job_log (job_name, status, message, finished_at)
    VALUES ('sp_place_order', 'FAILED', v_msg, NOW());
    RESIGNAL;
  END;

  -- 1. Validate input
  IF p_qty IS NULL OR p_qty <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantity must be greater than zero';
  END IF;

  START TRANSACTION;

  -- 2. Lock the product row so two buyers cannot sell the same last unit
  SELECT unit_price, stock_qty
    INTO v_price, v_stock
    FROM products
   WHERE product_id = p_product_id
     FOR UPDATE;

  IF v_price IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Product not found';
  END IF;
  IF v_stock < p_qty THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient stock for product';
  END IF;

  -- 3. Create the order; trigger trg_order_items_after_insert deducts stock
  INSERT INTO orders (customer_id, total_amount)
  VALUES (p_customer_id, v_price * p_qty);
  SET p_order_id = LAST_INSERT_ID();

  INSERT INTO order_items (order_id, product_id, quantity, unit_price)
  VALUES (p_order_id, p_product_id, p_qty, v_price);

  COMMIT;
END$$

DELIMITER ;
