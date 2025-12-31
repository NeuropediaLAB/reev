# 🧬 REEV - Automated Database Management System

Sistema automatizado de gestión y actualización de bases de datos genómicas para la plataforma REEV (Research Environment for Evaluating Variants).

## 📋 Descripción

Este repositorio contiene scripts y configuraciones para:
- Despliegue automatizado de REEV con Docker Compose
- Descarga inicial de bases de datos genómicas
- Actualización automática diaria de bases de datos
- Compilación de bases de datos desde fuentes originales
- Monitoreo y mantenimiento del sistema

## 🚀 Características

- ✅ **Actualización automática diaria** (ClinVar, Mehari Transcripts)
- ✅ **Gestión de backups** automática antes de cada actualización
- ✅ **Limpieza automática** de backups antiguos (>7 días)
- ✅ **Logs detallados** de todas las operaciones
- ✅ **Sistema de bloqueo** para prevenir ejecuciones simultáneas
- ✅ **Compilación de CADD** desde archivos TSV originales
- ✅ **Descarga de gnomAD** precompilado

## 📦 Bases de Datos Soportadas

| Base de Datos | Tamaño | Actualización | Fuente |
|--------------|--------|---------------|--------|
| **ClinVar** | ~1 GB | Automática (semanal) | [varfish-org/annonars-data-clinvar](https://github.com/varfish-org/annonars-data-clinvar) |
| **Mehari Transcripts** | ~300 MB | Automática (mensual) | [varfish-org/mehari-data-tx](https://github.com/varfish-org/mehari-data-tx) |
| **CADD** | ~25 GB | Manual | [CADD v1.7](https://krishna.gs.washington.edu/download/CADD/) |
| **gnomAD** | ~36 GB | Manual | [varfish-org/annonars-data-gnomad](https://github.com/varfish-org/annonars-data-gnomad) |

## 🛠️ Instalación

### Requisitos previos

- Docker y Docker Compose
- Git
- jq (para procesamiento JSON)
- Mínimo 100 GB de espacio en disco
- 8 GB RAM recomendado

### Instalación rápida

```bash
# Clonar el repositorio
git clone https://github.com/TU_USUARIO/reev.git
cd reev

# Ejecutar setup inicial
./setup.sh

# Iniciar servicios
docker compose up -d

# Configurar actualización automática
crontab -e
# Añadir: 0 3 * * * cd ~/docker/reev && ./auto_update_databases.sh >> logs/cron.log 2>&1
```

## 📚 Documentación

- **[ACTUALIZACION_AUTOMATICA.md](ACTUALIZACION_AUTOMATICA.md)** - Guía completa del sistema de actualización
- **[ESTADO_FINAL.md](ESTADO_FINAL.md)** - Estado actual del sistema
- **[COMPILACION_EN_PROGRESO.md](COMPILACION_EN_PROGRESO.md)** - Guía de compilación de bases de datos
- **[GUIA_COMPILACION_DATABASES.md](GUIA_COMPILACION_DATABASES.md)** - Guía detallada de compilación manual

## 🤖 Scripts Principales

### Actualización Automática

```bash
# Script de actualización diaria (se ejecuta automáticamente vía cron)
./auto_update_databases.sh
```

Verifica y descarga automáticamente:
- ClinVar GRCh37/38
- Mehari Transcripts GRCh37/38

### Actualización Manual de gnomAD

```bash
# Actualizar gnomAD (bases de datos grandes ~36 GB)
./update_gnomad.sh
```

### Compilación Inicial

```bash
# Compilar CADD + descargar gnomAD
./compile_CADD_gnomAD.sh

# Monitorear progreso
./monitor_compilation.sh
```

## ⚙️ Configuración

### Docker Compose

El sistema utiliza los siguientes servicios:

- **PostgreSQL** (puerto 5432) - Base de datos principal
- **Redis** (puerto 6379) - Cache
- **Annonars** (puerto 3001) - API de anotaciones
- **Mehari** (puerto 3002) - API de consecuencias moleculares
- **REEV Frontend** (puerto 3003) - Interfaz web

### Variables de Entorno

```yaml
# PostgreSQL
POSTGRES_USER: reev
POSTGRES_PASSWORD: reev_password
POSTGRES_DB: reev

# Frontend
VITE_API_BASE_URL: http://192.168.0.105:3000
VITE_ANNONARS_URL: http://192.168.0.105:3001
VITE_MEHARI_URL: http://192.168.0.105:3002
```

## 📊 Estructura del Proyecto

```
reev/
├── docker-compose.yml          # Configuración Docker
├── auto_update_databases.sh    # Actualización automática
├── update_gnomad.sh           # Actualización manual gnomAD
├── compile_CADD_gnomAD.sh     # Compilación inicial
├── monitor_compilation.sh     # Monitor de compilación
├── setup.sh                   # Setup inicial
├── .db_versions.json          # Versiones de bases de datos
├── data/                      # Bases de datos (gitignored)
│   ├── annonars/
│   ├── mehari/
│   └── sources/
├── logs/                      # Logs (gitignored)
│   ├── updates/
│   └── cron.log
├── annonars/                  # Código fuente Annonars
├── mehari/                    # Código fuente Mehari
└── reev-frontend/            # Código fuente Frontend
```

## 🔄 Sistema de Actualización Automática

### Funcionamiento

1. **Verificación diaria** (03:00 AM via cron)
2. **Consulta APIs** de GitHub para últimas versiones
3. **Compara** con versiones instaladas
4. **Descarga** si hay actualizaciones disponibles
5. **Crea backup** de versión anterior
6. **Actualiza** bases de datos
7. **Reinicia servicios** afectados
8. **Limpia backups** antiguos (>7 días)
9. **Registra** todo en logs

### Configuración Cron

```bash
# Ver tarea configurada
crontab -l | grep auto_update

# Editar horario
crontab -e

# Formatos ejemplo:
0 3 * * *     # 03:00 diario
0 */6 * * *   # Cada 6 horas
0 0 * * 0     # Domingos a medianoche
```

## 📝 Logs

```bash
# Ver log de actualizaciones de hoy
cat logs/updates/update_$(date +%Y%m%d).log

# Ver logs de cron
tail -f logs/cron.log

# Ver versiones actuales
cat .db_versions.json | jq

# Historial de actualizaciones
ls -lt logs/updates/
```

## 🛡️ Seguridad y Backups

- **Backups automáticos** antes de cada actualización
- **Formato**: `nombre.backup.YYYYMMDD`
- **Retención**: 7 días
- **Lock file** previene ejecuciones simultáneas
- **Logs completos** de todas las operaciones

### Restaurar desde backup

```bash
# Ejemplo: restaurar ClinVar GRCh37
cd data/grch37
rm -rf clinvar
mv clinvar.backup.20241231 clinvar
docker compose restart annonars
```

## 🚨 Solución de Problemas

### Verificar servicios

```bash
docker compose ps
docker compose logs --tail=50 annonars mehari
```

### Reiniciar actualización fallida

```bash
# El script usa wget -c, así que se puede reanudar
cd ~/docker/reev
./auto_update_databases.sh
```

### Limpiar espacio

```bash
# Limpiar backups antiguos
find data -name "*.backup.*" -mtime +7 -delete

# Limpiar logs antiguos
find logs -name "*.log" -mtime +30 -delete
```

## 🤝 Contribuir

Las contribuciones son bienvenidas. Por favor:

1. Fork el proyecto
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m Add some AmazingFeature`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## 📄 Licencia

Este proyecto está bajo la licencia MIT. Ver el archivo `LICENSE` para más detalles.

## 🔗 Enlaces Útiles

- [REEV Documentation](https://reev.readthedocs.io)
- [Annonars GitHub](https://github.com/varfish-org/annonars)
- [Mehari GitHub](https://github.com/varfish-org/mehari)
- [VarFish Organization](https://github.com/varfish-org)

## 👥 Autores

- Sistema de actualización automática - Configurado el 31/12/2024

## 📊 Estado del Proyecto

- ✅ Sistema base funcionando
- ✅ Actualización automática activa
- ✅ Documentación completa
- 🔄 Compilación de CADD en progreso
- ⏳ Pendiente: Integración completa de dbNSFP

## 🎯 Roadmap

- [ ] Añadir soporte para dbNSFP
- [ ] Notificaciones por email
- [ ] Dashboard web de monitoreo
- [ ] Integración con Slack/Discord
- [ ] Pruebas automatizadas
- [ ] CI/CD con GitHub Actions

---

**Desarrollado con ❤️ para la comunidad de genómica**
