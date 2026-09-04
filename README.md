# Ruta 38 Repuestos — Sistema POS

Sistema de punto de venta para repuestos de autos. Es una aplicación de una sola página (`index.html`), sin instalación ni build: se abre directo en el navegador.

## Cómo usar
Abrir `index.html` en el navegador (Chrome o Edge recomendado). Al entrar pide un PIN de acceso.

## Funciones
- **Caja / Ventas** — escaneo de código de barras, carrito, cobro y emisión de ticket (impresora POS 80mm)
- **Inventario** — alta/baja/edición de productos, transferencia depósito ↔ negocio, aumento masivo de precios
- **Historial** — ventas por lista o agrupadas por día, anulación con devolución de stock
- **Reportes** — métricas por día/semana/mes, gráfico de ventas y ranking de productos
- **Presupuesto** — cotizador para clientes con descuento, no descuenta stock
- **Admin** — gestión de categorías y marcas/modelos
- **Cierre de caja** — resumen del día y diferencia entre efectivo contado y esperado

## Datos y sincronización
Los datos viven en **Supabase** (backend en la nube, tablas `productos`, `ventas`, `items`, `categorias`, `marcas`). El navegador guarda una copia en `localStorage` como caché y para seguir funcionando sin conexión: las ventas hechas offline quedan en una cola local y se reintentan solas al recuperar internet.

`cargar_datos.js` es un script de un solo uso para precargar el catálogo inicial de categorías y marcas — se pega en la consola del navegador (F12), no forma parte de la app.

## Acceso
La app pide un PIN antes de mostrar cualquier pantalla (ver `APP_PIN` en el `<script>` de `index.html` para cambiarlo). Es un freno básico contra el acceso casual, **no reemplaza la seguridad real**: esa depende de las políticas RLS (Row Level Security) configuradas en el proyecto de Supabase, ya que la `anon key` queda visible en el código fuente del navegador.
