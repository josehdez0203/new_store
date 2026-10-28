-- 000001_init.down.sql
DROP TRIGGER IF EXISTS permissions_set_updated_at ON permissions;
DROP TRIGGER IF EXISTS roles_set_updated_at ON roles;
DROP TRIGGER IF EXISTS users_set_updated_at ON users;
DROP FUNCTION IF EXISTS set_updated_at();

DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS user_roles;
DROP TABLE IF EXISTS role_permissions;
DROP TABLE IF EXISTS permissions;
DROP TABLE IF EXISTS roles;
DROP TABLE IF EXISTS users;
