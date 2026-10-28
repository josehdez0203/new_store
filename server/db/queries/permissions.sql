-- name: CreatePermission :one
INSERT INTO permissions (name, description, module)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetPermissionByID :one
SELECT
    p.*,
    (SELECT COUNT(*) FROM role_permissions rp WHERE rp.permission_id = p.id) AS role_count
FROM permissions p
WHERE p.id = $1;

-- name: GetPermissionByName :one
SELECT *
FROM permissions
WHERE name = $1;

-- name: ListPermissions :many
SELECT
    p.*,
    (SELECT COUNT(*) FROM role_permissions rp WHERE rp.permission_id = p.id) AS role_count
FROM permissions p
WHERE (
        sqlc.narg('module')::text IS NULL
        OR p.module = sqlc.narg('module')::text
    )
    AND (
        sqlc.narg('search')::text IS NULL
        OR p.name ILIKE '%' || sqlc.narg('search')::text || '%'
        OR COALESCE(p.description, '') ILIKE '%' || sqlc.narg('search')::text || '%'
    )
ORDER BY p.module ASC, p.name ASC;

-- name: UpdatePermission :one
UPDATE permissions
SET name = $2,
    description = $3,
    module = $4
WHERE id = $1
RETURNING *;

-- name: DeletePermission :execrows
DELETE FROM permissions
WHERE id = $1;
