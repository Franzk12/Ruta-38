-- ════════════════════════════════════════════════════════════════════
-- Ruta 38 Repuestos — migración para una base que YA existe
-- Correr completo en el SQL Editor de Supabase. No borra datos y se puede
-- correr más de una vez sin problema.
--
-- Qué agrega:
--   · ventas.metodo (método de pago) y ventas.uid (evita ventas duplicadas)
--   · Acceso solo con login: la anon key sola ya no lee ni escribe nada
--   · Funciones que suman/restan stock en la base (dos cajas no se pisan)
--
-- DESPUÉS de correrlo (si no, la app no va a poder entrar):
--   1. Authentication → Users → "Add user": email y contraseña del local
--      (marcar "Auto Confirm User")
--   2. Authentication → Sign In / Providers → DESACTIVAR
--      "Allow new users to sign up"
-- ════════════════════════════════════════════════════════════════════

alter table public.ventas add column if not exists metodo text not null default 'efectivo';
alter table public.ventas add column if not exists uid text;
create unique index if not exists ventas_uid_key on public.ventas (uid);

-- ════════════════════════════════════════════════════════════════════
-- RLS — Row Level Security
-- ════════════════════════════════════════════════════════════════════
-- La "anon key" está a la vista en el código fuente del navegador, así que
-- por sí sola NO da acceso a nada: solo el rol "authenticated" (alguien que
-- entró con el email y la contraseña del local) puede leer y escribir.
--
-- IMPORTANTE: en Supabase → Authentication → Sign In / Providers hay que
-- DESACTIVAR "Allow new users to sign up". Si queda activado, cualquiera con
-- la anon key podría crearse su propia cuenta y pasar a ser "authenticated".
alter table public.productos  enable row level security;
alter table public.ventas     enable row level security;
alter table public.items      enable row level security;
alter table public.categorias enable row level security;
alter table public.marcas     enable row level security;

drop policy if exists "anon acceso total productos"  on public.productos;
drop policy if exists "anon acceso total ventas"     on public.ventas;
drop policy if exists "anon acceso total items"      on public.items;
drop policy if exists "anon acceso total categorias" on public.categorias;
drop policy if exists "anon acceso total marcas"     on public.marcas;

drop policy if exists "local acceso total productos"  on public.productos;
drop policy if exists "local acceso total ventas"     on public.ventas;
drop policy if exists "local acceso total items"      on public.items;
drop policy if exists "local acceso total categorias" on public.categorias;
drop policy if exists "local acceso total marcas"     on public.marcas;

create policy "local acceso total productos"  on public.productos  for all to authenticated using (true) with check (true);
create policy "local acceso total ventas"     on public.ventas     for all to authenticated using (true) with check (true);
create policy "local acceso total items"      on public.items      for all to authenticated using (true) with check (true);
create policy "local acceso total categorias" on public.categorias for all to authenticated using (true) with check (true);
create policy "local acceso total marcas"     on public.marcas     for all to authenticated using (true) with check (true);

-- ════════════════════════════════════════════════════════════════════
-- FUNCIONES DE STOCK
-- ════════════════════════════════════════════════════════════════════
-- El stock se suma/resta EN LA BASE (stock = stock - cantidad), nunca se
-- escribe un número calculado en el navegador. Así dos cajas que venden el
-- mismo producto al mismo tiempo no se pisan: Postgres las pone en fila.
-- Son "security invoker": corren con los permisos (y RLS) de quien las llama.

-- Stock actual de los productos de una venta — lo usa la app para refrescar su caché.
create or replace function public.stocks_de_venta(p_venta_id bigint)
returns jsonb language sql stable security invoker set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'stock', p.stock)), '[]'::jsonb)
  from public.productos p
  where p.id in (select producto_id from public.items where venta_id = p_venta_id);
$$;

-- Anula una venta y devuelve su stock. Si ya estaba anulada no hace nada
-- (se puede llamar dos veces sin devolver el stock dos veces).
create or replace function public.anular_venta(p_venta_id bigint)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  v_anulada boolean;
begin
  select anulada into v_anulada from public.ventas where id = p_venta_id for update;
  if not found then
    raise exception 'La venta % no existe', p_venta_id;
  end if;
  if not v_anulada then
    update public.ventas set anulada = true where id = p_venta_id;
    update public.productos p set stock = p.stock + x.cant
    from (select producto_id, sum(cantidad) as cant from public.items
          where venta_id = p_venta_id and producto_id is not null group by producto_id) x
    where p.id = x.producto_id;
  end if;
  return jsonb_build_object('venta_id', p_venta_id, 'stocks', public.stocks_de_venta(p_venta_id));
end;
$$;

-- Registra venta + items + descuento de stock en una sola transacción.
-- p_venta: {uid, fecha, total, pago, vuelto, metodo, anulada}
-- p_items: [{producto_id, cantidad, precio}, ...]
-- "uid" lo genera la caja: si la misma venta llega dos veces (reintento de la
-- cola offline, respuesta perdida) se devuelve la ya guardada, sin duplicar.
-- Si llega con anulada=true (se anuló mientras esperaba en la cola) no descuenta stock.
create or replace function public.registrar_venta(p_venta jsonb, p_items jsonb)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  v_uid     text    := nullif(p_venta->>'uid', '');
  v_anulada boolean := coalesce((p_venta->>'anulada')::boolean, false);
  v_id      bigint;
begin
  insert into public.ventas (uid, fecha, total, pago, vuelto, metodo, anulada)
  values (
    v_uid,
    coalesce((p_venta->>'fecha')::timestamptz, now()),
    coalesce((p_venta->>'total')::numeric, 0),
    coalesce((p_venta->>'pago')::numeric, 0),
    coalesce((p_venta->>'vuelto')::numeric, 0),
    coalesce(nullif(p_venta->>'metodo', ''), 'efectivo'),
    v_anulada
  )
  on conflict (uid) do nothing
  returning id into v_id;

  if v_id is null then
    -- Ya estaba registrada: no se vuelve a insertar ni a descontar.
    select id into v_id from public.ventas where uid = v_uid;
    if v_anulada then
      return public.anular_venta(v_id);
    end if;
    return jsonb_build_object('venta_id', v_id, 'stocks', public.stocks_de_venta(v_id));
  end if;

  insert into public.items (venta_id, producto_id, cantidad, precio, subtotal)
  select v_id,
         (select p.id from public.productos p where p.id = nullif(i->>'producto_id', '')::bigint),
         (i->>'cantidad')::integer,
         (i->>'precio')::numeric,
         (i->>'cantidad')::integer * (i->>'precio')::numeric
  from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) as i;

  if not v_anulada then
    update public.productos p set stock = p.stock - x.cant
    from (select producto_id, sum(cantidad) as cant from public.items
          where venta_id = v_id and producto_id is not null group by producto_id) x
    where p.id = x.producto_id;
  end if;

  return jsonb_build_object('venta_id', v_id, 'stocks', public.stocks_de_venta(v_id));
end;
$$;

-- Pasa unidades del depósito al negocio. Falla si en el depósito no alcanza.
create or replace function public.mover_stock(p_id bigint, p_cant integer)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare
  r jsonb;
begin
  update public.productos
     set stock = stock + p_cant, "stockDeposito" = "stockDeposito" - p_cant
   where id = p_id and p_cant > 0 and "stockDeposito" >= p_cant
  returning jsonb_build_object('id', id, 'stock', stock, 'stockDeposito', "stockDeposito") into r;
  if r is null then
    raise exception 'No hay suficiente stock en depósito';
  end if;
  return r;
end;
$$;

revoke all on function public.stocks_de_venta(bigint)       from public, anon;
revoke all on function public.anular_venta(bigint)          from public, anon;
revoke all on function public.registrar_venta(jsonb, jsonb) from public, anon;
revoke all on function public.mover_stock(bigint, integer)  from public, anon;
grant execute on function public.stocks_de_venta(bigint)       to authenticated;
grant execute on function public.anular_venta(bigint)          to authenticated;
grant execute on function public.registrar_venta(jsonb, jsonb) to authenticated;
grant execute on function public.mover_stock(bigint, integer)  to authenticated;
