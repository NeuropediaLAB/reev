#!/usr/bin/env bash
# =============================================================================
# update-databases.sh — comprobación y actualización de las bases de referencia
#                       de REEV
#
#   update-databases.sh            → informa de lo que hay y de lo que falta (no cambia nada)
#   update-databases.sh --apply    → descarga e instala lo que esté más nuevo
#
# QUÉ ACTUALIZA SOLO (seguro, sustituye el paquete y repunta el symlink):
#   · ClinVar GRCh37 y GRCh38  — releases semanales de bihealth/annonars-data-clinvar
#   · HPO (viguno)             — paquetes hpo-* en s3://varfish-public/full/viguno
#   · huecos de los paquetes annonars pinneados — delegando en download-smart.sh
#
# QUÉ SOLO COMPRUEBA (requiere decisión humana, se anota en el informe):
#   · mehari txs      — los de este stack se construyeron localmente (RefSeq), no
#                       son un asset del release; sustituirlos cambia anotación
#   · cada-prio model — graph.gpickle propio
#   · dotty cdot      — versión fijada por la imagen de dotty
#   · seqrepo         — snapshot de biocommons vía rsync (~15 GB a 0,3 MB/s)
#
# Tras instalar algo reinicia solo los servicios afectados (annonars / viguno).
# Escribe el informe en download-update.log junto a este script.
# =============================================================================
set -uo pipefail

BASE=/home/arkantu/produccion/reev
DATA=${REVV_DATA:-/mnt/datos-1tb/reev/volumes/reev-static/data}
LOG="$BASE/download-update.log"
S5CMD=${S5CMD:-/home/arkantu/.local/bin/s5cmd}
S3="s3://varfish-public"
ENDPOINT=https://ceph-s3-public.cubi.bihealth.org
CLINVAR_API=https://api.github.com/repos/bihealth/annonars-data-clinvar/releases/latest
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; echo "[$(date '+%H:%M:%S')] $*"; }
need_annonars=0
need_viguno=0
pending=0

# ── ClinVar ──────────────────────────────────────────────────────────────────
clinvar_step() {
    local build="$1" want asset url tmp installed
    want=$(curl -sL --max-time 60 "$CLINVAR_API" | python3 -c '
import sys, json, re
build = sys.argv[1]
r = json.load(sys.stdin)
for a in r.get("assets", []):
    n = a["name"]
    if n.startswith("annonars-clinvar-minimal-" + build + "-") and n.endswith(".tar.gz"):
        print(n); break
' "$build" 2>/dev/null)
    [ -z "$want" ] && { log "CLINVAR $build: no se pudo consultar el release"; pending=$((pending+1)); return; }

    installed=$(readlink -f "$DATA/annonars/$build/clinvar" 2>/dev/null | xargs -r -I{} sh -c 'grep -m1 "^x-version:" {}/spec.yaml 2>/dev/null | cut -d" " -f2')
    wanted_version=$(echo "$want" | sed "s/^annonars-clinvar-minimal-$build-//; s/\.tar\.gz$//")

    if [ "$installed" = "$wanted_version" ]; then
        log "CLINVAR $build: al día ($installed)"
        return
    fi
    # Comparar por la fecha del release de ClinVar, no por la cadena completa: el
    # paquete local puede haberse construido a mano más tarde que el publicado.
    local inst_date want_date
    inst_date=$(echo "$installed" | cut -d+ -f1 | tr -cd '0-9')
    want_date=$(echo "$wanted_version" | cut -d+ -f1 | tr -cd '0-9')
    if [ -n "$inst_date" ] && [ -n "$want_date" ] && [ "$inst_date" -ge "$want_date" ]; then
        log "CLINVAR $build: al día (local $installed, release $wanted_version)"
        return
    fi
    log "CLINVAR $build: instalado '${installed:-ninguno}' → disponible '$wanted_version'"
    pending=$((pending+1))
    [ "$APPLY" -eq 0 ] && return

    tmp=$(mktemp -d /mnt/datos-1tb/reev/volumes/clinvar-update.XXXXXX)
    url=$(curl -sL --max-time 60 "$CLINVAR_API" | python3 -c '
import sys, json
name = sys.argv[1]
for a in json.load(sys.stdin).get("assets", []):
    if a["name"] == name:
        print(a["browser_download_url"]); break
' "$want")
    log "CLINVAR $build: descargando $want"
    if ! curl -L --retry 5 --retry-delay 10 --max-time 7200 -o "$tmp/$want" "$url"; then
        log "CLINVAR $build: FALLO de descarga"; rm -rf "$tmp"; return
    fi
    if ! curl -sL --max-time 60 -o "$tmp/$want.sha256" "$url.sha256"; then
        log "CLINVAR $build: sin fichero .sha256, se omite por seguridad"; rm -rf "$tmp"; return
    fi
    local want_sha got_sha
    want_sha=$(awk '{print $1}' "$tmp/$want.sha256")
    got_sha=$(sha256sum "$tmp/$want" | awk '{print $1}')
    if [ -z "$want_sha" ] || [ "$want_sha" != "$got_sha" ]; then
        log "CLINVAR $build: SHA256 NO coincide, se descarta"; rm -rf "$tmp"; return
    fi
    tar -C "$DATA/download/annonars" -xzf "$tmp/$want" || { log "CLINVAR $build: error al extraer"; rm -rf "$tmp"; return; }
    local newdir
    newdir=$(tar tzf "$tmp/$want" | head -1 | cut -d/ -f1)
    ln -sfn "../../download/annonars/$newdir" "$DATA/annonars/$build/clinvar"
    log "CLINVAR $build: instalado $newdir y symlink repuntado"
    need_annonars=1
    rm -rf "$tmp"

    # conservar solo los dos paquetes ClinVar más recientes por build
    ls -1d "$DATA"/download/annonars/annonars-clinvar-minimal-"$build"-* 2>/dev/null \
      | sort -r | tail -n +3 | while read -r old; do
            log "CLINVAR $build: borrando paquete antiguo $(basename "$old")"
            rm -rf "$old"
        done
}

# ── HPO (viguno) ─────────────────────────────────────────────────────────────
viguno_step() {
    local newest installed
    newest=$("$S5CMD" --endpoint-url "$ENDPOINT" --no-sign-request ls "$S3/full/viguno/" 2>/dev/null \
        | awk '{print $NF}' | grep -E '^hpo-[0-9]{8}\+' | tr -d '/' | sort | tail -1)
    [ -z "$newest" ] && { log "HPO: no se pudo listar s3://varfish-public/full/viguno"; pending=$((pending+1)); return; }
    installed=$(cat "$DATA/hpo/.version" 2>/dev/null || echo "")
    if [ -z "$installed" ]; then
        # Sin sello de versión: deducir comparando tamaños con el paquete remoto.
        local remote_sizes local_ok=1 f rsize lsize
        remote_sizes=$("$S5CMD" --endpoint-url "$ENDPOINT" --no-sign-request ls -s "$S3/full/viguno/$newest/*" 2>/dev/null \
            | awk 'NF>=5 {print $(NF-1)"\t"$NF}')
        for f in hpo.bin hp.obo phenotype.hpoa phenotype_to_genes.txt; do
            rsize=$(echo "$remote_sizes" | awk -v n="$f" '$2 ~ ("/" n "$") || $2 ~ ("/" n ".zst$") {print $1; exit}')
            lsize=$(stat -c%s "$DATA/hpo/$f" 2>/dev/null || echo 0)
            if [ -n "$rsize" ] && [ "$rsize" != "$lsize" ]; then local_ok=0; fi
        done
        if [ "$local_ok" -eq 1 ]; then
            echo "$newest" > "$DATA/hpo/.version"
            log "HPO: sin sello previo; los tamaños coinciden con $newest, se sella y se da por al día"
            return
        fi
        installed="desconocido"
    fi
    if [ "$installed" = "$newest" ]; then
        log "HPO: al día ($installed)"
        return
    fi
    log "HPO: instalado '$installed' → disponible '$newest'"
    pending=$((pending+1))
    [ "$APPLY" -eq 0 ] && return

    "$S5CMD" --endpoint-url "$ENDPOINT" --no-sign-request sync \
        "$S3/full/viguno/$newest/*" "$DATA/download/viguno/$newest" >/dev/null 2>&1 \
        || { log "HPO: fallo al descargar $newest"; return; }
    local n=0 f
    for f in hpo.bin hp.obo phenotype.hpoa phenotype_to_genes.txt hgnc_xlink.tsv; do
        if [ -f "$DATA/download/viguno/$newest/$f" ]; then
            cp -f "$DATA/download/viguno/$newest/$f" "$DATA/hpo/$f" && n=$((n+1))
        fi
    done
    if [ "$n" -eq 0 ]; then
        log "HPO: el paquete $newest no contiene los ficheros esperados"
        return
    fi
    echo "$newest" > "$DATA/hpo/.version"
    log "HPO: $n ficheros actualizados desde $newest"
    need_viguno=1
}

# ── annonars: huecos de los paquetes pinneados ───────────────────────────────
annonars_step() {
    local out
    out=$(REVV_DATA="$DATA" bash "$BASE/download-smart.sh" --status 2>&1 | tail -40)
    if echo "$out" | grep -qiE 'falta|missing|incompleto|pendiente'; then
        log "ANNONARS: hay paquetes incompletos (ver detalle abajo)"
        echo "$out" | grep -iE 'falta|missing|incompleto|pendiente' | sed 's/^/    /' >> "$LOG"
        pending=$((pending+1))
        if [ "$APPLY" -eq 1 ]; then
            log "ANNONARS: lanzando download-smart.sh"
            if REVV_DATA="$DATA" bash "$BASE/download-smart.sh" >> "$LOG" 2>&1; then
                log "ANNONARS: download-smart.sh terminó correctamente"
                need_annonars=1
            else
                log "ANNONARS: download-smart.sh terminó con error"
            fi
        fi
    else
        log "ANNONARS: paquetes completos"
    fi
}

# ── solo comprobación ────────────────────────────────────────────────────────
check_only_steps() {
    local tag
    tag=$(curl -sL --max-time 60 'https://api.github.com/repos/varfish-org/mehari-data-tx/releases/latest' \
        | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null)
    log "MEHARI txs: release más reciente ${tag:-(desconocido)}; los ficheros instalados se construyeron localmente (RefSeq), revisar a mano"
    log "CADA-PRIO: modelo propio ($(ls -1 "$DATA/cada-prio/model/model" 2>/dev/null | head -1)); sin actualización automática"
    log "DOTTY: cdot fijado por datos instalados; seqrepo = snapshot biocommons (rsync manual, ~15 GB)"
}

# ── main ────────────────────────────────────────────────────────────────────
log "================ update-databases $( [ "$APPLY" -eq 1 ] && echo APPLY || echo STATUS ) ================"
df -BG --output=avail /mnt/datos-1tb 2>/dev/null | tail -1 | awk '{print "espacio libre: "$1}' | tee -a "$LOG"

clinvar_step grch37
clinvar_step grch38
viguno_step
annonars_step
check_only_steps

if [ "$need_annonars" -eq 1 ]; then
    log "reiniciando reev-annonars"
    docker restart reev-annonars >/dev/null 2>&1 || log "AVISO: no se pudo reiniciar annonars"
fi
if [ "$need_viguno" -eq 1 ]; then
    log "reiniciando reev-viguno"
    docker restart reev-viguno >/dev/null 2>&1 || log "AVISO: no se pudo reiniciar viguno"
fi

log "================ fin: $pending pendiente(s) ================"
[ "$pending" -eq 0 ] && exit 0 || exit 0
