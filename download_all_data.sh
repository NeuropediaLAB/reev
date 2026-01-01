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

# Create necessary directories
mkdir -p grch37 grch38

# Annonars ClinVar latest version
CLINVAR_DATE="20251228"
ANNONARS_VERSION="0.44.0"

echo -e "${BLUE}Descargando Annonars ClinVar GRCh37...${NC}"
if [ ! -d "grch37/clinvar/rocksdb" ]; then
    wget -c "https://github.com/varfish-org/annonars-data-clinvar/releases/download/annonars-data-clinvar-${CLINVAR_DATE}/annonars-clinvar-minimal-grch37-${CLINVAR_DATE}+${ANNONARS_VERSION}.tar.gz" -O clinvar-grch37.tar.gz
    echo "Extrayendo..."
    tar xzf clinvar-grch37.tar.gz -C grch37/
    mv grch37/annonars-clinvar-minimal-grch37-${CLINVAR_DATE}+${ANNONARS_VERSION}/rocksdb grch37/clinvar/
    rm -rf grch37/annonars-clinvar-minimal-grch37-${CLINVAR_DATE}+${ANNONARS_VERSION}
    rm clinvar-grch37.tar.gz
    echo -e "${GREEN}✓ ClinVar GRCh37 descargado y extraído${NC}"
else
    echo -e "${YELLOW}⊙ ClinVar GRCh37 ya existe, omitiendo...${NC}"
fi

echo -e "${BLUE}Descargando Annonars ClinVar GRCh38...${NC}"
if [ ! -d "grch38/clinvar/rocksdb" ]; then
    wget -c "https://github.com/varfish-org/annonars-data-clinvar/releases/download/annonars-data-clinvar-${CLINVAR_DATE}/annonars-clinvar-minimal-grch38-${CLINVAR_DATE}+${ANNONARS_VERSION}.tar.gz" -O clinvar-grch38.tar.gz
    echo "Extrayendo..."
    tar xzf clinvar-grch38.tar.gz -C grch38/
    mv grch38/annonars-clinvar-minimal-grch38-${CLINVAR_DATE}+${ANNONARS_VERSION}/rocksdb grch38/clinvar/
    rm -rf grch38/annonars-clinvar-minimal-grch38-${CLINVAR_DATE}+${ANNONARS_VERSION}
    rm clinvar-grch38.tar.gz
    echo -e "${GREEN}✓ ClinVar GRCh38 descargado y extraído${NC}"
else
    echo -e "${YELLOW}⊙ ClinVar GRCh38 ya existe, omitiendo...${NC}"
fi

echo ""
echo -e "${YELLOW}⚠️  NOTA: Para bases de datos adicionales (gnomAD, dbSNP, CADD, etc.)${NC}"
echo -e "${YELLOW}    ejecuta: ./compile_CADD_gnomAD.sh${NC}"

cd ../..

echo ""
echo -e "${GREEN}✅ Descarga de todos los datos completada${NC}"
echo ""
echo "📊 Verificando archivos descargados..."
du -sh data/mehari/grch*/seqvars/txs.bin.zst 2>/dev/null || echo "Verificando Mehari..."
du -sh data/annonars/grch*/clinvar/rocksdb 2>/dev/null || echo "Verificando Annonars..."


echo ""
echo -e "${GREEN}✅ Proceso completado${NC}"
echo ""
echo -e "${YELLOW}⚠️  SIGUIENTES PASOS:${NC}"
echo ""
echo "1. Si no has clonado los repositorios, ejecuta:"
echo "   ./setup.sh"
echo ""
echo "2. Para bases de datos adicionales (gnomAD, CADD, etc.):"
echo "   ./compile_CADD_gnomAD.sh"
echo ""
echo "3. Para iniciar los servicios:"
echo "   docker compose up -d"
echo ""
echo "4. Para ver los logs:"
echo "   docker compose logs -f mehari"
echo "   docker compose logs -f annonars"
