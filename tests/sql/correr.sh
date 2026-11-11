#!/usr/bin/env bash
# Prueba supabase_schema.sql + supabase_migracion.sql en un Postgres local (no toca Supabase).
# Uso: tests/sql/correr.sh        Requiere psql y un usuario que pueda crear bases
#      (variables PG* habituales; por defecto la conexión local del usuario actual).
set -euo pipefail
cd "$(dirname "$0")/../.."
DB_NUEVA=rpos_prueba_nueva
DB_VIEJA=rpos_prueba_vieja
P="psql -X -q -v ON_ERROR_STOP=1"

for db in $DB_NUEVA $DB_VIEJA; do
  $P -d postgres -c "drop database if exists $db" -c "create database $db"
  $P -d $db -f tests/sql/00_simular_supabase.sql
done

echo "== Base nueva: schema + migración (dos veces) =="
$P -d $DB_NUEVA -f supabase_schema.sql
$P -d $DB_NUEVA -f supabase_migracion.sql
$P -d $DB_NUEVA -f supabase_migracion.sql
$P -d $DB_NUEVA -f tests/sql/pruebas.sql

echo "== Base existente (esquema de la versión 7, con datos) + migración (dos veces) =="
$P -d $DB_VIEJA -f tests/sql/esquema_v7.sql
$P -d $DB_VIEJA <<'SQL'
insert into public.productos (nombre, precio, stock) values ('Producto viejo', 100, -2);
insert into public.ventas (total, pago) values (100, 100);
insert into public.items (venta_id, producto_id, cantidad, precio, subtotal)
  select v.id, p.id, 0, 100, 0 from public.ventas v, public.productos p;  -- fila vieja "inválida"
SQL
$P -d $DB_VIEJA -f supabase_migracion.sql
$P -d $DB_VIEJA -f supabase_migracion.sql
$P -d $DB_VIEJA -c "do \$\$ begin if (select count(*) from public.ventas) <> 1 or (select count(*) from public.items) <> 1 or (select stock from public.productos where nombre = 'Producto viejo') <> -2 then raise exception 'la migración alteró datos existentes'; end if; end \$\$"
$P -d $DB_VIEJA -f tests/sql/pruebas.sql

echo "== La base nueva y la migrada quedan iguales =="
estructura() {
  psql -X -At -d "$1" <<'SQL'
select 'col', table_name, column_name, data_type, is_nullable, coalesce(column_default,'') from information_schema.columns where table_schema='public' order by 2,3;
select 'pol', tablename, policyname, cmd, roles::text from pg_policies where schemaname='public' order by 2,3;
select 'priv', table_name, grantee, string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants where table_schema='public' and grantee in ('anon','authenticated') group by 2,3 order by 2,3;
select 'fn', proname, prosecdef, md5(prosrc) from pg_proc where pronamespace='public'::regnamespace order by 2;
select 'con', conrelid::regclass, conname, pg_get_constraintdef(oid) from pg_constraint where connamespace='public'::regnamespace order by 2,3;
select 'trg', tgrelid::regclass, tgname from pg_trigger where not tgisinternal order by 2,3;
SQL
}
diff <(estructura $DB_NUEVA) <(estructura $DB_VIEJA) && echo "iguales"

for db in $DB_NUEVA $DB_VIEJA; do $P -d postgres -c "drop database $db"; done
echo "TODO OK"
