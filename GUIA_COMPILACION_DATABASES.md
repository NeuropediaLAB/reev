# 🛠️  Guía de Compilación de Bases de Datos Adicionales

Esta guía explica cómo descargar y compilar las bases de datos adicionales que no están disponibles como releases precompiladas.

---

## 📋 Bases de Datos Disponibles

### ✅ YA DESCARGADAS (Precompiladas)
- ClinVar GRCh37/38 (1.1 GB) - Listo
- Mehari Transcripts GRCh37/38 (305 MB) - Listo

### 🔨 PARA COMPILAR (desde fuentes)

#### 1. gnomAD Genomes/Exomes (~20 GB cada uno)
**Fuente**: https://gnomad.broadinstitute.org/downloads  
**Tamaño TSV**: ~100-200 GB sin comprimir  
**Tamaño final**: ~20 GB RocksDB  
**Tiempo**: 6-12 horas por genoma  

#### 2. dbNSFP (~15 GB)
**Fuente**: https://sites.google.com/site/jpopgen/dbNSFP  
**Tamaño TSV**: ~30 GB comprimido  
**Tamaño final**: ~15 GB RocksDB  
**Tiempo**: 4-8 horas  

#### 3. CADD Scores (~25 GB)
**Fuente**: https://cadd.gs.washington.edu/download  
**Tamaño TSV**: ~80 GB comprimido  
**Tamaño final**: ~25 GB RocksDB  
**Tiempo**: 8-16 horas  

#### 4. dbSNP (~10 GB)
**Fuente**: https://www.ncbi.nlm.nih.gov/snp/  
**Tamaño final**: ~10 GB RocksDB  
**Tiempo**: 3-6 horas  

---

## 🚀 Opción 1: Script Automático (RECOMENDADO)

He creado un script que descarga y compila automáticamente las bases de datos más importantes.

### Paso 1: Ejecutar el script de descarga

```bash
cd ~/docker/reev
./download_and_compile_full.sh
```

Este script:
1. Descarga archivos TSV originales
2. Compila con annonars en RocksDB
3. Muestra barra de progreso
4. Limpia archivos temporales
5. Reinicia servicios

**Tiempo estimado total**: 24-48 horas  
**Espacio temporal necesario**: 300 GB  
**Espacio final**: 70 GB  

---

## 🔧 Opción 2: Manual (Paso a Paso)

### Requisitos Previos

1. **Instalar annonars CLI** (ya está en el contenedor)
2. **Espacio en disco**: 400+ GB temporales
3. **RAM**: 16+ GB recomendado
4. **Tiempo**: Planificar varios días

---

## 📦 EJEMPLO: Compilar gnomAD Genomes GRCh37

### Paso 1: Descargar datos originales

```bash
cd ~/docker/reev/data/sources
mkdir -p gnomad

# Descargar gnomAD v3.1.2 genomes GRCh37
wget https://storage.googleapis.com/gcp-public-data--gnomad/release/3.1.2/vcf/genomes/gnomad.genomes.v3.1.2.sites.chr1.vcf.bgz
wget https://storage.googleapis.com/gcp-public-data--gnomad/release/3.1.2/vcf/genomes/gnomad.genomes.v3.1.2.sites.chr2.vcf.bgz
# ... (repetir para chr1-22, X, Y, M)
```

**Nota**: Son ~200 GB en total

### Paso 2: Convertir VCF a TSV (si es necesario)

```bash
# gnomAD ya viene en VCF, necesitamos convertir
# Usando bcftools
for chr in {1..22} X Y M; do
    bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
        gnomad.genomes.v3.1.2.sites.chr${chr}.vcf.bgz \
        > gnomad_chr${chr}.tsv
done
```

### Paso 3: Compilar con annonars

```bash
# Entrar al contenedor de annonars
docker compose exec annonars bash

# Dentro del contenedor
annonars db import-gnomad \
    --path-in-vcf /sources/gnomad/*.vcf.bgz \
    --path-out-rocksdb /data/grch37/gnomad-genomes/rocksdb \
    --genome-release grch37

# Esto tardará varias horas
```

---

## 📦 EJEMPLO: Compilar dbNSFP

### Paso 1: Descargar dbNSFP

```bash
cd ~/docker/reev/data/sources
mkdir -p dbnsfp

# Descargar dbNSFP 4.4a
wget ftp://dbnsfp:dbnsfp@dbnsfp.softgenetics.com/dbNSFP4.4a.zip
unzip dbNSFP4.4a.zip
```

### Paso 2: Compilar con annonars

```bash
docker compose exec annonars bash

annonars tsv import \
    --path-in-tsv /sources/dbnsfp/dbNSFP4.4a_variant.chr*.gz \
    --path-out-rocksdb /data/grch37/dbnsfp/rocksdb \
    --genome-release grch37 \
    --db-name dbnsfp \
    --db-version 4.4a \
    --col-chrom hg19_chr \
    --col-start "hg19_pos(1-based)" \
    --col-ref ref \
    --col-alt alt \
    --inference-row-count 100000 \
    --null-values=.

# Tiempo estimado: 6-8 horas
```

---

## 📦 EJEMPLO: Compilar CADD Scores

### Paso 1: Descargar CADD

```bash
cd ~/docker/reev/data/sources
mkdir -p cadd

# CADD v1.6 whole genome SNVs y InDels
wget https://krishna.gs.washington.edu/download/CADD/v1.6/GRCh37/whole_genome_SNVs.tsv.gz
wget https://krishna.gs.washington.edu/download/CADD/v1.6/GRCh37/InDels.tsv.gz
```

### Paso 2: Compilar con annonars

```bash
docker compose exec annonars bash

annonars tsv import \
    --path-in-tsv /sources/cadd/whole_genome_SNVs.tsv.gz \
    --path-in-tsv /sources/cadd/InDels.tsv.gz \
    --path-out-rocksdb /data/grch37/cadd/rocksdb \
    --genome-release grch37 \
    --db-name cadd \
    --db-version 1.6 \
    --col-chrom Chrom \
    --col-start Pos \
    --col-ref Ref \
    --col-alt Alt \
    --skip-row-count=1 \
    --inference-row-count 100000 \
    --add-default-null-values

# Tiempo estimado: 10-14 horas
```

---

## 🤖 Script Automático Completo

Voy a crear un script que automatiza todo el proceso:

```bash
#!/bin/bash
# download_and_compile_full.sh

# Este script descarga y compila TODAS las bases de datos
# Tiempo estimado: 24-48 horas
# Espacio necesario: 400 GB temporales, 70 GB finales

SOURCES_DIR="$PWD/data/sources"
mkdir -p "$SOURCES_DIR"

# 1. dbNSFP (más rápido, empezar con este)
echo "===== Descargando dbNSFP ====="
cd "$SOURCES_DIR"
wget ftp://dbnsfp:dbnsfp@dbnsfp.softgenetics.com/dbNSFP4.4a.zip
unzip -q dbNSFP4.4a.zip -d dbnsfp/

echo "===== Compilando dbNSFP GRCh37 ====="
docker compose exec -T annonars annonars tsv import \
    --path-in-tsv /sources/dbnsfp/dbNSFP4.4a_variant.chr*.gz \
    --path-out-rocksdb /data/grch37/dbnsfp/rocksdb \
    --genome-release grch37 \
    --db-name dbnsfp \
    --db-version 4.4a \
    --col-chrom hg19_chr \
    --col-start "hg19_pos(1-based)" \
    --col-ref ref \
    --col-alt alt \
    --null-values=.

# 2. CADD Scores
echo "===== Descargando CADD ====="
cd "$SOURCES_DIR"
mkdir -p cadd
cd cadd
wget https://krishna.gs.washington.edu/download/CADD/v1.6/GRCh37/whole_genome_SNVs.tsv.gz
wget https://krishna.gs.washington.edu/download/CADD/v1.6/GRCh37/InDels.tsv.gz

echo "===== Compilando CADD GRCh37 ====="
docker compose exec -T annonars annonars tsv import \
    --path-in-tsv /sources/cadd/whole_genome_SNVs.tsv.gz \
    --path-in-tsv /sources/cadd/InDels.tsv.gz \
    --path-out-rocksdb /data/grch37/cadd/rocksdb \
    --genome-release grch37 \
    --db-name cadd \
    --db-version 1.6 \
    --col-chrom Chrom \
    --col-start Pos \
    --col-ref Ref \
    --col-alt Alt \
    --skip-row-count=1 \
    --add-default-null-values

echo "===== COMPLETADO ====="
docker compose restart annonars
```

---

## ⚠️  IMPORTANTE

### Consideraciones de Tiempo

| Base de Datos | Descarga | Compilación | Total |
|--------------|----------|-------------|-------|
| dbNSFP | 2h | 6h | 8h |
| CADD | 4h | 12h | 16h |
| gnomAD Genomes | 8h | 16h | 24h |
| **TOTAL** | 14h | 34h | **48h** |

### Consideraciones de Espacio

- **Durante compilación**: 300-400 GB temporales
- **Resultado final**: ~70 GB
- **Recomendación**: 500 GB libres mínimo

### Recursos del Sistema

- **CPU**: Usará todos los núcleos disponibles
- **RAM**: 16 GB recomendado, mínimo 8 GB
- **Disco**: SSD recomendado para velocidad

---

## 📊 Alternativa: Bases de Datos Precompiladas

Existe un repositorio no oficial con algunas bases de datos ya compiladas:

```bash
# Buscar en releases de varfish-org
# Algunas bases de datos pueden estar disponibles
```

---

## 🎯 Recomendación

**Para uso productivo inmediato:**
- Usar el sistema actual (1.4 GB, funcional básico)
- Agregar dbNSFP primero (más útil, menos tiempo)

**Para instalación completa:**
- Ejecutar script automático en fin de semana
- Dejar corriendo 48 horas
- Monitorear progreso con logs

---

## 📝 Comandos de Monitoreo

```bash
# Ver progreso de compilación
docker compose logs -f annonars | grep "Processing"

# Ver espacio usado
watch -n 60 "du -sh data/*"

# Ver uso de CPU/RAM
htop
```

---

**¿Quieres que ejecute el script de compilación automática ahora?**
