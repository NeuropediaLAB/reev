#!/bin/bash
set -e

CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

echo ""
echo -e "${CYAN}╔═════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  COMPILACIÓN: CADD + gnomAD                         ║${NC}"
echo -e "${CYAN}║  Tiempo estimado: 22-24 horas                        ║${NC}"
echo -e "${CYAN}║  Espacio: ~80 GB final                               ║${NC}"
echo -e "${CYAN}╚═════════════════════════════════════════════════════╝${NC}"
echo ""

START=$(date +%s)
mkdir -p data/sources/{cadd,gnomad} logs

echo "Inicio: $(date)" | tee logs/cadd_gnomad.log
echo ""

# ========== CADD ==========
echo -e "${CYAN}[1/5] Descargando CADD SNVs GRCh37 (~78 GB)${NC}"
cd data/sources/cadd

if [ ! -f "whole_genome_SNVs.tsv.gz" ]; then
    wget -c "https://krishna.gs.washington.edu/download/CADD/v1.7/GRCh37/whole_genome_SNVs.tsv.gz"
    echo -e "${GREEN}✓ SNVs descargado ($(du -h whole_genome_SNVs.tsv.gz | cut -f1))${NC}"
else
    echo -e "${GREEN}⊙ SNVs ya descargado ($(du -h whole_genome_SNVs.tsv.gz | cut -f1))${NC}"
fi

echo ""
echo -e "${CYAN}[2/5] Descargando CADD InDels GRCh37 (~12 GB)${NC}"
if [ ! -f "gnomad.genomes.r4.0.indel.tsv.gz" ]; then
    wget -c "https://krishna.gs.washington.edu/download/CADD/v1.7/GRCh37/gnomad.genomes.r4.0.indel.tsv.gz"
    echo -e "${GREEN}✓ InDels descargado ($(du -h gnomad.genomes.r4.0.indel.tsv.gz | cut -f1))${NC}"
else
    echo -e "${GREEN}⊙ InDels ya descargado ($(du -h gnomad.genomes.r4.0.indel.tsv.gz | cut -f1))${NC}"
fi

cd ~/docker/reev

echo ""
echo -e "${CYAN}[3/5] Compilando CADD GRCh37 (12-16 horas)${NC}"
echo "Inicio CADD: $(date)" | tee -a logs/cadd_gnomad.log

if [ ! -f "data/grch37/cadd/rocksdb/CURRENT" ]; then
    docker compose exec -T annonars annonars tsv import \
        --path-in-tsv /sources/cadd/whole_genome_SNVs.tsv.gz \
        --path-in-tsv /sources/cadd/gnomad.genomes.r4.0.indel.tsv.gz \
        --path-out-rocksdb /data/grch37/cadd/rocksdb \
        --genome-release grch37 \
        --db-name cadd \
        --db-version 1.7 \
        --col-chrom "#Chrom" \
        --col-start Pos \
        --col-ref Ref \
        --col-alt Alt \
        --inference-row-count 100000 \
        --add-default-null-values 2>&1 | tee logs/cadd_37_detailed.log
    
    echo "Fin CADD: $(date)" | tee -a logs/cadd_gnomad.log
    echo -e "${GREEN}✓ CADD compilado ($(du -sh data/grch37/cadd | cut -f1))${NC}"
else
    echo -e "${GREEN}⊙ CADD ya compilado${NC}"
fi

# ========== gnomAD ==========
echo ""
echo -e "${CYAN}[4/5] Descargando gnomAD Genomes GRCh37 (~18 GB)${NC}"
cd data/sources/gnomad

URL37="https://github.com/varfish-org/annonars-data-gnomad/releases/download/annonars-data-gnomad-genomes-20241215/annonars-gnomad-genomes-grch37-20241215+0.44.0.tar.gz"

if [ ! -d "~/docker/reev/data/grch37/gnomad-genomes/rocksdb" ]; then
    wget -c "$URL37" -O genomes-37.tar.gz && \
    echo "Extrayendo..." && \
    tar xzf genomes-37.tar.gz -C ~/docker/reev/data/grch37/ && \
    mv ~/docker/reev/data/grch37/annonars-gnomad-genomes-* ~/docker/reev/data/grch37/gnomad-genomes 2>/dev/null && \
    rm genomes-37.tar.gz && \
    echo -e "${GREEN}✓ gnomAD 37 instalado${NC}" || \
    echo -e "${YELLOW}⚠️  No disponible${NC}"
fi

echo ""
echo -e "${CYAN}[5/5] Descargando gnomAD Genomes GRCh38 (~18 GB)${NC}"
URL38="https://github.com/varfish-org/annonars-data-gnomad/releases/download/annonars-data-gnomad-genomes-20241215/annonars-gnomad-genomes-grch38-20241215+0.44.0.tar.gz"

if [ ! -d "~/docker/reev/data/grch38/gnomad-genomes/rocksdb" ]; then
    wget -c "$URL38" -O genomes-38.tar.gz && \
    echo "Extrayendo..." && \
    tar xzf genomes-38.tar.gz -C ~/docker/reev/data/grch38/ && \
    mv ~/docker/reev/data/grch38/annonars-gnomad-genomes-* ~/docker/reev/data/grch38/gnomad-genomes 2>/dev/null && \
    rm genomes-38.tar.gz && \
    echo -e "${GREEN}✓ gnomAD 38 instalado${NC}" || \
    echo -e "${YELLOW}⚠️  No disponible${NC}"
fi

cd ~/docker/reev

# ========== LIMPIEZA ==========
echo ""
echo -e "${YELLOW}Limpiando archivos temporales...${NC}"
rm -f data/sources/cadd/*.tsv.gz
echo -e "${GREEN}✓ Limpieza OK${NC}"

# ========== FINALIZACIÓN ==========
END=$(date +%s)
ELAPSED=$((END - START))
HOURS=$((ELAPSED / 3600))
MINS=$(((ELAPSED % 3600) / 60))

echo ""
echo "════════════════════════════════════════════════" | tee -a logs/cadd_gnomad.log
echo "Fin: $(date)" | tee -a logs/cadd_gnomad.log
echo "Tiempo: ${HOURS}h ${MINS}m" | tee -a logs/cadd_gnomad.log
echo "════════════════════════════════════════════════" | tee -a logs/cadd_gnomad.log

echo ""
echo -e "${BLUE}📊 Resultado:${NC}"
du -sh data/grch*/* 2>/dev/null | grep -E "cadd|gnomad"
echo ""
echo -e "${BLUE}Total: $(du -sh data | cut -f1)${NC}"

echo ""
echo -e "${BLUE}Reiniciando servicios...${NC}"
docker compose restart annonars

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ COMPILACIÓN COMPLETADA                   ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo "Ver logs: tail -f logs/cadd_37_detailed.log"
echo "Frontend: http://192.168.0.105:3003"
