-- 000005_customers.up.sql
-- Clientes del negocio y su estado dentro del ciclo de crédito.

CREATE TABLE customers (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    address     TEXT,
    city        TEXT,
    postal_code TEXT,
    phone       TEXT,
    email       CITEXT,
    status      TEXT NOT NULL DEFAULT 'prospecto'
        CHECK (status IN ('prospecto', 'cliente', 'en_pago', 'liquidado')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ
);

CREATE INDEX customers_name_active_idx
    ON customers (name)
    WHERE deleted_at IS NULL;

CREATE INDEX customers_status_active_idx
    ON customers (status)
    WHERE deleted_at IS NULL;

CREATE INDEX customers_deleted_at_idx ON customers (deleted_at);

CREATE TRIGGER customers_set_updated_at
    BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE customers IS 'Clientes; el borrado es lógico con deleted_at';
COMMENT ON COLUMN customers.postal_code IS 'Código postal como texto para conservar ceros iniciales';
COMMENT ON COLUMN customers.status IS 'prospecto, cliente, en_pago o liquidado';
