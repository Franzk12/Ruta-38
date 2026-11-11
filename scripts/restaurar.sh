#!/usr/bin/env bash
# Restaura una copia hecha con scripts/backup.sh en una base VACÍA (por ejemplo, un
# proyecto nuevo de Supabase). No usar sobre la base en uso: no pisa tablas que ya existen.
#
# Uso:   DESTINO_DB_URL='postgresql://...' BACKUP_PASSPHRASE='...' scripts/restaurar.sh copia.sql.gz.gpg
# Después: correr supabase_migracion.sql en esa base (repone permisos y seguridad).
set -euo pipefail

: "${DESTINO_DB_URL:?Falta DESTINO_DB_URL (cadena de conexión de la base vacía)}"
: "${BACKUP_PASSPHRASE:?Falta BACKUP_PASSPHRASE (la contraseña con la que se cifró la copia)}"
ARCHIVO="${1:?Indicá el archivo .sql.gz.gpg a restaurar}"

if [ "$(psql "$DESTINO_DB_URL" -X -At -c "select count(*) from information_schema.tables where table_schema='public' and table_name in ('productos','ventas','items')")" != "0" ]; then
  echo "ERROR: la base de destino ya tiene tablas de RepuestoPOS. Restaurá en una base vacía." >&2
  exit 1
fi

gpg --batch --quiet --decrypt --pinentry-mode loopback --passphrase-fd 3 "$ARCHIVO" 3<<<"$BACKUP_PASSPHRASE" \
  | gunzip \
  | sed '/^CREATE SCHEMA public;$/d' \
  | psql "$DESTINO_DB_URL" -X -q -o /dev/null -v ON_ERROR_STOP=1 --single-transaction

echo "Restauración terminada. Filas:"
psql "$DESTINO_DB_URL" -X -At -c "select 'productos', count(*) from public.productos union all select 'ventas', count(*) from public.ventas union all select 'items', count(*) from public.items" | sed 's/|/: /; s/^/  /'
echo "Falta: correr supabase_migracion.sql en esta base para reponer permisos y seguridad."
