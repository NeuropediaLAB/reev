#!/bin/bash
# REEV Manager - Script unificado para gestión completa de bases de datos
# Combina descarga, compilación y actualización automática

set -e

# ============================================
# COLORES Y CONFIGURACIÓN
# ============================================
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
RED="\033[0;31m"
NC="\033[0m"

REEV_DIR="$HOME/docker/reev"
LOG_DIR="$REEV_DIR/logs"
VERSION_FILE="$REEV_DIR/.db_versions.json"
LOCK_FILE="$REEV_DIR/.reev_manager.lock"

mkdir -p "$LOG_DIR"

# ============================================
# FUNCIONES AUXILIARES
# ============================================
log() {
    echo -e "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$CURRENT_LOG"
}

check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        LOCK_PID=$(cat "$LOCK_FILE")
        if ps -p "$LOCK_PID" > /dev/null 2>&1; then
            echo -e "${RED}❌ Proceso ya en ejecución (PID: $LOCK_PID)${NC}"
            exit 1
        else
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT
}

check_space() {
    local required=$1
    AVAIL_GB=$(df -BG "$REEV_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
    
    if [ "$AVAIL_GB" -lt "$required" ]; then
        echo -e "${RED}❌ Error: Se necesitan al menos ${required} GB libres${NC}"
        echo -e "${YELLOW}Disponible: ${AVAIL_GB} GB${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Espacio disponible: ${AVAIL_GB} GB${NC}"
}

init_version_file() {
    if [ ! -f "$VERSION_FILE" ]; then
        echo '{"clinvar":"none","mehari":"none","gnomad":"none","cadd":"1.7"}' > "$VERSION_FILE"
    fi
}

# ============================================
# DESCARGA INICIAL
# ============================================
download_initial_data() {
    CURRENT_LOG="$LOG_DIR/download_$(date +%Y%m%d_%H%M%S).log"
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  📥 DESCARGA INICIAL DE DATOS                     ║${NC}"
    echo -e "${CYAN}║  Mehari + Annonars ClinVar                        ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_space 20
    log "Iniciando descarga inicial..."
    
    cd "$REEV_DIR"
    mkdir -p data/mehari/grch37/seqvars
    mkdir -p data/mehari/grch38/seqvars
    mkdir -p data/annonars/grch37
    mkdir -p data/annonars/grch38
    
    # Mehari
    MEHARI_VERSION="0.11.0"
    log "📥 Descargando Mehari v${MEHARI_VERSION}..."
    
    cd data/mehari
    if [ ! -f "grch37/seqvars/txs.bin.zst" ]; then
        wget -c "https://github.com/varfish-org/mehari-data-tx/releases/download/v${MEHARI_VERSION}/mehari-data-txs-GRCh37-ensembl-and-refseq-${MEHARI_VERSION}.bin.zst" \
            -O grch37/seqvars/txs.bin.zst
        log "✓ Mehari GRCh37 descargado"
    fi
    
    if [ ! -f "grch38/seqvars/txs.bin.zst" ]; then
        wget -c "https://github.com/varfish-org/mehari-data-tx/releases/download/v${MEHARI_VERSION}/mehari-data-txs-GRCh38-ensembl-and-refseq-${MEHARI_VERSION}.bin.zst" \
            -O grch38/seqvars/txs.bin.zst
        log "✓ Mehari GRCh38 descargado"
    fi
    
    cd "$REEV_DIR"
    jq --arg ver "v${MEHARI_VERSION}" '.mehari = $ver' "$VERSION_FILE" > "${VERSION_FILE}.tmp" && mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
    
    # Annonars ClinVar
    CLINVAR_DATE="20251228"
    ANNONARS_VERSION="0.44.0"
    log "📥 Descargando Annonars ClinVar ${CLINVAR_DATE}..."
    
    cd data/annonars
    
    if [ ! -d "grch37/clinvar/rocksdb" ]; then
        wget -c "https://github.com/varfish-org/annonars-data-clinvar/releases/download/annonars-data-clinvar-${CLINVAR_DATE}/annonars-clinvar-minimal-grch37-${CLINVAR_DATE}+${ANNONARS_VERSION}.tar.gz" \
            -O clinvar-grch37.tar.gz
        tar xzf clinvar-grch37.tar.gz -C grch37/
        mv grch37/annonars-clinvar-minimal-grch37-${CLINVAR_DATE}+${ANNONARS_VERSION} grch37/clinvar
        rm clinvar-grch37.tar.gz
        log "✓ ClinVar GRCh37 instalado"
    fi
    
    if [ ! -d "grch38/clinvar/rocksdb" ]; then
        wget -c "https://github.com/varfish-org/annonars-data-clinvar/releases/download/annonars-data-clinvar-${CLINVAR_DATE}/annonars-clinvar-minimal-grch38-${CLINVAR_DATE}+${ANNONARS_VERSION}.tar.gz" \
            -O clinvar-grch38.tar.gz
        tar xzf clinvar-grch38.tar.gz -C grch38/
        mv grch38/annonars-clinvar-minimal-grch38-${CLINVAR_DATE}+${ANNONARS_VERSION} grch38/clinvar
        rm clinvar-grch38.tar.gz
        log "✓ ClinVar GRCh38 instalado"
    fi
    
    cd "$REEV_DIR"
    jq --arg ver "annonars-data-clinvar-${CLINVAR_DATE}" '.clinvar = $ver' "$VERSION_FILE" > "${VERSION_FILE}.tmp" && mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
    
    log ""
    log "✅ Descarga inicial completada"
    log "📝 Log: $CURRENT_LOG"
}

# ============================================
# COMPILACIÓN CADD + gnomAD
# ============================================
compile_heavy_databases() {
    CURRENT_LOG="$LOG_DIR/compile_$(date +%Y%m%d_%H%M%S).log"
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  🔨 COMPILACIÓN: CADD + gnomAD                    ║${NC}"
    echo -e "${CYAN}║  Tiempo estimado: 18-22 horas                     ║${NC}"
    echo -e "${CYAN}║  Espacio requerido: ~80 GB                        ║${NC}"
    echo -e "${CYAN}║  Nota: SNVs e InDels se compilan por separado    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  Esta operación es LARGA y requiere ~80 GB${NC}"
    echo -e "${YELLOW}¿Continuar? (s/n)${NC}"
    read -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Cancelado"
        exit 0
    fi
    
    check_space 80
    START=$(date +%s)
    log "Iniciando compilación de bases de datos pesadas..."
    
    cd "$REEV_DIR"
    mkdir -p data/sources/{cadd,gnomad}
    mkdir -p data/grch37/{cadd,cadd-indel,gnomad-genomes}
    mkdir -p data/grch38/gnomad-genomes
    
    # ========== CADD ==========
    log ""
    log "[1/5] Descargando CADD SNVs GRCh37 (~78 GB)"
    cd data/sources/cadd
    
    if [ ! -f "whole_genome_SNVs.tsv.gz" ]; then
        wget -c "https://krishna.gs.washington.edu/download/CADD/v1.7/GRCh37/whole_genome_SNVs.tsv.gz"
        log "✓ SNVs descargado ($(du -h whole_genome_SNVs.tsv.gz | cut -f1))"
    else
        log "⊙ SNVs ya descargado"
    fi
    
    log ""
    log "[2/5] Descargando CADD InDels GRCh37 (~12 GB)"
    if [ ! -f "gnomad.genomes-exomes.r4.0.indel.tsv.gz" ]; then
        wget -c "https://krishna.gs.washington.edu/download/CADD/v1.7/GRCh37/gnomad.genomes-exomes.r4.0.indel.tsv.gz"
        log "✓ InDels descargado ($(du -h gnomad.genomes-exomes.r4.0.indel.tsv.gz | cut -f1))"
    else
        log "⊙ InDels ya descargado"
    fi
    
    cd "$REEV_DIR"
    
    log ""
    log "[3/5] Compilando CADD SNVs GRCh37 (8-10 horas)"
    log "Esto puede tardar mucho tiempo..."
    
    if [ ! -f "data/grch37/cadd/rocksdb/CURRENT" ]; then
        log "Compilando SNVs..."
        docker compose exec -T annonars annonars tsv import \
            --path-in-tsv /sources/cadd/whole_genome_SNVs.tsv.gz \
            --path-out-rocksdb /data/grch37/cadd/rocksdb \
            --genome-release grch37 \
            --db-name cadd \
            --db-version 1.7 \
            --col-chrom "#Chrom" \
            --col-start Pos \
            --col-ref Ref \
            --col-alt Alt \
            --inference-row-count 100000 \
            --skip-row-count 2 \
            --add-default-null-values 2>&1 | tee "$LOG_DIR/cadd_snvs_37_detailed.log"
        
        log "✓ CADD SNVs compilado ($(du -sh data/grch37/cadd | cut -f1))"
    else
        log "⊙ CADD SNVs ya compilado"
    fi
    
    log ""
    log "[4/5] Compilando CADD InDels GRCh37 (4-6 horas)"
    
    if [ ! -f "data/grch37/cadd-indel/rocksdb/CURRENT" ]; then
        mkdir -p data/grch37/cadd-indel
        log "Compilando InDels..."
        docker compose exec -T annonars annonars tsv import \
            --path-in-tsv /sources/cadd/gnomad.genomes-exomes.r4.0.indel.tsv.gz \
            --path-out-rocksdb /data/grch37/cadd-indel/rocksdb \
            --genome-release grch37 \
            --db-name cadd-indel \
            --db-version 1.7 \
            --col-chrom "#Chrom" \
            --col-start Pos \
            --col-ref Ref \
            --col-alt Alt \
            --inference-row-count 100000 \
            --skip-row-count 2 \
            --add-default-null-values 2>&1 | tee "$LOG_DIR/cadd_indels_37_detailed.log"
        
        log "✓ CADD InDels compilado ($(du -sh data/grch37/cadd-indel | cut -f1))"
    else
        log "⊙ CADD InDels ya compilado"
    fi
    
    # ========== gnomAD ==========
    log ""
    log "[5/5] gnomAD Genomes - Descarga manual requerida"
    log "⚠️  Los releases precompilados han cambiado de ubicación"
    log "⚠️  Visita: https://github.com/varfish-org/annonars-data-gnomad/releases"
    log "⚠️  Descarga los archivos manualmente y colócalos en:"
    log "    - data/grch37/gnomad-genomes/"
    log "    - data/grch38/gnomad-genomes/"
    log ""
    log "ℹ️  El sistema CADD funcionará correctamente sin gnomAD"
    
    cd "$REEV_DIR"
    
    # Limpieza opcional
    log ""
    log "ℹ️  Los archivos TSV se mantienen en data/sources/cadd/"
    log "ℹ️  Para liberarlos manualmente: rm data/sources/cadd/*.tsv.gz"
    
    # Finalización
    END=$(date +%s)
    ELAPSED=$((END - START))
    HOURS=$((ELAPSED / 3600))
    MINS=$(((ELAPSED % 3600) / 60))
    
    log ""
    log "════════════════════════════════════════════════"
    log "✅ COMPILACIÓN COMPLETADA"
    log "Tiempo total: ${HOURS}h ${MINS}m"
    log "════════════════════════════════════════════════"
    log ""
    log "📊 Tamaños:"
    du -sh data/grch*/* 2>/dev/null | grep -E "cadd|gnomad" | while read line; do
        log "  $line"
    done
    log ""
    log "📝 Log: $CURRENT_LOG"
    
    log ""
    log "🔄 Reiniciando servicios..."
    docker compose restart annonars
    log "✓ Servicios reiniciados"
}

# ============================================
# ACTUALIZACIÓN AUTOMÁTICA
# ============================================
check_updates() {
    CURRENT_LOG="$LOG_DIR/update_$(date +%Y%m%d_%H%M%S).log"
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  🔄 VERIFICACIÓN DE ACTUALIZACIONES              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "Verificando actualizaciones disponibles..."
    
    CURRENT_CLINVAR=$(jq -r '.clinvar // "none"' "$VERSION_FILE" 2>/dev/null || echo "none")
    CURRENT_MEHARI=$(jq -r '.mehari // "none"' "$VERSION_FILE" 2>/dev/null || echo "none")
    
    UPDATES_AVAILABLE=0
    
    # ClinVar
    log ""
    log "📋 Verificando ClinVar..."
    LATEST_CLINVAR=$(curl -s "https://api.github.com/repos/varfish-org/annonars-data-clinvar/releases/latest" | jq -r '.tag_name // "none"')
    
    if [ "$LATEST_CLINVAR" != "null" ] && [ "$LATEST_CLINVAR" != "none" ] && [ "$LATEST_CLINVAR" != "$CURRENT_CLINVAR" ]; then
        log "  ✨ Nueva versión: $LATEST_CLINVAR (actual: $CURRENT_CLINVAR)"
        UPDATES_AVAILABLE=$((UPDATES_AVAILABLE + 1))
    else
        log "  ✓ ClinVar actualizado ($CURRENT_CLINVAR)"
    fi
    
    # Mehari
    log ""
    log "📋 Verificando Mehari..."
    LATEST_MEHARI=$(curl -s "https://api.github.com/repos/varfish-org/mehari-data-tx/releases/latest" | jq -r '.tag_name // "none"')
    
    if [ "$LATEST_MEHARI" != "null" ] && [ "$LATEST_MEHARI" != "none" ] && [ "$LATEST_MEHARI" != "$CURRENT_MEHARI" ]; then
        log "  ✨ Nueva versión: $LATEST_MEHARI (actual: $CURRENT_MEHARI)"
        UPDATES_AVAILABLE=$((UPDATES_AVAILABLE + 1))
    else
        log "  ✓ Mehari actualizado ($CURRENT_MEHARI)"
    fi
    
    log ""
    log "📋 gnomAD y CADD:"
    log "  ℹ️  Bases de datos grandes, verificar manualmente"
    log "  ℹ️  Actualizar con: $0 update-gnomad"
    
    if [ $UPDATES_AVAILABLE -gt 0 ]; then
        log ""
        log "${YELLOW}⚠️  $UPDATES_AVAILABLE actualización(es) disponible(s)${NC}"
        log "${YELLOW}Ejecuta: $0 update para aplicarlas${NC}"
    else
        log ""
        log "✅ Todas las bases de datos están actualizadas"
    fi
    
    log ""
    log "📝 Log: $CURRENT_LOG"
}

# ============================================
# APLICAR ACTUALIZACIONES
# ============================================
apply_updates() {
    CURRENT_LOG="$LOG_DIR/update_$(date +%Y%m%d_%H%M%S).log"
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  ⬆️  APLICANDO ACTUALIZACIONES                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "Aplicando actualizaciones..."
    
    cd "$REEV_DIR"
    CURRENT_CLINVAR=$(jq -r '.clinvar // "none"' "$VERSION_FILE")
    CURRENT_MEHARI=$(jq -r '.mehari // "none"' "$VERSION_FILE")
    
    UPDATES_APPLIED=0
    
    # ClinVar
    log ""
    log "📋 Actualizando ClinVar..."
    LATEST_CLINVAR=$(curl -s "https://api.github.com/repos/varfish-org/annonars-data-clinvar/releases/latest" | jq -r '.tag_name')
    
    if [ "$LATEST_CLINVAR" != "$CURRENT_CLINVAR" ]; then
        cd data/sources
        mkdir -p clinvar_update && cd clinvar_update
        
        CLINVAR_TAG="${LATEST_CLINVAR#annonars-data-clinvar-}"
        
        log "  📥 Descargando GRCh37..."
        wget -q "https://github.com/varfish-org/annonars-data-clinvar/releases/download/${LATEST_CLINVAR}/annonars-clinvar-minimal-grch37-${CLINVAR_TAG}+0.44.0.tar.gz" \
            -O clinvar-37.tar.gz
        tar xzf clinvar-37.tar.gz
        [ -d "$REEV_DIR/data/grch37/clinvar" ] && mv "$REEV_DIR/data/grch37/clinvar" "$REEV_DIR/data/grch37/clinvar.backup.$(date +%Y%m%d)"
        mv annonars-clinvar-minimal-grch37-* "$REEV_DIR/data/grch37/clinvar"
        rm clinvar-37.tar.gz
        log "  ✓ GRCh37 actualizado"
        
        log "  📥 Descargando GRCh38..."
        wget -q "https://github.com/varfish-org/annonars-data-clinvar/releases/download/${LATEST_CLINVAR}/annonars-clinvar-minimal-grch38-${CLINVAR_TAG}+0.44.0.tar.gz" \
            -O clinvar-38.tar.gz
        tar xzf clinvar-38.tar.gz
        [ -d "$REEV_DIR/data/grch38/clinvar" ] && mv "$REEV_DIR/data/grch38/clinvar" "$REEV_DIR/data/grch38/clinvar.backup.$(date +%Y%m%d)"
        mv annonars-clinvar-minimal-grch38-* "$REEV_DIR/data/grch38/clinvar"
        rm clinvar-38.tar.gz
        log "  ✓ GRCh38 actualizado"
        
        cd "$REEV_DIR"
        rm -rf data/sources/clinvar_update
        jq --arg ver "$LATEST_CLINVAR" '.clinvar = $ver' "$VERSION_FILE" > "${VERSION_FILE}.tmp" && mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
        
        UPDATES_APPLIED=$((UPDATES_APPLIED + 1))
    else
        log "  ✓ ClinVar ya está actualizado"
    fi
    
    # Mehari
    log ""
    log "📋 Actualizando Mehari..."
    LATEST_MEHARI=$(curl -s "https://api.github.com/repos/varfish-org/mehari-data-tx/releases/latest" | jq -r '.tag_name')
    
    if [ "$LATEST_MEHARI" != "$CURRENT_MEHARI" ]; then
        cd data/sources
        mkdir -p mehari_update && cd mehari_update
        
        MEHARI_VER="${LATEST_MEHARI#v}"
        
        log "  📥 Descargando GRCh37..."
        wget -q "https://github.com/varfish-org/mehari-data-tx/releases/download/${LATEST_MEHARI}/mehari-data-txs-grch37-ensembl-and-refseq-${MEHARI_VER}.bin.zst" \
            -O mehari-37.bin.zst
        [ -f "$REEV_DIR/data/mehari/grch37/seqvars/txs.bin.zst" ] && mv "$REEV_DIR/data/mehari/grch37/seqvars/txs.bin.zst" "$REEV_DIR/data/mehari/grch37/seqvars/txs.bin.zst.backup.$(date +%Y%m%d)"
        mv mehari-37.bin.zst "$REEV_DIR/data/mehari/grch37/seqvars/txs.bin.zst"
        log "  ✓ GRCh37 actualizado"
        
        log "  📥 Descargando GRCh38..."
        wget -q "https://github.com/varfish-org/mehari-data-tx/releases/download/${LATEST_MEHARI}/mehari-data-txs-grch38-ensembl-and-refseq-${MEHARI_VER}.bin.zst" \
            -O mehari-38.bin.zst
        [ -f "$REEV_DIR/data/mehari/grch38/seqvars/txs.bin.zst" ] && mv "$REEV_DIR/data/mehari/grch38/seqvars/txs.bin.zst" "$REEV_DIR/data/mehari/grch38/seqvars/txs.bin.zst.backup.$(date +%Y%m%d)"
        mv mehari-38.bin.zst "$REEV_DIR/data/mehari/grch38/seqvars/txs.bin.zst"
        log "  ✓ GRCh38 actualizado"
        
        cd "$REEV_DIR"
        rm -rf data/sources/mehari_update
        jq --arg ver "$LATEST_MEHARI" '.mehari = $ver' "$VERSION_FILE" > "${VERSION_FILE}.tmp" && mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
        
        UPDATES_APPLIED=$((UPDATES_APPLIED + 1))
    else
        log "  ✓ Mehari ya está actualizado"
    fi
    
    # Finalización
    if [ $UPDATES_APPLIED -gt 0 ]; then
        log ""
        log "🔄 $UPDATES_APPLIED actualización(es) aplicadas"
        log "🔄 Reiniciando servicios..."
        docker compose restart annonars mehari
        log "✓ Servicios reiniciados"
        
        log ""
        log "🗑️  Limpiando backups antiguos (>7 días)..."
        find data -name "*.backup.*" -mtime +7 -delete 2>/dev/null || true
        log "✓ Limpieza completada"
    fi
    
    log ""
    log "✅ Actualización completada"
    log "📝 Log: $CURRENT_LOG"
}

# ============================================
# ACTUALIZAR gnomAD
# ============================================
update_gnomad() {
    CURRENT_LOG="$LOG_DIR/gnomad_update_$(date +%Y%m%d_%H%M%S).log"
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  📥 ACTUALIZACIÓN DE gnomAD                       ║${NC}"
    echo -e "${CYAN}║  Tamaño: ~36 GB | Tiempo: 4-6 horas              ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  Esta operación descargará ~36 GB${NC}"
    echo -e "${YELLOW}¿Continuar? (s/n)${NC}"
    read -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Cancelado"
        exit 0
    fi
    
    check_space 40
    log "Actualizando gnomAD..."
    
    cd "$REEV_DIR/data/sources"
    mkdir -p gnomad_update && cd gnomad_update
    
    LATEST=$(curl -s "https://api.github.com/repos/varfish-org/annonars-data-gnomad/releases" | jq -r '.[0].tag_name')
    GNOMAD_DATE="${LATEST#annonars-data-gnomad-genomes-}"
    
    log "📥 Última versión: $LATEST"
    
    # GRCh37
    log ""
    log "Descargando gnomAD Genomes GRCh37..."
    wget -c "https://github.com/varfish-org/annonars-data-gnomad/releases/download/${LATEST}/annonars-gnomad-genomes-grch37-${GNOMAD_DATE}+0.44.0.tar.gz" \
        -O gnomad-37.tar.gz
    tar xzf gnomad-37.tar.gz
    [ -d "$REEV_DIR/data/grch37/gnomad-genomes" ] && mv "$REEV_DIR/data/grch37/gnomad-genomes" "$REEV_DIR/data/grch37/gnomad-genomes.backup.$(date +%Y%m%d)"
    mv annonars-gnomad-genomes-grch37-* "$REEV_DIR/data/grch37/gnomad-genomes"
    rm gnomad-37.tar.gz
    log "✓ GRCh37 actualizado"
    
    # GRCh38
    log ""
    log "Descargando gnomAD Genomes GRCh38..."
    wget -c "https://github.com/varfish-org/annonars-data-gnomad/releases/download/${LATEST}/annonars-gnomad-genomes-grch38-${GNOMAD_DATE}+0.44.0.tar.gz" \
        -O gnomad-38.tar.gz
    tar xzf gnomad-38.tar.gz
    [ -d "$REEV_DIR/data/grch38/gnomad-genomes" ] && mv "$REEV_DIR/data/grch38/gnomad-genomes" "$REEV_DIR/data/grch38/gnomad-genomes.backup.$(date +%Y%m%d)"
    mv annonars-gnomad-genomes-grch38-* "$REEV_DIR/data/grch38/gnomad-genomes"
    rm gnomad-38.tar.gz
    log "✓ GRCh38 actualizado"
    
    cd "$REEV_DIR"
    rm -rf data/sources/gnomad_update
    jq --arg ver "$LATEST" '.gnomad = $ver' "$VERSION_FILE" > "${VERSION_FILE}.tmp" && mv "${VERSION_FILE}.tmp" "$VERSION_FILE"
    
    log ""
    log "🔄 Reiniciando servicios..."
    docker compose restart annonars
    log "✓ Servicios reiniciados"
    
    log ""
    log "✅ gnomAD actualizado correctamente"
    log "📝 Log: $CURRENT_LOG"
}

# ============================================
# ESTADO DEL SISTEMA
# ============================================
show_status() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  📊 ESTADO DEL SISTEMA REEV                       ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ! -f "$VERSION_FILE" ]; then
        echo -e "${YELLOW}⚠️  No hay bases de datos instaladas${NC}"
        echo ""
        echo "Ejecuta: $0 download"
        exit 0
    fi
    
    echo -e "${BLUE}📦 Versiones instaladas:${NC}"
    echo ""
    jq -r 'to_entries[] | "  \(.key): \(.value)"' "$VERSION_FILE"
    
    echo ""
    echo -e "${BLUE}💾 Uso de espacio:${NC}"
    echo ""
    du -sh "$REEV_DIR/data"/* 2>/dev/null | while read size path; do
        echo "  $(basename $path): $size"
    done
    
    echo ""
    echo -e "${BLUE}🐳 Estado de contenedores:${NC}"
    echo ""
    cd "$REEV_DIR"
    docker compose ps
    
    echo ""
    AVAIL_GB=$(df -BG "$REEV_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
    echo -e "${BLUE}💾 Espacio disponible: ${AVAIL_GB} GB${NC}"
}

# ============================================
# MENÚ PRINCIPAL
# ============================================
show_help() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  REEV Manager - Gestor unificado de bases de datos║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Uso: $0 <comando>"
    echo ""
    echo "Comandos:"
    echo ""
    echo "  download          Descarga inicial (Mehari + ClinVar)"
    echo "                    Tiempo: 2-4 horas | Espacio: ~20 GB"
    echo ""
    echo "  compile           Compila CADD + gnomAD"
    echo "                    Tiempo: 22-24 horas | Espacio: ~80 GB"
    echo ""
    echo "  check             Verifica actualizaciones disponibles"
    echo ""
    echo "  update            Aplica actualizaciones (ClinVar + Mehari)"
    echo "                    Tiempo: 1-2 horas"
    echo ""
    echo "  update-gnomad     Actualiza gnomAD manualmente"
    echo "                    Tiempo: 4-6 horas | Espacio: ~36 GB"
    echo ""
    echo "  status            Muestra estado del sistema"
    echo ""
    echo "  full              Instalación completa (download + compile)"
    echo "                    Tiempo: 24-28 horas | Espacio: ~100 GB"
    echo ""
    echo "Ejemplos:"
    echo ""
    echo "  # Instalación rápida (bases de datos básicas)"
    echo "  $0 download"
    echo ""
    echo "  # Instalación completa (todas las bases de datos)"
    echo "  $0 full"
    echo ""
    echo "  # Verificar y aplicar actualizaciones"
    echo "  $0 check"
    echo "  $0 update"
    echo ""
    echo "  # Ver estado"
    echo "  $0 status"
    echo ""
}

# ============================================
# MAIN
# ============================================
cd "$REEV_DIR"
init_version_file

case "${1:-}" in
    download)
        check_lock
        download_initial_data
        ;;
    compile)
        check_lock
        compile_heavy_databases
        ;;
    check)
        check_updates
        ;;
    update)
        check_lock
        apply_updates
        ;;
    update-gnomad)
        check_lock
        update_gnomad
        ;;
    status)
        show_status
        ;;
    full)
        check_lock
        download_initial_data
        echo ""
        echo -e "${YELLOW}Presiona Enter para continuar con la compilación...${NC}"
        read
        compile_heavy_databases
        ;;
    *)
        show_help
        exit 1
        ;;
esac

exit 0
