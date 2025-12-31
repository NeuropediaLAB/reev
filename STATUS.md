# 📊 REEV Platform - Estado Actual

**Fecha**: 31 Diciembre 2024 01:15  
**Servidor**: 192.168.0.105:4001

---

## ✅ Servicios Funcionando

| Servicio | Estado | Puerto | URL |
|----------|--------|--------|-----|
| **PostgreSQL** | ✅ Running | 5432 | localhost:5432 |
| **Redis** | ✅ Running | 6379 | localhost:6379 |
| **Frontend** | ✅ Running | 3003 | http://192.168.0.105:3003 |

## ❌ Servicios Detenidos (Requieren Datos)

| Servicio | Estado | Razón |
|----------|--------|-------|
| **Annonars** | ⏹️ Stopped | Bases de datos vacías (RocksDB) |
| **Mehari** | ⏹️ Stopped | Archivos txs.bin.zst vacíos |

---

## 🐛 Problemas Identificados

### 1. Archivos de Datos Vacíos

#### Mehari
```
data/mehari/grch37/seqvars/txs.bin.zst    0 bytes (debe ser ~5-8 GB)
data/mehari/grch38/seqvars/txs.bin.zst    0 bytes (debe ser ~5-8 GB)
```

**Error original:**
```
Error: failed to read file /data/grch37/seqvars/txs.bin.zst: incomplete frame
```

#### Annonars
```
data/annonars/grch37/clinvar/rocksdb/     4KB (debe ser ~15-20 GB)
data/annonars/grch38/clinvar/rocksdb/     4KB (debe ser ~15-20 GB)
```

**Error original:**
```
Error: problem opening database: IO error: No such file or directory: 
/data/grch37/clinvar/rocksdb/CURRENT
```

### 2. Setup Script Incompleto

El script `setup.sh` creó la estructura de directorios pero no descargó las bases de datos.

---

## 🔧 Soluciones Implementadas

### 1. Documentación Creada

- ✅ `DATA_SETUP.md` - Guía detallada de configuración
- ✅ `download_data.sh` - Script automático de descarga
- ✅ `STATUS.md` - Este archivo de estado

### 2. Servicios Organizados

Los servicios fueron detenidos de manera controlada para evitar restart loops:

```bash
docker compose down annonars mehari
```

Solo quedan activos los servicios que funcionan correctamente.

### 3. Script de Descarga

Creado `download_data.sh` que:
- ✅ Verifica espacio en disco (requiere 20+ GB)
- ✅ Descarga datos de Mehari desde GitHub releases
- ✅ Extrae y organiza automáticamente
- ✅ Reinicia servicios al completar

---

## 🚀 Próximos Pasos

### Opción A: Descarga Automática (Recomendado)

```bash
cd ~/docker/reev
./download_data.sh
```

**Tiempo estimado**: 30-60 minutos  
**Descarga**: ~15 GB (solo Mehari)  
**Resultado**: Mehari funcionará, Annonars seguirá sin datos

### Opción B: Descarga Manual Completa

```bash
# Ver instrucciones detalladas en:
cat DATA_SETUP.md
```

Incluye tanto Mehari como Annonars (~50 GB total)

### Opción C: Solo Frontend (Estado Actual)

El frontend está accesible en:
- **URL**: http://192.168.0.105:3003
- **Funcionalidad**: Limitada (sin backend de búsqueda)

---

## 📊 Recursos del Sistema

### Espacio en Disco
```
Disponible: 41 GB
Necesario mínimo: 20 GB (Mehari solo)
Necesario completo: 60 GB (Mehari + Annonars)
Estado: ✅ Suficiente para Mehari
        ⚠️ Justo para instalación completa
```

### Memoria
```
Servicios activos: ~500 MB (PostgreSQL + Redis + Frontend)
Con Mehari: ~2 GB
Con Annonars: ~4 GB
Total esperado: ~6-8 GB RAM
```

---

## 📝 Comandos Útiles

### Ver Estado
```bash
docker compose ps
docker compose logs -f
```

### Iniciar Descarga
```bash
./download_data.sh
```

### Verificar Progreso
```bash
# Durante descarga
watch -n 5 "du -sh data/mehari/grch*"

# Ver logs
docker compose logs -f mehari annonars
```

### Reiniciar Todo
```bash
docker compose restart
```

---

## 🔗 Enlaces Útiles

- **Frontend**: http://192.168.0.105:3003
- **Annonars API** (cuando funcione): http://192.168.0.105:3001
- **Mehari API** (cuando funcione): http://192.168.0.105:3002
- **PostgreSQL**: localhost:5432
- **Redis**: localhost:6379

---

## 📞 Documentación

- `README.md` - Documentación general de REEV
- `DATA_SETUP.md` - Guía de configuración de datos
- `download_data.sh` - Script de descarga automática
- `STATUS.md` - Este archivo (estado actual)

---

**Conclusión**: El sistema está parcialmente funcional. PostgreSQL, Redis y Frontend están OK. 
Mehari y Annonars necesitan descarga de bases de datos (~15-50 GB dependiendo de la opción).

Ejecuta `./download_data.sh` para iniciar la descarga automática de datos esenciales.
