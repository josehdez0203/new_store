# CrediStore API

API REST del sistema de ventas a crédito: autenticación con JWT + refresh
tokens, sesiones persistidas, RBAC (usuarios, roles y permisos) y métricas del
panel.

## Stack

- Go 1.26.5 · Gin 1.12.0
- PostgreSQL 17 con pgx/v5 5.11.0 (`pgxpool`)
- sqlc v1.30.0
- golang-migrate v4.20.1
- Air v1.65.3

## Arranque

```bash
cp .env.example .env
make up       # PostgreSQL 17 en localhost:5433
make air      # API en localhost:8081 con recarga en caliente
```

Sin Air:

```bash
make run      # go run ./cmd/api
# o
make build && ./bin/api
```

`make dev` ejecuta `make up` y luego Air. Al arrancar, el API espera a Postgres,
aplica las migraciones y ejecuta el seed si `AUTO_MIGRATE` / `SEED_ON_START`
están activos.

Comprobación rápida:

```bash
curl http://localhost:8081/health
curl http://localhost:8081/ready
```

## Variables de entorno

Se cargan desde `.env` (desarrollo) y las variables del proceso tienen
precedencia.

| Variable | Por defecto | Descripción |
|---|---|---|
| `APP_ENV` | `development` | `development` o `production` |
| `API_PORT` | `8081` | Puerto HTTP |
| `DATABASE_URL` | `postgres://credit_store:credit_store@localhost:5433/credit_store?sslmode=disable` | Conexión a Postgres |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | `credit_store` | Credenciales del contenedor |
| `POSTGRES_PORT` | `5433` | Puerto host de Postgres |
| `JWT_SECRET` | secreto de desarrollo | Firma HS256; mínimo 32 caracteres |
| `JWT_ISSUER` | `credit-store-api` | Issuer esperado en el token |
| `ACCESS_TOKEN_TTL` | `15m` | Vigencia del access token |
| `REFRESH_TOKEN_TTL` | `168h` | Vigencia del refresh token |
| `BCRYPT_COST` | `12` | Costo bcrypt (10–14) |
| `CORS_ORIGINS` | — | Orígenes exactos permitidos en producción |
| `AUTO_MIGRATE` | `true` | Aplica migraciones al iniciar |
| `SEED_ON_START` | `true` en desarrollo | Carga datos de prueba |
| `SEED_PASSWORD` | `123456` | Contraseña de los usuarios seed |
| `DOWNLOADS_DIR` | `./downloads` | Carpeta de fotos de productos; se sirve en `/downloads` |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` |

En desarrollo se permite cualquier origen `localhost`, `127.0.0.1` o `::1`
(necesario para el puerto aleatorio de Flutter web). En producción solo se
aceptan los orígenes de `CORS_ORIGINS`.

## Modelo de datos

```text
users ──< user_roles >── roles ──< role_permissions >── permissions
  │
  └──< sessions
```

Diagrama ER, cardinalidades y reglas de borrado:
[docs/database.md](../docs/database.md).

- `users`: soft delete (`deleted_at`), estado activo, hash bcrypt y último acceso.
- `roles`: nombre único; `is_system` protege al rol `admin`.
- `permissions`: catálogo con nombre único (`modulo.accion`) y módulo.
- `role_permissions` y `user_roles`: tablas pivote con integridad referencial.
- `sessions`: `refresh_token_hash` (SHA-256), user agent, IP, expiración,
  revocación y último uso. Nunca guarda el refresh token en claro.
- `products`: catálogo de productos/servicios. `margin` es una columna generada
  (`price - cost`), `barcode` es único entre productos vigentes y el borrado es
  lógico (`deleted_at`).
- `product_images`: fotografías del catálogo (1 producto → N fotos). Los archivos
  se guardan en `DOWNLOADS_DIR/products/<producto>/` y se publican bajo
  `/downloads/...`; `file_path` es único.
- `customers`: clientes con datos de contacto, dirección y estado
  (`prospecto`, `cliente`, `en_pago`, `liquidado`). Usa soft delete.
- `credit_settings`: configuración única de anticipos (porcentajes), plazos y
  interés mensual. Solo el admin la modifica.
- `sales`: venta/cotización con cliente, vendedor, fecha, estado, forma de pago,
  anticipo, financiamiento, interés y total calculado.
- `sale_items`: partidas con producto, cantidad, precio snapshot y subtotal.
- `sale_payments`: plan de pagos generado (anticipo, mensualidades o contado).

## Autenticación

1. `POST /api/v1/auth/login` valida correo/contraseña, crea una fila en
   `sessions` y devuelve un **access token** y un **refresh token**.
2. Las peticiones autenticadas usan `Authorization: Bearer <access_token>`.
3. Cuando el access token expira, `POST /api/v1/auth/refresh` rota el refresh
   token: el anterior deja de funcionar y se emite un par nuevo.
4. `POST /api/v1/auth/logout` revoca la sesión actual;
   `POST /api/v1/auth/logout-all` revoca todas.
5. El middleware vuelve a consultar la sesión y los permisos en cada petición,
   por lo que un logout, una desactivación o un cambio de roles se aplican al
   instante.

El access token incluye `sub`, `sid`, `email`, `roles` y `permissions` como
datos informativos; la autorización real se resuelve con la base de datos.

### Ejemplo de login

```bash
curl -s -X POST http://localhost:8081/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@gmail.com","password":"123456"}' | jq
```

```json
{
  "data": {
    "access_token": "eyJ...",
    "refresh_token": "osCs...",
    "token_type": "Bearer",
    "expires_in": 900,
    "refresh_expires_in": 604800,
    "user": {
      "id": "10bfb55b-f409-4d9f-963e-698c59bc4f9a",
      "email": "admin@gmail.com",
      "full_name": "Administrador del Sistema",
      "is_active": true,
      "roles": ["admin"],
      "permissions": ["dashboard.read", "users.read"],
      "last_login_at": "2026-10-26T22:02:00Z",
      "created_at": "2026-10-26T22:01:54Z",
      "updated_at": "2026-10-26T22:01:54Z"
    }
  }
}
```

## Endpoints

Base: `http://localhost:8081/api/v1`

### Salud

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| GET | `/health` | No | Liveness |
| GET | `/ready` | No | Comprueba Postgres |

### Autenticación y sesiones

| Método | Ruta | Auth | Permiso |
|---|---|---|---|
| POST | `/auth/login` | No | — |
| POST | `/auth/refresh` | No | — |
| GET | `/auth/me` | Sí | — |
| PATCH | `/auth/me` | Sí | — |
| POST | `/auth/logout` | Sí | — |
| POST | `/auth/logout-all` | Sí | — |
| POST | `/auth/change-password` | Sí | — |
| GET | `/auth/sessions` | Sí | — |
| DELETE | `/auth/sessions/:id` | Sí | — |

`PATCH /auth/me` acepta `full_name` y/o `email`.
`POST /auth/change-password` requiere `current_password` y `new_password` (mínimo
6 caracteres) y revoca las demás sesiones.

### Usuarios

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/users?search=&role=&is_active=&page=&page_size=` | `users.read` |
| POST | `/users` | `users.create` |
| GET | `/users/:id` | `users.read` |
| PATCH | `/users/:id` | `users.update` |
| DELETE | `/users/:id` | `users.delete` |
| PUT | `/users/:id/roles` | `users.assign_roles` |
| POST | `/users/:id/reset-password` | `users.update` |

Crear usuario:

```json
{
  "email": "nuevo@gmail.com",
  "full_name": "Nuevo Vendedor",
  "password": "123456",
  "is_active": true,
  "role_ids": ["<uuid-del-rol-vendedor>"]
}
```

`PATCH /users/:id` acepta `full_name`, `email`, `is_active`, `password` y
`role_ids` (reemplaza los roles actuales). No se permite eliminarse,
desactivarse ni quitarse el último rol `admin` a uno mismo.

### Productos

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/products?search=&type=&page=&page_size=` | `products.read` |
| POST | `/products` (multipart, mínimo 3 fotos) | `products.create` |
| GET | `/products/:id` | `products.read` |
| PUT | `/products/:id` (JSON, solo datos) | `products.update` |
| DELETE | `/products/:id` | `products.delete` |
| GET | `/products/:id/images` | `products.read` |
| POST | `/products/:id/images` (multipart) | `products.manage_images` |
| PUT | `/products/:id/images/:image_id` (multipart) | `products.manage_images` |
| DELETE | `/products/:id/images/:image_id` | `products.manage_images` |

Crear un producto con sus fotos (mínimo 3):

```bash
curl -X POST http://localhost:8081/api/v1/products \
  -H "Authorization: Bearer $TOKEN" \
  -F "name=Café americano" \
  -F "description=Bebida caliente" \
  -F "barcode=7501234567890" \
  -F "price=35.5" \
  -F "cost=12.25" \
  -F "type=product" \
  -F "images=@foto-1.png" \
  -F "images=@foto-2.png" \
  -F "images=@foto-3.png"
```

Los campos de datos también pueden ser los de un servicio (`type=service`).
Las fotos se envían en el campo repetido `images`.

- La creación **exige multipart/form-data y al menos 3 fotos**. Un `POST` JSON se
  rechaza con `422`.
- Los valores canónicos de `type` son `product` y `service`; también se aceptan
  los alias `producto` y `servicio`.
- `barcode` es opcional; si se envía, debe ser único entre los productos vigentes.
- `margin` se calcula en PostgreSQL como `price - cost`; se devuelve solo a
  usuarios con `products.view_margin` (admin). Para el vendedor el campo se
  omite. No se envía en el body.
- `DELETE /products/:id` aplica soft delete: el producto deja de aparecer en el
  listado y no puede consultarse, pero el registro se conserva para futuras ventas.
- `GET /products` acepta `search` (nombre, descripción o código), `type` y
  paginación. Cada producto incluye `images` e `images_count`.

Fotos:

- Agregar: `POST /products/:id/images` con uno o más archivos en `images`.
- Reemplazar: `PUT /products/:id/images/:image_id` con un archivo en `image`.
- Eliminar: `DELETE /products/:id/images/:image_id`. No se permite bajar de 3
  fotos (`409`).
- Formatos permitidos: JPG, PNG o WebP; máximo **5 MB por foto** y **20 fotos por
  producto**. Los archivos se guardan bajo `DOWNLOADS_DIR/products/<producto>/`.
- Solo los roles con `products.manage_images` (el admin del seed) pueden
  agregar, reemplazar o eliminar fotos. El vendedor puede verlas con
  `products.read`, pero no recibe `margin`.
- Las imágenes se sirven públicamente en `/downloads/...`. En producción puedes
  proteger esa ruta con el proxy/CDN que corresponda.

### Clientes

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/customers?search=&status=&page=&page_size=` | `customers.read` |
| POST | `/customers` | `customers.create` |
| GET | `/customers/:id` | `customers.read` |
| PUT | `/customers/:id` | `customers.update` |
| DELETE | `/customers/:id` | `customers.delete` |

```json
{
  "name": "María López",
  "address": "Av. Reforma 123",
  "city": "Ciudad de México",
  "postal_code": "01000",
  "phone": "5551234567",
  "email": "maria@example.com",
  "status": "prospecto"
}
```

- `status` solo admite `prospecto`, `cliente`, `en_pago` o `liquidado`.
- `postal_code` es texto para conservar ceros iniciales.
- `address`, `city`, `postal_code`, `phone` y `email` son opcionales.
- `DELETE /customers/:id` aplica soft delete.
- El vendedor del seed puede consultar, crear y actualizar clientes; el cobrador
  solo consultarlos; el admin tiene todos los permisos.

### Ventas y crédito

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/sales?search=&status=&page=&page_size=` | `sales.read` |
| POST | `/sales` | `sales.create` |
| GET | `/sales/:id` | `sales.read` |
| PUT | `/sales/:id` | `sales.update` |
| PATCH | `/sales/:id/status` | `sales.update` |
| POST | `/sales/:id/cancel` | `sales.cancel` |
| GET | `/credit-settings` | `sales.read` |
| PUT | `/credit-settings` | `credit_settings.update` |

Crear una venta:

```json
{
  "client_id": "<uuid-cliente>",
  "seller_id": "<uuid-vendedor>",
  "sale_date": "2026-10-27",
  "status": "cotizacion",
  "payment_type": "credito",
  "down_payment_percent": 20,
  "months": 6,
  "items": [
    {"product_id": "<uuid-producto-1>", "quantity": 2},
    {"product_id": "<uuid-producto-2>", "quantity": 1}
  ]
}
```

Reglas:

- El vendedor se toma del usuario autenticado. El admin debe enviar
  `seller_id` y solo puede asignar usuarios con rol `vendedor`.
- Cada partida guarda el precio del producto al momento de la venta. El
  `subtotal` se genera y `sales.total` se recalcula con un trigger.
- `payment_type`: `contado` o `credito`. En crédito, el anticipo debe ser uno
  de los porcentajes configurados y los meses uno de los plazos configurados.
- El interés se calcula en el servidor con el porcentaje mensual de
  `credit_settings` sobre el saldo financiado. El plan queda guardado en
  `sale_payments`.
- `PUT /sales/:id` permite editar cliente, vendedor, fecha, estado, forma de
  pago, partidas y plan de crédito. Recalcula partidas, total y plan de pagos.
  No se permite editar una venta cancelada (`409`).
- El vendedor solo consulta y edita sus propias ventas; el admin ve y edita
  todas. El vendedor puede confirmar una cotización (`cotizacion` → `venta`);
  cancelar requiere `sales.cancel` (admin en el seed).
- `PUT /credit-settings` acepta `down_payment_options` (porcentajes),
  `credit_months` y `monthly_interest_rate`; solo el admin lo modifica.

### Roles

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/roles` | `roles.read` |
| POST | `/roles` | `roles.create` |
| GET | `/roles/:id` | `roles.read` |
| PUT | `/roles/:id` | `roles.update` |
| DELETE | `/roles/:id` | `roles.delete` |
| PUT | `/roles/:id/permissions` | `roles.update` |

Crear rol con permisos:

```json
{
  "name": "supervisor",
  "description": "Supervisa operaciones",
  "permission_ids": ["<uuid-permiso-1>", "<uuid-permiso-2>"]
}
```

Reglas:

- El rol `admin` es de sistema: no se elimina ni se renombra.
- Un rol con usuarios asignados no se elimina hasta reasignarlos.
- `PUT /roles/:id/permissions` reemplaza el conjunto completo.

### Permisos

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/permissions?search=&module=` | `permissions.read` |
| POST | `/permissions` | `permissions.create` |
| GET | `/permissions/:id` | `permissions.read` |
| PUT | `/permissions/:id` | `permissions.update` |
| DELETE | `/permissions/:id` | `permissions.delete` |

Formato de nombre: `modulo.accion` (por ejemplo `customers.read`). Un permiso
asignado a roles no se puede eliminar hasta quitar la asignación.

### Dashboard

| Método | Ruta | Permiso |
|---|---|---|
| GET | `/dashboard/stats` | `dashboard.read` |

Devuelve totales de usuarios, usuarios activos, roles, permisos, sesiones
activas y usuarios por rol.

## Formato de respuestas

Éxito:

```json
{"data": { ... }}
```

Lista paginada:

```json
{
  "data": [ ... ],
  "meta": {"page": 1, "page_size": 10, "total": 3, "total_pages": 1}
}
```

Error:

```json
{
  "error": {
    "code": "validation_error",
    "message": "Revisa los datos enviados.",
    "details": [
      {"field": "email", "message": "Ingresa un correo electrónico válido."}
    ]
  }
}
```

Códigos HTTP usados: `200`, `201`, `204`, `400`, `401`, `403`, `404`, `405`,
`409`, `422`, `500`, `503`. Todas las respuestas incluyen `X-Request-ID`.

## Migraciones

Las migraciones viven en `db/migrations` y se embeben en el binario
(`db/migrations/embed.go`), por lo que el API puede aplicarlas al iniciar.
También son compatibles con el CLI de golang-migrate:

```bash
make migrate-up
make migrate-down               # revierte una
make migrate-create name=add_loans
make migrate-force version=1    # solo si hay un estado dirty
```

> `make migrate-down` revierte la última migración. No lo uses sobre datos
> reales sin respaldo.

## sqlc

```bash
# 1. edita db/queries/*.sql
make sqlc
```

La configuración está en `sqlc.yaml`; el código generado se escribe en
`internal/database/sqlc` y no debe editarse a mano. Los tipos `uuid`, `citext` y
`timestamptz` se mapean a `uuid.UUID`, `string`, `time.Time` (o punteros).

## Seed

El seed es idempotente y se ejecuta con `make seed` o al iniciar el API con
`SEED_ON_START=true`:

- Crea/actualiza el catálogo de **37 permisos**, incluidos `products.*`, `customers.*`, `sales.*` y `credit_settings.update`.
- Crea los roles `admin`, `vendedor` y `cobrador`.
- Asigna al rol `admin` **todos** los permisos del catálogo en cada ejecución.
- El rol `vendedor` recibe `products.read` (puede consultar el catálogo y sus
  fotos, pero no modificarlos), `customers.read/create/update` y
  `sales.read/create/update`; **no** recibe `products.view_margin` ni
  `sales.cancel`.
- `products.manage_images`, `products.view_margin`, `sales.cancel` y
  `credit_settings.update` se asignan solo al rol `admin`.
- Crea los usuarios `admin@gmail.com`, `vendedor@gmail.com` y
  `cobrador@gmail.com` con la contraseña `SEED_PASSWORD` (por defecto `123456`)
  si no existen.
- No restablece contraseñas ni elimina asignaciones existentes.

## Pruebas

```bash
make test          # unitarias: JWT, bcrypt, permisos y validaciones
make vet
make e2e           # 61 comprobaciones de auth/RBAC/sesiones
make e2e-products  # 41 comprobaciones del CRUD, la galería y el margen
```

La suite E2E cubre login/refresh/logout, rotación de refresh tokens, sesiones,
RBAC, CRUD de usuarios/roles/permisos, protecciones del último admin,
validaciones y CORS. La suite de productos cubre creación multipart con 3 fotos,
margen calculado, servicios, código de barras duplicado, búsqueda, filtros,
actualización, agregar/reemplazar/eliminar fotos, mínimo de 3, archivos
inválidos, publicación en `/downloads`, soft delete, permisos del vendedor y
margen oculto para el vendedor.

## Solución de problemas

### Air: `error obtaining VCS status: exit status 128`

Go intenta incluir metadatos de Git al enlazar el binario y el directorio no es
un repositorio Git válido. El proyecto ya lo evita en los comandos de desarrollo:

- `.air.toml` compila con `go build -buildvcs=false`.
- El `Makefile` exporta `GOFLAGS=-buildvcs=false` para `go run`, `go test` y
  `go build`.

Si ejecutas Go directamente:

```bash
GOFLAGS=-buildvcs=false go run ./cmd/api
```

Si prefieres conservar el stamping de VCS, inicializa un repositorio Git válido
(`git init`) y ejecuta los comandos sin esa bandera.

## Logs de peticiones

Cada petición imprime una línea compacta en stdout, con colores ANSI:

```text
[2026/10/28-13:52:28] GET     auth/login                                   200 203.0.113.10
[2026/10/28-13:52:31] POST    sales                                        201 203.0.113.10
[2026/10/28-13:52:35] DELETE  users/123                                    204 203.0.113.10
```

- El timestamp usa la zona horaria del proceso (`TZ`). En el compose de
  producción se puede definir `TZ=America/Mexico_City`.
- El método se colorea: GET cian, POST verde, PUT amarillo, PATCH magenta,
  DELETE rojo.
- La ruta elimina el prefijo `/api/v1`: `auth/login`, `sales`, etc.
- El status se colorea: 2xx verde, 3xx cian, 4xx amarillo, 5xx rojo.
- La IP se toma de `X-Real-IP` o del primer valor IPv4 de
  `X-Forwarded-For`, que Nginx configura al hacer proxy.
- La IP se normaliza siempre a IPv4: `::1` se muestra como `127.0.0.1`, una
  dirección IPv4-mapped se convierte a IPv4 y un cliente exclusivamente IPv6
  se registra como `0.0.0.0`.
- No se muestran latencia ni request ID en esta línea; el request ID sigue
  disponible en la cabecera `X-Request-ID`.

## Notas de seguridad

- Cambia `JWT_SECRET` y `POSTGRES_PASSWORD` en producción.
- Pon `SEED_ON_START=false` y rota la contraseña del administrador.
- Usa HTTPS y configura `CORS_ORIGINS` de forma explícita.
- Añade rate limiting al login si el API queda expuesto a Internet.
- Los refresh tokens se almacenan hasheados y se rotan en cada uso.
- El cliente Flutter guarda los tokens en `shared_preferences` por simplicidad;
  en producción debe usar almacenamiento seguro del sistema.

## Despliegue en producción

La API y PostgreSQL se despliegan con Docker y se integran a un Nginx existente
con el único archivo de sitio [`../deploy/nginx/api_store`](../deploy/nginx/api_store).
La guía está en [`../deploy/README.md`](../deploy/README.md).
