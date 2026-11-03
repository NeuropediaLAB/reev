# REEV — Laboratorio Genómico (datos y bases)

**Stack:** `/home/arkantu/produccion/reev/` (compose + `.env`)
**Datos:** `/mnt/datos-1tb/reev/` (NVMe de datos del escritorio; migrado desde .193 el 2026-11-02)
**Nota:** documento rescatado de `SERVICES_DOCUMENTATION.md` (raíz, obsoleto y eliminado 2026-10-04):
las rutas antiguas (`~/workspace/docker/reev/`, `produccion/genomic-stack/reev/`) ya no existen.
La sección de servicios/versión de disco sigue siendo válida.

---

## Servicios del stack

| Contenedor | Imagen | Puerto | Función |
|---|---|---|---|
| reev-backend | ghcr.io/bihealth/reev:main | 127.0.0.1:8082→8080 | Aplicación principal REEV |
| reev-celery-worker | ghcr.io/bihealth/reev:main | interno | Worker tareas asíncronas |
| reev-celery-beat | ghcr.io/bihealth/reev:main | interno | Scheduler tareas periódicas |
| reev-annonars | ghcr.io/varfish-org/annonars:latest | interno | Anotación variantes (gnomAD, CADD, ClinVar…) |
| reev-mehari | ghcr.io/varfish-org/mehari:latest | interno | Anotación transcritos / efectos variantes |
| reev-viguno | ghcr.io/varfish-org/viguno:latest | interno | Relaciones fenotipo/gen (HPO) |
| reev-dotty | ghcr.io/bihealth/dotty:latest | interno | Traducción notación c./n./g. a SPDI |
| reev-cada-prio | ghcr.io/bihealth/cada-prio:main | interno | Priorización basada en fenotipo |
| reev-auto-acmg | ghcr.io/bihealth/auto-acmg:main | interno | Clasificación ACMG automática (ACMG/AMP) |
| reev-nginx | nginx:1 | interno | Archivos estáticos genómicos |
| reev-postgres | postgres:12 | interno | Base de datos principal |
| reev-redis | redis:7 | interno | Caché / sesiones |
| reev-rabbitmq | rabbitmq:3 | interno | Cola de mensajes Celery |
| reev-pgadmin | dpage/pgadmin4:latest | interno | Admin BD |
| reev-flower | mher/flower:latest | interno | Monitor Celery |

## Estructura de datos

```
volumes/reev-static/data/
├── download/                  ← descargas brutas (no tocar)
│   ├── annonars/              ← bases de datos annonars por versión
│   ├── mehari/                ← transcriptos y frecuencias mehari
│   ├── viguno/                ← HPO viguno
│   ├── dotty/                 ← cdot JSON + seqrepo dotty
│   └── cada/                  ← modelo cada-prio
├── annonars/
│   ├── grch37/{cadd,clinvar,clinvar-sv,cons,dbnsfp,dbscsnv,dbsnp,
│   │           functional,gnomad-exomes,gnomad-genomes,gnomad-mtdna,
│   │           gnomad-sv-exomes,gnomad-sv-genomes,helixmtdb,regions}
│   ├── grch38/{idem grch37 + alphamissense}
│   ├── genes/                 ← ACMG SF + gnomAD constraints + HPO
│   └── clinvar-genes/
├── mehari/{grch37,grch38}/
│   ├── txs.bin.zst            ← transcritos RefSeq (mehari-data-tx v0.8.1)
│   └── seqvars/{freqs,clinvar}
├── dotty/                     ← *.json.gz (cdot 0.2.21) + seqrepo/
├── cada-prio/model/           ← modelo 20231112+0.6.1
├── viguno/ → hpo/             ← HPO 20240116+0.3.1
└── hgnc_xlink.tsv
volumes/seqrepo/
├── local/2024-12-20/          ← biocommons seqrepo (~75 GB, para auto-acmg)
└── master/
volumes/{postgres,redis,rabbitmq,pgadmin}/
```

## Versiones de bases de datos

| Base de datos | Versión | Fuente | Tamaño aprox. |
|---|---|---|---|
| annonars (motor) | 0.39.0 | S3 CUBI BIH | — |
| CADD grch37 | 1.6 | NAS 192.168.0.193 | ~155 GB |
| CADD grch38 | 1.6 | S3 CUBI BIH | ~155 GB |
| gnomAD genomes grch37 | 2.1.1 | NAS 192.168.0.193 | ~149 GB |
| gnomAD genomes grch38 | 4.1 | S3 CUBI BIH | ~383 GB |
| gnomAD exomes grch37 | 2.1.1 | NAS 192.168.0.193 | ~54 GB |
| gnomAD exomes grch38 | 4.1 | S3 CUBI BIH | — |
| ClinVar | 20240606+0.38.0 | GitHub bihealth | < 1 GB |
| dbSNP | b151+0.39.0 | S3 CUBI BIH | < 1 GB |
| dbNSFP | 4.5a+0.39.0 | S3 CUBI BIH | — |
| HPO (viguno) | 20240116+0.3.1 | S3 CUBI BIH | < 1 GB |
| mehari transcripts | 0.8.1 | GitHub bihealth | < 1 GB |
| dotty cdot | 0.2.21 | GitHub SACGF | < 1 GB |
| cada-prio model | 20231112+0.6.1 | GitHub bihealth | < 1 GB |
| seqrepo (auto-acmg) | 2024-12-20 | biocommons.org rsync | ~75 GB |

## Configuración auto-acmg (`.env`)

```ini
AUTO_ACMG_API_ANNONARS_URL=http://annonars:8080
AUTO_ACMG_API_MEHARI_URL=http://mehari:8080
AUTO_ACMG_API_DOTTY_URL=http://dotty:8080
AUTO_ACMG_SEQREPO_DATA_DIR=/home/auto-acmg/seqrepo/master
```

## Scripts de operación (junto a los datos)

| Script | Descripción |
|---|---|
| `status.sh` | Monitor de estado: disco, sesiones screen, datos presentes |
| `rsync-from-nas.sh` | Copia annonars grch37 desde NAS 192.168.0.193 |
| `download-grch38.sh` | Descarga grch38 + mehari + dotty + cada-prio + clinvar desde S3/GitHub |
| `download-seqrepo.sh` | Descarga seqrepo biocommons para auto-acmg (~75 GB) |

## Notas técnicas

- Basado en [bihealth/reev-docker-compose](https://github.com/bihealth/reev-docker-compose) v0.6.0
- Herramienta de descarga S3: `s5cmd` v2.3.0 (`~/.local/bin/s5cmd`)
- Symlinks en `data/annonars/grch3{7,8}/` apuntan a `data/download/annonars/<versión>/`
- Red Docker interna: bridge `br-reev` (servicios se comunican por hostname)
