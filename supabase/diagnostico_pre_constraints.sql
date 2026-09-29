-- ════════════════════════════════════════════════════════════════════
-- Diagnóstico de SOLO LECTURA — correr en el SQL Editor antes del paso 5
-- No modifica nada. Sirve para saber si las constraints futuras
-- (UNIQUE codigo, CHECK de stock) se pueden aplicar con los datos actuales.
-- ════════════════════════════════════════════════════════════════════

-- 1. Códigos duplicados entre productos activos (bloquearían UNIQUE(codigo))
select codigo, count(*) as cantidad, array_agg(id order by id) as ids, array_agg(nombre) as nombres
  from public.productos
 where codigo is not null and codigo <> '' and activos
 group by codigo
having count(*) > 1
 order by cantidad desc;

-- 2. Códigos vacíos ('') que deberían ser NULL
select id, nombre from public.productos where codigo = '';

-- 3. Stock negativo hoy (bloquearía CHECK(stock >= 0))
select id, nombre, stock, "stockDeposito"
  from public.productos
 where stock < 0 or "stockDeposito" < 0;

-- 4. Ventas duplicadas probables (mismo total y fecha con menos de 1 minuto de diferencia)
select a.id as venta_a, b.id as venta_b, a.total, a.fecha as fecha_a, b.fecha as fecha_b
  from public.ventas a
  join public.ventas b on b.id > a.id and b.total = a.total
                      and abs(extract(epoch from (b.fecha - a.fecha))) < 60
 order by a.id desc
 limit 50;

-- 5. Ventas sin items (posibles ventas parciales por fallo a mitad de guardado)
select v.id, v.fecha, v.total
  from public.ventas v
  left join public.items i on i.venta_id = v.id
 where i.id is null
 order by v.id desc;

-- 6. Items huérfanos (producto borrado o dado de baja)
select count(*) filter (where producto_id is null) as sin_producto,
       count(*) as total_items
  from public.items;

-- 7. Volumen: cuánto falta para los topes de carga del front (1000 / 2000 filas)
select (select count(*) from public.productos where activos) as productos_activos,
       (select count(*) from public.ventas) as ventas,
       (select count(*) from public.items)  as items;
