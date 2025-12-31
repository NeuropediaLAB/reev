#!/bin/bash
set -e

echo "📥 REEV Data Downloader (All Data)"
echo "=================================="
echo ""

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

# Check available space
AVAIL_GB=$(df -BG . | tail -1 | awk "{print \$4}" | sed "s/G//")
echo -e "${BLUE}💾 Espacio disponible: ${AVAIL_GB} GB${NC}"

if [ "$AVAIL_GB" -lt 60 ]; then # Increased space requirement for annonars
    echo -e "${RED}❌ Error: Se necesitan al menos 60 GB libres${NC}"
    echo -e "${YELLOW}Disponible: ${AVAIL_GB} GB${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Espacio suficiente${NC}"
echo ""

# Create directories if they dont exist
mkdir -p data/mehari/grch37/seqvars
mkdir -p data/mehari/grch38/seqvars
mkdir -p data/annonars/grch37
mkdir -p data/annonars/grch38

echo "📥 Descargando datos de Mehari..."
echo "Este proceso puede tardar un tiempo dependiendo de tu conexión"
echo ""

cd data/mehari

# Check latest releases for Mehari
MEHARI_VERSION="0.11.0" # Latest version from download_data_updated.sh

echo -e "${BLUE}Descargando Mehari GRCh37...${NC}"
if [ ! -f "grch37/seqvars/txs.bin.zst" ] || [ ! -s "grch37/seqvars/txs.bin.zst" ]; then
    wget -c "https://github.com/varfish-org/mehari-data-tx/releases/download/v${MEHARI_VERSION}/mehari-data-txs-GRCh37-ensembl-and-refseq-${MEHARI_VERSION}.bin.zst" -O grch37/seqvars/txs.bin.zst
    echo -e "${GREEN}✓ GRCh37 descargado${NC}"
else
    echo -e "${YELLOW}⊙ GRCh37 ya existe, omitiendo...${NC}"
fi

echo -e "${BLUE}Descargando Mehari GRCh38...${NC}"
if [ ! -f "grch38/seqvars/txs.bin.zst" ] || [ ! -s "grch38/seqvars/txs.bin.zst" ]; then
    wget -c "https://github.com/varfish-org/mehari-data-tx/releases/download/v${MEHARI_VERSION}/mehari-data-txs-GRCh38-ensembl-and-refseq-${MEHARI_VERSION}.bin.zst" -O grch38/seqvars/txs.bin.zst
    echo -e "${GREEN}✓ GRCh38 descargado${NC}"
else
    echo -e "${YELLOW}⊙ GRCh38 ya existe, omitiendo...${NC}"
fi

cd ../..

echo ""
echo "📥 Descargando datos de Annonars..."
echo "Este proceso puede tardar un tiempo dependiendo de tu conexión"
echo ""

cd data/annonars

# Annonars download links from previous search
ANNONARS_GRCH37_URL="https://github.com/varfish-org/annonars/releases/download/2023-11-07/annonars-data-grch37-20231107.tar.gz"
ANNONARS_GRCH38_URL="https://github.com/varfish-org/annonars/releases/download/2023-11-07/annonars-data-grch38-20231107.tar.gz"

echo -e "${BLUE}Descargando Annonars GRCh37...${NC}"
if [ ! -f "annonars-data-grch37-20231107.tar.gz" ] || [ ! -s "annonars-data-grch37-20231107.tar.gz" ]; then
    wget -c "${ANNONARS_GRCH37_URL}" -O annonars-data-grch37-20231107.tar.gz
    echo "Extrayendo..."
    tar xzf annonars-data-grch37-20231107.tar.gz
    rm annonars-data-grch37-20231107.tar.gz
    echo -e "${GREEN}✓ GRCh37 descargado y extraído${NC}"
else
    echo -e "${YELLOW}⊙ GRCh37 ya existe, omitiendo...${NC}"
fi

echo -e "${BLUE}Descargando Annonars GRCh38...${NC}"
if [ ! -f "annonars-data-grch38-20231107.tar.gz" ] || [ ! -s "annonars-data-grch38-20231107.tar.gz" ]; then
    wget -c "${ANNONARS_GRCH38_URL}" -O annonars-data-grch38-20231107.tar.gz
    echo "Extrayendo..."
    tar xzf annonars-data-grch38-20231107.tar.gz
    rm annonars-data-grch38-20231107.tar.gz
    echo -e "${GREEN}✓ GRCh38 descargado y extraído${NC}"
else
    echo -e "${YELLOW}⊙ GRCh38 ya existe, omitiendo...${NC}"
fi

cd ../..

echo ""
echo -e "${GREEN}✅ Descarga de todos los datos completada${NC}"
echo ""
echo "📊 Verificando archivos descargados..."
du -sh data/mehari/grch*/seqvars/txs.bin.zst 2>/dev/null || echo "Verificando Mehari..."
du -sh data/annonars/grch*/clinvar/rocksdb 2>/dev/null || echo "Verificando Annonars..."


echo ""
echo -e "${BLUE}🔄 Iniciando servicios...${NC}"
docker compose up -d annonars mehari

echo ""
echo -e "${GREEN}✅ Proceso completado${NC}"
echo ""
echo "Para ver los logs:"
echo "  docker compose logs -f mehari"
echo "  docker compose logs -f annonars"
echo ""
echo "Para verificar estado:"
echo "  docker compose ps"
