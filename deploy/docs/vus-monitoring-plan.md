# Monitorización automática de VUS — estado real y plan

Fecha: 2026-11-02. Basado en inspección en vivo del stack `~/produccion/reev` y del código
`~/workspace/reev-src` (fork NeuropediaLAB, imagen `neuropedialab/reev:0.6.0-neuropedia12`).

## 1. Lo que ya existe (y funciona)

Motor de reanálisis en el fork (`backend/app/casearchive/`, 2026-10-20):

- `CaseVariant` — variante "seguida" dentro de un caso (obj_type `seqvar`/`strucvar`, flag `follow`).
- `AcmgAssessment` — histórico por variante con `acmg_class`, `criteria`, `source`, `engine_version`,
  `data_signature`, `data_versions`, `is_conflicting`.
- `ReanalysisRun` — una pasada (trigger, status, n_variants, n_changed, n_failed, firma de datos).
- `ReanalysisAlert` — alerta por cambio de clase, con severidad, clase vieja/nueva, `read_at`.
- `DataVersion` — versiones observadas de las bases de referencia, con `is_current`.

Programación (celery beat, activa: `CASEARCHIVE_REANALYSIS_ENABLED=True`):

- `poll_data_versions` cada 6 h (minuto 17): lee `/annos/db-info` de annonars, calcula una firma
  sha256 y, si cambia respecto a la última pasada correcta, dispara reanálisis completo.
- `reanalyze_all_cases` domingo 03:41 (reanálisis semanal ciego, por si acaso).

API (`/api/v1/casearchive/...`): listar/añadir/quitar variantes seguidas, `/reanalyze`,
`/alerts`, `/alerts/{id}/read`, `/summary`, `/data-versions`.

Clasificación: `app/casearchive/acmg.py` es un port literal de las reglas del frontend
(`acmgSeqvar.ts`): niveles de evidencia + reglas de combinación + nivel `Conflicting`.
Los criterios NO se recalculan ahí: se piden a `auto-acmg` (`/api/v1/predict/seqvar`).

UI: `CaseArchiveCard` montada sólo en `ProfileView`; cliente en `api/casearchive/`.

## 2. Estado real del laboratorio (medido hoy)

```
casos (caseinfo)          0
variantes seguidas        0
acmg_assessment           0
reanalysis_run            1   (manual, 2026-10-20, 1 variante, 0 cambios)
reanalysis_alert          0
data_version              0
clinvarsubactivity        0
```

Es decir: el motor está escrito y arrancado, pero **no vigila nada** porque no hay casos ni
variantes cargadas, y no hay vía de ingesta (sólo alta manual de un caso y "seguir" una variante
por su id spdi).

## 3. Fallos concretos encontrados (con evidencia)

### 3.1 ClinVar no entra en la firma de datos (crítico)
`/annos/db-info` devuelve `clinvar: null` en GRCh37 y GRCh38. annonars sí sirve ClinVar
(una consulta de MTHFR C677T GRCh37 devuelve `VCV000003520`), pero no reporta su versión.
Consecuencia: la actualización de ClinVar —el disparador principal de una reclasificación— NUNCA
cambia la firma. El poll de cada 6 h es ciego justo a lo que importa.

### 3.2 No hay dataset ClinVar GRCh38
En disco sólo existe `clinvar-grch37-2026-10-24+0.39.0`. Un caso en GRCh38 no tiene anotación
ClinVar (verificado: MTHFR hg38 → `clinvar: null`).

### 3.3 auto-acmg pierde el HGVS proteico de mehari (afecta a PS1/PM5/BP7)
mehari 0.25.3 devuelve `hgvs_p: "p.Q1395H"` en el nivel superior del resultado; el cliente de
auto-acmg busca otra estructura y obtiene `pHGVS=''`. Resultado en vivo para BRCA1
`grch37-17-41242961-G-A`:

```
ps1 | failed  | No valid primary amino acid change for PS1/PM5 prediction
pm5 | failed  | No valid primary amino acid change for PS1/PM5 prediction
bp7 | failed  | Missing phyloP100 score
pm2/ba1/bs1/bs2 | failed | No allele frequency found in gnomad data
```

PS1/PM5 son precisamente los criterios que hacen virar un VUS cuando ClinVar acumula casos.
(En variantes comunes sí funciona: MTHFR C677T → BA1+BS2+PP3+BP4.)

### 3.4 Criterio "failed" se trata como "no aplicable"
`_call_auto_acmg` reduce todo a booleano (`prediction == "applicable"`). Un fallo técnico y una
evidencia ausente son indistinguibles, y `run_reanalysis` acaba en `success`. Un cambio de clase
puede deberse a que una base de datos dejó de responder, no a nueva evidencia — sin ningún aviso.

### 3.5 Las intensidades se pierden al clasificar
auto-acmg devuelve `strength` (PP3 strong/moderate/supporting, etc.) y el código lo guarda en
`_strengths`, pero `classify()` cuenta todo como "1 criterio supporting". Infravalora PP3 fuerte y
PM2 → clases sistemáticamente conservadoras (más VUS de los que tocan).

### 3.6 La línea base es la máquina, no el clínico
`assess_variant` compara el último `AcmgAssessment` automático con el nuevo. La clasificación
firmada por el laboratorio (`acmgseqvar`, la que el clínico guarda en la UI, con sus criterios)
no participa en la comparación. El sistema detecta "cambios del motor", no "cambios frente a lo
que firmé".

### 3.7 Nada de bibliografía
El único contacto con literatura es un proxy a PubTator3 para la tarjeta de gen. No hay job que
busque publicaciones nuevas por variante/gen.

### 3.8 Las alertas no salen de la aplicación
No hay email, Telegram ni digest. `reanalysis_alert` sólo se ve entrando a la web.

### 3.9 Refresco de datos manual y sin verificación
`download-smart.sh` se lanza a mano desde el monitor. No se comprueba si hay release nueva
upstream (ClinVar/gnomAD/dbNSFP), ni se valida que el dataset recién bajado esté completo.

### 3.10 UI enterrada
`CaseArchiveCard` vive en `ProfileView`: no hay lista de trabajo clínica de VUS.

## 4. Plan propuesto

### Fase 0 — Base fiable (1-2 días de trabajo)
1. Detectar versión de ClinVar: leer el manifiesto/fecha del dataset y, si no existe, la release
   de ClinVar (`clinvar_variant_summary` / API NCBI o `variant_summary.txt.gz` header) e incluirla
   en la firma. Sin esto el resto no sirve.
2. Descargar y registrar `clinvar-grch38` (dataset varfish/annonars) y reiniciar annonars.
3. Fijar versión de `auto-acmg` (dejar de usar `:main`) y parchear el cliente de mehari al shape
   0.25.3; validar PS1/PM5/BP7 con variantes donde ClinVar tiene aminoácido concordante.
4. Modelar el estado por criterio: `applicable | not_applicable | not_automated | failed |
   deprecated` en lugar de booleano. Regla dura: si un criterio que sostenía la clase pasa a
   `failed`, la clase NO se degrada automáticamente; la alerta es "cobertura incompleta".
5. Sustituir el conteo plano por el sistema de puntos ClinGen SVI (Bayesian 2024) usando las
   intensidades que auto-acmg ya entrega; guardar `engine_version` por criterio.

### Fase 1 — Vigilancia real
6. Lista de vigilancia independiente del caso: `variant_watch(build, chrom, pos, ref, alt, gene,
   hgnc, hgvs_c, hgvs_p, rsid, pseudonimo, clase_entrada, criterios_entrada, fuente)`.
   Ingesta por CSV/HGVS/VCF y export directo desde la vista de caso.
7. Job de literatura (semanal): Europe PMC + PubTator por variante (rsid + hgvs_p + gen) y por gen;
   guardar PMID/DOI/año/tipo, deduplicar, y triaje con LLM local (OVMS) que propone qué criterio
   podría verse afectado (PS3/PS4/PP1/BS4). Nunca cambia la clase: crea propuesta para revisión.
8. Vigilancia a nivel de gen (en neuropediatría es donde más reclasificaciones aparecen):
   validez gen-enfermedad de ClinGen, OMIM, PanelApp, nuevas asociaciones HPO-gen, constraint de
   gnomAD. Un cambio de validez del gen reclasifica variantes enteras.
9. Notificación: Telegram/email con tabla de diff (qué criterio cambió, valor viejo → nuevo),
   severidad y enlace. La alerta in-app queda como registro de auditoría.
10. Comprobación de releases upstream + verificación post-descarga antes de dar un dataset por bueno.

### Fase 2 — Calidad de laboratorio
11. Línea base = clasificación firmada por el clínico (criterios + intensidades + fecha + firma).
    El reanálisis compara "evidencia de hoy" contra "criterios en el momento de firma" y produce
    una lista de trabajo: "revisar estas 12 variantes, por estos 3 criterios".
12. Informe de reclasificación exportable a PDF para el expediente, con versiones de datos y de
    motor (trazabilidad tipo ISO 15189).
13. Caché de evidencia por firma de datos: un barrido de 500 VUS debe tardar segundos y ser
    reejecutable. (Hoy: ~0,3-0,5 s por variante en caliente contra auto-acmg.)
14. Suite de regresión: 30-50 variantes con resultado esperado (incluidas reclasificaciones
    históricas conocidas). Se ejecuta en cada cambio de motor o de datos; sin esto no hay
    "solidez", sólo confianza.
15. Selección de VCEP por gen/panel (auto-acmg ya aplica ENIGMA para BRCA1/2); para neuro pediatría
    hay que mapear los VCEP de ClinGen que apliquen y declarar explícitamente cuando se usa el
    criterio genérico sin VCEP.

### Fase 3 — Cerrar el círculo
16. `CLINVAR_USE_PRODUCTION` está en `false` (API de test): pasar a producción y monitorizar el
    estado de nuestras propias submisiones (existe `clinvarsub` en el fork, sin usar).
17. Alertas → tarea en OpenProject/Seafile para el flujo del laboratorio; digest semanal.

## 6. Ingesta real: los VUS llegan como HGVS (transcrito + c. + p.)

Formato de entrada del laboratorio: `NM_004992.4:c.397C>T p.(Arg133Cys)` (o `p.Arg133Cys`).
Verificado en vivo contra el stack: la notación es resoluble y suficiente.

Cadena validada (GRCh37):

```
dotty /api/v1/to-spdi?q=NM_004992.4:c.397C>T&assembly=GRCh37
  -> X:153296882 G>A
mehari /seqvars/csq  -> hgvs_p p.R133C   (coincide con el p. declarado)
```

Ejemplos comprobados, con verificación del p. declarado contra el calculado por mehari:

| gen   | HGVS                    | GRCh37        | p. mehari | estado |
|-------|-------------------------|---------------|-----------|--------|
| MECP2 | NM_004992.4:c.397C>T    | X:153296882 G>A | p.R133C | OK |
| HBB   | NM_000518.5:c.20A>T     | 11:5248232 T>A  | p.E7V   | OK |
| TP53  | NM_000546.5:c.743G>A    | 17:7577538 C>T  | p.R248Q | OK |
| SCN1A | NM_001165963.4:c.3700A>G | 2:166870259     | —       | FALLA: secuencia (seqrepo corrupto) |

Pipeline del importador:

1. Parser tolerante: `TRANSCRITO:c.<cambio>` + `p.(Xxx)` opcional, uno por línea (CSV/Excel/pegado).
2. Resolución a SPDI por ensamblado con dotty (`to-spdi`), contig/pos/ref/alt.
3. Verificación: recalcular el p. con mehari y compararlo con el declarado (normalizando 3 letras
   a 1). Un desacuerdo = transcrito equivocado, error de notación o falta de secuencia → se marca,
   no se ingesta a ciegas.
4. Duplicados: se colapsan por (transcrito, c.) y por (contig, pos, ref, alt); un mismo VUS puede
   venir escrito con dos transcritos distintos del mismo gen.
5. Alta en `variant_watch` con clase de entrada, criterios de entrada, fecha y procedencia.

Requisito bloqueante detectado: el dataset seqrepo de dotty
(`/mnt/reev-data/volumes/reev-static/data/download/dotty/2024-12-20/seqrepo`) tiene ficheros
fasta truncados de la descarga del 25-oct. Verificado con CRC de gzip: fallan chr2, chr3, chr4
(fichero compartido) y chr6/chr9, además de todo GRCh38. Script de auditoría:
`~/workspace/scripts/seqrepo-integrity-check.py`. Hay que volver a bajar los ficheros dañados
antes de fiarse de cualquier resolución de HGVS.

## 5. Lo que necesito de ti para empezar

- Qué formato tienes de los VUS actuales: export CSV/Excel del laboratorio, lista de HGVS, o VCF.
  Con eso cargo `variant_watch` y el sistema tiene algo que vigilar desde el primer día.
- Cuántos VUS y en qué genes/paneles (para dimensionar el barrido y elegir VCEP).
- Si quieres que el aviso salga por Telegram, email o ambos.
