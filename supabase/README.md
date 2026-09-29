# Plan de endurecimiento — Supabase

Cambios de base de datos para pasar la lógica crítica (ventas, stock, permisos) del navegador a PostgreSQL, sin reescribir la interfaz. La auditoría que originó este plan señala como problemas principales: RLS abierta, stock no atómico, método de pago sin persistir y XSS.

## Estado

| Paso | Contenido | Estado |
|---|---|---|
| 0 | Backup + proyecto de staging | Checklist abajo |
| 1 | `migrations/001_aditiva.sql` (columnas, ledger, índices; no cambia el comportamiento) | **Escrita, sin aplicar** |
| 2 | RPC `registrar_venta`, `anular_venta`, `mover_stock`, `aplicar_aumento` | Pendiente |
| 3 | `esc()` (XSS), cierre de caja, quitar `document.write` con datos | Pendiente |
| 4 | Supabase Auth + RLS real + revocar escritura directa | Pendiente |
| 5 | Constraints (`UNIQUE(codigo)`, `CHECK` de stock) | Pendiente, ver `diagnostico_pre_constraints.sql` |

## Paso 0 — antes de tocar la base

1. **Backup**: Supabase → Database → Backups (o Table Editor → export CSV de `productos`, `ventas`, `items`, `categorias`, `marcas`). Guardar los archivos fuera del repo.
2. **Staging**: crear un segundo proyecto Supabase, correr `supabase_schema.sql` y cargar una copia de los datos. Probar cada migración ahí primero.
3. **Diagnóstico**: correr `diagnostico_pre_constraints.sql` (solo lectura) en producción y guardar el resultado. Define qué datos hay que limpiar antes del paso 5.
4. Confirmar con el dueño del local la política de **stock negativo**: si dos cajas venden la última unidad, la venta se acepta y se marca la discrepancia (recomendado) o se rechaza.

## Aplicar la migración 001

1. En **staging**: SQL Editor → pegar `migrations/001_aditiva.sql` → Run.
2. Abrir `index.html` apuntando a staging y usarlo normalmente (vender, editar, anular): debe funcionar igual que antes.
3. Recién entonces repetir en producción.

La migración es idempotente y trae el rollback manual al final del archivo.

## Notas

- `supabase_schema.sql` (esquema desde cero) todavía **no** incluye lo de la migración 001. Se actualizará cuando el plan esté aplicado, para que un proyecto nuevo nazca con el esquema final.
- `ventas.metodo_pago` de las ventas históricas queda en `'efectivo'` por defecto: ese dato nunca se guardó, así que no es información real.
- Los campos `items.nombre` y `items.costo` se rellenan con los valores **actuales** del producto; para ventas antiguas pueden diferir de los de la fecha.
