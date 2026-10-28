-- name: CreateCustomer :one
INSERT INTO customers (name, address, city, postal_code, phone, email, status)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING *;

-- name: GetCustomerByID :one
SELECT *
FROM customers
WHERE id = $1 AND deleted_at IS NULL;

-- name: ListCustomers :many
SELECT *
FROM customers
WHERE deleted_at IS NULL
  AND (
      sqlc.narg('search')::text IS NULL
      OR name ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(address, '') ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(city, '') ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(postal_code, '') ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(phone, '') ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(email::text, '') ILIKE '%' || sqlc.narg('search')::text || '%'
  )
  AND (
      sqlc.narg('status')::text IS NULL
      OR status = sqlc.narg('status')::text
  )
ORDER BY name ASC
LIMIT sqlc.arg('limit')::int OFFSET sqlc.arg('offset')::int;

-- name: CountCustomers :one
SELECT COUNT(*)
FROM customers
WHERE deleted_at IS NULL
  AND (
      sqlc.narg('search')::text IS NULL
      OR name ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(address, '') ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(city, '') ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(postal_code, '') ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(phone, '') ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(email::text, '') ILIKE '%' || sqlc.narg('search')::text || '%'
  )
  AND (
      sqlc.narg('status')::text IS NULL
      OR status = sqlc.narg('status')::text
  );

-- name: UpdateCustomer :one
UPDATE customers
SET name        = $2,
    address     = $3,
    city        = $4,
    postal_code = $5,
    phone       = $6,
    email       = $7,
    status      = $8
WHERE id = $1 AND deleted_at IS NULL
RETURNING *;

-- name: SoftDeleteCustomer :execrows
UPDATE customers
SET deleted_at = NOW()
WHERE id = $1 AND deleted_at IS NULL;
