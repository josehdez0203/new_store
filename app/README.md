# CrediStore App

Cliente Flutter web del sistema de ventas a crédito. Consume el API de Go ubicado
en `../server`; el proyecto incluye además los scaffolds de Linux y Android.

## Funcionalidades

- Login contra `POST /api/v1/auth/login`.
- Persistencia local de la sesión y restauración automática con `/auth/me`.
- Renovación automática del access token usando el refresh token rotativo.
- Cierre de sesión local y remoto.
- Home para cualquier usuario autenticado, con:
  - saludo y roles del usuario;
  - métricas del sistema (si tiene `dashboard.read`);
  - módulos accesibles únicamente desde el menú lateral.
- Drawer con secciones **Operación**, **Administración**, **Cuenta** y
  **Preferencias**, construido a partir de los permisos del API.
- Perfil con datos de la cuenta, roles, permisos y sesiones activas.
- Catálogo de **Productos** con CRUD, búsqueda, filtro por tipo, paginación,
  galería con carrusel (mínimo 3 fotos, máximo 20), subida a `/downloads` y
  acciones condicionadas por permisos. El **margen** se muestra solo con
  `products.view_margin` (admin); el vendedor no lo ve.
- Administración de **Usuarios** para el admin: listado, búsqueda, filtros por
  rol/estado, alta, edición, activación/desactivación, eliminación y cambio de
  roles. Las acciones respetan `users.create`, `users.update`, `users.delete` y
  `users.assign_roles`.
- **Clientes** con CRUD, búsqueda, filtro por estado, paginación y los campos
  nombre, dirección, ciudad, C.P., teléfono, correo y estado (prospecto, cliente,
  en pago o liquidado).
- **Ventas** con cotizaciones/ventas, varias partidas, total calculado, pago de
  contado o crédito, anticipo, interés y plan de pagos mensual. Las ventas y
  cotizaciones se pueden editar desde el detalle; el servidor recalcula total y
  plan. El plan se exporta a PDF, correo o WhatsApp.
- **Configuración de crédito** en Administración (solo admin): anticipos, plazos
  e interés mensual, persistidos en `credit_settings`. También se abre desde el
  botón de ajustes de Ventas.
- Preferencias de tema:
  - **Claro:** Catppuccin Latte (por defecto).
  - **Oscuro:** Tokyo Night.
  - Persistidas con `shared_preferences` y aplicadas al instante.
- Diseño responsive para web, escritorio y móvil.
- Pantalla de carga HTML con branding, favicon, iconos PWA y manifest para web.

> **Usuarios**, **Clientes**, **Ventas** y **Productos** ya son funcionales. Los
> módulos de créditos, cobros, reportes, roles, permisos y configuración aún
> muestran una pantalla “Disponible próximamente”.

## Capturas

> Las capturas corresponden a la versión web anterior a la pantalla de
> Productos. No se regeneraron; el foco de esta entrega fue la corrección de la
> aserción de semántica y la galería de fotos.

Las capturas están en [`../docs/screenshots`](../docs/screenshots):

- `login-light.png` · Catppuccin Latte.
- `login-dark.png` · Tokyo Night.
- `home-admin.png` · panel del administrador.
- `drawer-vendedor.png` · menú filtrado para el rol vendedor.

## Requisitos

- Flutter 3.44.6 / Dart 3.12.2.
- El API de Go en ejecución (`../server`, puerto 8081).

## Ejecutar

```bash
cd app
flutter pub get

# Web (recomendado para probar rápido)
flutter run -d chrome

# Escritorio Linux
flutter run -d linux
```

La URL del API se resuelve así:

| Plataforma | URL por defecto |
|---|---|
| Web / Linux / macOS / Windows | `http://localhost:8081/api/v1` |
| Emulador Android | `http://10.0.2.2:8081/api/v1` |

Para una IP o dominio distinto:

```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=http://192.168.1.10:8081/api/v1
```

El Android manifest incluye `usesCleartextTraffic="true"` **solo para desarrollo**
(HTTP local). En producción sirve el API por HTTPS y elimina ese atributo.

## Build y despliegue web

```bash
flutter build web --release \
  --dart-define=API_BASE_URL=https://api.tudominio.com/api/v1

# Servir el artefacto en local
python3 -m http.server 5173 --directory build/web
```

- Salida: `build/web`.
- Para una subruta: `flutter build web --base-href /credistore/`.
- El `index.html` incluye la pantalla de carga (se retira con el evento
  `flutter-first-frame`) y los iconos en `web/icons`.
- La app usa `shared_preferences` sobre `localStorage` para tokens y tema. En
  producción, valora cookies httpOnly o almacenamiento seguro.
- El dominio del front debe estar en `CORS_ORIGINS` del API.

## Credenciales de prueba

| Correo | Contraseña | Rol |
|---|---|---|
| `admin@gmail.com` | `123456` | Administrador |
| `vendedor@gmail.com` | `123456` | Vendedor |
| `cobrador@gmail.com` | `123456` | Cobrador |

## Estructura

```text
lib/
├── main.dart                    # bootstrap y providers
├── app.dart                     # MaterialApp + AuthGate
├── core/
│   ├── config/app_config.dart   # URL del API y constantes
│   ├── network/                 # ApiClient, ApiException, refresh automático
│   ├── storage/                 # TokenStorage (shared_preferences)
│   ├── theme/                   # Catppuccin Latte y Tokyo Night
│   ├── utils/                   # formato de fechas y etiquetas
│   └── widgets/                 # AppLogo, SectionHeader
└── features/
    ├── auth/
    │   ├── models/              # AuthUser, AuthSession
    │   ├── providers/           # AuthProvider
    │   └── pages/               # LoginPage, SplashPage
    ├── home/
    │   ├── navigation/          # destinos y filtrado por permiso
    │   ├── pages/home_page.dart
    │   └── widgets/             # AppDrawer, StatCard, ModuleCard
    ├── products/
    │   ├── models/              # Product, ProductImage y ProductFormData
    │   ├── pages/               # listado/CRUD
    │   └── widgets/             # formulario, carrusel y gestor de fotos
    ├── users/
    │   ├── models/              # ManagedUser y AppRole
    │   ├── pages/               # listado/CRUD de usuarios
    │   └── widgets/             # formulario y cambio de roles
    ├── customers/
    │   ├── models/              # Customer y estados
    │   ├── pages/               # listado/CRUD de clientes
    │   └── widgets/             # formulario de cliente
    ├── sales/
    │   ├── models/              # Sale, SaleItem, SalePayment, CreditSettings
    │   ├── pages/               # listado, formulario, detalle y configuración
    │   └── services/             # exportación PDF/correo/WhatsApp
    ├── profile/pages/           # perfil + sesiones
    ├── settings/
    │   ├── providers/           # ThemeProvider
    │   ├── pages/               # Apariencia
    │   └── widgets/             # ThemeOptionCard con vista previa
    └── modules/pages/           # placeholder de módulos
```

## Autenticación en la app

`ApiClient` centraliza las peticiones:

1. Agrega `Authorization: Bearer <access_token>` cuando corresponde.
2. Si recibe `401`, llama a `/auth/refresh` una sola vez aunque haya peticiones
   concurrentes.
3. Guarda el nuevo par de tokens y reintenta la petición original.
4. Si el refresh falla, limpia la sesión e invoca `onSessionExpired`; el
   `AuthProvider` vuelve al login con un mensaje.

`AuthProvider` restaura la sesión al arrancar, expone el usuario autenticado y
mantiene el estado `checking` / `authenticated` / `unauthenticated` que consume
`AuthGate`.

Los tokens se guardan en `shared_preferences` para que el ejemplo funcione en
web, Linux y Android sin librerías nativas. **En producción usa
`flutter_secure_storage`** (Keychain/Keystore) y considera cookies httpOnly si
expones la app en web.

## Permisos y menú

`lib/features/home/navigation/app_destinations.dart` define los módulos, su
permiso y su sección. `visibleDestinations(permissions)` filtra la lista con los
permisos que devuelve `/auth/me`. El drawer usa exactamente ese filtro, por lo
que el menú no depende de comparar nombres de rol:

| Permiso | Módulo |
|---|---|
| `products.read` | Productos |
| `sales.read` | Ventas |
| `customers.read` | Clientes |
| `credits.read` | Créditos |
| `payments.read` | Cobros |
| `reports.read` | Reportes |
| `users.read` | Usuarios |
| `roles.read` | Roles |
| `permissions.read` | Permisos |
| `settings.read` | Configuración |

`*` funciona como comodín si se configura un rol con acceso total.

Las acciones de fotos (agregar, reemplazar y eliminar) requieren
`products.manage_images`, asignado solo al rol `admin` en el seed. El vendedor
puede ver la galería con `products.read`.

La administración de usuarios requiere `users.read` para entrar; crear, editar,
eliminar y cambiar roles requiere `users.create`, `users.update`, `users.delete`
y `users.assign_roles`. En el seed solo el rol `admin` tiene esos permisos.

Clientes requiere `customers.read`; crear/editar usa `customers.create` y
`customers.update` (admin y vendedor en el seed); eliminar requiere
`customers.delete` (admin).

Ventas requiere `sales.read`. Crear usa `sales.create`; confirmar una cotización
usa `sales.update`; cancelar usa `sales.cancel`. La configuración de anticipos,
plazos e interés usa `credit_settings.update` (solo admin).

El **margen de ganancia** requiere `products.view_margin`, también solo para el
rol `admin` en el seed. El API omite el campo `margin` para el vendedor y la
interfaz no muestra la columna ni la métrica de margen.

## Temas

`ThemeProvider` lee `preferences.theme_mode` al iniciar. Valores admitidos:
`light` y `dark`; cualquier otro valor cae en **light**. El tema por defecto es
Catppuccin Latte. El cambio se puede hacer desde:

- el icono sol/luna del AppBar;
- el switch del pie del drawer;
- la pantalla **Apariencia**, con vista previa de cada paleta.

## Pruebas y build

```bash
flutter pub get      # nuevas dependencias de fotos
flutter analyze      # sin incidencias
flutter test         # 37 pruebas (36/37; fallo ajeno de app_config_test)
flutter build web    # build de producción en build/web
```

Las pruebas cubren, entre otras cosas:

- parseo de usuario/permisos y cálculo de iniciales;
- filtrado y agrupación del menú por permisos;
- paletas y valores de los dos temas;
- persistencia y toggle del tema;
- login, errores, refresh automático y expiración de sesión con `MockClient`;
- render del login y del drawer según rol con `WidgetTester`;
- layout responsive en escritorio y en una pantalla móvil compacta;
- URL por defecto del API para escritorio y para el emulador Android;
- regresión de selección de fotos en el formulario (semántica + carrusel);
- regresión de agregar una foto desde la galería del producto;
- regresión del alta completa desde la página de productos (formulario + carrusel + tabla);
- layout móvil del resumen en 2 columnas;
- cambio de rol de usuario desde el módulo Usuarios;
- alta de un cliente desde la pantalla de Clientes;
- plan de pagos de venta en texto y PDF;
- alta de una venta completa desde el formulario;
- edición de anticipos, plazos e interés desde Configuración de crédito;
- edición de una venta existente desde el formulario.

La app se verificó con `flutter analyze` (sin incidencias) y
`flutter build web`. Se agregaron pruebas de regresión de semántica de fotos,
alta de producto, layout móvil del resumen, cambio de rol de usuario
(`users_page_roles_test.dart`), alta de cliente
(`customers_page_test.dart`) y exportación de ventas
(`sale_export_test.dart`, `sale_form_test.dart`,
`credit_settings_page_test.dart` y `sale_edit_test.dart`). La suite completa
queda en 36/37: el único fallo es el test previo de `app_config_test`, que
espera `10.0.2.2` pero `AppConfig` usa la IP LAN `192.168.100.16`.

Dependencias relevantes:

```yaml
carousel_slider: ^5.1.2
image_picker: ^1.2.4
pdf: ^3.13.1
printing: ^5.15.1
url_launcher: ^6.3.3
```

Después de actualizar el proyecto ejecuta `flutter pub get` antes de compilar.

## Notas

- El home consume `/dashboard/stats`; si el usuario no tiene `dashboard.read`,
  la sección Resumen se omite.
- **Productos** requiere `products.read`; los botones de alta, edición y borrado
  aparecen solo con `products.create`, `products.update` y `products.delete`.
  El vendedor del seed solo tiene lectura.
- El alta de producto exige seleccionar **mínimo 3 fotos** (JPG, PNG o WebP, 5 MB
  cada una, máximo 20). Las imágenes se envían al API y se guardan en
  `server/downloads/products/...`; la app las muestra desde `/downloads`.
- La galería usa `carousel_slider`; la selección de archivos usa `image_picker`.
  Solo `products.manage_images` (admin) ve los botones para agregar, reemplazar
  o eliminar fotos. Al llegar a 3, la eliminación queda bloqueada.
- El formulario de producto calcula el margen en vivo (`precio - costo`) solo
  para el admin; el API lo devuelve calculado por PostgreSQL. El vendedor no ve
  el margen en la tabla ni en las tarjetas.
- El dashboard no muestra la cuadrícula de módulos; los módulos están
  únicamente en el menú lateral.
- **Usuarios** permite cambiar roles con el endpoint
  `PUT /users/:id/roles`; el admin no puede eliminarse a sí mismo desde la UI y
  el servidor protege las reglas del último administrador.
- **Clientes** muestra los estados con etiquetas: Prospecto, Cliente, En pago y
  Liquidado. El código postal se trata como texto para conservar ceros iniciales.
- **Ventas** guarda el plan de pagos en el servidor. La exportación PDF usa
  `pdf` + `printing`; correo y WhatsApp usan `url_launcher`. La acción **Editar
  venta** del detalle abre el formulario precargado y guarda con `PUT /sales/:id`;
  una venta cancelada no se puede editar.
- **Configuración de crédito** aparece en Administración y en el botón de
  ajustes de Ventas solo con `credit_settings.update` (admin). Guarda contra
  `PUT /credit-settings`; el servidor aplica los nuevos valores a las ventas
  posteriores.
- El botón **Usar demo** del login rellena las credenciales del administrador.
- `flutter build web` usa CanvasKit; el resultado está en `build/web`.
- La entrega activa es **web**; los scaffolds de Linux y Android quedan
  disponibles en `linux/` y `android/`.
- Para ejecutar en Android, el API debe ser accesible desde el emulador
  (`10.0.2.2`) y el backend debe escuchar en `0.0.0.0` (lo hace por defecto).
