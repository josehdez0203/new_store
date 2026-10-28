-- name: CreateSale :one
INSERT INTO sales (
    client_id,
    seller_id,
    sale_date,
    status,
    payment_type,
    down_payment_percent,
    down_payment,
    financed_amount,
    monthly_interest_rate,
    months,
    total_interest
)
VALUES ($1, $2, $3, $4, $5, 0, 0, 0, 0, 0, 0)
RETURNING *;

-- name: GetSaleByID :one
SELECT
    s.id,
    s.sale_number,
    s.client_id,
    c.name AS client_name,
    c.phone AS client_phone,
    c.email AS client_email,
    s.seller_id,
    u.full_name AS seller_name,
    s.sale_date,
    s.status,
    s.payment_type,
    s.down_payment_percent,
    s.down_payment,
    s.financed_amount,
    s.monthly_interest_rate,
    s.months,
    s.total_interest,
    s.total,
    s.created_at,
    s.updated_at
FROM sales s
JOIN customers c ON c.id = s.client_id
JOIN users u ON u.id = s.seller_id
WHERE s.id = $1;

-- name: ListSales :many
SELECT
    s.id,
    s.sale_number,
    s.client_id,
    c.name AS client_name,
    c.phone AS client_phone,
    c.email AS client_email,
    s.seller_id,
    u.full_name AS seller_name,
    s.sale_date,
    s.status,
    s.payment_type,
    s.down_payment_percent,
    s.down_payment,
    s.financed_amount,
    s.monthly_interest_rate,
    s.months,
    s.total_interest,
    s.total,
    s.created_at,
    s.updated_at
FROM sales s
JOIN customers c ON c.id = s.client_id
JOIN users u ON u.id = s.seller_id
WHERE (
        sqlc.narg('search')::text IS NULL
        OR s.sale_number ILIKE '%' || sqlc.narg('search')::text || '%'
        OR c.name ILIKE '%' || sqlc.narg('search')::text || '%'
        OR u.full_name ILIKE '%' || sqlc.narg('search')::text || '%'
    )
    AND (sqlc.narg('status')::text IS NULL OR s.status = sqlc.narg('status')::text)
    AND (sqlc.narg('seller_id')::uuid IS NULL OR s.seller_id = sqlc.narg('seller_id')::uuid)
ORDER BY s.sale_date DESC, s.sale_number DESC
LIMIT sqlc.arg('limit')::int OFFSET sqlc.arg('offset')::int;

-- name: CountSales :one
SELECT COUNT(*)
FROM sales s
JOIN customers c ON c.id = s.client_id
JOIN users u ON u.id = s.seller_id
WHERE (
        sqlc.narg('search')::text IS NULL
        OR s.sale_number ILIKE '%' || sqlc.narg('search')::text || '%'
        OR c.name ILIKE '%' || sqlc.narg('search')::text || '%'
        OR u.full_name ILIKE '%' || sqlc.narg('search')::text || '%'
    )
    AND (sqlc.narg('status')::text IS NULL OR s.status = sqlc.narg('status')::text)
    AND (sqlc.narg('seller_id')::uuid IS NULL OR s.seller_id = sqlc.narg('seller_id')::uuid);

-- name: ListSaleItems :many
SELECT si.id, si.sale_id, si.product_id, p.name AS product_name, si.quantity, si.unit_price, si.subtotal
FROM sale_items si
JOIN products p ON p.id = si.product_id
WHERE si.sale_id = $1
ORDER BY p.name ASC;

-- name: CreateSaleItem :one
INSERT INTO sale_items (sale_id, product_id, quantity, unit_price)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: ListSalePayments :many
SELECT *
FROM sale_payments
WHERE sale_id = $1
ORDER BY installment_number ASC;

-- name: CreateSalePayment :one
INSERT INTO sale_payments (sale_id, installment_number, kind, due_date, amount)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: UpdateSalePlan :one
UPDATE sales
SET down_payment_percent = $2,
    down_payment = $3,
    financed_amount = $4,
    monthly_interest_rate = $5,
    months = $6,
    total_interest = $7
WHERE id = $1
RETURNING *;

-- name: UpdateSaleStatus :one
UPDATE sales
SET status = $2
WHERE id = $1
RETURNING *;

-- name: IsUserSeller :one
SELECT EXISTS (
    SELECT 1
    FROM users u
    JOIN user_roles ur ON ur.user_id = u.id
    JOIN roles r ON r.id = ur.role_id
    WHERE u.id = $1
      AND u.is_active = TRUE
      AND u.deleted_at IS NULL
      AND r.name = 'vendedor'
);

-- name: UpdateSale :one
UPDATE sales
SET client_id = $2,
    seller_id = $3,
    sale_date = $4,
    status = $5,
    payment_type = $6
WHERE id = $1
RETURNING *;

-- name: DeleteSaleItems :exec
DELETE FROM sale_items WHERE sale_id = $1;

-- name: DeleteSalePayments :exec
DELETE FROM sale_payments WHERE sale_id = $1;
