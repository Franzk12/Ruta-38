#!/usr/bin/env bash
# Hace una copia completa de la base (tablas, datos, funciones y seguridad del esquema
# public), la comprime y la cifra con contraseña.
#
# Uso:   SUPABASE_DB_URL='postgresql://...' BACKUP_PASSPHRASE='...' scripts/backup.sh [carpeta]
# Deja:  <carpeta>/ruta38-AAAA-MM-DD_HHMM.sql.gz.gpg
#
# Lo corre todos los días el workflow .github/workflows/backup.yml, y también se puede
# correr a mano en cualquier PC con pg_dump (igual o más nuevo que la base) y gpg.
set -euo pipefail

: "${SUPABASE_DB_URL:?Falta SUPABASE_DB_URL (cadena de conexión de la base)}"
: "${BACKUP_PASSPHRASE:?Falta BACKUP_PASSPHRASE (contraseña para cifrar la copia)}"
DESTINO="${1:-.}"
mkdir -p "$DESTINO"
ARCHIVO="$DESTINO/ruta38-$(date -u +%Y-%m-%d_%H%M).sql.gz.gpg"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

pg_dump "$SUPABASE_DB_URL" --schema=public --no-owner --no-privileges > "$TMP"

# Una copia vacía o cortada no sirve: se comprueba que estén las tablas principales.
for tabla in productos ventas items; do
  grep -q "^COPY public\.$tabla " "$TMP" || { echo "ERROR: la copia no contiene la tabla $tabla" >&2; exit 1; }
done

gzip -c "$TMP" | gpg --batch --yes --quiet --symmetric --cipher-algo AES256 \
  --pinentry-mode loopback --passphrase-fd 3 -o "$ARCHIVO" 3<<<"$BACKUP_PASSPHRASE"

echo "Copia creada: $ARCHIVO ($(du -h "$ARCHIVO" | cut -f1))"
echo "Filas copiadas:"
for tabla in productos ventas items movimientos_stock categorias marcas; do
  n=$(awk -v t="^COPY public\\\\.$tabla " '$0 ~ t {f=1; next} f && /^\\\.$/ {f=0} f {c++} END {print c+0}' "$TMP")
  echo "  $tabla: $n"
done
