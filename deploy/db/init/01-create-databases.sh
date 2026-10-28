#!/bin/sh
set -eu

# Crea las dos bases de datos si no existen. Es idempotente y se ejecuta:
#  - en la inicialización de un volumen PostgreSQL nuevo;
#  - en el servicio db-init en cada `docker compose up`.
API_DB_NAME="${API_DB_NAME:-api-store}"
XAPARI_DB_NAME="${XAPARI_DB_NAME:-xapari}"
ADMIN_DB="${POSTGRES_DB:-postgres}"

psql -v ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER" \
    --dbname "$ADMIN_DB" \
    -v api_db="$API_DB_NAME" \
    -v xapari_db="$XAPARI_DB_NAME" <<'SQL'
SELECT format('CREATE DATABASE %I OWNER %I', :'api_db', current_user)
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'api_db')
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'xapari_db', current_user)
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'xapari_db')
\gexec
SQL
