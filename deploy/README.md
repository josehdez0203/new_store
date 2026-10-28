# Despliegue de producción · CrediStore API

Despliegue simplificado para un servidor que **ya tiene Nginx** administrando
otros servicios. La API y PostgreSQL corren en Docker; tu Nginx existente sirve
también el build de **Flutter web** y hace proxy al API con un único archivo de
sitio: `deploy/nginx/api_store`.

PostgreSQL contiene **dos bases de datos** en la misma instancia:

- `api-store`: usada por la API de CrediStore.
- `xapari`: disponible para el otro servicio. No la usa la API.

```
Internet
   │ 80/443 (Nginx existente)
   ▼
Nginx del host
  ├── /             → redirección a /app/
  ├── /app/         → build Flutter web (/home/jose/web/app)
  ├── /api/         → 127.0.0.1:8081 → API Docker → PostgreSQL
  ├── /downloads/   → API
  ├── /health       → API
  └── /ready        → API + PostgreSQL

PostgreSQL:
  ├── api-store (API)
  └── xapari (otro servicio)
```

- Solo el Nginx que ya tienes publica `80/443`.
- La app web se sirve como archivos estáticos en `/app/`.
- La API se publica únicamente en loopback (`127.0.0.1:8081`).
- PostgreSQL no se publica al exterior.
- La misma instancia contiene `api-store` y `xapari`.
- No se crea un contenedor Nginx ni un contenedor Certbot.
- El único archivo de Nginx es `deploy/nginx/api_store`.

## Archivos

```
deploy/
├── docker-compose.prod.yml       # PostgreSQL + API
├── .env.production.example       # variables de producción
├── db/
│   └── init/
│       └── 01-create-databases.sh  # crea api-store y xapari (idempotente)
├── nginx/
│   └── api_store                 # único archivo: /app + proxy del API
└── scripts/
    └── seed-production.sh
server/Dockerfile                 # imagen de la API y binario de seed
app/build/web/                    # build de Flutter que se copia a /home/jose/web/app
```

## Requisitos

- Docker Engine y Docker Compose v2.
- Nginx instalado en el host, con otros sitios ya configurados.
- Dominio o subdominio apuntando al servidor, por ejemplo
  `api.midominio.com`.
- Un certificado TLS para ese dominio, o Certbot/disponibilidad para emitirlo.
- Los puertos 80/443 ya están siendo usados por tu Nginx; no los publiques
  desde Docker.

## 1. Variables de entorno

```bash
cd /ruta/al/proyecto
cp deploy/.env.production.example deploy/.env
chmod 600 deploy/.env
```

Edita `deploy/.env`:

- `POSTGRES_PASSWORD`: contraseña larga y compatible con URL (sin `@`, `:`, `/`
  ni espacios).
- `API_DB_NAME`: nombre de la base de la API; por defecto `api-store`.
- `XAPARI_DB_NAME`: base para el otro servicio; por defecto `xapari`.
- `JWT_SECRET`: genera uno con:
  ```bash
  openssl rand -hex 32
  ```
- `SEED_PASSWORD`: contraseña inicial fuerte del administrador.
- `CORS_ORIGINS`: origen exacto del frontend, por ejemplo
  `https://app.midominio.com`.
- `API_HOST_PORT`: puerto local para el API; por defecto `8081`. Si ya está
  ocupado, cámbialo aquí y también en `deploy/nginx/api_store`.
- `SEED_ON_START=false`: el seed se ejecuta una vez de forma controlada.
- `AUTO_MIGRATE=true`: la API aplica migraciones al iniciar.

## 2. Construir y arrancar PostgreSQL + API

```bash
docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml --env-file deploy/.env \
  build api

docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml --env-file deploy/.env \
  up -d db api
```

Al arrancar:

1. PostgreSQL crea el volumen y ejecuta `01-create-databases.sh`.
2. El servicio `db-init` vuelve a ejecutar el script de forma idempotente
   (también sirve si el volumen ya existía).
3. La API espera a que `db-init` termine y aplica las migraciones en
   `api-store`.

Comprueba las bases y el API:

```bash
docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml --env-file deploy/.env \
  exec db psql -U credit_store -d postgres -c '\l'

curl -fsS http://127.0.0.1:8081/ready
```

### Bases de datos

| Base | Uso | Credenciales |
|---|---|---|
| `api-store` | API CrediStore; `AUTO_MIGRATE` crea el esquema aquí | `POSTGRES_USER` / `POSTGRES_PASSWORD` |
| `xapari` | Otro servicio; no la toca la API | `POSTGRES_USER` / `POSTGRES_PASSWORD` |

Para entrar a `xapari`:

```bash
docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml --env-file deploy/.env \
  exec db psql -U credit_store -d xapari
```

Si otro contenedor de Docker va a usar `xapari`, conéctalo a la red
`credit-store-prod_backend` y usa el host `db`, puerto `5432`, base `xapari`.
PostgreSQL no está publicado al host.

#### Volumen existente de una entrega anterior

Si el volumen ya tenía la base `credit_store` de una entrega anterior, los
datos **no se mueven automáticamente** a `api-store`. Haz una copia y luego,
con la API detenida:

```bash
docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml --env-file deploy/.env stop api

# Si db-init ya creó api-store vacío:
docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml --env-file deploy/.env \
  exec -T db psql -U credit_store -d postgres \
  -c 'DROP DATABASE IF EXISTS "api-store";'

docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml --env-file deploy/.env \
  exec -T db psql -U credit_store -d postgres \
  -c 'ALTER DATABASE credit_store RENAME TO "api-store";'

docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml --env-file deploy/.env up -d api
```

También puedes respaldar `credit_store` y restaurarla en `api-store`; lo
importante es no ejecutar la API sobre una base vacía.

## 3. Crear permisos, roles y admin inicial

```bash
./deploy/scripts/seed-production.sh
```

El administrador inicial es `admin@gmail.com` y su contraseña es
`SEED_PASSWORD`.

> El seed crea también las cuentas demo `vendedor@gmail.com` y
> `cobrador@gmail.com`. Después del primer acceso, entra como administrador,
> cambia la contraseña inicial y modifica o elimina esas cuentas desde Usuarios.
> No vuelvas a ejecutar el seed si ya las eliminaste.

## 4. Instalar el único archivo de Nginx

El archivo es [api_store](nginx/api_store). Antes de copiarlo, edítalo y
reemplaza `api.example.com` por tu dominio real y ajusta las rutas de
`ssl_certificate` si tu certificado no está en la ruta estándar de Let's
Encrypt.

### Debian/Ubuntu (`sites-available` / `sites-enabled`)

```bash
sudo cp deploy/nginx/api_store /etc/nginx/sites-available/api_store
sudo ln -s /etc/nginx/sites-available/api_store /etc/nginx/sites-enabled/api_store
```

### RHEL / conf.d

El `include` de `conf.d` normalmente busca `*.conf`; en ese caso:

```bash
sudo cp deploy/nginx/api_store /etc/nginx/conf.d/api_store.conf
```

El archivo en el repositorio sigue llamándose `api_store`.

### Comprobar y recargar

```bash
sudo nginx -t
sudo systemctl reload nginx
```

El archivo contiene:

- redirección HTTP → HTTPS;
- bloque HTTPS con tu certificado;
- proxy `/api/` al API;
- proxy `/health` y `/ready`;
- proxy `/downloads/` al API;
- cabeceras de seguridad;
- límite de subida de 120 MB.

No reemplaza la configuración de tus otros sitios: es un `server` adicional
para el dominio elegido.

## 5. Certificado TLS

El archivo `api_store` ya incluye `listen 443 ssl`, por lo que el certificado
debe existir antes de recargar Nginx.

### Si ya tienes certificado

Ajusta:

```nginx
ssl_certificate     /ruta/a/fullchain.pem;
ssl_certificate_key /ruta/a/privkey.pem;
```

### Si usas Certbot

Puedes emitir el certificado con el flujo que ya uses para tus otros sitios.
Por ejemplo, con el plugin de Nginx:

```bash
sudo certbot --nginx -d api.example.com
```

Si usas webroot, el bloque HTTP de `api_store` sirve
`/.well-known/acme-challenge/` desde `/var/www/certbot`; pero como el bloque
HTTPS necesita el certificado para cargar, emite primero el certificado con tu
método habitual (DNS-01 o el plugin de Nginx) o comenta temporalmente el bloque
HTTPS mientras ejecutas:

```bash
sudo certbot certonly --webroot -w /var/www/certbot -d api.example.com
```

Después descomenta el bloque HTTPS y recarga Nginx.

### Renovación

Usa el mecanismo que ya tengas para los demás sitios (`certbot renew` +
`systemctl reload nginx`). Este despliegue no instala un Certbot adicional.

## 6. Verificar

```bash
curl -fsS https://api.example.com/health
curl -fsS https://api.example.com/ready
```

Prueba de login:

```bash
curl -fsS -X POST https://api.example.com/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@gmail.com","password":"TU_SEED_PASSWORD"}'
```

## 7. Publicar Flutter web en el mismo dominio

El archivo `api_store` sirve el build de Flutter en `/app/` y el API en
`/api/v1`. Así la app y el API comparten origen y no necesitas CORS.

### Compilar

Desde tu máquina o el servidor:

```bash
cd app
flutter build web --release \
  --base-href /app/ \
  --dart-define=API_BASE_URL=https://api-store.jhc-sistemas.com/api/v1
```

`--base-href /app/` es obligatorio: Flutter genera las rutas de `main.dart.js`,
assets, CanvasKit y service worker bajo `/app/`. Sin ese parámetro, la app carga
en `/app/` pero sus archivos se piden en `/` y fallan.

El resultado está en `app/build/web/`.

### Copiar al servidor

```bash
sudo mkdir -p /home/jose/web/app
sudo rsync -a --delete app/build/web/ /home/jose/web/app/
sudo chown -R www-data:www-data /home/jose/web/app
```

El usuario puede variar según tu Nginx (`www-data`, `nginx`, etc.). El archivo
`api_store` del repositorio usa:

```nginx
root /home/jose/web;
index index.html;
```

y sirve la aplicación desde `/home/jose/web/app` en `/app/`.

Si en tu servidor el `root` es `/home/jose/web/api_store`, el build debe quedar
en `/home/jose/web/api_store/app`. La ruta del build y el `root` deben coincidir
siempre:

| `root` | Build de Flutter |
|---|---|
| `/home/jose/web` | `/home/jose/web/app` |
| `/home/jose/web/api_store` | `/home/jose/web/api_store/app` |

Si prefieres una ruta más segura para Nginx, usa `/var/www/credistore-web/app`
y cambia el `root` del archivo `api_store` a `/var/www/credistore-web`.

> Si Nginx no puede atravesar `/home/jose` (permisos 700/750), la web devolverá
> 403. En ese caso mueve el build a `/var/www/credistore-web` y actualiza el
> `root`; no abras permisos de todo el home.

### Verificar

```bash
curl -I https://api-store.jhc-sistemas.com/
curl -I https://api-store.jhc-sistemas.com/app/
curl -I https://api-store.jhc-sistemas.com/app/main.dart.js
curl -fsS https://api-store.jhc-sistemas.com/health
```

Abre:

```text
https://api-store.jhc-sistemas.com/app/
```

La app llama a:

```text
https://api-store.jhc-sistemas.com/api/v1/...
```

### CORS

Al servirse en el mismo dominio no hay CORS entre la web y el API. Aun así,
puedes dejar el dominio en `CORS_ORIGINS` para evitar problemas si algún
navegador envía `Origin`:

```env
CORS_ORIGINS=https://api-store.jhc-sistemas.com
```

Después recrea el API:

```bash
docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml --env-file deploy/.env \
  up -d --force-recreate api
```

### Si quieres la web en otro dominio

En ese caso publica `app/build/web` en otro servidor/subdominio y agrega su
origen exacto a `CORS_ORIGINS`; el API seguirá en
`https://api-store.jhc-sistemas.com/api/v1`.

### `flutter_bootstrap.js` se sirve como `text/html`

Si el navegador muestra:

```text
El recurso ... /app/flutter_bootstrap.js se bloqueó debido a la falta de
coincidencia del tipo MIME ("text/html") (X-Content-Type-Options: nosniff)
```

significa que Nginx está devolviendo `/app/index.html` en lugar del archivo
JavaScript. El `try_files` del SPA está actuando como fallback porque
`flutter_bootstrap.js` no existe en la ruta real que resuelve Nginx.

Comprueba la ruta según tu `root`:

```bash
# Si tu root es /home/jose/web/api_store:
ls -l /home/jose/web/api_store/app/flutter_bootstrap.js

# Si tu root es /home/jose/web:
ls -l /home/jose/web/app/flutter_bootstrap.js
```

Si no existe, vuelve a copiar **todo** el build:

```bash
cd app
flutter build web --release \
  --base-href /app/ \
  --dart-define=API_BASE_URL=https://api-store.jhc-sistemas.com/api/v1

# Ajusta el destino a tu root real:
sudo mkdir -p /home/jose/web/api_store/app
sudo rsync -a --delete build/web/ /home/jose/web/api_store/app/
sudo chown -R www-data:www-data /home/jose/web/api_store/app
```

Si el archivo existe pero Nginx sigue devolviendo HTML, agrega estas reglas
antes del `location /app/` del SPA:

```nginx
location = /app/flutter_bootstrap.js {
    try_files $uri =404;
    default_type application/javascript;
    expires -1;
}

location = /app/flutter.js {
    try_files $uri =404;
    default_type application/javascript;
    expires -1;
}

location ~* ^/app/.*\.(js|mjs|css)$ {
    try_files $uri =404;
    default_type application/javascript;
    expires 1h;
}

location ~* ^/app/.*\.(json|map|png|jpe?g|gif|svg|ico|woff2?|ttf|otf)$ {
    try_files $uri =404;
    expires 30d;
}
```

El fallback `/app/index.html` solo debe aplicarse a rutas de navegación del SPA,
no a archivos con extensión. El archivo [api_store](nginx/api_store) del
repositorio ya incluye estas reglas.

No elimines `X-Content-Type-Options: nosniff`; no es el problema. El problema es
que el archivo JavaScript no se está sirviendo como JavaScript.

Verifica:

```bash
curl -I https://api-store.jhc-sistemas.com/app/flutter_bootstrap.js
curl -I https://api-store.jhc-sistemas.com/app/main.dart.js
```

Debe responder `200` con:

```text
Content-Type: application/javascript
```

Si responde `404`, el archivo no está en la ruta. Si responde `200 text/html`,
el fallback del SPA sigue capturando la petición.

## Rutas publicadas por tu Nginx

| Ruta | Destino |
|---|---|
| `/api/v1/...` | API Docker en `127.0.0.1:8081` |
| `/health` | API (`/health`) |
| `/ready` | API + PostgreSQL |
| `/downloads/...` | API, que sirve las fotos del volumen |
| `/` | Redirección a `/app/` |
| `/app/` | Flutter web (`/home/jose/web/app`) |
| `/app/main.dart.js`, `/app/assets/`, `/app/canvaskit/` | Assets estáticos de Flutter |

## Operación

### Logs

```bash
docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml logs -f api
```

### Actualizar

```bash
git pull
docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml --env-file deploy/.env \
  build api
docker compose --project-directory deploy \
  -f deploy/docker-compose.prod.yml --env-file deploy/.env \
  up -d
```

`AUTO_MIGRATE=true` aplica migraciones al arrancar.

### Respaldos

Bases de datos:

```bash
mkdir -p backups
for DB in api-store xapari; do
  docker compose --project-directory deploy \
    -f deploy/docker-compose.prod.yml --env-file deploy/.env \
    exec -T db pg_dump -U credit_store -d "$DB" -Fc \
    > "backups/credit-store-${DB}-$(date +%F).dump"
done
```

Fotos:

```bash
docker run --rm \
  -v credit_store_prod_downloads:/data:ro \
  -v "$PWD/backups":/backup \
  alpine tar czf /backup/downloads-$(date +%F).tgz -C /data .
```

### Restaurar bases de datos

Primero deben existir las bases (`db-init` las crea). Luego:

```bash
for DB in api-store xapari; do
  docker compose --project-directory deploy \
    -f deploy/docker-compose.prod.yml --env-file deploy/.env \
    exec -T db pg_restore -U credit_store -d "$DB" --clean --if-exists \
    < "backups/credit-store-${DB}-2026-10-28.dump"
done
```

## Notas de integración

- Si tu Nginx corre en **otro contenedor**, `127.0.0.1` no apunta al host.
  En ese caso publica el API en una IP/red alcanzable y cambia los
  `proxy_pass` de `api_store`.
- Si cambias `API_HOST_PORT`, actualiza los cuatro `proxy_pass` del archivo
  `api_store`.
- `api-store` y `xapari` comparten la misma instancia y usuario de PostgreSQL.
- El servicio `db-init` es de un solo uso; si falla, la API no arranca.
- El certificado TLS debe cubrir `api-store.jhc-sistemas.com`. El archivo
  `api_store` conserva las rutas `delivery.jhc-sistemas.com-0001` que ya tenías;
  verifica que ese certificado incluya el dominio del API. Si no, cambia
  `ssl_certificate` y `ssl_certificate_key` o emite el certificado correcto.
- La web se sirve desde el mismo dominio del API, por lo que no requiere CORS.
- La app se publica en `/app/`; el API sigue en `/api/v1`.
- El archivo `api_store` no define `limit_req_zone` porque esa directiva
  pertenece al contexto `http` de tu configuración principal. Si quieres rate
  limiting, define la zona en `nginx.conf` y añade `limit_req` en `/api/`.
- Tus otros sitios no se tocan: solo se añade un `server` para el dominio del
  API.
- No publiques PostgreSQL ni el puerto de la API en el firewall; solo 80/443.
