-- 04_triggers.sql : event-driven automation inside the database
USE retail_db;
DROP TRIGGER IF EXISTS trg_order_items_after_insert;
DROP TRIGGER IF EXISTS trg_orders_after_update;
DROP TRIGGER IF EXISTS trg_products_after_update;
DELIMITER $$

-- T1: every sold line item reduces stock and is written to the audit trail
CREATE TRIGGER trg_order_items_after_insert
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
  UPDATE products
     SET stock_qty = stock_qty - NEW.quantity
   WHERE product_id = NEW.product_id;

  INSERT INTO stock_movements (product_id, change_qty, reason, ref_id)
  VALUES (NEW.product_id, -NEW.quantity, 'SALE', NEW.order_id);
END$$

-- T2: cancelling an order puts the stock back
CREATE TRIGGER trg_orders_after_update
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
  IF OLD.status <> 'CANCELLED' AND NEW.status = 'CANCELLED' THEN
    -- aggregate per product first, so an order with two lines of the same
    -- product restocks the full quantity (a plain JOIN update would not)
    UPDATE products p
      JOIN (SELECT product_id, SUM(quantity) AS qty
              FROM order_items
             WHERE order_id = NEW.order_id
             GROUP BY product_id) x ON x.product_id = p.product_id
       SET p.stock_qty = p.stock_qty + x.qty;

    INSERT INTO stock_movements (product_id, change_qty, reason, ref_id)
    SELECT product_id, quantity, 'CANCEL_RESTOCK', NEW.order_id
      FROM order_items
     WHERE order_id = NEW.order_id;
  END IF;
END$$

-- T3: low-stock alert (no duplicates) + auto-resolve + price audit
CREATE TRIGGER trg_products_after_update
AFTER UPDATE ON products
FOR EACH ROW
BEGIN
  IF NEW.stock_qty <= NEW.reorder_level THEN
    -- OPEN or ORDERED: do not raise a second alert while stock is already on order
    IF NOT EXISTS (SELECT 1 FROM low_stock_alerts
                    WHERE product_id = NEW.product_id
                      AND status IN ('OPEN','ORDERED')) THEN
      INSERT INTO low_stock_alerts (product_id, stock_at_alert, reorder_level)
      VALUES (NEW.product_id, NEW.stock_qty, NEW.reorder_level);
    END IF;
  ELSE
    UPDATE low_stock_alerts
       SET status = 'RESOLVED'
     WHERE product_id = NEW.product_id
       AND status IN ('OPEN','ORDERED');
  END IF;

  IF OLD.unit_price <> NEW.unit_price THEN
    INSERT INTO price_audit (product_id, old_price, new_price)
    VALUES (NEW.product_id, OLD.unit_price, NEW.unit_price);
  END IF;
END$$

DELIMITER ;
