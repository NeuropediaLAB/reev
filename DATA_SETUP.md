# 📥 Configuración de Bases de Datos para REEV

## 🚨 Estado Actual

Los contenedores `annonars` y `mehari` están fallando porque las bases de datos no están descargadas.

## 📋 Archivos Necesarios

### Mehari (Consecuencias Moleculares)

Los siguientes archivos deben descargarse en `data/mehari/`:

```
data/mehari/
├── grch37/
│   └── seqvars/
│       ├── txs.bin.zst          # ❌ Vacío (0 bytes)
│       ├── clinvar/rocksdb/     # ❌ Vacío (4KB)
│       └── frequencies/rocksdb/ # ❌ Vacío (4KB)
└── grch38/
    └── seqvars/
        ├── txs.bin.zst          # ❌ Vacío (0 bytes)
        ├── clinvar/rocksdb/     # ❌ Vacío (4KB)
        └── frequencies/rocksdb/ # ❌ Vacío (4KB)
```

**Tamaño esperado**: ~10-15 GB

### Annonars (Anotaciones Genómicas)

Los siguientes archivos deben descargarse en `data/annonars/`:

```
data/annonars/
├── grch37/
│   └── clinvar/rocksdb/  # ❌ Vacío (4KB)
└── grch38/
    └── clinvar/rocksdb/  # ❌ Vacío (4KB)
```

**Tamaño esperado**: ~30-40 GB (gnomAD, ClinVar, dbNSFP, etc.)

## 🔗 Fuentes de Descarga

### Opción 1: Releases Oficiales

#### Mehari Transcripts Data
Repositorio: https://github.com/varfish-org/mehari-data-tx/releases

Buscar archivos:
- `mehari-data-txs-grch37-*.tar.gz`
- `mehari-data-txs-grch38-*.tar.gz`

#### Annonars Database
Repositorio: https://github.com/varfish-org/annonars/releases

Buscar archivos:
- `annonars-data-grch37-*.tar.gz`
- `annonars-data-grch38-*.tar.gz`

### Opción 2: Datos de Ejemplo (Demo)

Para testing rápido, puedes crear bases de datos vacías funcionales:

```bash
# Este script está en desarrollo
# Por ahora los servicios permanecerán detenidos
```

## 📦 Proceso de Descarga

### 1. Descargar Mehari Data

```bash
cd ~/docker/reev/data/mehari

# GRCh37
wget https://github.com/varfish-org/mehari-data-tx/releases/download/v0.3.0/mehari-data-txs-grch37-0.3.0.tar.gz
tar xzf mehari-data-txs-grch37-0.3.0.tar.gz
rm mehari-data-txs-grch37-0.3.0.tar.gz

# GRCh38
wget https://github.com/varfish-org/mehari-data-tx/releases/download/v0.3.0/mehari-data-txs-grch38-0.3.0.tar.gz
tar xzf mehari-data-txs-grch38-0.3.0.tar.gz
rm mehari-data-txs-grch38-0.3.0.tar.gz
```

### 2. Descargar Annonars Data

```bash
cd ~/docker/reev/data/annonars

# Visita: https://github.com/varfish-org/annonars/releases
# Descarga los archivos correspondientes según versión disponible
```

### 3. Verificar Descarga

```bash
cd ~/docker/reev

# Verificar tamaños
du -sh data/mehari/grch*/seqvars/txs.bin.zst
du -sh data/annonars/grch*/clinvar/rocksdb
```

### 4. Reiniciar Servicios

```bash
cd ~/docker/reev
docker compose up -d annonars mehari
docker compose logs -f annonars mehari
```

## ⚡ Solución Rápida (Solo para Testing)

Si quieres probar REEV sin descargar todas las bases de datos:

### Frontend Funcional

El frontend ya está funcionando en puerto 3003, pero las búsquedas fallarán sin los datos backend.

### APIs Mock (Próximamente)

Se puede crear un mock server que devuelva datos de ejemplo.

## 📊 Espacio en Disco Necesario

```bash
# Verificar espacio disponible
df -h ~/docker/reev/data

# Espacio necesario aproximado:
# - Mehari: 15 GB
# - Annonars: 40 GB
# - PostgreSQL: 5 GB
# - Total: ~60 GB mínimo
```

## 🐛 Errores Actuales

### reev-mehari
```
Error: failed to read file /data/grch37/seqvars/txs.bin.zst: incomplete frame
```
**Causa**: Archivo vacío (0 bytes)

### reev-annonars
```
Error: problem opening database: IO error: No such file or directory: 
/data/grch37/clinvar/rocksdb/CURRENT
```
**Causa**: Base de datos RocksDB vacía

## ✅ Verificar Estado

```bash
cd ~/docker/reev

# Ver servicios
docker compose ps

# Ver logs
docker compose logs annonars mehari

# Verificar archivos
find data/ -type f -size +100M
```

## 📞 Ayuda Adicional

- Documentación Mehari: https://github.com/varfish-org/mehari
- Documentación Annonars: https://github.com/varfish-org/annonars
- REEV Docs: https://reev.readthedocs.io

---

**Nota**: Una vez descargadas las bases de datos, los servicios iniciarán automáticamente.
