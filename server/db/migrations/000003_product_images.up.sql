-- 000003_product_images.up.sql
-- Fotografías del catálogo. Los archivos viven en DOWNLOADS_DIR/products.

CREATE TABLE product_images (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id    UUID NOT NULL REFERENCES products (id) ON DELETE CASCADE,
    file_name     TEXT NOT NULL,
    file_path     TEXT NOT NULL UNIQUE,
    original_name TEXT,
    mime_type     TEXT NOT NULL,
    size_bytes    BIGINT NOT NULL CHECK (size_bytes > 0),
    sort_order    INTEGER NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX product_images_product_id_idx
    ON product_images (product_id, sort_order, created_at);

CREATE TRIGGER product_images_set_updated_at
    BEFORE UPDATE ON product_images
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE product_images IS 'Galería de productos; mínimo 3 imágenes por producto (regla de aplicación)';
COMMENT ON COLUMN product_images.file_path IS 'Ruta relativa dentro de DOWNLOADS_DIR';
COMMENT ON COLUMN product_images.sort_order IS 'Orden de aparición en el carrusel';
