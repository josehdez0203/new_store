-- 000002_products.up.sql
-- Catálogo de productos y servicios del negocio.

CREATE TABLE products (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    description TEXT,
    barcode     TEXT,
    price       NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
    cost        NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (cost >= 0),
    -- El margen es siempre precio - costo; no se puede desincronizar.
    margin      NUMERIC(12,2) GENERATED ALWAYS AS (price - cost) STORED,
    type        TEXT NOT NULL CHECK (type IN ('product', 'service')),
    stock       INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ
);

-- Permite reutilizar un código de barras si el producto anterior fue eliminado.
CREATE UNIQUE INDEX products_barcode_active_uidx
    ON products (barcode)
    WHERE barcode IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX products_name_idx ON products (name) WHERE deleted_at IS NULL;
CREATE INDEX products_type_idx ON products (type) WHERE deleted_at IS NULL;
CREATE INDEX products_deleted_at_idx ON products (deleted_at);

CREATE TRIGGER products_set_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE products IS 'Catálogo de productos y servicios a la venta';
COMMENT ON COLUMN products.margin IS 'Margen calculado: price - cost';
COMMENT ON COLUMN products.type IS 'product o service';
COMMENT ON COLUMN products.deleted_at IS 'Soft delete: NULL significa producto vigente';
