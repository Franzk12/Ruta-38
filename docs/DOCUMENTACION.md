# RepuestoPOS — Documentación técnica

Sistema de punto de venta de **Ruta 38 Repuestos**. Versión 8 · Noviembre 2026.

Este documento reemplaza a `RepuestoPOS_Documentacion.docx` (versión 7), que queda en el repositorio solo como referencia histórica. Los cambios entre versiones están en [CHANGELOG.md](CHANGELOG.md).

## Índice

1. [Descripción general](#1-descripción-general)
2. [Acceso y usuarios](#2-acceso-y-usuarios)
3. [Puesta en marcha y actualización](#3-puesta-en-marcha-y-actualización)
4. [Módulos](#4-módulos)
5. [Base de datos](#5-base-de-datos)
6. [Funcionamiento sin conexión](#6-funcionamiento-sin-conexión)
7. [Almacenamiento local del navegador](#7-almacenamiento-local-del-navegador)
8. [Copias de seguridad](#8-copias-de-seguridad)
9. [Publicación y vuelta atrás](#9-publicación-y-vuelta-atrás)
10. [Pruebas](#10-pruebas)
11. [Diagnóstico y problemas comunes](#11-diagnóstico-y-problemas-comunes)
12. [Estilos](#12-estilos)
13. [Límites conocidos](#13-límites-conocidos)

## 1. Descripción general

RepuestoPOS es una aplicación web de una sola página (`index.html`) para la caja, el inventario y las ventas del local.

```
 Navegador de cada caja                          Nube
┌──────────────────────────────┐        ┌───────────────────────────┐
│ index.html (interfaz+lógica) │◄──────►│ Vercel: publica la app    │
│ sw.js (copia para abrir      │        │ desde la rama main        │
│        sin internet)         │        └───────────────────────────┘
│ localStorage:                │        ┌───────────────────────────┐
│  · caché de productos/ventas │◄──────►│ Supabase                  │
│  · cola de ventas pendientes │  HTTPS │  · Auth (login)           │
└──────────────────────────────┘        │  · PostgreSQL + API REST  │
                                        │  · funciones de stock     │
 GitHub Actions ── backup diario ──────►│                           │
                                        └───────────────────────────┘
```

- **La app** se publica en Vercel: cada cambio en la rama `main` sale en vivo. También se puede abrir como archivo local.
- **Los datos** viven en Supabase (PostgreSQL con autenticación). El navegador guarda una copia como caché y una cola de ventas pendientes.
- **La copia de seguridad** la hace GitHub Actions todos los días.

### Tecnologías

- HTML, CSS y JavaScript sin framework ni paso de compilación. Todo el código de la app está en `index.html`.
- Supabase: PostgreSQL, API REST (PostgREST) y Supabase Auth.
- Service worker (`sw.js`) y manifiesto web: la app abre sin internet y se puede instalar.
- SheetJS 0.18.5 (lector de Excel del importador), incluido en `vendor/`. Es la única librería externa.
- Fuentes de Google (IBM Plex Mono e IBM Plex Sans). Si no hay internet la primera vez, se usan las del sistema.

### Archivos del proyecto

| Archivo | Para qué sirve |
| --- | --- |
| `index.html` | La aplicación completa. Contiene la URL y la clave pública de Supabase (`SUPABASE_URL`, `SUPABASE_KEY`). |
| `sw.js` | Service worker: guarda una copia de la app para abrir sin internet. |
| `manifest.webmanifest`, `icons/` | Datos e íconos para instalar la app. |
| `vendor/xlsx.full.min.js` | SheetJS, para importar Excel. |
| `supabase_schema.sql` | Crea las tablas. Solo para un proyecto de Supabase nuevo. |
| `supabase_migracion.sql` | Seguridad, auditoría y funciones. Se corre siempre: en base nueva (después del anterior) y en base existente. Se puede correr más de una vez. |
| `cargar_datos.js` | Script de un solo uso para precargar categorías y marcas. |
| `scripts/backup.sh`, `scripts/restaurar.sh` | Copia de seguridad cifrada y su restauración. |
| `.github/workflows/backup.yml` | Corre el backup todos los días. |
| `tests/` | Pruebas automáticas (ver [sección 10](#10-pruebas)). |
| `docs/` | Esta documentación y el registro de cambios. |

## 2. Acceso y usuarios

Se entra con **email y contraseña** (Supabase Auth). Sin sesión, la base rechaza toda lectura y escritura. La sesión queda guardada en cada PC y se renueva sola.

> **Seguridad.** La clave pública (`SUPABASE_KEY`) está a la vista en el código de la página. Es seguro **solo si** en Supabase está desactivado *Allow new users to sign up* (Authentication → Sign In / Providers). Si se activa, cualquiera con esa clave puede crearse una cuenta y entrar a los datos.

### Un usuario por persona

Cada venta y cada anulación guarda el email de quien la hizo. Para que ese dato sirva, **cada persona debe entrar con su propio usuario** (Authentication → Users → Add user). Si todos comparten una cuenta, el sistema funciona igual pero la auditoría no distingue a nadie.

Hoy todos los usuarios tienen los mismos permisos: no hay roles (dueño / vendedor). Ver [límites conocidos](#13-límites-conocidos).

### Cerrar sesión

Desde **Admin → Cerrar sesión**. Borra la copia local de productos e historial de esa PC, pero **no** las ventas pendientes de sincronizar: se envían al volver a entrar. Si hay ventas pendientes, la app avisa antes.

### Sesión vencida

El token se renueva solo antes de vencer. Si Supabase rechaza la renovación (cambio de contraseña, usuario eliminado), la app muestra el login con "La sesión venció — volvé a ingresar". Si la renovación falla por falta de internet, la sesión **no** se cierra y las ventas siguen yendo a la cola.

## 3. Puesta en marcha y actualización

### Proyecto de Supabase nuevo

1. Crear el proyecto en supabase.com y copiar la **Project URL** y la **anon public key** (Project Settings → API) en `SUPABASE_URL` y `SUPABASE_KEY` de `index.html`.
2. Correr `supabase_schema.sql` completo en el **SQL Editor**.
3. Correr `supabase_migracion.sql` completo en el **SQL Editor**.
4. **Authentication → Users → Add user**: crear un usuario por persona, marcando *Auto Confirm User*.
5. **Authentication → Sign In / Providers**: desactivar *Allow new users to sign up*.
6. Abrir la app, iniciar sesión y, en la consola (F12), pegar `cargar_datos.js` para precargar categorías y marcas.

### Base existente

Correr `supabase_migracion.sql` en el SQL Editor. No borra datos y se puede correr más de una vez.

La migración de la versión 8 es **compatible con la app de la versión 7**: se puede correr antes de publicar la app nueva y la caja sigue funcionando. Aun así, conviene hacerlo fuera del horario de atención y con un backup previo (ver [sección 9](#9-publicación-y-vuelta-atrás)).

## 4. Módulos

### 4.1 Caja

Pantalla principal. Se agregan productos con el lector de código de barras o buscando por nombre, categoría o marca/modelo.

1. El operador escanea o busca el producto. Si no hay stock en el negocio pero sí en depósito, se muestra un aviso.
2. Se puede tocar el precio de un item del carrito para cambiarlo solo en esa venta.
3. Se elige el **método de pago**: Efectivo, Transferencia, Débito o Crédito. En efectivo se ingresa lo recibido y se calcula el vuelto. En los demás, si no se ingresa monto, se cobra el total justo.
4. Al tocar **COBRAR**, la venta se anota primero en la cola local de esa PC, el carrito se vacía (evita cobrar dos veces con un doble clic) y la venta se envía a la base con `registrar_venta`.
5. Cuando la base responde, se muestra el ticket con el **número definitivo** y la venta sale de la cola. Si no hay internet o tarda más de 6 segundos, el ticket sale con número **provisorio** y la venta se envía sola más tarde.
6. Si algún producto quedó por debajo del stock mínimo, aparece una alerta.

| Función | Qué hace |
| --- | --- |
| `escanear()` | Busca el producto por código de barras o ID y lo agrega al carrito |
| `buscarEnCaja()` / `elegirSug(id)` | Búsqueda por texto con sugerencias |
| `agregarAlCarro(prod)` | Valida stock y agrega o incrementa el producto |
| `cambiarCant(i, d)` / `quitarItem(i)` | Modifica cantidades o quita un item |
| `editarPrecio(i, el)` | Cambia el precio de un item solo para esta venta |
| `cobrar()` | Valida el pago, anota la venta en la cola, descuenta stock local, la envía y muestra el ticket |
| `guardarVenta(venta)` / `enviarPendiente(venta)` | Envían la venta a la base y la quitan de la cola cuando la base confirma |

### 4.2 Ticket y número de comprobante

El ticket está pensado para impresora térmica de 80 mm. Incluye logo, datos del local, número, fecha, detalle, total, método de pago y vuelto (si hubo).

| Número | Significado |
| --- | --- |
| `#0123` | Definitivo: es el número de la venta en la base. Único para todas las cajas. |
| `P-0005` | Provisorio de esa PC: la venta todavía no llegó a la base. El ticket lo indica. Al sincronizarse, el historial muestra el definitivo. |

La numeración definitiva puede tener **huecos** en casos poco frecuentes (por ejemplo, si un envío se interrumpe del lado de la base). No es un problema porque el ticket **no es una factura**: el pie dice "Cupón no válido como factura" y la app no emite comprobantes fiscales (ARCA).

### 4.3 Inventario

Grilla de productos con filtros por texto, categoría y marca/modelo, en vista de tarjetas o lista.

| Función | Qué hace |
| --- | --- |
| `abrirModal(id?)` / `guardarProducto()` | Alta y edición. Valida nombre, categoría, valores no negativos y código de barras no repetido. |
| Edición de stock | El stock solo se guarda si se cambió a mano en el formulario. Si no, se conserva el de la base, que pudo bajar por ventas de otra caja. |
| `eliminarProducto(id)` | Baja lógica: el producto queda inactivo y sus ventas conservan el detalle. |
| `abrirMover(id)` / `confirmarMover()` | Pasa unidades del depósito al negocio con `mover_stock`. Se rechaza si el depósito no alcanza. |
| `abrirAumento()` / `aplicarAumento()` | Aumento masivo de precios por porcentaje o monto fijo, filtrando por categoría o marca. |
| Crear similar (menú ⋯) | Abre "Nuevo producto" con los datos de otro. Código y stock quedan vacíos. |

**Carga rápida con escáner.** Para ingresar mercadería sin mouse. Se elige dónde se suma (negocio o depósito), la cantidad por escaneo y el % de ganancia para productos nuevos. Si el código existe, suma stock en la base (`ajustar_stock`). Si no existe, abre un formulario corto. Cada operación tiene **Deshacer**.

**Importar productos.** Carga masiva desde Excel (.xlsx/.xls), CSV o una tabla pegada. Tres pasos: qué columna es cada dato, qué hacer con los productos que ya existen, y vista previa fila por fila (NUEVO, ACTUALIZA, SIN CAMBIOS o ERROR). Entiende números en formato argentino. "Descargar plantilla Excel" baja un modelo. Funciona sin internet para leer el archivo, pero necesita conexión para guardar.

### 4.4 Historial

Ventas de la más nueva a la más vieja, en vista **Lista** o **Por día**. Se busca por monto, producto o número.

- Al abrir la app se cargan todas las ventas desde el 1° del mes anterior.
- Las más viejas se traen con **"Cargar ventas anteriores"** (de a 500).
- Si un producto fue dado de baja, aparece como "(producto borrado)".

**Anular una venta.** Desde su detalle. Si ya está en la base se usa `anular_venta`, que la marca, guarda quién y cuándo la anuló, y devuelve el stock una sola vez. Requiere conexión. Si la venta todavía está en la cola, se marca anulada ahí y llega a la base como anulada, sin descontar stock.

### 4.5 Reportes y cierre de caja

Reportes para **Hoy**, **Esta semana** y **Este mes**: ingresos, cantidad de ventas, unidades, ticket promedio, gráfico por día y ranking de productos. Las anuladas no cuentan.

**Cierre de caja.** Totales del día por método de pago. "Efectivo esperado en caja" suma solo las ventas en efectivo. Al ingresar lo contado se calcula la diferencia. **Imprimir cierre** genera el resumen con el detalle.

### 4.6 Presupuesto

Cotizador: funciona como la Caja pero **no** descuenta stock ni registra ventas. Permite un descuento porcentual y genera un documento imprimible con número propio de cada PC.

### 4.7 Administración

- **Categorías** y **marcas**: alta y baja lógica.
- **Ventas sin sincronizar**: cuántas ventas esperan para enviarse y cuántas rechazó la base, con botones **Reintentar ahora** (envía la cola y vuelve a probar las rechazadas) y **Descargar copia** (ver [sección 6](#6-funcionamiento-sin-conexión)).
- **Apariencia**: tema claro (por defecto) u oscuro. Se guarda en cada PC.
- **Sesión**: con qué cuenta está conectada la PC y botón para cerrarla.

## 5. Base de datos

### Tablas

| Tabla | Contenido | Columnas destacadas |
| --- | --- | --- |
| `productos` | Catálogo | `codigo`, `nombre`, `categoria`, `marca` (modelos separados por `\|`), `precio`, `costo`, `stock`, `"stockDeposito"`, `"minStock"`, `activos` |
| `ventas` | Cabecera de cada venta | `id` (= número de comprobante), `fecha`, `total`, `pago`, `vuelto`, `metodo`, `anulada`, `uid` (id único generado en la caja), `usuario_id`, `usuario_email`, `anulada_por`, `anulada_por_email`, `anulada_en` |
| `items` | Detalle de cada venta | `venta_id`, `producto_id`, `cantidad` (> 0), `precio` (≥ 0), `subtotal` |
| `movimientos_stock` | Auditoría: una fila por cada cambio de stock | `fecha`, `producto_id`, `origen`, `venta_id`, `delta_negocio`, `delta_deposito`, `stock_negocio`, `stock_deposito`, `usuario_email` |
| `categorias` | Categorías | `nombre`, `activa` |
| `marcas` | Marcas y modelos | `nombre` (formato `Marca\|Modelo1,Modelo2`), `activa` |

`movimientos_stock.origen` vale `venta`, `anulacion`, `mover`, `ajuste` (carga rápida, importador, deshacer), `edicion` (stock cambiado a mano en el formulario) o `alta` (producto nuevo con stock).

### Qué puede hacer un usuario con sesión

| Tabla | Leer | Crear | Modificar | Borrar |
| --- | --- | --- | --- | --- |
| `productos`, `categorias`, `marcas` | Sí | Sí | Sí | No |
| `ventas`, `items` | Sí | Solo con `registrar_venta` | Solo con `anular_venta` | No |
| `movimientos_stock` | Sí | No (lo escribe un trigger) | No | No |

El rol `anon` (la clave pública sola) no puede leer, escribir ni ejecutar funciones. Las ventas no se pueden borrar ni editar desde la app ni desde la API; solo el dueño del proyecto puede hacerlo desde el panel de Supabase.

### Funciones

El stock se suma y se resta **dentro de la base** (`stock = stock - cantidad`); nunca se escribe un número calculado en el navegador. Dos cajas que venden el mismo producto a la vez no se pisan.

| Función | Qué hace |
| --- | --- |
| `registrar_venta(p_venta, p_items)` | Guarda venta, detalle y descuento de stock en una transacción. **Calcula el total y el vuelto** a partir de los items (ignora los que mande el navegador). Rechaza ventas sin items o con cantidad ≤ 0 o precio negativo. Si el mismo `uid` llega dos veces, devuelve la venta ya guardada. Si llega anulada, no descuenta stock. |
| `anular_venta(p_venta_id)` | Marca la venta como anulada, guarda quién y cuándo, y devuelve el stock. Si ya estaba anulada no hace nada. |
| `mover_stock(p_id, p_cant)` | Pasa unidades del depósito al negocio. Falla si el depósito no alcanza. |
| `ajustar_stock(p_items)` | Suma o resta stock en lote sobre el valor de la base. |
| `stocks_de_venta(p_venta_id)` | Uso interno: stock actual de los productos de una venta. |

**El stock puede quedar negativo.** Es a propósito: una venta hecha sin conexión ya ocurrió en el mostrador y hay que poder registrarla aunque otra caja haya vendido la última unidad. Un stock negativo indica que hay que revisar ese producto.

### Consultas útiles (SQL Editor)

```sql
-- Movimientos de stock de un producto, del más nuevo al más viejo
select fecha, origen, venta_id, delta_negocio, delta_deposito, stock_negocio, stock_deposito, usuario_email
from movimientos_stock where producto_id = 123 order by fecha desc;

-- Ventas anuladas del mes: quién vendió y quién anuló
select id, fecha, total, usuario_email, anulada_por_email, anulada_en
from ventas where anulada and fecha >= date_trunc('month', now()) order by fecha desc;

-- Productos con stock negativo
select id, codigo, nombre, stock from productos where stock < 0 and activos;
```

## 6. Funcionamiento sin conexión

- **La app abre sin internet**, también después de cerrar el navegador o apagar la PC, siempre que se haya abierto al menos una vez con conexión en esa PC. De eso se encarga `sw.js`. Con internet siempre se usa la versión publicada: no queda ninguna caja en una versión vieja.
- **Se puede vender**: productos e historial se leen de la copia local.
- **Toda venta se anota en la cola local antes de enviarse** (`rpos_pending_ventas`) y sale de la cola recién cuando la base confirma. Si se corta internet o la luz a mitad del envío, la venta no se pierde: se reenvía sola al volver la conexión o al abrir la app.
- Cada venta tiene un `uid` único: reenviarla no la duplica.
- El indicador de la barra superior muestra el estado: "Conectado", "Guardando…", "Sin conexión — en cola".

**Ventas rechazadas.** Si la base rechaza una venta por datos inválidos, reintentar no sirve. La app la aparta en una lista propia (`rpos_rejected_ventas`) para que no trabe a las demás, y avisa. Siguen apareciendo en el historial y en el cierre de caja con número provisorio, porque la plata está en la caja. En **Admin → Ventas sin sincronizar** se ve cuántas hay, **Reintentar ahora** las vuelve a enviar (sirve si el rechazo se debía a algo ya corregido en la base) y **Descargar copia** baja un archivo `.json` con el detalle y el motivo, para cargarlas a mano o enviarlo a soporte.

> **Límites sin conexión.** No se pueden anular ventas ya guardadas, mover stock entre depósito y negocio, ni crear o editar productos. La app avisa y no aplica el cambio.
>
> El login necesita internet: una PC que nunca inició sesión no puede empezar a usarse sin conexión.
>
> La cola vive en el navegador de esa PC. **No borrar los datos del navegador mientras haya ventas pendientes**; ante la duda, descargar la copia desde Admin.

## 7. Almacenamiento local del navegador

| Clave | Contenido |
| --- | --- |
| `rpos_session` | Sesión de Supabase (tokens y email). Se borra al cerrar sesión. |
| `rpos_pending_ventas` | Cola de ventas que todavía no confirmó la base. **No borrar.** |
| `rpos_rejected_ventas` | Ventas que la base rechazó. **No borrar** sin descargar la copia. |
| `rpos_cache_prod` | Copia del catálogo de productos. Se puede borrar: se vuelve a bajar. |
| `rpos_cache_hist` | Copia del historial cargado. Se puede borrar: se vuelve a bajar. |
| `rpos_vnum` | Contador de números provisorios (P-xxxx) de esa PC. |
| `rpos_presnum` | Contador de números de presupuesto de esa PC. |
| `rpos_tema` | Tema elegido (claro u oscuro). |
| `rpos_inv_vista` | Vista del inventario (tarjetas o lista). |
| `rpos_cr_destino`, `rpos_cr_margen`, `rpos_cr_cat` | Preferencias de la carga rápida. |

El navegador da unos 5 MB. Si se llena, la app prioriza la cola de ventas: libera las copias de historial y productos, que se pueden volver a bajar.

Aparte, el service worker guarda la copia de la app en *Cache Storage* (`rpos-app-v1`).

## 8. Copias de seguridad

Un workflow de GitHub (`.github/workflows/backup.yml`) copia la base **todos los días a las 03:17** (hora de Argentina). La copia incluye tablas, datos, funciones y seguridad; se comprime, se **cifra con contraseña** y queda guardada 90 días.

Objetivo: perder como máximo un día de datos (las ventas hechas después del último backup).

### Configurarlo (una sola vez)

En GitHub: **Settings → Secrets and variables → Actions → New repository secret**. Crear dos secretos:

| Secreto | Valor |
| --- | --- |
| `SUPABASE_DB_URL` | En Supabase, botón **Connect** → **Session pooler** → copiar la cadena y reemplazar `[YOUR-PASSWORD]` por la contraseña de la base. Tiene que ser la del *pooler*: la conexión directa no funciona desde GitHub. |
| `BACKUP_PASSPHRASE` | Una contraseña larga inventada. **Guardarla también fuera de GitHub** (por ejemplo, anotada junto a la documentación del local): sin ella las copias no se pueden abrir. |

Después: **Actions → Backup de la base → Run workflow** para hacer la primera copia y comprobar que termina en verde.

Notas:

- El backup programado solo corre desde la rama `main`, y **falla todos los días hasta que existan los dos secretos**.
- La copia queda como archivo descargable de la ejecución. Si el repositorio es público, cualquier persona con cuenta de GitHub puede bajarla: lo único que la protege es el cifrado, así que la contraseña tiene que ser larga (por ejemplo, seis palabras al azar).
- GitHub pausa los workflows programados si el repositorio pasa 60 días sin actividad. Si llega un aviso por mail, entrar a Actions y reactivarlo.
- Si la ejecución falla, GitHub avisa por mail al dueño del repositorio.
- Si falla con "server version mismatch", subir `PG_VERSION` en el workflow a la versión de PostgreSQL del proyecto.

### Descargar una copia

**Actions → Backup de la base →** la ejecución del día **→ Artifacts**. Baja un `.zip` con el archivo `ruta38-AAAA-MM-DD_HHMM.sql.gz.gpg`.

### Restaurar

La restauración se hace en un **proyecto de Supabase nuevo y vacío**; nunca encima de la base en uso.

1. Crear un proyecto nuevo en Supabase y copiar su cadena de conexión.
2. En una PC con `psql` y `gpg`:
   ```bash
   DESTINO_DB_URL='postgresql://...' BACKUP_PASSPHRASE='la contraseña' scripts/restaurar.sh ruta38-2026-11-10_0617.sql.gz.gpg
   ```
3. Correr `supabase_migracion.sql` en el SQL Editor del proyecto nuevo (repone permisos y seguridad).
4. Crear los usuarios (Authentication → Users) y desactivar *Allow new users to sign up*.
5. Poner la URL y la clave pública del proyecto nuevo en `index.html` y publicar.

**Probar la restauración una vez**, cuando el backup esté configurado, y repetirla cada seis meses. Un backup que nunca se restauró no está comprobado.

### Copia manual

Sigue siendo posible exportar tablas a CSV desde Supabase → Table Editor → Export. Sirve para mirar datos en Excel, no como backup completo.

## 9. Publicación y vuelta atrás

Cada cambio en la rama `main` se publica solo en Vercel. No hay entorno de prueba separado.

### Publicar una versión

1. Trabajar en una rama y correr las pruebas (ver [sección 10](#10-pruebas)).
2. Si la versión trae cambios de base: hacer un backup (**Run workflow**) y correr `supabase_migracion.sql`, fuera del horario de atención.
3. Mergear a `main`. Verificar en Vercel → Deployments que la publicación terminó.
4. En cada PC, recargar la página. Con internet, la versión nueva aparece en la primera recarga.

### Primera publicación de la versión 8

El backup automático todavía no existe en `main`, así que el orden cambia. La app nueva funciona con la base de la versión 7 y la app de la versión 7 funciona con la base nueva, de modo que ningún paso deja la caja sin andar.

1. Mergear a `main` y verificar la publicación en Vercel.
2. Crear los dos secretos del backup (sección 8) y hacer **Run workflow**. Comprobar que termina en verde y descargar esa copia.
3. Fuera del horario de atención, correr `supabase_migracion.sql` en el SQL Editor.
4. Hacer una venta de prueba y anularla. Verificar en Supabase que `ventas.usuario_email` tiene el email y que `movimientos_stock` tiene las dos filas.
5. Crear un usuario por persona, si todavía comparten cuenta.

Si se prefiere tener el backup antes de mergear, correr `scripts/backup.sh` a mano desde una PC con `pg_dump` y `gpg`.

### Volver atrás

- **La app:** Vercel → Deployments → elegir la publicación anterior → **Promote to Production** (o *Instant Rollback*). Después, revertir el cambio en `main` para que la próxima publicación no lo vuelva a traer.
- **La base:** las migraciones solo agregan columnas, tablas y funciones; la app anterior sigue funcionando con la base nueva, así que normalmente no hace falta volver atrás la base. Ante un daño en los datos, restaurar el último backup (sección 8).

## 10. Pruebas

Ninguna prueba toca la base real de Supabase.

| Comando | Qué comprueba | Requiere |
| --- | --- | --- |
| `tests/sql/correr.sh` | `supabase_schema.sql` y `supabase_migracion.sql` en un Postgres local: base nueva, base de la versión 7 con datos, que la migración se pueda correr dos veces, permisos, auditoría, cálculo del total y funciones de stock. | PostgreSQL local (`psql`) |
| `tests/sql/probar_backup.sh` | Backup cifrado, restauración en una base vacía y comparación de datos. | PostgreSQL local, `gpg` |
| `node tests/e2e/smoke.js` | La app en Chromium con Supabase simulado: login, venta, cola sin conexión, cierre de pestaña a mitad del envío, venta rechazada, venta anulada en cola, navegador sin espacio. | Node.js y Playwright |
| `node tests/e2e/offline.js` | El service worker: la app abre sin internet y toma la versión nueva al publicarse. | Node.js y Playwright |

`tests/sql/00_simular_supabase.sql` imita lo mínimo de Supabase (roles `anon` / `authenticated`, `auth.uid()`, `auth.jwt()`) para poder probar en un Postgres común.

## 11. Diagnóstico y problemas comunes

Herramientas: consola del navegador (**F12 → Console**; los errores de la base aparecen como "ERROR SUPABASE …"), indicador de sincronización de la barra superior, **Admin → Ventas sin sincronizar**, y en Supabase el **Table Editor** y los **Logs**.

| Problema | Causa probable y solución |
| --- | --- |
| "Email o contraseña incorrectos" | Verificar el usuario en Supabase → Authentication → Users (que esté confirmado). Ahí se puede cambiar la contraseña. |
| "Sin conexión — no se pudo ingresar" | No hay internet. El login necesita conexión; una vez iniciada, la sesión funciona sin conexión. |
| Después de actualizar sigue la versión vieja | Verificar en Vercel → Deployments que la publicación terminó y recargar. Si no hay internet, la app muestra la última copia guardada: es lo esperado. |
| No cargan productos ni ventas | Revisar la consola. Si dice "permission denied" o "row-level security", falta correr `supabase_migracion.sql` o la sesión no es válida (cerrar sesión y volver a entrar). |
| Ventas quedan "en cola" con internet | Revisar la consola: si la función `registrar_venta` no existe, falta la migración. Probar **Admin → Reintentar ahora**. |
| Aviso "La base rechazó la venta" | La venta tenía un dato inválido o la base tiene un problema. Está apartada, no perdida, y sigue contando en el cierre. **Admin → Descargar copia** y enviar el archivo a soporte; corregido el problema, **Reintentar ahora**. |
| El ticket sale con número P-xxxx | La venta no llegó a la base en 6 segundos. Se guarda sola; el historial mostrará el número definitivo. |
| "No alcanza el stock en depósito" | Otra PC ya movió esas unidades. Recargar para ver el stock actual. |
| Faltan ventas viejas en el historial | Es lo esperado: se cargan desde el mes anterior. Usar "Cargar ventas anteriores". |
| Stock que no coincide entre PCs | Recargar la página: la copia local se actualiza con el stock de la base. Para ver qué pasó con un producto, consultar `movimientos_stock` (sección 5). |
| "El navegador se quedó sin espacio para la copia local" | Las ventas se siguen guardando. Recargar con internet; si persiste, cerrar sesión y volver a entrar (libera las copias locales, no las ventas pendientes). |
| El backup diario falla | Entrar a Actions y leer el paso en rojo. Lo más común: el secreto `SUPABASE_DB_URL` no es la cadena del *Session pooler* o tiene mal la contraseña. |

## 12. Estilos

Estilos adaptados a celulares con media queries; el corte principal es 700 px. El tema es **claro por defecto**; el oscuro se activa desde Admin → Apariencia y se guarda en cada PC.

| Variable | Tema claro | Tema oscuro |
| --- | --- | --- |
| `--bg` | `#f5f4f1` | `#131211` |
| `--surface` | `#ffffff` | `#1c1b19` |
| `--border` | `#e2dfd9` | `#33302c` |
| `--accent` | `#ea580c` | `#f97316` |
| `--green` | `#16884a` | `#3ec27a` |
| `--danger` | `#d4351f` | `#ef5a4a` |
| `--warn` | `#a86b00` | `#f2c94c` |

La lista completa de variables está al principio del `<style>` de `index.html`. Las fuentes son IBM Plex Sans e IBM Plex Mono. El logo está embebido una sola vez en la barra superior (`#logo-img`) y lo reutilizan el ticket y el presupuesto.

## 13. Límites conocidos

- **Sin roles.** Cualquier usuario con sesión puede anular ventas, cambiar precios y dar de baja productos. Queda registrado quién lo hizo, pero no se impide.
- **La auditoría se consulta en Supabase.** La app todavía no muestra quién hizo cada venta ni el historial de movimientos de un producto (ver consultas de la sección 5).
- **Sin entorno de prueba.** Lo que se mergea a `main` sale directo al local.
- **Todo el código en un archivo.** `index.html` tiene unas 6.000 líneas con estilos, interfaz y lógica.
- **Sin política de seguridad de contenido (CSP).** El código usa manejadores en línea (`onclick`), así que una CSP útil requiere antes separar el código.
- **Marcas y modelos como texto.** No son tablas propias, lo que limita filtros y reportes por modelo.
- **No emite facturas.** No hay integración con ARCA.
- **Plan gratuito de Supabase.** No permite restaurar a un momento exacto; la protección es el backup diario.
