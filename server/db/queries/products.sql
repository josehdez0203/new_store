-- name: CreateProduct :one
INSERT INTO products (name, description, barcode, price, cost, type)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: GetProductByID :one
SELECT *
FROM products
WHERE id = $1 AND deleted_at IS NULL;

-- name: ListProducts :many
SELECT *
FROM products
WHERE deleted_at IS NULL
  AND (
      sqlc.narg('search')::text IS NULL
      OR name ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(description, '') ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(barcode, '') ILIKE '%' || sqlc.narg('search')::text || '%'
  )
  AND (
      sqlc.narg('type')::text IS NULL
      OR type = sqlc.narg('type')::text
  )
ORDER BY name ASC
LIMIT sqlc.arg('limit')::int OFFSET sqlc.arg('offset')::int;

-- name: CountProducts :one
SELECT COUNT(*)
FROM products
WHERE deleted_at IS NULL
  AND (
      sqlc.narg('search')::text IS NULL
      OR name ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(description, '') ILIKE '%' || sqlc.narg('search')::text || '%'
      OR COALESCE(barcode, '') ILIKE '%' || sqlc.narg('search')::text || '%'
  )
  AND (
      sqlc.narg('type')::text IS NULL
      OR type = sqlc.narg('type')::text
  );

-- name: UpdateProduct :one
UPDATE products
SET name        = $2,
    description = $3,
    barcode     = $4,
    price       = $5,
    cost        = $6,
    type        = $7
WHERE id = $1 AND deleted_at IS NULL
RETURNING *;

-- name: SoftDeleteProduct :execrows
UPDATE products
SET deleted_at = NOW()
WHERE id = $1 AND deleted_at IS NULL;

-- name: BarcodeExists :one
SELECT EXISTS (
    SELECT 1
    FROM products
    WHERE barcode = $1
      AND deleted_at IS NULL
      AND id <> $2
) AS barcode_exists;
