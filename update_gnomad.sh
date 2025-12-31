#!/bin/bash
# Script manual para actualizar gnomAD (base de datos grande)

set -e

CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  📥 ACTUALIZACIÓN MANUAL DE gnomAD                ║${NC}"
echo -e "${CYAN}║  Tamaño: ~36 GB | Tiempo: 4-6 horas               ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}⚠️  Esta operación descargará ~36 GB${NC}"
echo -e "${YELLOW}¿Continuar? (s/n)${NC}"
read -n 1 -r
echo

if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Cancelado"
    exit 0
fi

LOG="logs/gnomad_update_$(date +%Y%m%d).log"
mkdir -p logs

echo "Inicio: $(date)" | tee "$LOG"

cd data/sources
mkdir -p gnomad_update
cd gnomad_update

GNOMAD_URL="https://api.github.com/repos/varfish-org/annonars-data-gnomad/releases"
LATEST=$(curl -s "$GNOMAD_URL" | jq -r '.[0].tag_name')

echo -e "${BLUE}📥 Última versión: $LATEST${NC}" | tee -a "$LOG"

# GRCh37
echo ""
echo -e "${BLUE}Descargando gnomAD Genomes GRCh37...${NC}"
wget -c "https://github.com/varfish-org/annonars-data-gnomad/releases/download/${LATEST}/annonars-gnomad-genomes-grch37-${LATEST#annonars-data-gnomad-genomes-}+0.44.0.tar.gz" \
    -O gnomad-37.tar.gz | tee -a "$LOG"

echo "Extrayendo..."
tar xzf gnomad-37.tar.gz

if [ -d "~/docker/reev/data/grch37/gnomad-genomes" ]; then
    echo "Creando backup..."
    mv ~/docker/reev/data/grch37/gnomad-genomes ~/docker/reev/data/grch37/gnomad-genomes.backup.$(date +%Y%m%d)
fi

mv annonars-gnomad-genomes-grch37-* ~/docker/reev/data/grch37/gnomad-genomes
rm gnomad-37.tar.gz

echo -e "${GREEN}✓ GRCh37 actualizado${NC}"

# GRCh38
echo ""
echo -e "${BLUE}Descargando gnomAD Genomes GRCh38...${NC}"
wget -c "https://github.com/varfish-org/annonars-data-gnomad/releases/download/${LATEST}/annonars-gnomad-genomes-grch38-${LATEST#annonars-data-gnomad-genomes-}+0.44.0.tar.gz" \
    -O gnomad-38.tar.gz | tee -a "$LOG"

echo "Extrayendo..."
tar xzf gnomad-38.tar.gz

if [ -d "~/docker/reev/data/grch38/gnomad-genomes" ]; then
    mv ~/docker/reev/data/grch38/gnomad-genomes ~/docker/reev/data/grch38/gnomad-genomes.backup.$(date +%Y%m%d)
fi

mv annonars-gnomad-genomes-grch38-* ~/docker/reev/data/grch38/gnomad-genomes
rm gnomad-38.tar.gz

echo -e "${GREEN}✓ GRCh38 actualizado${NC}"

cd ~/docker/reev
rm -rf data/sources/gnomad_update

# Actualizar versión
VERSION_FILE=".db_versions.json"
jq --arg ver "$LATEST" '.gnomad = $ver' "$VERSION_FILE" > "${VERSION_FILE}.tmp" && mv "${VERSION_FILE}.tmp" "$VERSION_FILE"

echo ""
echo -e "${BLUE}Reiniciando servicios...${NC}"
docker compose restart annonars

echo ""
echo "Fin: $(date)" | tee -a "$LOG"
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ gnomAD ACTUALIZADO CORRECTAMENTE              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
