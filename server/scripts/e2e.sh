#!/usr/bin/env bash
set -uo pipefail
BASE="http://127.0.0.1:8081/api/v1"
TMP="$(mktemp -d)"
PASS=0
FAIL=0

pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1 (status=$2 body=$3)"; FAIL=$((FAIL+1)); }

req() { # method path token [data]
  local method="$1" path="$2" token="${3:-}" data="${4:-}"
  local args=(-s -o "$TMP/body.json" -w '%{http_code}' -X "$method" "$BASE$path")
  [ -n "$token" ] && args+=(-H "Authorization: Bearer $token")
  if [ -n "$data" ]; then
    args+=(-H 'Content-Type: application/json' -d "$data")
  fi
  curl "${args[@]}"
}

expect() { # expected actual label
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3" "$2" "$(cat "$TMP/body.json")"; fi
}

login() {
  curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$2\"}" -o "$TMP/login.json" -w '%{http_code}'
}

ADMIN_RAW=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d '{"email":"admin@gmail.com","password":"123456"}')
ADMIN=$(jq -r '.data.access_token' <<<"$ADMIN_RAW")
ADMIN_REFRESH=$(jq -r '.data.refresh_token' <<<"$ADMIN_RAW")

# --- Auth base ---
expect 200 "$(req GET /auth/me "$ADMIN")" "admin /auth/me"
expect 200 "$(req GET /dashboard/stats "$ADMIN")" "admin /dashboard/stats"
expect 200 "$(req GET /users "$ADMIN")" "admin lista usuarios"
jq -e '.data | length == 3' "$TMP/body.json" >/dev/null && pass "seed tiene 3 usuarios" || fail "seed tiene 3 usuarios" 0 "$(cat "$TMP/body.json")"
expect 200 "$(req GET /roles "$ADMIN")" "admin lista roles"
expect 200 "$(req GET /permissions "$ADMIN")" "admin lista permisos"

VENDEDOR_RAW=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d '{"email":"vendedor@gmail.com","password":"123456"}')
VENDEDOR=$(jq -r '.data.access_token' <<<"$VENDEDOR_RAW")
expect 403 "$(req GET /users "$VENDEDOR")" "vendedor no puede listar usuarios"
expect 200 "$(req GET /dashboard/stats "$VENDEDOR")" "vendedor ve dashboard (tiene permiso)"
expect 200 "$(req GET /auth/me "$VENDEDOR")" "vendedor /auth/me"
jq -e '.data.roles == ["vendedor"]' "$TMP/body.json" >/dev/null && pass "vendedor tiene rol vendedor" || fail "vendedor rol" 200 "$(cat "$TMP/body.json")"

# IDs de catálogo
VENDEDOR_ROLE=$(req GET /roles "$ADMIN" >/dev/null; jq -r '.data[] | select(.name=="vendedor") | .id' "$TMP/body.json")
ADMIN_ROLE=$(req GET /roles "$ADMIN" >/dev/null; jq -r '.data[] | select(.name=="admin") | .id' "$TMP/body.json")
DASH_PERM=$(req GET /permissions "$ADMIN" >/dev/null; jq -r '.data[] | select(.name=="dashboard.read") | .id' "$TMP/body.json")
REPORTS_PERM=$(req GET /permissions "$ADMIN" >/dev/null; jq -r '.data[] | select(.name=="reports.read") | .id' "$TMP/body.json")

# --- CRUD usuario ---
STATUS=$(req POST /users "$ADMIN" "{\"email\":\"nuevo@gmail.com\",\"full_name\":\"Nuevo Vendedor\",\"password\":\"123456\",\"role_ids\":[\"$VENDEDOR_ROLE\"]}")
expect 201 "$STATUS" "crear usuario"
NEW_ID=$(jq -r '.data.id' "$TMP/body.json")

expect 200 "$(req GET "/users/$NEW_ID" "$ADMIN")" "obtener usuario"
jq -e '.data.roles == ["vendedor"]' "$TMP/body.json" >/dev/null && pass "usuario creado con rol" || fail "usuario con rol" 200 "$(cat "$TMP/body.json")"

expect 200 "$(login nuevo@gmail.com 123456)" "login usuario nuevo"
NEW_TOKEN=$(jq -r '.data.access_token' "$TMP/login.json")
expect 403 "$(req GET /users "$NEW_TOKEN")" "usuario nuevo sin permiso de usuarios"

expect 200 "$(req PATCH "/users/$NEW_ID" "$ADMIN" '{"full_name":"Nuevo Vendedor Actualizado"}')" "actualizar usuario"
jq -e '.data.full_name == "Nuevo Vendedor Actualizado"' "$TMP/body.json" >/dev/null && pass "nombre actualizado" || fail "nombre actualizado" 200 "$(cat "$TMP/body.json")"

expect 204 "$(req POST "/users/$NEW_ID/reset-password" "$ADMIN" '{"password":"654321"}')" "reset password admin"
expect 401 "$(login nuevo@gmail.com 123456)" "password anterior ya no sirve"
expect 200 "$(login nuevo@gmail.com 654321)" "login con password reseteado"
NEW_TOKEN2=$(jq -r '.data.access_token' "$TMP/login.json")

expect 200 "$(req PATCH "/users/$NEW_ID" "$ADMIN" '{"is_active":false}')" "desactivar usuario"
expect 401 "$(req GET /auth/me "$NEW_TOKEN2")" "token de usuario desactivado rechazado"
expect 403 "$(login nuevo@gmail.com 654321)" "login de usuario desactivado rechazado"
expect 200 "$(req PATCH "/users/$NEW_ID" "$ADMIN" '{"is_active":true}')" "reactivar usuario"

# --- Protecciones admin ---
ADMIN_ID=$(req GET /auth/me "$ADMIN" >/dev/null; jq -r '.data.id' "$TMP/body.json")
expect 409 "$(req DELETE "/users/$ADMIN_ID" "$ADMIN")" "no puede eliminarse a sí mismo"
expect 409 "$(req PUT "/users/$ADMIN_ID/roles" "$ADMIN" '{"role_ids":[]}')" "no puede quitarse el último admin"
expect 409 "$(req DELETE "/roles/$ADMIN_ROLE" "$ADMIN")" "no puede borrar rol de sistema"
expect 409 "$(req PATCH "/users/$ADMIN_ID" "$ADMIN" '{"is_active":false}')" "no puede desactivarse a sí mismo"

# --- Refresh tokens ---
ROT=$(curl -s -X POST "$BASE/auth/refresh" -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$ADMIN_REFRESH\"}")
ROT_ACCESS=$(jq -r '.data.access_token' <<<"$ROT")
[ "$ROT_ACCESS" != "null" ] && pass "refresh emite access token" || fail "refresh emite access token" 0 "$ROT"
expect 401 "$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X POST "$BASE/auth/refresh" -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$ADMIN_REFRESH\"}")" "refresh token rotado no reutilizable"
expect 200 "$(req GET /auth/me "$ROT_ACCESS")" "access token refrescado funciona"
expect 204 "$(req POST /auth/logout "$ROT_ACCESS")" "logout"
expect 401 "$(req GET /auth/me "$ROT_ACCESS")" "token revocado tras logout"

# --- Sesiones ---
ADMIN_RAW2=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' -d '{"email":"admin@gmail.com","password":"123456"}')
SESSION_A=$(jq -r '.data.access_token' <<<"$ADMIN_RAW2")
ADMIN_RAW3=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' -d '{"email":"admin@gmail.com","password":"123456"}')
SESSION_B=$(jq -r '.data.access_token' <<<"$ADMIN_RAW3")
expect 200 "$(req GET /auth/sessions "$SESSION_B")" "listar sesiones"
jq -e '[.data[] | select(.current==true)] | length == 1' "$TMP/body.json" >/dev/null && pass "marca la sesión actual" || fail "marca sesión actual" 200 "$(cat "$TMP/body.json")"
SESSION_A_ID=$(req GET /auth/sessions "$SESSION_A" >/dev/null; jq -r '.data[] | select(.current==true) | .id' "$TMP/body.json")
expect 204 "$(req DELETE "/auth/sessions/$SESSION_A_ID" "$SESSION_B")" "revocar otra sesión"
expect 401 "$(req GET /auth/me "$SESSION_A")" "sesión revocada rechazada"

# La sesión original se cerró en la prueba de logout: usa la sesión B desde aquí.
ADMIN="$SESSION_B"

# --- CRUD roles ---
STATUS=$(req POST /roles "$ADMIN" "{\"name\":\"supervisor\",\"description\":\"Supervisa operaciones\",\"permission_ids\":[\"$DASH_PERM\"]}")
expect 201 "$STATUS" "crear rol"
ROLE_ID=$(jq -r '.data.id' "$TMP/body.json")
expect 200 "$(req GET "/roles/$ROLE_ID" "$ADMIN")" "obtener rol"
jq -e '.data.permissions | length == 1' "$TMP/body.json" >/dev/null && pass "rol con permiso asignado" || fail "rol con permiso" 200 "$(cat "$TMP/body.json")"
expect 200 "$(req PUT "/roles/$ROLE_ID" "$ADMIN" '{"name":"supervisor","description":"Supervisión general"}')" "actualizar rol"
expect 200 "$(req PUT "/roles/$ROLE_ID/permissions" "$ADMIN" "{\"permission_ids\":[\"$DASH_PERM\",\"$REPORTS_PERM\"]}")" "reemplazar permisos del rol"
jq -e '.data.permission_count == 2' "$TMP/body.json" >/dev/null && pass "dos permisos en rol" || fail "dos permisos" 200 "$(cat "$TMP/body.json")"
expect 409 "$(req POST /roles "$ADMIN" '{"name":"supervisor","description":"duplicado"}')" "rol duplicado conflictúa"
expect 204 "$(req DELETE "/roles/$ROLE_ID" "$ADMIN")" "eliminar rol"

# --- CRUD permisos ---
STATUS=$(req POST /permissions "$ADMIN" '{"name":"test.read","description":"Permiso de prueba","module":"test"}')
expect 201 "$STATUS" "crear permiso"
PERM_ID=$(jq -r '.data.id' "$TMP/body.json")
expect 200 "$(req PUT "/permissions/$PERM_ID" "$ADMIN" '{"name":"test.read","description":"Permiso actualizado","module":"test"}')" "actualizar permiso"
expect 204 "$(req DELETE "/permissions/$PERM_ID" "$ADMIN")" "eliminar permiso sin roles"

STATUS=$(req POST /permissions "$ADMIN" '{"name":"test.write","description":"Otro permiso","module":"test"}')
PERM2_ID=$(jq -r '.data.id' "$TMP/body.json")
STATUS=$(req POST /roles "$ADMIN" "{\"name\":\"temporal\",\"description\":\"Rol temporal\",\"permission_ids\":[\"$PERM2_ID\"]}")
TEMP_ROLE=$(jq -r '.data.id' "$TMP/body.json")
expect 409 "$(req DELETE "/permissions/$PERM2_ID" "$ADMIN")" "no elimina permiso asignado"
expect 204 "$(req DELETE "/roles/$TEMP_ROLE" "$ADMIN")" "elimina rol temporal"
expect 204 "$(req DELETE "/permissions/$PERM2_ID" "$ADMIN")" "elimina permiso tras desasignar"

# --- Validaciones ---
expect 422 "$(req POST /users "$ADMIN" '{"email":"no-es-correo","full_name":"X","password":"123"}')" "validación crear usuario"
jq -e '.error.details | length >= 2' "$TMP/body.json" >/dev/null && pass "detalles de validación por campo" || fail "detalles de validación" 422 "$(cat "$TMP/body.json")"
expect 422 "$(req POST /roles "$ADMIN" '{"name":"X"}')" "validación nombre de rol"
expect 400 "$(req GET '/users?page=0' "$ADMIN")" "paginación inválida"
expect 400 "$(req GET '/users/no-es-uuid' "$ADMIN")" "UUID inválido"
expect 401 "$(curl -s -o "$TMP/body.json" -w '%{http_code}' "$BASE/users")" "sin token rechazado"

# --- Eliminar usuario ---
expect 204 "$(req DELETE "/users/$NEW_ID" "$ADMIN")" "eliminar usuario"
expect 401 "$(login nuevo@gmail.com 654321)" "usuario eliminado no puede entrar"

# --- CORS ---
CORS_HEADERS=$(curl -s -D - -o /dev/null -X OPTIONS "$BASE/auth/login" \
  -H 'Origin: http://localhost:5173' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type')
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "$BASE/auth/login" \
  -H 'Origin: http://localhost:5173' -H 'Access-Control-Request-Method: POST')
[ "$CODE" = "204" ] && pass "preflight CORS" || fail "preflight CORS" "$CODE" "$CORS_HEADERS"
grep -qi 'Access-Control-Allow-Origin: http://localhost:5173' <<<"$CORS_HEADERS" && pass "CORS permite localhost" || fail "CORS permite localhost" 0 "$CORS_HEADERS"

echo
echo "RESULTADO: $PASS pasaron, $FAIL fallaron"
rm -rf "$TMP"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
