#!/usr/bin/env bash
set -euo pipefail

# Carga permisos, roles y usuarios iniciales. Ejecutar UNA VEZ tras el primer deploy.
# El seed es idempotente, pero crea las cuentas demo vendedor/cobrador si no existen.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$DEPLOY_DIR/.env}"
COMPOSE=(docker compose --project-directory "$DEPLOY_DIR" -f "$DEPLOY_DIR/docker-compose.prod.yml" --env-file "$ENV_FILE")

cd "$DEPLOY_DIR"
"${COMPOSE[@]}" run --rm --entrypoint /app/seed api
