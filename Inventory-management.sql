-- =====================================================
-- INVENTORY & STOCK MANAGEMENT SYSTEM
-- Domain: Retail / Warehouse
-- Features: Product entry, Stock in/out, Low-stock alert,
--           Supplier-wise tracking, Sales record
-- PL/SQL Concepts: Function, Procedures, Trigger, Cursor
-- =====================================================

SET SERVEROUTPUT ON;

-- 1. Tables
CREATE TABLE suppliers (
    supplier_id NUMBER PRIMARY KEY,
    supplier_name VARCHAR2(100) NOT NULL,
    phone VARCHAR2(15),
    city VARCHAR2(50)
);

CREATE TABLE products (
    product_id NUMBER PRIMARY KEY,
    product_name VARCHAR2(100) NOT NULL,
    supplier_id NUMBER,
    price NUMBER(12,2) CHECK (price > 0),
    stock_qty NUMBER DEFAULT 0 CHECK (stock_qty >= 0),
    reorder_level NUMBER DEFAULT 10,                    -- Alert when stock <= this
    CONSTRAINT fk_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
);

CREATE TABLE stock_transactions (
    txn_id NUMBER PRIMARY KEY,
    product_id NUMBER NOT NULL,
    txn_type VARCHAR2(10) CHECK (txn_type IN ('IN', 'OUT')),
    quantity NUMBER NOT NULL CHECK (quantity > 0),
    txn_date DATE DEFAULT SYSDATE,
    CONSTRAINT fk_product FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- 2. Sequences
CREATE SEQUENCE seq_supplier START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_product START WITH 1001 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_txn START WITH 1 INCREMENT BY 1 NOCACHE;

-- 3. Function: Get current stock of a product
CREATE OR REPLACE FUNCTION fn_get_stock (
    p_product_id IN NUMBER
) RETURN NUMBER IS
    v_stock products.stock_qty%TYPE;
BEGIN
    SELECT stock_qty INTO v_stock
    FROM products
    WHERE product_id = p_product_id;
    
    RETURN v_stock;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20001, 'Product ID not found!');
END fn_get_stock;
/

-- 4. Procedure: Stock In (Purchase / Add stock)
CREATE OR REPLACE PROCEDURE proc_stock_in (
    p_product_id IN NUMBER,
    p_quantity IN NUMBER
) IS
BEGIN
    -- Validation: Quantity must be positive
    IF p_quantity <= 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Quantity must be greater than zero!');
    END IF;
    
    -- Update stock
    UPDATE products
    SET stock_qty = stock_qty + p_quantity
    WHERE product_id = p_product_id;
    
    -- Log transaction
    INSERT INTO stock_transactions (txn_id, product_id, txn_type, quantity)
    VALUES (seq_txn.NEXTVAL, p_product_id, 'IN', p_quantity);
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Stock IN successful! Added ' || p_quantity || 
                         ' units. New stock: ' || fn_get_stock(p_product_id));
END proc_stock_in;
/

-- 5. Procedure: Stock Out (Sale / Remove stock)
CREATE OR REPLACE PROCEDURE proc_stock_out (
    p_product_id IN NUMBER,
    p_quantity IN NUMBER
) IS
    v_current_stock NUMBER;
BEGIN
    IF p_quantity <= 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Quantity must be greater than zero!');
    END IF;
    
    v_current_stock := fn_get_stock(p_product_id);
    
    IF v_current_stock < p_quantity THEN
        RAISE_APPLICATION_ERROR(-20002, 'Insufficient stock! Available: ' || v_current_stock);
    END IF;
    
    UPDATE products
    SET stock_qty = stock_qty - p_quantity
    WHERE product_id = p_product_id;
    
    INSERT INTO stock_transactions (txn_id, product_id, txn_type, quantity)
    VALUES (seq_txn.NEXTVAL, p_product_id, 'OUT', p_quantity);
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Stock OUT successful! Removed ' || p_quantity || 
                         ' units. Remaining stock: ' || fn_get_stock(p_product_id));
END proc_stock_out;
/

-- 6. Trigger: Prevent negative stock (extra safety)
CREATE OR REPLACE TRIGGER trg_prevent_negative
BEFORE UPDATE OF stock_qty ON products
FOR EACH ROW
BEGIN
    IF :NEW.stock_qty < 0 THEN
        RAISE_APPLICATION_ERROR(-20004, 'Stock cannot go negative - Transaction blocked!');
    END IF;
END trg_prevent_negative;
/

-- =============================================
-- TEST DATA & DEMO
-- =============================================

-- Suppliers
INSERT INTO suppliers (supplier_id, supplier_name, phone, city)
VALUES (seq_supplier.NEXTVAL, 'Tech Suppliers Pvt Ltd', '9876543210', 'Mumbai');

INSERT INTO suppliers (supplier_id, supplier_name, phone, city)
VALUES (seq_supplier.NEXTVAL, 'Global Electronics', '9123456789', 'Delhi');

-- Products
INSERT INTO products (product_id, product_name, supplier_id, price, stock_qty, reorder_level)
VALUES (seq_product.NEXTVAL, 'Dell Laptop XPS', 1, 85000, 15, 5);

INSERT INTO products (product_id, product_name, supplier_id, price, stock_qty, reorder_level)
VALUES (seq_product.NEXTVAL, 'HP Printer', 1, 12000, 8, 10);

INSERT INTO products (product_id, product_name, supplier_id, price, stock_qty, reorder_level)
VALUES (seq_product.NEXTVAL, 'Samsung LED TV', 2, 45000, 3, 5);

COMMIT;

-- 1. Check initial stock
SELECT fn_get_stock(1001) FROM DUAL;  -- Should show 15

-- 2. Stock In
BEGIN proc_stock_in(1001, 20); END;   -- Add 20 laptops
/

BEGIN proc_stock_in(1003, 10); END;   -- Add 10 TVs
/

-- 3. Stock Out (Normal)
BEGIN proc_stock_out(1001, 12); END;  -- Sell 12 laptops
/

-- 4. Stock Out Error (Insufficient)
BEGIN proc_stock_out(1002, 20); END;  -- Only 8 printers → Error!
/

-- 5. Trigger Test (Try to force negative)
UPDATE products SET stock_qty = -5 WHERE product_id = 1001;  -- Blocked!

-- 6. Low Stock Alert Report (Cursor)
DECLARE
    CURSOR cur_low_stock IS
        SELECT p.product_name, p.stock_qty, s.supplier_name
        FROM products p
        JOIN suppliers s ON p.supplier_id = s.supplier_id
        WHERE p.stock_qty <= p.reorder_level
        ORDER BY p.stock_qty;
    v_rec cur_low_stock%ROWTYPE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== LOW STOCK ALERT ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('Product', 25) || RPAD('Stock', 10) || 'Supplier');
    DBMS_OUTPUT.PUT_LINE('---------------------------------------------');
    OPEN cur_low_stock;
    LOOP
        FETCH cur_low_stock INTO v_rec;
        EXIT WHEN cur_low_stock%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(RPAD(v_rec.product_name, 25) || 
                             RPAD(v_rec.stock_qty, 10) || v_rec.supplier_name);
    END LOOP;
    CLOSE cur_low_stock;
END;
/

-- 7. Supplier-wise Stock Report
SELECT s.supplier_name, p.product_name, p.price, p.stock_qty
FROM suppliers s
JOIN products p ON s.supplier_id = p.supplier_id
ORDER BY s.supplier_name, p.stock_qty DESC;

-- 8. Full Transaction History
SELECT t.txn_id, p.product_name, t.txn_type, t.quantity, t.txn_date
FROM stock_transactions t
JOIN products p ON t.product_id = p.product_id
ORDER BY t.txn_date DESC;

BEGIN
    DBMS_OUTPUT.PUT_LINE('========================================');
    DBMS_OUTPUT.PUT_LINE('INVENTORY MANAGEMENT SYSTEM READY!');
    DBMS_OUTPUT.PUT_LINE('All features working perfectly.');
    DBMS_OUTPUT.PUT_LINE('========================================');
END;
/