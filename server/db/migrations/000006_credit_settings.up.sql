-- 000006_credit_settings.up.sql
-- Parámetros de financiamiento de la empresa. Solo el admin los modifica.

CREATE TABLE credit_settings (
    id                     SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    down_payment_options   DOUBLE PRECISION[] NOT NULL DEFAULT ARRAY[10, 20, 30]::double precision[],
    credit_months          INTEGER[] NOT NULL DEFAULT ARRAY[3, 6, 12],
    monthly_interest_rate  DOUBLE PRECISION NOT NULL DEFAULT 2.0
        CHECK (monthly_interest_rate >= 0 AND monthly_interest_rate <= 100),
    updated_by             UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT credit_settings_down_payments_not_empty
        CHECK (array_length(down_payment_options, 1) BETWEEN 1 AND 10),
    CONSTRAINT credit_settings_months_not_empty
        CHECK (array_length(credit_months, 1) BETWEEN 1 AND 10)
);

INSERT INTO credit_settings (id) VALUES (1) ON CONFLICT DO NOTHING;

COMMENT ON TABLE credit_settings IS 'Configuración única de anticipos, meses e interés; solo admin';
COMMENT ON COLUMN credit_settings.down_payment_options IS 'Porcentajes de anticipo permitidos (0-100)';
COMMENT ON COLUMN credit_settings.credit_months IS 'Plazos en meses permitidos';
COMMENT ON COLUMN credit_settings.monthly_interest_rate IS 'Interés mensual simple sobre el saldo financiado';
