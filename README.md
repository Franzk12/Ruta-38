# Ruta 38 Repuestos — Sistema POS

Sistema de punto de venta para repuestos de autos. Es una aplicación de una sola página (`index.html`), sin instalación ni build: se abre directo en el navegador.

## Cómo usar
Abrir la app publicada (o `index.html`) en Chrome o Edge. La primera vez en cada PC pide **email y contraseña** (la sesión queda guardada). Desde el navegador se puede instalar como aplicación.

## Funciones
- **Caja / Ventas** — escaneo de código de barras, carrito, cobro y emisión de ticket (impresora POS 80mm)
- **Inventario** — alta/baja/edición de productos, transferencia depósito ↔ negocio, aumento masivo de precios
  - **Carga rápida:** escanear códigos para sumar stock o crear productos nuevos con un formulario corto (sin mouse)
  - **Importar:** carga masiva desde Excel, CSV o una tabla pegada (PDF, mail, WhatsApp), con vista previa antes de guardar y plantilla descargable
  - **Crear similar** (menú ⋯ de cada producto): crear un producto nuevo copiando otro; vista en **tarjetas o lista**
- **Historial** — ventas por lista o agrupadas por día, anulación con devolución de stock
- **Reportes** — métricas por día/semana/mes, gráfico de ventas y ranking de productos
- **Presupuesto** — cotizador para clientes con descuento, no descuenta stock
- **Admin** — gestión de categorías y marcas/modelos
- **Cierre de caja** — resumen del día y diferencia entre efectivo contado y esperado

## Datos y sincronización
Los datos viven en **Supabase** (tablas `productos`, `ventas`, `items`, `movimientos_stock`, `categorias`, `marcas`). El navegador guarda una copia en `localStorage` como caché.

**Sin conexión:** la app abre igual (service worker `sw.js`) y se puede vender. Cada venta se anota en una cola local *antes* de enviarse y sale de la cola recién cuando la base confirma; se reintenta sola al volver internet y no se duplica. En **Admin → Ventas sin sincronizar** se ve el estado y se puede descargar una copia.

`cargar_datos.js` es un script de un solo uso para precargar el catálogo inicial de categorías y marcas — se pega en la consola del navegador (F12), no forma parte de la app.

## Acceso
- **Login (email + contraseña):** es lo que protege los datos. Sin sesión, la base no deja leer ni escribir nada, aunque alguien tenga la `anon key` que queda visible en el código.
- **Un usuario por persona:** cada venta y anulación guarda quién la hizo. La sesión se cierra desde **Admin → Cerrar sesión**.

## Seguridad de los datos
- Las ventas **no se pueden borrar ni editar** desde la app ni desde la API: solo se registran y anulan con las funciones de la base (`registrar_venta`, `anular_venta`), que además calculan el total.
- Cada cambio de stock queda anotado en `movimientos_stock` (venta, anulación, carga, movimiento, edición).
- Dos cajas que venden el mismo producto al mismo tiempo no se pisan: el stock se suma y resta en la base.
- **Backup diario cifrado** con GitHub Actions (`.github/workflows/backup.yml`). Necesita dos secretos del repositorio: `SUPABASE_DB_URL` y `BACKUP_PASSPHRASE`.

## Puesta en marcha / actualización de la base
1. **Base nueva:** correr `supabase_schema.sql` y después `supabase_migracion.sql` en el SQL Editor de Supabase.
   **Base que ya existe:** correr solo `supabase_migracion.sql` (no borra datos, se puede correr más de una vez).
2. Authentication → Users → **Add user**: crear un usuario por persona (marcar *Auto Confirm User*).
3. Authentication → Sign In / Providers → **desactivar "Allow new users to sign up"**. Si queda activado, cualquiera con la `anon key` podría crearse una cuenta propia.
4. Abrir `index.html` e ingresar con ese email y contraseña.
5. Configurar los secretos del backup (ver documentación, sección 8).

## Pruebas
Ninguna toca la base real.

```bash
tests/sql/correr.sh          # base y migración, en un Postgres local
tests/sql/probar_backup.sh   # backup cifrado y restauración
node tests/e2e/smoke.js      # la app en Chromium con Supabase simulado
node tests/e2e/offline.js    # abrir sin internet
```

## Documentación
- [docs/DOCUMENTACION.md](docs/DOCUMENTACION.md) — documentación técnica completa (versión 8).
- [docs/CHANGELOG.md](docs/CHANGELOG.md) — cambios por versión.
- `RepuestoPOS_Documentacion.docx` — versión 7, solo como referencia histórica.
