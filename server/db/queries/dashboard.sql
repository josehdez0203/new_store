-- name: GetDashboardStats :one
SELECT
    (SELECT COUNT(*) FROM users WHERE deleted_at IS NULL) AS users_total,
    (SELECT COUNT(*) FROM users WHERE deleted_at IS NULL AND is_active = TRUE) AS users_active,
    (SELECT COUNT(*) FROM roles) AS roles_total,
    (SELECT COUNT(*) FROM permissions) AS permissions_total,
    (SELECT COUNT(*) FROM sessions WHERE revoked_at IS NULL AND expires_at > NOW()) AS active_sessions;

-- name: ListUserCountsByRole :many
SELECT
    r.name::text AS role,
    COUNT(u.id) AS total
FROM roles r
LEFT JOIN user_roles ur ON ur.role_id = r.id
LEFT JOIN users u ON u.id = ur.user_id AND u.deleted_at IS NULL
GROUP BY r.name
ORDER BY r.name;
