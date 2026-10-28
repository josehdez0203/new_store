-- name: CreateUser :one
INSERT INTO users (email, password_hash, full_name, is_active)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: GetUserByID :one
SELECT *
FROM users
WHERE id = $1 AND deleted_at IS NULL;

-- name: GetUserByEmail :one
SELECT *
FROM users
WHERE email = $1 AND deleted_at IS NULL;

-- name: UserEmailExists :one
SELECT EXISTS (
    SELECT 1
    FROM users
    WHERE email = $1
      AND deleted_at IS NULL
      AND id <> $2
) AS email_exists;

-- name: UpdateUser :one
UPDATE users
SET email         = COALESCE(sqlc.narg('email')::citext, email),
    full_name     = COALESCE(sqlc.narg('full_name'), full_name),
    is_active     = COALESCE(sqlc.narg('is_active'), is_active),
    password_hash = COALESCE(sqlc.narg('password_hash'), password_hash)
WHERE id = sqlc.arg('id') AND deleted_at IS NULL
RETURNING *;

-- name: TouchLastLogin :exec
UPDATE users
SET last_login_at = NOW()
WHERE id = $1;

-- name: SoftDeleteUser :execrows
UPDATE users
SET deleted_at = NOW(), is_active = FALSE
WHERE id = $1 AND deleted_at IS NULL;

-- name: ListUsers :many
SELECT
    u.*,
    COALESCE(
        (
            SELECT array_agg(r.name ORDER BY r.name)
            FROM user_roles ur
            JOIN roles r ON r.id = ur.role_id
            WHERE ur.user_id = u.id
        ),
        ARRAY[]::text[]
    )::text[] AS roles
FROM users u
WHERE u.deleted_at IS NULL
  AND (
      sqlc.narg('search')::text IS NULL
      OR u.email::text ILIKE '%' || sqlc.narg('search')::text || '%'
      OR u.full_name ILIKE '%' || sqlc.narg('search')::text || '%'
  )
  AND (
      sqlc.narg('is_active')::boolean IS NULL
      OR u.is_active = sqlc.narg('is_active')::boolean
  )
  AND (
      sqlc.narg('role')::text IS NULL
      OR EXISTS (
          SELECT 1
          FROM user_roles ur2
          JOIN roles r2 ON r2.id = ur2.role_id
          WHERE ur2.user_id = u.id AND r2.name = sqlc.narg('role')::text
      )
  )
ORDER BY u.created_at DESC
LIMIT sqlc.arg('limit')::int OFFSET sqlc.arg('offset')::int;

-- name: CountUsers :one
SELECT COUNT(*)
FROM users u
WHERE u.deleted_at IS NULL
  AND (
      sqlc.narg('search')::text IS NULL
      OR u.email::text ILIKE '%' || sqlc.narg('search')::text || '%'
      OR u.full_name ILIKE '%' || sqlc.narg('search')::text || '%'
  )
  AND (
      sqlc.narg('is_active')::boolean IS NULL
      OR u.is_active = sqlc.narg('is_active')::boolean
  )
  AND (
      sqlc.narg('role')::text IS NULL
      OR EXISTS (
          SELECT 1
          FROM user_roles ur2
          JOIN roles r2 ON r2.id = ur2.role_id
          WHERE ur2.user_id = u.id AND r2.name = sqlc.narg('role')::text
      )
  );

-- name: GetUserAccess :one
SELECT
    u.id,
    u.email,
    u.full_name,
    u.is_active,
    u.last_login_at,
    u.created_at,
    u.updated_at,
    COALESCE(
        (
            SELECT array_agg(r.name ORDER BY r.name)
            FROM user_roles ur
            JOIN roles r ON r.id = ur.role_id
            WHERE ur.user_id = u.id
        ),
        ARRAY[]::text[]
    )::text[] AS roles,
    COALESCE(
        (
            SELECT array_agg(DISTINCT p.name ORDER BY p.name)
            FROM user_roles ur
            JOIN role_permissions rp ON rp.role_id = ur.role_id
            JOIN permissions p ON p.id = rp.permission_id
            WHERE ur.user_id = u.id
        ),
        ARRAY[]::text[]
    )::text[] AS permissions
FROM users u
WHERE u.id = $1 AND u.deleted_at IS NULL;

-- name: ListUserRoles :many
SELECT r.*
FROM roles r
JOIN user_roles ur ON ur.role_id = r.id
WHERE ur.user_id = $1
ORDER BY r.name;

-- name: DeleteUserRoles :exec
DELETE FROM user_roles
WHERE user_id = $1;

-- name: AddUserRole :exec
INSERT INTO user_roles (user_id, role_id, assigned_by)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, role_id) DO NOTHING;

-- name: CountActiveAdmins :one
SELECT COUNT(*)
FROM users u
JOIN user_roles ur ON ur.user_id = u.id
JOIN roles r ON r.id = ur.role_id
WHERE r.name = 'admin'
  AND u.is_active = TRUE
  AND u.deleted_at IS NULL;
