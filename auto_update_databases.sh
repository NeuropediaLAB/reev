#!/bin/bash
# Script de actualización automática diaria de bases de datos REEV

set -e

CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

LOG_DIR="$HOME/docker/reev/logs/updates"
LOCK_FILE="$HOME/docker/reev/.update_lock"
UPDATE_LOG="$LOG_DIR/update_$(date +%Y%m%d).log"
VERSION_FILE="$HOME/docker/reev/.db_versions.json"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$UPDATE_LOG"
}

# Verificar lock
if [ -f "$LOCK_FILE" ]; then
    LOCK_PID=$(cat "$LOCK_FILE")
    if ps -p "$LOCK_PID" > /dev/null 2>&1; then
        log "⚠️  Actualización ya en curso (PID: $LOCK_PID)"
        exit 0
    else
        rm -f "$LOCK_FILE"
    fi
fi

echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

log ""
log "╔════════════════════════════════════════════════════╗"
log "║  🔄 VERIFICACIÓN AUTOMÁTICA DE ACTUALIZACIONES    ║"
log "╚════════════════════════════════════════════════════╝"
log ""

# Cargar versiones actuales
CURRENT_CLINVAR=$(jq -r '.clinvar // "none"' "$VERSION_FILE" 2>/dev/null || echo "none")
CURRENT_MEHARI=$(jq -r '.mehari // "none"' "$VERSION_FILE" 2>/dev/null || echo "none")

UPDATES_AVAILABLE=0

# ============================================
# 1. Verificar ClinVar
# ============================================
log "📋 Verificando ClinVar..."

LATEST_CLINVAR=$(curl -s "https://api.github.com/repos/varfish-org/annonars-data-clinvar/releases/latest" | jq -r '.tag_name // "none"')

if [ "$LATEST_CLINVAR" != "null" ] && [ "$LATEST_CLINVAR" != "none" ] && [ "$LATEST_CLINVAR" != "$CURRENT_CLINVAR" ]; then
    log "  ✨ Nueva versión de ClinVar: $LATEST_CLINVAR (actual: $CURRENT_CLINVAR)"
    UPDATES_AVAILABLE=$((UPDATES_AVAILABLE + 1))
    
    cd ~/docker/reev/data/sources
    mkdir -p clinvar_update && cd clinvar_update
    
    log "  📥 Descargando ClinVar GRCh37..."
    CLINVAR_TAG="${LATEST_CLINVAR#annonars-data-clinvar-}"
    if wget -q "https://github.com/varfish-org/annonars-data-clinvar/releases/download/${LATEST_CLINVAR}/annonars-clinvar-minimal-grch37-${CLINVAR_TAG}+0.44.0.tar.gz" -O clinvar-37.tar.gz; then
        tar xzf clinvar-37.tar.gz
        [ -d ~/docker/reev/data/grch37/clinvar ] && mv ~/docker/reev/data/grch37/clinvar ~/docker/reev/data/grch37/clinvar.backup.$(date +%Y%m%d)
        mv annonars-clinvar-minimal-grch37-* ~/docker/reev/data/grch37/clinvar
        rm clinvar-37.tar.gz
        log "  ✓ ClinVar GRCh37 actualizado"
    fi
    
    log "  📥 Descargando ClinVar GRCh38..."
    if wget -q "https://github.com/varfish-org/annonars-data-clinvar/releases/download/${LATEST_CLINVAR}/annonars-clinvar-minimal-grch38-${CLINVAR_TAG}+0.44.0.tar.gz" -O clinvar-38.tar.gz; then
        tar xzf clinvar-38.tar.gz
        [ -d ~/docker/reev/data/grch38/clinvar ] && mv ~/docker/reev/data/grch38/clinvar ~/docker/reev/data/grch38/clinvar.backup.$(date +%Y%m%d)
        mv annonars-clinvar-minimal-grch38-* ~/docker/reev/data/grch38/clinvar
        rm clinvar-38.tar.gz
        log "  ✓ ClinVar GRCh38 actualizado"
    fi
    
    cd ~/docker/reev
    rm -rf data/sources/clinvar_update
    jq --arg ver "$LATEST_CLINVAR" '.clinvar = $ver' "$VERSION_FILE" > "${VERSION_FILE}.tmp" && mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
else
    log "  ✓ ClinVar actualizado ($CURRENT_CLINVAR)"
fi

# ============================================
# 2. Verificar Mehari
# ============================================
log ""
log "📋 Verificando Mehari Transcripts..."

LATEST_MEHARI=$(curl -s "https://api.github.com/repos/varfish-org/mehari-data-tx/releases/latest" | jq -r '.tag_name // "none"')

if [ "$LATEST_MEHARI" != "null" ] && [ "$LATEST_MEHARI" != "none" ] && [ "$LATEST_MEHARI" != "$CURRENT_MEHARI" ]; then
    log "  ✨ Nueva versión de Mehari: $LATEST_MEHARI (actual: $CURRENT_MEHARI)"
    UPDATES_AVAILABLE=$((UPDATES_AVAILABLE + 1))
    
    cd ~/docker/reev/data/sources
    mkdir -p mehari_update && cd mehari_update
    
    MEHARI_VER="${LATEST_MEHARI#v}"
    
    log "  📥 Descargando Mehari GRCh37..."
    if wget -q "https://github.com/varfish-org/mehari-data-tx/releases/download/${LATEST_MEHARI}/mehari-data-txs-grch37-ensembl-and-refseq-${MEHARI_VER}.bin.zst" -O mehari-37.bin.zst; then
        [ -f ~/docker/reev/data/mehari/grch37/seqvars/txs.bin.zst ] && mv ~/docker/reev/data/mehari/grch37/seqvars/txs.bin.zst ~/docker/reev/data/mehari/grch37/seqvars/txs.bin.zst.backup.$(date +%Y%m%d)
        mv mehari-37.bin.zst ~/docker/reev/data/mehari/grch37/seqvars/txs.bin.zst
        log "  ✓ Mehari GRCh37 actualizado"
    fi
    
    log "  📥 Descargando Mehari GRCh38..."
    if wget -q "https://github.com/varfish-org/mehari-data-tx/releases/download/${LATEST_MEHARI}/mehari-data-txs-grch38-ensembl-and-refseq-${MEHARI_VER}.bin.zst" -O mehari-38.bin.zst; then
        [ -f ~/docker/reev/data/mehari/grch38/seqvars/txs.bin.zst ] && mv ~/docker/reev/data/mehari/grch38/seqvars/txs.bin.zst ~/docker/reev/data/mehari/grch38/seqvars/txs.bin.zst.backup.$(date +%Y%m%d)
        mv mehari-38.bin.zst ~/docker/reev/data/mehari/grch38/seqvars/txs.bin.zst
        log "  ✓ Mehari GRCh38 actualizado"
    fi
    
    cd ~/docker/reev
    rm -rf data/sources/mehari_update
    jq --arg ver "$LATEST_MEHARI" '.mehari = $ver' "$VERSION_FILE" > "${VERSION_FILE}.tmp" && mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
else
    log "  ✓ Mehari actualizado ($CURRENT_MEHARI)"
fi

# ============================================
# 3. Información sobre gnomAD y CADD
# ============================================
log ""
log "📋 gnomAD y CADD:"
log "  ℹ️  Bases de datos grandes, no se actualizan automáticamente"
log "  ℹ️  Para actualizar gnomAD: ~/docker/reev/update_gnomad.sh"
log "  ℹ️  CADD v1.7 es la última versión estable"

# ============================================
# Reiniciar servicios
# ============================================
if [ $UPDATES_AVAILABLE -gt 0 ]; then
    log ""
    log "🔄 $UPDATES_AVAILABLE actualización(es) aplicadas"
    log "🔄 Reiniciando servicios Docker..."
    
    cd ~/docker/reev
    docker compose restart annonars mehari > /dev/null 2>&1
    log "✓ Servicios reiniciados"
    
    log ""
    log "🗑️  Limpiando backups antiguos (>7 días)..."
    find ~/docker/reev/data -name "*.backup.*" -mtime +7 -delete 2>/dev/null || true
    log "✓ Limpieza completada"
else
    log ""
    log "✓ Todas las bases de datos están actualizadas"
fi

log ""
log "╔════════════════════════════════════════════════════╗"
log "║  ✅ VERIFICACIÓN COMPLETADA                       ║"
log "╚════════════════════════════════════════════════════╝"
log ""

log "📊 Uso de espacio:"
du -sh ~/docker/reev/data/* 2>/dev/null | while read size path; do
    log "  $(basename $path): $size"
done

log ""
log "📝 Log: $UPDATE_LOG"

exit 0
