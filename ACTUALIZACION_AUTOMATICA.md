# 🔄 Sistema de Actualización Automática de Bases de Datos

**Configurado**: 31 Diciembre 2024  
**Ejecución**: Diaria a las 03:00 AM  
**Estado**: ✅ Activo

---

## 📋 Resumen

El sistema verifica automáticamente cada día si hay nuevas versiones de:
- ✅ **ClinVar** - Actualización automática
- ✅ **Mehari Transcripts** - Actualización automática
- ⚠️  **gnomAD** - Notificación (actualización manual)
- ⚠️  **CADD** - Solo notificación

---

## 🤖 Script Principal

**Archivo**: `~/docker/reev/auto_update_databases.sh`

### Funcionalidades

1. **Verificación de versiones**
   - Consulta APIs de GitHub para últimas releases
   - Compara con versiones instaladas
   - Registra en `.db_versions.json`

2. **Descarga automática** (solo bases pequeñas)
   - ClinVar GRCh37/38 (~1 GB)
   - Mehari Transcripts GRCh37/38 (~300 MB)

3. **Backup automático**
   - Crea backup antes de actualizar
   - Elimina backups antiguos (>7 días)

4. **Reinicio de servicios**
   - Solo si hubo actualizaciones
   - Docker compose restart automático

5. **Logging completo**
   - `logs/updates/update_YYYYMMDD.log`
   - Registro de todas las operaciones

---

## ⏰ Configuración Cron

```bash
# Ver configuración actual
crontab -l | grep auto_update

# Editar horario (cambiar de 03:00 a otro)
crontab -e
# Modificar: 0 3 * * * a: 0 [HORA] * * *
```

### Formatos de horario

```
0 3 * * *    # 03:00 diario
0 */6 * * *  # Cada 6 horas
0 0 * * 0    # Domingos a medianoche
30 2 * * *   # 02:30 diario
```

---

## 📝 Logs de Actualización

### Ver último log
```bash
ls -lt ~/docker/reev/logs/updates/ | head -5
cat ~/docker/reev/logs/updates/update_$(date +%Y%m%d).log
```

### Ver logs de cron
```bash
tail -f ~/docker/reev/logs/cron.log
```

### Buscar actualizaciones realizadas
```bash
grep "Nueva versión" ~/docker/reev/logs/updates/*.log
```

---

## 🔧 Actualización Manual

### Ejecutar verificación ahora
```bash
cd ~/docker/reev
./auto_update_databases.sh
```

### Actualizar gnomAD manualmente
```bash
cd ~/docker/reev
./update_gnomad.sh
```

### Forzar actualización de todo
```bash
# Borrar versiones conocidas
rm ~/docker/reev/.db_versions.json
./auto_update_databases.sh
```

---

## 📊 Archivo de Versiones

**Ubicación**: `~/docker/reev/.db_versions.json`

```json
{
  "clinvar": "annonars-data-clinvar-20251228",
  "mehari": "v0.11.0",
  "gnomad": "none",
  "cadd": "1.7",
  "last_check": "2024-12-31"
}
```

### Ver versiones actuales
```bash
cat ~/docker/reev/.db_versions.json | jq
```

---

## 🔔 Notificaciones

El script puede enviar notificaciones del sistema si está disponible `notify-send`.

### Habilitar notificaciones por email (opcional)
Añadir al final de `auto_update_databases.sh`:

```bash
if [ $UPDATES_AVAILABLE -gt 0 ]; then
    echo "Se actualizaron $UPDATES_AVAILABLE bases de datos" | \
        mail -s "REEV: Bases de datos actualizadas" tu@email.com
fi
```

---

## 🛡️  Seguridad

### Lock file
- Previene ejecuciones simultáneas
- Ubicación: `~/docker/reev/.update_lock`
- Se limpia automáticamente

### Backups
- Se crean antes de cada actualización
- Formato: `nombre.backup.YYYYMMDD`
- Se eliminan después de 7 días

### Restaurar backup
```bash
# Ejemplo: restaurar ClinVar GRCh37
cd ~/docker/reev/data/grch37
rm -rf clinvar
mv clinvar.backup.20241231 clinvar
docker compose restart annonars
```

---

## 📈 Monitoreo

### Verificar si cron está funcionando
```bash
# Ver últimas ejecuciones
grep auto_update /var/log/syslog | tail -20

# O en sistemas con systemd journal
journalctl -u cron | grep auto_update | tail -20
```

### Ver espacio usado
```bash
du -sh ~/docker/reev/data/*
```

### Verificar servicios después de actualización
```bash
cd ~/docker/reev
docker compose ps
docker compose logs --tail=50 annonars mehari
```

---

## ⚙️  Configuración Avanzada

### Cambiar bases de datos a verificar

Editar `auto_update_databases.sh` y comentar/descomentar secciones:

```bash
# Deshabilitar verificación de Mehari
# log "📋 Verificando Mehari Transcripts..."
# ... (comentar toda la sección)

# Habilitar actualización automática de gnomAD (no recomendado)
# Modificar la sección gnomAD para descargarlo automáticamente
```

### Añadir nuevas bases de datos

Copiar una sección existente y modificar URLs y nombres:

```bash
# Ejemplo: añadir dbSNP
log "📋 Verificando dbSNP..."
DBSNP_URL="https://..."
# ... resto de la lógica
```

---

## 🚨 Solución de Problemas

### El script no se ejecuta
```bash
# Verificar que cron está corriendo
sudo systemctl status cron

# Ver errores en el log
tail -50 ~/docker/reev/logs/cron.log
```

### Descarga fallida
```bash
# Verificar conectividad
curl -I https://api.github.com/repos/varfish-org/annonars-data-clinvar/releases/latest

# Reintentar manualmente
cd ~/docker/reev
./auto_update_databases.sh
```

### Espacio insuficiente
```bash
# Limpiar backups antiguos manualmente
find ~/docker/reev/data -name "*.backup.*" -delete

# Limpiar logs antiguos
find ~/docker/reev/logs/updates -name "*.log" -mtime +30 -delete
```

### Servicios no reinician
```bash
# Reiniciar manualmente
cd ~/docker/reev
docker compose restart annonars mehari

# Ver logs de error
docker compose logs --tail=100
```

---

## 📊 Estadísticas de Actualizaciones

### Frecuencia esperada de actualizaciones

| Base de Datos | Frecuencia | Tamaño | Impacto |
|--------------|-----------|--------|---------|
| ClinVar | Semanal | ~1 GB | Bajo |
| Mehari | Mensual | ~300 MB | Bajo |
| gnomAD | Trimestral | ~36 GB | Alto |
| CADD | Anual | ~90 GB | Muy Alto |

### Tiempo de ejecución

- Sin actualizaciones: ~2 minutos
- Con ClinVar: ~15 minutos
- Con Mehari: ~5 minutos
- Con ambos: ~20 minutos

---

## 📞 Scripts Disponibles

| Script | Propósito | Ejecución |
|--------|-----------|-----------|
| `auto_update_databases.sh` | Actualización automática diaria | Cron |
| `update_gnomad.sh` | Actualizar gnomAD manualmente | Manual |
| `compile_CADD_gnomAD.sh` | Compilar CADD + gnomAD inicial | Manual |
| `download_all_data.sh` | Descarga inicial completa | Manual |
| `monitor_compilation.sh` | Monitorear compilaciones | Manual |

---

## ✅ Comandos Útiles Rápidos

```bash
# Ver última actualización
cat ~/docker/reev/.db_versions.json | jq

# Ejecutar ahora
~/docker/reev/auto_update_databases.sh

# Ver log de hoy
cat ~/docker/reev/logs/updates/update_$(date +%Y%m%d).log

# Ver próxima ejecución cron
crontab -l | grep auto_update

# Deshabilitar temporalmente
crontab -e  # Comentar la línea con #

# Ver historial de actualizaciones
ls -lth ~/docker/reev/data/grch37/*/backup.* 2>/dev/null

# Espacio total usado
du -sh ~/docker/reev/data
```

---

## 🎯 Resumen

- ✅ **Automático**: Verifica diariamente a las 03:00
- ✅ **Seguro**: Crea backups antes de actualizar
- ✅ **Eficiente**: Solo descarga lo necesario
- ✅ **Monitoreado**: Logs completos de todas las operaciones
- ✅ **Flexible**: Fácil de personalizar y extender

**El sistema está listo y funcionando automáticamente** 🚀

