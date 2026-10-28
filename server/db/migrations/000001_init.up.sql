-- 000001_init.up.sql
-- Esquema base del sistema de ventas a crédito: autenticación y RBAC.

CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─────────────────────────────────────────────────────────────
-- Usuarios
-- ─────────────────────────────────────────────────────────────
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         CITEXT NOT NULL,
    password_hash TEXT NOT NULL,
    full_name     TEXT NOT NULL,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at    TIMESTAMPTZ
);

-- Permite reutilizar un correo si el usuario anterior fue eliminado (soft delete).
CREATE UNIQUE INDEX users_email_active_uidx
    ON users (email)
    WHERE deleted_at IS NULL;

CREATE INDEX users_deleted_at_idx ON users (deleted_at);
CREATE INDEX users_created_at_idx ON users (created_at DESC);

COMMENT ON TABLE users IS 'Usuarios del sistema (empleados y administradores)';
COMMENT ON COLUMN users.deleted_at IS 'Soft delete: NULL significa usuario vigente';

-- ─────────────────────────────────────────────────────────────
-- Roles
-- ─────────────────────────────────────────────────────────────
CREATE TABLE roles (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    description TEXT,
    is_system   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT roles_name_format CHECK (name ~ '^[a-z][a-z0-9_-]{2,49}$')
);

COMMENT ON TABLE roles IS 'Roles del sistema; el rol admin es de sistema y no se elimina';
COMMENT ON COLUMN roles.is_system IS 'Los roles de sistema no pueden eliminarse desde la API';

-- ─────────────────────────────────────────────────────────────
-- Permisos
-- ─────────────────────────────────────────────────────────────
CREATE TABLE permissions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    description TEXT,
    module      TEXT NOT NULL DEFAULT 'general',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT permissions_name_format CHECK (name ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){0,2}$')
);

CREATE INDEX permissions_module_idx ON permissions (module);

COMMENT ON TABLE permissions IS 'Catálogo de permisos atómicos asignables a roles';

-- ─────────────────────────────────────────────────────────────
-- Relación roles ↔ permisos
-- ─────────────────────────────────────────────────────────────
CREATE TABLE role_permissions (
    role_id       UUID NOT NULL REFERENCES roles (id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions (id) ON DELETE CASCADE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (role_id, permission_id)
);

CREATE INDEX role_permissions_permission_id_idx
    ON role_permissions (permission_id);

-- ─────────────────────────────────────────────────────────────
-- Relación usuarios ↔ roles
-- ─────────────────────────────────────────────────────────────
CREATE TABLE user_roles (
    user_id     UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    role_id     UUID NOT NULL REFERENCES roles (id) ON DELETE CASCADE,
    assigned_by UUID REFERENCES users (id) ON DELETE SET NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, role_id)
);

CREATE INDEX user_roles_role_id_idx ON user_roles (role_id);
CREATE INDEX user_roles_assigned_by_idx ON user_roles (assigned_by);

-- ─────────────────────────────────────────────────────────────
-- Sesiones (refresh tokens)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE sessions (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    refresh_token_hash TEXT NOT NULL UNIQUE,
    user_agent         TEXT,
    ip_address         TEXT,
    expires_at         TIMESTAMPTZ NOT NULL,
    revoked_at         TIMESTAMPTZ,
    last_used_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX sessions_user_id_idx ON sessions (user_id);
CREATE INDEX sessions_expires_at_idx ON sessions (expires_at);
CREATE INDEX sessions_active_idx
    ON sessions (user_id)
    WHERE revoked_at IS NULL;

COMMENT ON TABLE sessions IS 'Sesiones activas; guarda el hash SHA-256 del refresh token, nunca el token';

-- ─────────────────────────────────────────────────────────────
-- Trigger genérico de updated_at
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER roles_set_updated_at
    BEFORE UPDATE ON roles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER permissions_set_updated_at
    BEFORE UPDATE ON permissions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
