-- 000004_remove_product_stock.up.sql
-- La existencia deja de formar parte del catálogo de productos.
ALTER TABLE products DROP COLUMN stock;
