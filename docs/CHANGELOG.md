# Registro de cambios

## Versión 8 — Noviembre 2026

Objetivo: proteger las ventas y los datos.

| Área | Versión 7 | Versión 8 |
| --- | --- | --- |
| Ventas en la base | Cualquier sesión podía borrarlas o editarlas por la API | Solo lectura. Se registran y anulan únicamente con las funciones de la base |
| Auditoría | No se guardaba quién hizo cada operación | Cada venta y anulación guarda el usuario; cada cambio de stock queda en `movimientos_stock` |
| Total de la venta | Lo calculaba el navegador y la base lo aceptaba | Lo calcula la base a partir de los items. Rechaza cantidades y precios inválidos |
| Numeración | Cada reintento de una venta gastaba un número | El reintento reutiliza la venta ya guardada |
| Venta en vuelo | Si se cerraba la pestaña a mitad del envío, la venta se perdía | La venta se anota en la cola antes de enviarse y sale cuando la base confirma |
| Cola sin conexión | Una venta cobrada mientras se sincronizaba podía quedar pisada. Una venta rechazada trababa a todas las siguientes | La cola se relee en cada envío. Las rechazadas se apartan y se pueden descargar |
| Almacenamiento lleno | Un error al escribir la copia local frenaba el cobro | Las escrituras están protegidas y la cola tiene prioridad |
| Abrir sin internet | Solo si la página ya estaba abierta | Service worker: abre aunque se haya cerrado el navegador. Se puede instalar como app |
| Importar Excel | Bajaba SheetJS de un CDN en cada uso | SheetJS incluido en el proyecto: funciona sin conexión |
| Backup | Exportar CSV a mano | Backup diario automático y cifrado, con script de restauración |
| Archivos SQL | Funciones y seguridad duplicadas en dos archivos | Una sola copia en `supabase_migracion.sql` |
| Pruebas | Ninguna | Pruebas de la base, del backup y de la app en el navegador |
| Documentación | Word (`.docx`) | Markdown en `docs/`, corregida |

Correcciones de la documentación respecto de la versión 7: el tema por defecto es claro (no oscuro); la app sí usa una librería externa (SheetJS); se documentan todas las claves de `localStorage`; se agregan publicación, vuelta atrás, pruebas y límites conocidos.

Para actualizar desde la versión 7: correr `supabase_migracion.sql`, publicar, y configurar los secretos del backup. Ver [DOCUMENTACION.md](DOCUMENTACION.md), secciones 3, 8 y 9.

## Versión 7 — Septiembre 2026

| Área | Versión 6 | Versión 7 |
| --- | --- | --- |
| Backend | Google Sheets (Apps Script) | Supabase (PostgreSQL + Auth) |
| Acceso | Sin control de acceso real | Login con email y contraseña |
| Stock entre cajas | Cada navegador escribía su número (se pisaban) | Se suma y resta en la base de forma atómica |
| Número de comprobante | Contador de cada PC | Número único de la base (provisorio P-xxxx sin conexión) |
| Método de pago | No se guardaba | Se guarda, se imprime y se usa en el cierre |
| Cierre de caja | Efectivo esperado incluía tarjetas y transferencias | Solo efectivo |
| Ventas offline | Se guardaban con la hora de sincronización | Conservan su fecha real y no se duplican |
| Historial | Últimas 2.000 ventas | Desde el mes anterior + "Cargar ventas anteriores" |
| Carga de productos | De a uno, con el formulario | Carga rápida con escáner, importador y "Similar" |
