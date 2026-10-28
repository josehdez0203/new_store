-- name: CreateRole :one
INSERT INTO roles (name, description, is_system)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetRoleByID :one
SELECT
    r.*,
    (SELECT COUNT(*) FROM user_roles ur WHERE ur.role_id = r.id) AS user_count,
    (SELECT COUNT(*) FROM role_permissions rp WHERE rp.role_id = r.id) AS permission_count
FROM roles r
WHERE r.id = $1;

-- name: GetRoleByName :one
SELECT *
FROM roles
WHERE name = $1;

-- name: ListRoles :many
SELECT
    r.*,
    (SELECT COUNT(*) FROM user_roles ur WHERE ur.role_id = r.id) AS user_count,
    (SELECT COUNT(*) FROM role_permissions rp WHERE rp.role_id = r.id) AS permission_count
FROM roles r
ORDER BY r.is_system DESC, r.name ASC;

-- name: UpdateRole :one
UPDATE roles
SET name = $2, description = $3
WHERE id = $1
RETURNING *;

-- name: DeleteRole :execrows
DELETE FROM roles
WHERE id = $1;

-- name: ListRolePermissions :many
SELECT
    p.*,
    (SELECT COUNT(*) FROM role_permissions rp2 WHERE rp2.permission_id = p.id) AS role_count
FROM permissions p
JOIN role_permissions rp ON rp.permission_id = p.id
WHERE rp.role_id = $1
ORDER BY p.module ASC, p.name ASC;

-- name: DeleteRolePermissions :exec
DELETE FROM role_permissions
WHERE role_id = $1;

-- name: AddRolePermission :exec
INSERT INTO role_permissions (role_id, permission_id)
VALUES ($1, $2)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- name: SetRoleSystem :exec
UPDATE roles
SET is_system = $2
WHERE id = $1;
