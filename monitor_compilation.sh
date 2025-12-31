#!/bin/bash

CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

while true; do
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Monitor de Compilación - REEV Databases      ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}📊 Espacio en Disco:${NC}"
    df -h . | tail -1
    echo ""
    
    echo -e "${BLUE}📁 Tamaños de Datos:${NC}"
    du -sh data/sources/* 2>/dev/null | while read size path; do
        echo "  Fuentes: $size ($path)"
    done
    du -sh data/grch*/* 2>/dev/null | while read size path; do
        name=$(basename "$path")
        genome=$(basename $(dirname "$path"))
        echo "  $genome/$name: $size"
    done
    echo ""
    
    echo -e "${BLUE}🔄 Estado de Servicios:${NC}"
    docker compose ps --format "table {{.Name}}\t{{.Status}}" | grep -E "NAME|annonars|mehari"
    echo ""
    
    echo -e "${BLUE}📝 Últimas Líneas de Logs:${NC}"
    echo ""
    
    if [ -f logs/dbnsfp_grch37.log ]; then
        echo -e "${YELLOW}dbNSFP GRCh37:${NC}"
        tail -3 logs/dbnsfp_grch37.log 2>/dev/null | sed "s/^/  /"
        echo ""
    fi
    
    if [ -f logs/dbnsfp_grch38.log ]; then
        echo -e "${YELLOW}dbNSFP GRCh38:${NC}"
        tail -3 logs/dbnsfp_grch38.log 2>/dev/null | sed "s/^/  /"
        echo ""
    fi
    
    if [ -f logs/cadd_grch37.log ]; then
        echo -e "${YELLOW}CADD GRCh37:${NC}"
        tail -3 logs/cadd_grch37.log 2>/dev/null | sed "s/^/  /"
        echo ""
    fi
    
    echo -e "${CYAN}──────────────────────────────────────────────${NC}"
    echo -e "${GREEN}Actualizando cada 30 segundos... (Ctrl+C para salir)${NC}"
    
    sleep 30
done
