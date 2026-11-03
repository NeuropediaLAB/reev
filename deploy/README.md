# Despliegue de REEV (Khazad-dum)

Este directorio sustituye al repositorio `NeuropediaLAB/reev-deploy`, que queda
obsoleto: el despliegue vive ahora aquí, junto al código del que depende, para que
imagen y compose no se puedan desincronizar.

## Contenido

| Fichero | Para qué |
| --- | --- |
| `docker-compose.yml` | stack completo (17 servicios: backend, celery, postgres, annonars, mehari, dotty, viguno, cada-prio, auto-acmg, jbrowse2, nginx, monitor, pgadmin, flower) |
| `.env` | **no versionado**; crear desde `.env.example` con las credenciales reales |
| `monitor/` | dashboard de bases de datos (:8300) y lanzador de actualizaciones |
| `download-smart.sh` | descarga/reanudación de los paquetes annonars desde el S3 de CUBI (aria2c multiparte) |
| `update-databases.sh` | comprobación semanal de **todas** las bases: ClinVar (grch37/grch38), HPO, huecos de annonars; informa de mehari/cada-prio/dotty/seqrepo |
| `systemd/` | `reev-update-databases.service` + `.timer` (domingos 04:30) |
| `docs/vus-monitoring-plan.md` | hallazgos y plan de monitorización de VUS |
| `docs/reev-databases.md` | inventario de bases de datos y rutas |

## Rutina

```bash
# imagen del código (desde la raíz del repo)
TAG=neuropedialab/reev:0.6.0-neuropediaN ./utils/docker/build-fork.sh

# desplegar
cd deploy && docker compose up -d

# estado de las bases y actualización manual
bash update-databases.sh            # informe, no cambia nada
bash update-databases.sh --apply    # descarga e instala lo que esté más nuevo
```

Los datos **no** están en el repositorio: viven en `/mnt/datos-1tb/reev` (annonars,
mehari, dotty/seqrepo, hpo, cada-prio) y los volúmenes de postgres/redis/rabbitmq/
pgadmin en `/home/arkantu/produccion/reev/volumes`.

## Dos capas de actualización automática

1. **Datos** (host): `reev-update-databases.timer`, semanal. Instala ClinVar nuevo,
   HPO y repone paquetes annonars; reinicia annonars/viguno si cambia algo.
2. **Reanálisis** (aplicación): `reev-celery-beat` lanza `poll_data_versions` cada 6 h,
   que registra la versión de cada base, y `reanalyze_all_cases` los domingos 03:41.
   Las tareas de `app.casearchive.tasks` deben estar enrutadas a `main-queue`
   (`task_routes`), o se publican en una cola sin consumidor y se pierden.

## Credenciales

`POSTGRES_PASSWORD`, `FIRST_SUPERUSER_PASSWORD`, `SECRET_KEY` y `FLOWER_BASIC_AUTH`
se leen de `.env`. Nunca deben volver al compose: este repositorio es público y las
versiones antiguas de `reev-deploy` dejaron la contraseña de Postgres en el historial.
