-- name: CreateProductImage :one
INSERT INTO product_images (
    product_id, file_name, file_path, original_name, mime_type, size_bytes, sort_order
)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING *;

-- name: ListProductImages :many
SELECT *
FROM product_images
WHERE product_id = $1
ORDER BY sort_order ASC, created_at ASC;

-- name: GetProductImageByID :one
SELECT *
FROM product_images
WHERE id = $1 AND product_id = $2;

-- name: CountProductImages :one
SELECT COUNT(*)
FROM product_images
WHERE product_id = $1;

-- name: NextProductImageSortOrder :one
SELECT COALESCE(MAX(sort_order), -1) + 1
FROM product_images
WHERE product_id = $1;

-- name: UpdateProductImage :one
UPDATE product_images
SET file_name     = $3,
    file_path     = $4,
    original_name = $5,
    mime_type     = $6,
    size_bytes    = $7
WHERE id = $1 AND product_id = $2
RETURNING *;

-- name: DeleteProductImage :execrows
DELETE FROM product_images
WHERE id = $1 AND product_id = $2;
