# Ruta 38 Repuestos — Sistema POS

Sistema de punto de venta para repuestos de autos. Es una aplicación de una sola página (`index.html`), sin instalación ni build: se abre directo en el navegador.

## Cómo usar
Abrir `index.html` en el navegador (Chrome o Edge recomendado). La primera vez en cada PC pide el **email y la contraseña del local** (la sesión queda guardada) y después el **PIN** de bloqueo.

## Funciones
- **Caja / Ventas** — escaneo de código de barras, carrito, cobro y emisión de ticket (impresora POS 80mm)
- **Inventario** — alta/baja/edición de productos, transferencia depósito ↔ negocio, aumento masivo de precios
  - **⚡ Carga rápida:** escanear códigos para sumar stock o crear productos nuevos con un formulario corto (sin mouse)
  - **📥 Importar:** carga masiva desde Excel, CSV o una tabla pegada (PDF, mail, WhatsApp), con vista previa antes de guardar y plantilla descargable
  - **⧉ Similar:** crear un producto nuevo copiando otro
- **Historial** — ventas por lista o agrupadas por día, anulación con devolución de stock
- **Reportes** — métricas por día/semana/mes, gráfico de ventas y ranking de productos
- **Presupuesto** — cotizador para clientes con descuento, no descuenta stock
- **Admin** — gestión de categorías y marcas/modelos
- **Cierre de caja** — resumen del día y diferencia entre efectivo contado y esperado

## Datos y sincronización
Los datos viven en **Supabase** (backend en la nube, tablas `productos`, `ventas`, `items`, `categorias`, `marcas`). El navegador guarda una copia en `localStorage` como caché y para seguir funcionando sin conexión: las ventas hechas offline quedan en una cola local y se reintentan solas al recuperar internet.

`cargar_datos.js` es un script de un solo uso para precargar el catálogo inicial de categorías y marcas — se pega en la consola del navegador (F12), no forma parte de la app.

## Acceso
- **Login (email + contraseña del local):** es lo que protege los datos. Sin sesión, la base no deja leer ni escribir nada, aunque alguien tenga la `anon key` que queda visible en el código. La sesión se renueva sola; se cierra desde **Admin → Cerrar sesión**.
- **PIN** (`APP_PIN` en el `<script>` de `index.html`): solo bloquea la pantalla cuando te alejás de la caja (botón 🔒), sin cerrar la sesión.

## Stock entre varias cajas
Las ventas, anulaciones y movimientos depósito → negocio se hacen con funciones de la base (`registrar_venta`, `anular_venta`, `mover_stock`) que suman o restan **en Supabase**. Dos cajas que venden el mismo producto al mismo tiempo no se pisan, y una venta reintentada desde la cola offline no se duplica.

## Puesta en marcha / actualización de la base
1. **Base nueva:** correr `supabase_schema.sql` completo en el SQL Editor de Supabase.
   **Base que ya existe:** correr `supabase_migracion.sql` (no borra datos, se puede correr más de una vez).
2. Authentication → Users → **Add user**: crear el email y la contraseña del local (marcar *Auto Confirm User*).
3. Authentication → Sign In / Providers → **desactivar "Allow new users to sign up"**. Si queda activado, cualquiera con la `anon key` podría crearse una cuenta propia.
4. Abrir `index.html` e ingresar con ese email y contraseña.
