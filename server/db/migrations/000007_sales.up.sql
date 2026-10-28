-- 000007_sales.up.sql
-- Ventas, detalle de productos y plan de pagos.

CREATE SEQUENCE sale_number_seq;

CREATE TABLE sales (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_number           TEXT NOT NULL UNIQUE
        DEFAULT ('V-' || lpad(nextval('sale_number_seq')::text, 6, '0')),
    client_id             UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    seller_id             UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    sale_date             DATE NOT NULL DEFAULT CURRENT_DATE,
    status                TEXT NOT NULL DEFAULT 'cotizacion'
        CHECK (status IN ('cotizacion', 'venta', 'cancelada')),
    payment_type          TEXT NOT NULL
        CHECK (payment_type IN ('contado', 'credito')),
    down_payment_percent  DOUBLE PRECISION NOT NULL DEFAULT 0
        CHECK (down_payment_percent >= 0 AND down_payment_percent <= 100),
    down_payment          NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (down_payment >= 0),
    financed_amount       NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (financed_amount >= 0),
    monthly_interest_rate DOUBLE PRECISION NOT NULL DEFAULT 0
        CHECK (monthly_interest_rate >= 0 AND monthly_interest_rate <= 100),
    months                INTEGER NOT NULL DEFAULT 0 CHECK (months >= 0 AND months <= 60),
    total_interest        NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (total_interest >= 0),
    total                 NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX sales_client_idx ON sales (client_id);
CREATE INDEX sales_seller_idx ON sales (seller_id);
CREATE INDEX sales_status_idx ON sales (status);
CREATE INDEX sales_date_idx ON sales (sale_date DESC);

CREATE TABLE sale_items (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id    UUID NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity   INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
    subtotal   NUMERIC(12, 2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    UNIQUE (sale_id, product_id)
);

CREATE INDEX sale_items_sale_idx ON sale_items (sale_id);

CREATE TABLE sale_payments (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id            UUID NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
    installment_number INTEGER NOT NULL CHECK (installment_number >= 0),
    kind               TEXT NOT NULL CHECK (kind IN ('anticipo', 'mensualidad', 'contado')),
    due_date           DATE NOT NULL,
    amount             NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    UNIQUE (sale_id, installment_number)
);

CREATE INDEX sale_payments_sale_idx ON sale_payments (sale_id);

CREATE TRIGGER sales_set_updated_at
    BEFORE UPDATE ON sales
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- El total de la venta es calculado a partir de sus partidas.
CREATE OR REPLACE FUNCTION refresh_sale_total() RETURNS TRIGGER AS $$
DECLARE
    target_sale UUID;
    new_total   NUMERIC(12, 2);
BEGIN
    target_sale := COALESCE(NEW.sale_id, OLD.sale_id);

    SELECT COALESCE(SUM(subtotal), 0)
    INTO new_total
    FROM sale_items
    WHERE sale_id = target_sale;

    UPDATE sales
    SET total = new_total
    WHERE id = target_sale;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sale_items_refresh_total
    AFTER INSERT OR UPDATE OR DELETE ON sale_items
    FOR EACH ROW EXECUTE FUNCTION refresh_sale_total();

COMMENT ON TABLE sales IS 'Ventas/cotizaciones; total calculado por trigger desde sale_items';
COMMENT ON TABLE sale_payments IS 'Plan de pagos: anticipo, mensualidades o contado';
