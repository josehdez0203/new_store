#!/usr/bin/env bash
# Suite E2E del catálogo de productos y su galería de fotos.
# Requiere el API en ejecución y jq.
set -uo pipefail

BASE="${BASE_URL:-http://127.0.0.1:8081/api/v1}"
ORIGIN="${BASE%/api/v1}"
TMP="$(mktemp -d)"
PASS=0
FAIL=0
PRODUCT_ID=""
SERVICE_ID=""

pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1 (status=$2 body=$(cat "$TMP/body.json" 2>/dev/null))"; FAIL=$((FAIL + 1)); }

req() {
  local method="$1" path="$2" token="${3:-}" data="${4:-}"
  local args=(-s -o "$TMP/body.json" -w '%{http_code}' -X "$method" "$BASE$path")
  [ -n "$token" ] && args+=(-H "Authorization: Bearer $token")
  if [ -n "$data" ]; then
    args+=(-H 'Content-Type: application/json' -d "$data")
  fi
  curl "${args[@]}"
}

expect() {
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3" "$2"; fi
}

# PNG 1x1 válido, suficiente para validar el flujo de archivos.
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' \
  | base64 -d > "$TMP/p1.png"
for n in 2 3 4 5; do cp "$TMP/p1.png" "$TMP/p$n.png"; done
printf 'no soy una imagen' > "$TMP/bad.txt"

ADMIN_RAW=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d '{"email":"admin@gmail.com","password":"123456"}')
ADMIN=$(jq -r '.data.access_token' <<<"$ADMIN_RAW")
VENDEDOR_RAW=$(curl -s -X POST "$BASE/auth/login" -H 'Content-Type: application/json' \
  -d '{"email":"vendedor@gmail.com","password":"123456"}')
VENDEDOR=$(jq -r '.data.access_token' <<<"$VENDEDOR_RAW")

BARCODE="TEST-IMG-$(date +%s)"
STATUS=$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X POST "$BASE/products" \
  -H "Authorization: Bearer $ADMIN" \
  -F "name=TEST Producto" -F "description=Producto de prueba" -F "barcode=$BARCODE" \
  -F "price=35.5" -F "cost=12.25" -F "type=product" \
  -F "images=@$TMP/p1.png" -F "images=@$TMP/p2.png" -F "images=@$TMP/p3.png")
expect 201 "$STATUS" "crear producto con 3 fotos"
PRODUCT_ID=$(jq -r '.data.id' "$TMP/body.json")
jq -e '.data.margin == 23.25 and .data.images_count == 3 and (.data.images | length) == 3' \
  "$TMP/body.json" >/dev/null \
  && pass "margen y galería de 3 fotos" || fail "margen y galería de 3 fotos" 201

IMAGE_URL=$(jq -r '.data.images[0].url' "$TMP/body.json")
expect 200 "$(curl -s -o /dev/null -w '%{http_code}' "$ORIGIN$IMAGE_URL")" \
  "servir foto desde /downloads"

STATUS=$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X POST "$BASE/products" \
  -H "Authorization: Bearer $ADMIN" \
  -F "name=TEST Pocas" -F "price=1" -F "cost=0" -F "type=product" \
  -F "images=@$TMP/p1.png" -F "images=@$TMP/p2.png")
expect 422 "$STATUS" "rechazar producto con menos de 3 fotos"

STATUS=$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X POST "$BASE/products" \
  -H "Authorization: Bearer $ADMIN" \
  -F "name=TEST Archivo inválido" -F "price=1" -F "cost=0" -F "type=product" \
  -F "images=@$TMP/p1.png" -F "images=@$TMP/p2.png" -F "images=@$TMP/bad.txt")
expect 422 "$STATUS" "rechazar archivo que no es imagen"

STATUS=$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X POST "$BASE/products" \
  -H "Authorization: Bearer $ADMIN" \
  -F "name=TEST Duplicado" -F "barcode=$BARCODE" -F "price=10" -F "cost=5" \
  -F "type=product" \
  -F "images=@$TMP/p1.png" -F "images=@$TMP/p2.png" -F "images=@$TMP/p3.png")
expect 409 "$STATUS" "código de barras duplicado"

STATUS=$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X POST "$BASE/products" \
  -H "Authorization: Bearer $ADMIN" \
  -F "name=TEST Servicio" -F "price=200" -F "cost=0" -F "type=service" \
  -F "images=@$TMP/p1.png" -F "images=@$TMP/p2.png" -F "images=@$TMP/p3.png")
expect 201 "$STATUS" "crear servicio con 3 fotos"
SERVICE_ID=$(jq -r '.data.id' "$TMP/body.json")

expect 200 "$(req GET '/products?search=TEST' "$ADMIN")" "buscar productos"
jq -e '(.data | length) == 2' "$TMP/body.json" >/dev/null \
  && pass "búsqueda devuelve 2" || fail "búsqueda devuelve 2" 200
expect 200 "$(req GET '/products?search=TEST&type=service' "$ADMIN")" "filtrar servicios"
jq -e '(.data | length) == 1 and .data[0].type == "service"' "$TMP/body.json" >/dev/null \
  && pass "filtro service" || fail "filtro service" 200
expect 200 "$(req GET '/products?search=TEST&type=product' "$ADMIN")" "filtrar productos"
jq -e '(.data | length) == 1 and .data[0].type == "product"' "$TMP/body.json" >/dev/null \
  && pass "filtro product" || fail "filtro product" 200

expect 200 "$(req GET "/products/$PRODUCT_ID" "$ADMIN")" "obtener producto"
STATUS=$(req PUT "/products/$PRODUCT_ID" "$ADMIN" \
  "{\"name\":\"TEST Producto Editado\",\"description\":\"Actualizado\",\"barcode\":\"$BARCODE\",\"price\":50,\"cost\":20,\"type\":\"product\"}")
expect 200 "$STATUS" "actualizar datos del producto"
jq -e '.data.margin == 30 and .data.images_count == 3' "$TMP/body.json" >/dev/null \
  && pass "actualización conserva fotos y recalcula margen" \
  || fail "actualización conserva fotos y recalcula margen" 200

STATUS=$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X POST "$BASE/products/$PRODUCT_ID/images" \
  -H "Authorization: Bearer $ADMIN" -F "images=@$TMP/p4.png")
expect 200 "$STATUS" "agregar cuarta foto"
jq -e '.data.images_count == 4' "$TMP/body.json" >/dev/null \
  && pass "cuenta sube a 4" || fail "cuenta sube a 4" 200
NEW_IMAGE=$(jq -r '.data.images[-1].id' "$TMP/body.json")
FIRST_IMAGE=$(jq -r '.data.images[0].id' "$TMP/body.json")

STATUS=$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X PUT \
  "$BASE/products/$PRODUCT_ID/images/$FIRST_IMAGE" \
  -H "Authorization: Bearer $ADMIN" -F "image=@$TMP/p5.png")
expect 200 "$STATUS" "reemplazar una foto"
jq -e '.data.images_count == 4' "$TMP/body.json" >/dev/null \
  && pass "reemplazo conserva 4 fotos" || fail "reemplazo conserva 4 fotos" 200
REPLACED_URL=$(jq -r '.data.images[0].url' "$TMP/body.json")
expect 200 "$(curl -s -o /dev/null -w '%{http_code}' "$ORIGIN$REPLACED_URL")" \
  "servir la foto reemplazada"

expect 200 "$(req GET "/products/$PRODUCT_ID/images" "$ADMIN")" "listar galería"
jq -e '(.data | length) == 4' "$TMP/body.json" >/dev/null \
  && pass "galería con 4 fotos" || fail "galería con 4 fotos" 200

expect 204 "$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X DELETE \
  "$BASE/products/$PRODUCT_ID/images/$NEW_IMAGE" -H "Authorization: Bearer $ADMIN")" \
  "eliminar cuarta foto"
expect 409 "$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X DELETE \
  "$BASE/products/$PRODUCT_ID/images/$FIRST_IMAGE" -H "Authorization: Bearer $ADMIN")" \
  "no permitir bajar de 3 fotos"

expect 200 "$(req GET /products "$VENDEDOR")" "vendedor puede listar productos"
jq -e '(.data | length) > 0 and ([.data[] | has("margin")] | all(. == false))' "$TMP/body.json" >/dev/null \
  && pass "vendedor no recibe el margen" || fail "vendedor no recibe el margen" 200
expect 200 "$(req GET "/products/$PRODUCT_ID/images" "$VENDEDOR")" "vendedor puede ver fotos"
STATUS=$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X POST \
  "$BASE/products/$PRODUCT_ID/images" -H "Authorization: Bearer $VENDEDOR" \
  -F "images=@$TMP/p4.png")
expect 403 "$STATUS" "vendedor no puede agregar fotos"
STATUS=$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X PUT \
  "$BASE/products/$PRODUCT_ID/images/$FIRST_IMAGE" -H "Authorization: Bearer $VENDEDOR" \
  -F "image=@$TMP/p5.png")
expect 403 "$STATUS" "vendedor no puede reemplazar fotos"
expect 403 "$(curl -s -o "$TMP/body.json" -w '%{http_code}' -X DELETE \
  "$BASE/products/$PRODUCT_ID/images/$FIRST_IMAGE" -H "Authorization: Bearer $VENDEDOR")" \
  "vendedor no puede eliminar fotos"
expect 403 "$(req POST /products "$VENDEDOR" '{"name":"TEST Vendedor","price":1,"cost":0,"type":"product"}')" \
  "vendedor no puede crear productos"
expect 403 "$(req PUT "/products/$PRODUCT_ID" "$VENDEDOR" \
  "{\"name\":\"TEST Vendedor\",\"price\":1,\"cost\":0,\"type\":\"product\"}")" \
  "vendedor no puede actualizar productos"
expect 403 "$(req DELETE "/products/$PRODUCT_ID" "$VENDEDOR")" \
  "vendedor no puede eliminar productos"

STATUS=$(req POST /products "$ADMIN" '{"name":"TEST Inexistente","price":1,"cost":0,"type":"product"}')
expect 422 "$STATUS" "rechazar creación JSON sin fotos"

expect 204 "$(req DELETE "/products/$SERVICE_ID" "$ADMIN")" "eliminar servicio"
expect 404 "$(req GET "/products/$SERVICE_ID" "$ADMIN")" "servicio eliminado no se encuentra"
expect 204 "$(req DELETE "/products/$PRODUCT_ID" "$ADMIN")" "eliminar producto"
expect 404 "$(req GET "/products/$PRODUCT_ID" "$ADMIN")" "producto eliminado no se encuentra"
expect 200 "$(req GET '/products?search=TEST' "$ADMIN")" "productos eliminados fuera del listado"
jq -e '(.data | length) == 0' "$TMP/body.json" >/dev/null \
  && pass "soft delete oculta los productos" || fail "soft delete" 200

echo
echo "RESULTADO: $PASS pasaron, $FAIL fallaron"
rm -rf "$TMP"

# Limpieza física de los datos de prueba y sus archivos, si Docker está disponible.
if command -v docker >/dev/null 2>&1; then
  docker compose exec -T db psql -U "${POSTGRES_USER:-credit_store}" \
    -d "${POSTGRES_DB:-credit_store}" -tAc \
    "SELECT id FROM products WHERE name LIKE 'TEST %';" 2>/dev/null \
    | while read -r product_id; do
        if [ -n "$product_id" ]; then
          rm -rf -- "downloads/products/$product_id"
        fi
      done
  docker compose exec -T db psql -U "${POSTGRES_USER:-credit_store}" \
    -d "${POSTGRES_DB:-credit_store}" \
    -c "DELETE FROM products WHERE name LIKE 'TEST %';" >/dev/null 2>&1 || true
fi

exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
