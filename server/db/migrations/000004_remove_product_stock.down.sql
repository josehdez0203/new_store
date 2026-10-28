-- 000004_remove_product_stock.down.sql
ALTER TABLE products
    ADD COLUMN stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0);
