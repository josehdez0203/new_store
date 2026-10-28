-- name: GetCreditSettings :one
SELECT *
FROM credit_settings
WHERE id = 1;

-- name: UpdateCreditSettings :one
UPDATE credit_settings
SET down_payment_options = $1,
    credit_months = $2,
    monthly_interest_rate = $3,
    updated_by = $4,
    updated_at = NOW()
WHERE id = 1
RETURNING *;
