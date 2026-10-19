# Parches de UI/backend de REEV

Estos ficheros son las **versiones vivas** que se montan una a una dentro de `reev-backend`
(ver `docker-compose.yml`, sección `volumes:` del servicio `reev-backend`). No hay checkout
del frontend de REEV en el host ni build propio: los assets se editan a mano sobre el bundle
minificado de `bihealth/reev`.

Fuente en el host: `~/workspace/reev/volumes/` (copia idéntica en
`~/workspace/docker/genomic-stack/reev/volumes/`). Cualquier cambio aquí debe copiarse también
al host y recargar el contenedor.

## `volumes/reev-ui-patches/`

| Fichero | Parche |
|---|---|
| `index.html` | **Tarjetas colapsables.** Bloque JS propio (sin tocar el bundle) que contrae por defecto las tarjetas de Literature/Bibliografía y cualquier tarjeta cuyo cuerpo supere 1200 px, con botón "▾ Mostrar / ▴ Ocultar" en la línea del título. El estado se recuerda en `sessionStorage` (`reevCardOpen`). Debe arrancar en `DOMContentLoaded` (`document.body` es null desde `<head>`). |
| `index-jMqp1mrs.js` | (1) null-check de `ucsc_conservation` en GRCh37, (2) envoltorio de `clinvar records`, (3) formato de respuesta SPDI de dotty, (4) null-check del abstract de pubtator3. Sentry desactivado (`dsn:void 0`). |
| `GeneLiteratureCard-Av9mbsqx.js` | optional-chaining sobre `abstract.pmid/journal/date/passages`. |
| `SeqvarScoresCard-QuWJsaiW.js` | fallback de CADD para SIFT, PolyPhen2 HVAR y Gerp++ cuando falta dbNSFP (GRCh37). |
| `StrucvarClinsigCard-dT0IsBqR.js` | card de significación clínica de variantes estructurales. |

## `volumes/reev-backend-patches/`

| Fichero | Parche |
|---|---|
| `proxy.py` | sube el timeout de httpx a 120 s para los servicios respaldados por NAS. |
| `remote.py` | respuesta no-JSON de WinterVar → rating ACMG por defecto en lugar de 500. |

## Desplegar un cambio

```bash
# 1. editar EN EL SITIO (mismo inodo) los ficheros de ~/workspace/reev/volumes/...
#    Los bind mounts de un solo fichero se quedan apuntando al inodo viejo si el
#    editor reemplaza el archivo (rename). Señal: /proc/self/mountinfo muestra
#    ".../fichero//deleted" dentro del contenedor.
docker exec reev-backend grep -E 'ui/' /proc/self/mountinfo   # buscar "//deleted"
# 2. si hubo reemplazo de inodo: docker restart reev-backend
# 3. verificar con cache-buster: http://<host>:8200/seqvar/<...>?v=N
```
