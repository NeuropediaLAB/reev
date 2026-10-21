#!/usr/bin/env bash
# =============================================================================
# download-smart.sh — actualización de las bases de datos de referencia de REEV
#
# Lo lanza reev-monitor (botón "Lanzar actualización") mediante nsenter en el
# namespace del host, porque el contenedor no tiene s5cmd/aria2c.
#
#   bash download-smart.sh            → descarga lo que falta
#   bash download-smart.sh --status   → solo informa del estado
#
# POR QUÉ ARIA2C Y NO S5CMD:
#   ceph-s3-public.cubi.bihealth.org da ~0,5 MB/s POR CONEXIÓN (el path
#   internacional está degradado: ICMP 100% de pérdida, un solo GET se queda
#   colgado). Con 12-24 conexiones en paralelo por rangos HTTP sí se alcanza la
#   línea completa (~8 MB/s medidos). s5cmd baja cada objeto en UNA conexión, así
#   que con los .sst grandes se queda en ~0,5 MB/s → 270 GB serían semanas y
#   parece que "no hace nada". Por eso: s5cmd solo para listar (ligero) y aria2c
#   --split/--max-connection-per-server para bajar.
#
# Otras propiedades:
#   · Idempotente: los paquetes con rocksdb/CURRENT se omiten; los ficheros ya
#     completos se saltan comparando tamaño; las descargas parciales se reanudan.
#   · "Smart" en espacio: los grandes de GRCh38 vienen de reduced-exomes (cadd
#     52 GB en vez de 503, gnomad-genomes 47 en vez de 411, dbnsfp 45) y antes de
#     cada paquete se comprueba que quepa con margen.
#   · Prioriza lo pequeño y crítico primero.
#   · Al terminar reinicia reev-annonars si ha enlazado paquetes nuevos.
# =============================================================================
set -uo pipefail

DATA="${REVV_DATA:-/mnt/reev-data/volumes/reev-static/data}"
ANNONARS="$DATA/annonars"
DL="$DATA/download/annonars"
PIDFILE="/tmp/reev-download-smart.pid"
S5CMD="${S5CMD:-/home/arkantu/.local/bin/s5cmd}"
ARIA2C="${ARIA2C:-/usr/bin/aria2c}"
ENDPOINT="https://ceph-s3-public.cubi.bihealth.org"
S3ROOT="s3://varfish-public"
URLROOT="$ENDPOINT/varfish-public"
RESERVE_GB="${REVV_RESERVE_GB:-20}"     # margen de disco que no se debe tocar
CONNS="${REVV_CONNS:-12}"               # conexiones por fichero (aria2c -x/-s)
JOBS="${REVV_JOBS:-6}"                  # ficheros simultáneos
ONLY="${REVV_ONLY:-}"                   # limitar a un paquete (pruebas)

STATUS_ONLY=0
[ "${1:-}" = "--status" ] && STATUS_ONLY=1

mkdir -p "$ANNONARS" "$DL"

# ── Catálogo ────────────────────────────────────────────────────────────────
# enlace | paquete | ensamblaje | prioridad | prefijo S3
# Prioridad baja = se descarga antes (pequeños y críticos primero).
CATALOG=(
  "functional     functional-grch38-110+0.39.0             grch38 10 full/annonars"
  "alphamissense  alphamissense-grch38-1+0.39.0             grch38 11 full/annonars"
  "regions        regions-grch38-20240711+0.39.0            grch38 12 full/annonars"
  "gnomad-mtdna   gnomad-mtdna-grch38-3.1+0.39.0            grch38 13 full/annonars"
  "helixmtdb      helixmtdb-grch38-20200327+0.39.0          grch38 14 full/annonars"
  "gnomad-sv-exomes gnomad-sv-exomes-grch38-4.1+0.39.0      grch38 15 full/annonars"
  "gnomad-sv-genomes gnomad-sv-genomes-grch38-4.1+0.39.0    grch38 16 full/annonars"
  "cons           cons-grch38-20190906+0.39.0               grch38 20 full/annonars"
  "dbscsnv        dbscsnv-grch38-1.1+0.39.0                 grch38 21 full/annonars"
  "dbsnp          dbsnp-grch38-b151+0.39.0                  grch38 30 reduced-exomes/annonars"
  "dbnsfp         dbnsfp-grch38-4.5c+0.39.0                 grch38 31 reduced-exomes/annonars"
  "gnomad-genomes gnomad-genomes-grch38-4.1+0.39.0          grch38 40 reduced-exomes/annonars"
  "gnomad-exomes  gnomad-exomes-grch38-4.1+0.39.0           grch38 41 reduced-exomes/annonars"
  "cadd           cadd-grch38-1.6+0.39.0                    grch38 50 reduced-exomes/annonars"
  # GRCh37 — completo en producción; se comprueba por si hay que reponer algo
  "alphamissense  alphamissense-grch37-1+0.39.0             grch37 60 full/annonars"
  "cons           cons-grch37-20161007+0.39.0               grch37 61 full/annonars"
  "dbscsnv        dbscsnv-grch37-1.1+0.39.0                 grch37 62 full/annonars"
  "functional     functional-grch37-105.20201022+0.39.0     grch37 63 full/annonars"
  "regions        regions-grch37-20240711+0.39.0            grch37 64 full/annonars"
  "gnomad-mtdna   gnomad-mtdna-grch37-3.1+0.39.0            grch37 65 full/annonars"
  "helixmtdb      helixmtdb-grch37-20200327+0.39.0          grch37 66 full/annonars"
  "gnomad-sv-exomes gnomad-sv-exomes-grch37-0.3.1+0.39.0    grch37 67 full/annonars"
  "gnomad-sv-genomes gnomad-sv-genomes-grch37-2.1.1+0.39.0  grch37 68 full/annonars"
  "dbsnp          dbsnp-grch37-b151+0.39.0                  grch37 70 full/annonars"
  "dbnsfp         dbnsfp-grch37-4.5a+0.39.0                 grch37 71 full/annonars"
  "gnomad-genomes gnomad-genomes-grch37-2.1.1+0.39.0        grch37 72 full/annonars"
  "gnomad-exomes  gnomad-exomes-grch37-2.1.1+0.39.0         grch37 73 full/annonars"
  "cadd           cadd-grch37-1.6+0.39.0                    grch37 74 full/annonars"
)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

pkg_complete() { [ -f "$1/CURRENT" ] || [ -f "$1/rocksdb/CURRENT" ]; }

free_gb() { df -BG --output=avail /mnt/reev-data 2>/dev/null | tail -1 | tr -dc '0-9'; }

# Lista remota de un paquete → "tamaño<TAB>clave", grandes primero
list_pkg() {
  "$S5CMD" --endpoint-url "$ENDPOINT" --no-sign-request ls -s "$S3ROOT/$1/$2/*" 2>/dev/null \
    | awk 'NF>=5 {print $(NF-1)"\t"$NF}' | sort -rn
}

# ── Modo estado ──────────────────────────────────────────────────────────────
if [ "$STATUS_ONLY" = 1 ]; then
  echo "DISCO: $(free_gb) GB libres en /mnt/reev-data"
  for row in "${CATALOG[@]}"; do
    read -r link pkg asm prio prefix <<< "$row"
    if pkg_complete "$DL/$pkg"; then
      if [ -e "$ANNONARS/$asm/$link" ]; then
        echo "✓ ${asm}/${link}: instalado (${pkg})"
      else
        echo "⏳ ${asm}/${link}: descargado pero sin enlazar (incompleto)"
      fi
    else
      n=$(ls "$DL/$pkg" 2>/dev/null | wc -l)
      if [ "$n" -gt 0 ]; then
        echo "⏳ ${asm}/${link}: descarga incompleta (${n} ficheros de ${pkg})"
      else
        echo "✗ ${asm}/${link}: no descargado (${pkg})"
      fi
    fi
  done
  exit 0
fi

# ── Modo descarga ────────────────────────────────────────────────────────────
if [ -z "$ONLY" ]; then
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "Ya hay una actualización en curso (PID $(cat "$PIDFILE")). Saliendo."
    exit 0
  fi
  echo $$ > "$PIDFILE"
  trap 'rm -f "$PIDFILE"' EXIT
fi

[ -x "$S5CMD" ]  || { log "ERROR: no se encuentra s5cmd en $S5CMD"; exit 1; }
[ -x "$ARIA2C" ] || { log "ERROR: no se encuentra aria2c en $ARIA2C"; exit 1; }

log "=== REEV · actualización de bases de datos ==="
log "Datos: $DATA · disco: $(free_gb) GB libres · $JOBS ficheros x $CONNS conexiones"

linked_any=0
failed=0

# bajar un paquete; devuelve 0 ok, 1 error
fetch_pkg() {  # $1=prefijo  $2=paquete  $3=destino
  local prefix="$1" pkg="$2" dest="$3"
  local listing listfile total_mb=0 size key local_size rc

  listing=$(list_pkg "$prefix" "$pkg")
  if [ -z "$listing" ]; then
    log "ERROR: no se pudo listar $prefix/$pkg (¿red o nombre incorrecto?)"
    return 1
  fi

  listfile=$(mktemp)
  while IFS=$'\t' read -r size key; do
    total_mb=$(( total_mb + size / 1048576 ))
    local_size=$(stat -c %s "$dest/$key" 2>/dev/null || echo -1)
    [ "$local_size" = "$size" ] && continue          # ya completo
    printf '%s/%s/%s/%s\n  out=%s\n  continue=true\n' "$URLROOT" "$prefix" "$pkg" "$key" "$key" >> "$listfile"
  done <<< "$listing"

  if [ ! -s "$listfile" ]; then
    rm -f "$listfile"
    log "· ${pkg}: todos los ficheros ya estaban"
    return 0
  fi

  log "⬇  ${pkg} → ${dest} (${total_mb} MB)"
  mkdir -p "$dest"
  "$ARIA2C" --input-file="$listfile" --dir="$dest" \
     --max-concurrent-downloads="$JOBS" --split="$CONNS" --max-connection-per-server="$CONNS" \
     --min-split-size=4M --continue=true --auto-file-renaming=false --allow-overwrite=true \
     --file-allocation=none --max-tries=5 --retry-wait=5 --timeout=30 --connect-timeout=20 \
     --summary-interval=0 --console-log-level=warn --download-result=hide
  rc=$?
  rm -f "$listfile"
  # aria2c: 0 ok, 13 fichero ya existente/renombrado, 7 parada parcial
  case "$rc" in
    0|13) return 0 ;;
    *)    log "ERROR aria2c en ${pkg} (rc=${rc})"; return 1 ;;
  esac
}

while read -r link pkg asm prio prefix; do
  [ -z "${link:-}" ] && continue
  [ -n "$ONLY" ] && [ "$ONLY" != "$pkg" ] && continue

  dest="$DL/$pkg"
  pkg_complete "$dest" && continue

  # Tamaño remoto de lo que realmente falta, para el control de espacio
  need_mb=0
  while IFS=$'\t' read -r size key; do
    [ -z "${key:-}" ] && continue
    local_size=$(stat -c %s "$dest/$key" 2>/dev/null || echo -1)
    [ "$local_size" = "$size" ] && continue
    need_mb=$(( need_mb + size / 1048576 ))
  done <<< "$(list_pkg "$prefix" "$pkg")"

  if [ "$need_mb" -gt 0 ]; then
    free=$(free_gb)
    if [ $(( free - need_mb / 1024 )) -lt "$RESERVE_GB" ]; then
      log "OMITIDO ${pkg}: necesita ~$(( need_mb / 1024 )) GB y quedan ${free} GB libres"
      continue
    fi
  fi

  if fetch_pkg "$prefix" "$pkg" "$dest"; then
    pkg_complete "$dest" && log "✅ ${pkg} completo" \
                         || log "⚠  ${pkg} bajado, pero sin rocksdb/CURRENT (paquete vacío en S3?)"
    mkdir -p "$ANNONARS/$asm"
    if [ ! -e "$ANNONARS/$asm/$link" ]; then
      ln -sfn "../../download/annonars/$pkg" "$ANNONARS/$asm/$link"
      log "🔗 ${asm}/${link} → download/annonars/${pkg}"
      linked_any=1
    fi
  else
    failed=$(( failed + 1 ))
    log "fallo en ${pkg}; se reanudará en la próxima ejecución"
  fi
done < <(printf '%s\n' "${CATALOG[@]}" | sort -k4,4n)

# genes / clinvar-genes son independientes del ensamblaje y viven en annonars/
GENES_PKG=$(ls -d "$DL"/genes-* 2>/dev/null | head -1)
if [ -n "${GENES_PKG:-}" ] && [ ! -e "$ANNONARS/genes" ]; then
  ln -sfn "../download/annonars/$(basename "$GENES_PKG")" "$ANNONARS/genes"
  log "🔗 genes → download/annonars/$(basename "$GENES_PKG")"
  linked_any=1
fi

if [ "$linked_any" = 1 ]; then
  log "Reiniciando reev-annonars para que cargue los nuevos paquetes…"
  docker restart reev-annonars >/dev/null 2>&1 \
    && log "reev-annonars reiniciado" \
    || log "AVISO: no se pudo reiniciar reev-annonars (reinícialo a mano)"
fi

log "=== Fin · fallos: ${failed} · disco libre: $(free_gb) GB ==="
