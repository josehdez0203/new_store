-- name: CreateSession :one
INSERT INTO sessions (user_id, refresh_token_hash, user_agent, ip_address, expires_at)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: GetSessionByRefreshToken :one
SELECT *
FROM sessions
WHERE refresh_token_hash = $1;

-- name: RotateSessionRefreshToken :one
UPDATE sessions
SET refresh_token_hash = $2,
    last_used_at = NOW(),
    expires_at = $3
WHERE id = $1
  AND revoked_at IS NULL
RETURNING *;

-- name: RevokeUserSession :execrows
UPDATE sessions
SET revoked_at = NOW()
WHERE id = $1
  AND user_id = $2
  AND revoked_at IS NULL;

-- name: RevokeAllUserSessions :execrows
UPDATE sessions
SET revoked_at = NOW()
WHERE user_id = $1
  AND revoked_at IS NULL;

-- name: RevokeOtherUserSessions :execrows
UPDATE sessions
SET revoked_at = NOW()
WHERE user_id = $1
  AND id <> $2
  AND revoked_at IS NULL;

-- name: ListUserSessions :many
SELECT
    id,
    user_agent,
    ip_address,
    expires_at,
    revoked_at,
    last_used_at,
    created_at
FROM sessions
WHERE user_id = $1
  AND revoked_at IS NULL
  AND expires_at > NOW()
ORDER BY last_used_at DESC;

-- name: GetAuthContext :one
SELECT
    u.id,
    u.email,
    u.full_name,
    u.is_active,
    u.last_login_at,
    u.created_at,
    u.updated_at,
    s.id AS session_id,
    s.expires_at AS session_expires_at,
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
FROM sessions s
JOIN users u ON u.id = s.user_id
WHERE s.id = $1
  AND s.revoked_at IS NULL
  AND s.expires_at > NOW()
  AND u.deleted_at IS NULL
  AND u.is_active = TRUE;

-- name: DeleteStaleSessions :execrows
DELETE FROM sessions
WHERE (expires_at < NOW() - INTERVAL '30 days')
   OR (revoked_at IS NOT NULL AND revoked_at < NOW() - INTERVAL '30 days');
