-- Pruebas de la base. Cada bloque falla con una excepción si algo no da lo esperado.
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

create or replace function pg_temp.ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FALLÓ: %', msg; end if;
  raise notice 'ok  %', msg;
end $$;
-- Ejecuta un SQL que TIENE que fallar
create or replace function pg_temp.debe_fallar(q text, msg text) returns void language plpgsql as $$
begin
  begin
    execute q;
  exception when others then
    raise notice 'ok  % (rechazado: %)', msg, sqlerrm;
    return;
  end;
  raise exception 'FALLÓ: % — se esperaba un error y no lo hubo', msg;
end $$;

-- Datos de prueba (como dueño de la base)
insert into public.productos (id, codigo, nombre, precio, costo, stock, "stockDeposito")
overriding system value values
  (9001, 'T-1', 'Filtro de prueba', 1000, 600, 10, 5),
  (9002, 'T-2', 'Bujía de prueba',   250.50, 100, 3, 0);

-- ── Sin sesión (rol anon): nada ──
set role anon;
select pg_temp.debe_fallar($$select count(*) from public.productos$$, 'anon no lee productos');
select pg_temp.debe_fallar($$select count(*) from public.ventas$$, 'anon no lee ventas');
select pg_temp.debe_fallar($$select public.registrar_venta('{"uid":"x"}', '[{"producto_id":9001,"cantidad":1,"precio":1}]')$$, 'anon no registra ventas');
reset role;

-- ── Con sesión ──
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","email":"caja1@prueba.test"}', false);

-- Venta: el total lo calcula la base aunque el navegador mande otro
select public.registrar_venta(
  '{"uid":"t-venta-1","total":1,"pago":3000,"vuelto":999,"metodo":"efectivo"}',
  '[{"producto_id":9001,"cantidad":2,"precio":1000},{"producto_id":9002,"cantidad":1,"precio":200}]') as r \gset
select (:'r'::jsonb->>'venta_id')::bigint as vid \gset
select pg_temp.ok((select total = 2200 and vuelto = 800 and pago = 3000 from public.ventas where id = :vid), 'la base calcula total (2200) y vuelto (800), con el precio editado del item');
select pg_temp.ok((select usuario_email = 'caja1@prueba.test' and usuario_id = '11111111-1111-1111-1111-111111111111' from public.ventas where id = :vid), 'la venta guarda quién la hizo');
select pg_temp.ok((select stock from public.productos where id = 9001) = 8, 'descuenta stock (10 → 8)');
select pg_temp.ok((select count(*) from public.movimientos_stock where venta_id = :vid and origen = 'venta' and usuario_email = 'caja1@prueba.test') = 2, 'anota 2 movimientos de stock de la venta');
select pg_temp.ok((select delta_negocio = -2 and stock_negocio = 8 from public.movimientos_stock where venta_id = :vid and producto_id = 9001), 'el movimiento guarda la diferencia y el stock resultante');

-- Reintento con el mismo uid: no duplica ni vuelve a descontar, ni gasta números
select public.registrar_venta('{"uid":"t-venta-1","pago":3000}', '[{"producto_id":9001,"cantidad":2,"precio":1000}]') as r2 \gset
select pg_temp.ok((:'r2'::jsonb->>'venta_id')::bigint = :vid, 'reintento devuelve la misma venta');
select pg_temp.ok((select stock from public.productos where id = 9001) = 8, 'reintento no descuenta de nuevo');
select public.registrar_venta('{"uid":"t-venta-2","pago":250.5,"metodo":"debito"}', '[{"producto_id":9002,"cantidad":1,"precio":250.5}]') as r3 \gset
select pg_temp.ok((:'r3'::jsonb->>'venta_id')::bigint = :vid + 1, 'el reintento no dejó un hueco en la numeración');

-- Venta sin conexión que deja stock negativo: se acepta (la venta ya ocurrió)
select public.registrar_venta('{"uid":"t-venta-3"}', '[{"producto_id":9002,"cantidad":5,"precio":250.5}]') as r4 \gset
select pg_temp.ok((select stock from public.productos where id = 9002) = -4, 'una venta puede dejar stock negativo (3 - 1 - 1 - 5 = -4)');
select pg_temp.ok((select pago = total and vuelto = 0 from public.ventas where uid = 't-venta-3'), 'sin pago informado se toma el total justo');

-- Datos inválidos
select pg_temp.debe_fallar($$select public.registrar_venta('{"uid":"t-mala-1"}', '[]')$$, 'rechaza venta sin items');
select pg_temp.debe_fallar($$select public.registrar_venta('{"uid":"t-mala-2"}', '[{"producto_id":9001,"cantidad":0,"precio":10}]')$$, 'rechaza cantidad 0');
select pg_temp.debe_fallar($$select public.registrar_venta('{"uid":"t-mala-3"}', '[{"producto_id":9001,"cantidad":1,"precio":-5}]')$$, 'rechaza precio negativo');
select pg_temp.debe_fallar($$select public.registrar_venta('{"uid":"t-mala-4"}', '[{"producto_id":9001,"cantidad":1,"precio":null}]')$$, 'rechaza precio vacío');
select pg_temp.ok((select count(*) from public.ventas where uid like 't-mala-%') = 0, 'las ventas rechazadas no dejan nada guardado');
select pg_temp.ok((select stock from public.productos where id = 9001) = 8, 'las ventas rechazadas no tocan el stock');

-- Producto borrado/inexistente: la venta se guarda igual, sin producto
select public.registrar_venta('{"uid":"t-venta-4"}', '[{"producto_id":424242,"cantidad":1,"precio":10}]') as r5 \gset
select pg_temp.ok((select producto_id is null from public.items where venta_id = (:'r5'::jsonb->>'venta_id')::bigint), 'item de producto inexistente queda sin producto');

-- Anulación (otro usuario)
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","email":"duenio@prueba.test"}', false);
select public.anular_venta(:vid);
select pg_temp.ok((select anulada and anulada_por_email = 'duenio@prueba.test' and anulada_en is not null and usuario_email = 'caja1@prueba.test' from public.ventas where id = :vid), 'la anulación guarda quién y cuándo, sin pisar quién vendió');
select pg_temp.ok((select stock from public.productos where id = 9001) = 10, 'la anulación devuelve el stock (8 → 10)');
select public.anular_venta(:vid);
select pg_temp.ok((select stock from public.productos where id = 9001) = 10, 'anular dos veces no devuelve el stock dos veces');
select pg_temp.ok((select count(*) from public.movimientos_stock where venta_id = :vid and origen = 'anulacion') = 2, 'anota los movimientos de la anulación una sola vez');
select pg_temp.debe_fallar($$select public.anular_venta(987654321)$$, 'anular una venta inexistente da error');

-- Venta que llega ya anulada desde la cola offline: no descuenta stock
select public.registrar_venta('{"uid":"t-venta-5","anulada":true}', '[{"producto_id":9001,"cantidad":4,"precio":1000}]');
select pg_temp.ok((select stock from public.productos where id = 9001) = 10, 'venta que llega anulada no descuenta stock');
select pg_temp.ok((select anulada and anulada_por_email = 'duenio@prueba.test' from public.ventas where uid = 't-venta-5'), 'venta que llega anulada queda anulada con su autor');
-- Venta registrada y luego reenviada como anulada: se anula
select public.registrar_venta('{"uid":"t-venta-6"}', '[{"producto_id":9001,"cantidad":1,"precio":1000}]');
select public.registrar_venta('{"uid":"t-venta-6","anulada":true}', '[{"producto_id":9001,"cantidad":1,"precio":1000}]');
select pg_temp.ok((select stock from public.productos where id = 9001) = 10 and (select anulada from public.ventas where uid = 't-venta-6'), 'reenvío anulado de una venta ya guardada la anula y devuelve stock');

-- Las ventas no se pueden tocar por fuera de las funciones
select pg_temp.debe_fallar($$delete from public.ventas$$, 'no se pueden borrar ventas');
select pg_temp.debe_fallar($$update public.ventas set total = 1$$, 'no se pueden editar ventas');
select pg_temp.debe_fallar($$insert into public.ventas (total) values (5)$$, 'no se pueden insertar ventas a mano');
select pg_temp.debe_fallar($$delete from public.items$$, 'no se pueden borrar items');
select pg_temp.debe_fallar($$update public.items set precio = 1$$, 'no se pueden editar items');
select pg_temp.debe_fallar($$delete from public.productos where id = 9002$$, 'no se pueden borrar productos (solo baja lógica)');
select pg_temp.debe_fallar($$insert into public.movimientos_stock (origen, stock_negocio, stock_deposito) values ('x',0,0)$$, 'no se pueden inventar movimientos de stock');
select pg_temp.debe_fallar($$delete from public.movimientos_stock$$, 'no se pueden borrar movimientos de stock');

-- Lo que la app hace directo sobre las tablas sigue funcionando
insert into public.productos (nombre, precio, costo, stock, "stockDeposito") values ('Alta de prueba', 10, 5, 7, 2);
select pg_temp.ok((select count(*) from public.movimientos_stock m join public.productos p on p.id = m.producto_id where p.nombre = 'Alta de prueba' and m.origen = 'alta' and m.delta_negocio = 7 and m.delta_deposito = 2) = 1, 'crear un producto con stock anota el alta');
update public.productos set precio = 1100 where id = 9001;
select pg_temp.ok((select count(*) from public.movimientos_stock where producto_id = 9001 and origen = 'edicion') = 0, 'cambiar solo el precio no anota movimiento de stock');
update public.productos set stock = 12 where id = 9001;
select pg_temp.ok((select delta_negocio = 2 and usuario_email = 'duenio@prueba.test' from public.movimientos_stock where producto_id = 9001 and origen = 'edicion') , 'editar el stock a mano queda anotado como edición');
update public.productos set activos = false where nombre = 'Alta de prueba';
insert into public.categorias (nombre) values ('Categoría de prueba');
update public.categorias set activa = false where nombre = 'Categoría de prueba';
insert into public.marcas (nombre) values ('Marca de prueba');

-- mover_stock y ajustar_stock
select public.mover_stock(9001, 3);
select pg_temp.ok((select stock = 15 and "stockDeposito" = 2 from public.productos where id = 9001), 'mover_stock pasa 3 del depósito al negocio');
select pg_temp.ok((select delta_negocio = 3 and delta_deposito = -3 from public.movimientos_stock where producto_id = 9001 and origen = 'mover'), 'mover_stock queda anotado');
select pg_temp.debe_fallar($$select public.mover_stock(9001, 99)$$, 'mover_stock falla si el depósito no alcanza');
select public.ajustar_stock('[{"id":9001,"negocio":1,"deposito":4},{"id":9001,"negocio":1}]');
select pg_temp.ok((select stock = 17 and "stockDeposito" = 6 from public.productos where id = 9001), 'ajustar_stock suma en lote');
select pg_temp.ok((select delta_negocio = 2 and delta_deposito = 4 from public.movimientos_stock where producto_id = 9001 and origen = 'ajuste'), 'ajustar_stock queda anotado');

-- Lectura que usa la app para el historial (venta con items y nombre de producto)
select pg_temp.ok((select count(*) from public.ventas v join public.items i on i.venta_id = v.id left join public.productos p on p.id = i.producto_id) > 0, 'la sesión lee ventas con su detalle');
reset role;
\echo PRUEBAS SQL: TODO OK
