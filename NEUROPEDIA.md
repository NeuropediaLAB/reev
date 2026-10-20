# Fork NeuropediaLAB de REEV

Fork completo de [`bihealth/reev`](https://github.com/bihealth/reev) para el despliegue
de `reev.neuropedialab.org`. Sustituye el esquema anterior de parches sobre bundles
minificados (`volumes/reev-ui-patches`, `volumes/reev-backend-patches`) por cambios
reales en el código fuente.

## Repositorios

| Repo | Contenido |
|---|---|
| `NeuropediaLAB/reev` (este) | Código fuente: `backend/` (FastAPI + Celery) y `frontend/` (Vue 3 + Vite) |
| `NeuropediaLAB/reev-deploy` | Despliegue vivo: `docker-compose.yml`, `config/`, `monitor/`, parches históricos |

`NeuropediaLAB/reev-deploy` era el antiguo `NeuropediaLAB/reev`.

## Ramas

- `main` — espejo exacto de `bihealth/reev:main`. No se toca; sólo se avanza con
  `git fetch upstream && git merge upstream/main`.
- `neuropedia` — rama de trabajo con nuestras modificaciones.

```bash
git remote add upstream https://github.com/bihealth/reev.git   # si no existe
git fetch upstream
git checkout main && git merge --ff-only upstream/main
git checkout neuropedia && git merge main
```

## Build

Un solo Dockerfile (`utils/docker/Dockerfile`) produce una imagen con backend y
frontend estático en `/home/reev/ui`:

```bash
./utils/docker/build-fork.sh                 # tag neuropedialab/reev:<git describe>
TAG=neuropedialab/reev:dev ./utils/docker/build-fork.sh
```

El submódulo `frontend/src/ext/reev-frontend-lib` (bihealth) debe estar clonado:

```bash
git submodule update --init --recursive
```

## Despliegue

En `reev-deploy/docker-compose.yml` los servicios `reev-backend`, `reev-celery-worker`
y `reev-celery-beat` usan la imagen construida en lugar de `ghcr.io/bihealth/reev:0.6.0`,
y se eliminan los bind mounts de `volumes/reev-ui-patches/*` y
`volumes/reev-backend-patches/*` (sus cambios viven ya en el árbol fuente).

Variables relevantes: `SERVE_FRONTEND=/home/reev/ui` (ya es el default de la imagen),
`POSTGRES_*`, `SECRET_KEY`, `BACKEND_CORS_ORIGINS`.

## Estado de partida

- Base: `0.6.0` (mismo release que las imágenes `ghcr.io/bihealth/reev:0.6.0` en producción).
- Python 3.10 (`.python-version`), dependencias con Pipenv (`backend/Pipfile`).
- Node 20 para el build del frontend (probado con npm sobre Node 24).
- Licencia MIT (ver `LICENSE`).
