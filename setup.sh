#!/bin/bash
set -e

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                                                                      ║"
echo "║              🚀 REEV PLATFORM - SETUP SCRIPT 🚀                     ║"
echo "║                                                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# Colores
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
NC='\\033[0m'

echo "📋 Este script configurará REEV Platform paso a paso"
echo ""

# Verificar Docker
echo "1️⃣  Verificando Docker..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker no encontrado${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker instalado${NC}"

# Verificar Docker Compose
echo "2️⃣  Verificando Docker Compose..."
if ! docker compose version &> /dev/null; then
    echo -e "${RED}❌ Docker Compose no encontrado${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker Compose instalado${NC}"

# Advertencia sobre datos
echo ""
echo -e "${YELLOW}⚠️  IMPORTANTE: DESCARGA DE BASES DE DATOS${NC}"
echo ""
echo "REEV requiere bases de datos grandes (~50 GB total):"
echo "  • Annonars DB: ~30 GB (gnomAD, ClinVar, dbNSFP, etc.)"
echo "  • Mehari DB: ~10 GB (transcripts RefSeq/ENSEMBL)"
echo "  • Otros: ~10 GB"
echo ""
echo "Opciones:"
echo "  A) Descargar bases de datos completas (recomendado para producción)"
echo "  B) Usar bases de datos de ejemplo/demo (rápido, limitado)"
echo "  C) Saltar por ahora y configurar manualmente después"
echo ""
read -p "Elige opción (A/B/C): " OPTION

case $OPTION in
    [Aa]* )
        echo ""
        echo "📥 Descargando bases de datos completas..."
        echo "⏰ ADVERTENCIA: Esto tomará varias horas dependiendo de tu conexión"
        echo ""
        read -p "¿Continuar? (s/n): " CONTINUE
        if [[ $CONTINUE =~ ^[Ss]$ ]]; then
            # Descargar Annonars DB
            echo "Descargando Annonars databases..."
            mkdir -p data/annonars
            # TODO: URLs de descarga oficial cuando estén disponibles
            echo "⚠️  Por favor descarga manualmente desde:"
            echo "   https://github.com/varfish-org/annonars/releases"
            
            # Descargar Mehari DB
            echo "Descargando Mehari databases..."
            mkdir -p data/mehari
            echo "⚠️  Por favor descarga manualmente desde:"
            echo "   https://github.com/varfish-org/mehari-data-tx/releases"
        fi
        ;;
    [Bb]* )
        echo "📦 Configurando bases de datos demo..."
        mkdir -p data/annonars data/mehari
        echo "⚠️  Modo demo: funcionalidad limitada"
        ;;
    [Cc]* )
        echo "⏭️  Saltando descarga de bases de datos"
        echo "📝 Recuerda configurar las bases de datos antes de usar REEV"
        ;;
    * )
        echo "Opción inválida"
        exit 1
        ;;
esac

echo ""
echo "3️⃣  Construyendo imágenes Docker..."
echo "⏰ Esto puede tomar 10-30 minutos..."
docker compose build

echo ""
echo "4️⃣  Iniciando servicios..."
docker compose up -d

echo ""
echo "5️⃣  Esperando a que los servicios estén listos..."
sleep 10

echo ""
echo "6️⃣  Verificando estado..."
docker compose ps

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                                                                      ║"
echo "║              ✅ SETUP COMPLETADO ✅                                  ║"
echo "║                                                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  https://reev.readthedocs.io"
echo ""

# Function to get service URL
get_service_url() {
    local service_name=$1
    local internal_port=$2
    local port_mapping=$(docker compose port $service_name $internal_port)
    if [[ -n "$port_mapping" ]]; then
        echo "http://$port_mapping"
    else
        echo "URL no disponible"
    fi
}

echo "🌐 URLs de acceso:"
echo "  • REEV Frontend: $(get_service_url reev-frontend 80)"
echo "  • Annonars API:  $(get_service_url annonars 8080)"
echo "  • Mehari API:    $(get_service_url mehari 8080)"

echo ""
echo "📊 Para ver logs:"
echo "  docker compose logs -f"
echo ""
echo "🛑 Para detener:"
echo "  docker compose down"
echo ""
echo "📖 Documentación:"
echo "  https://reev.readthedocs.io"
echo ""
