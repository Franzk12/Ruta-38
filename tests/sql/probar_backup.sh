#!/usr/bin/env bash
# Prueba scripts/backup.sh y scripts/restaurar.sh de punta a punta en un Postgres local:
# arma una base con datos, la copia, la restaura en otra vacía y compara.
set -euo pipefail
cd "$(dirname "$0")/../.."
P="psql -X -q -v ON_ERROR_STOP=1"
ORIGEN=rpos_bk_origen; DESTINO=rpos_bk_destino
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export BACKUP_PASSPHRASE='clave de prueba 123'

for db in $ORIGEN $DESTINO; do
  $P -d postgres -c "drop database if exists $db" -c "create database $db"
  $P -d $db -f tests/sql/00_simular_supabase.sql
done
$P -d $ORIGEN -f supabase_schema.sql -f supabase_migracion.sql
$P -d $ORIGEN -f tests/sql/pruebas.sql > /dev/null 2>&1      # deja productos, ventas y movimientos

SUPABASE_DB_URL="dbname=$ORIGEN" scripts/backup.sh "$TMP"
COPIA=$(ls "$TMP"/*.gpg)

echo "== La copia está cifrada =="
if gunzip -c "$COPIA" > /dev/null 2>&1 || grep -q "COPY public" "$COPIA"; then echo "ERROR: la copia se puede leer sin contraseña"; exit 1; fi
if BACKUP_PASSPHRASE='otra clave' DESTINO_DB_URL="dbname=$DESTINO" scripts/restaurar.sh "$COPIA" > /dev/null 2>&1; then echo "ERROR: restauró con una contraseña equivocada"; exit 1; fi
echo "ok"

echo "== Restaurar en una base vacía =="
DESTINO_DB_URL="dbname=$DESTINO" scripts/restaurar.sh "$COPIA"
$P -d $DESTINO -f supabase_migracion.sql

contenido() {
  psql -X -At -d "$1" -c "select 'p', md5(string_agg(t::text, '|' order by id)) from public.productos t
    union all select 'v', md5(string_agg(t::text, '|' order by id)) from public.ventas t
    union all select 'i', md5(string_agg(t::text, '|' order by id)) from public.items t
    union all select 'm', md5(string_agg(t::text, '|' order by id)) from public.movimientos_stock t
    union all select 'pol', count(*)::text from pg_policies where schemaname = 'public'
    union all select 'fn', count(*)::text from pg_proc where pronamespace = 'public'::regnamespace"
}
diff <(contenido $ORIGEN) <(contenido $DESTINO) && echo "ok: datos, políticas y funciones idénticos"

echo "== La base restaurada sigue numerando bien y no deja restaurar encima =="
$P -d $DESTINO -c "set role authenticated" -c "select set_config('request.jwt.claims','{\"sub\":\"11111111-1111-1111-1111-111111111111\",\"email\":\"a@b.c\"}',false)" \
  -c "do \$\$ declare r jsonb; m bigint; begin select max(id) into m from public.ventas; r := public.registrar_venta('{\"uid\":\"post-restauracion\"}', '[{\"producto_id\":9001,\"cantidad\":1,\"precio\":10}]'); if (r->>'venta_id')::bigint <> m + 1 then raise exception 'numeración incorrecta tras restaurar: % (máximo previo %)', r->>'venta_id', m; end if; end \$\$"
if DESTINO_DB_URL="dbname=$DESTINO" scripts/restaurar.sh "$COPIA" > /dev/null 2>&1; then echo "ERROR: dejó restaurar sobre una base con datos"; exit 1; fi
echo "ok"

for db in $ORIGEN $DESTINO; do $P -d postgres -c "drop database $db"; done
echo "BACKUP Y RESTAURACIÓN: TODO OK"
