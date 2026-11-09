# Revisión 18 — recuperación del repositorio

Fecha: 2026-11-08. Fuente de verdad: Git, código y documentación local.

## Estado recuperado antes de editar

- Repositorio: `C:\Users\Dell\Documents\svelte\proyectosupabase`.
- Rama: `fix/subida-fotos-galeria`.
- HEAD: `d78a99d26307925111e4132756f748b22d02f091`.
- 32 archivos versionados modificados/eliminados; 31 archivos nuevos; nada
  staged. Las dos eliminaciones de imágenes ya existían y se conservaron.
- Últimos cambios del pipeline: `media.js` (00:30:41 UTC), SQL (00:28:18),
  worker (00:28:05), cliente (00:27:02), cola de subida y tests (00:25–00:26).
- No se encontraron documentos identificados como Revisión 17/18. Los
  documentos disponibles describían el MVP; no acreditaban su validación.
  No se ha inventado un acta de la conversación perdida ni una aprobación de R17.
- Había logs y artefactos generados de desarrollo; no se usaron como prueba.
  No aparecieron `.tmp`, `.bak`, `.orig`, `.rej`, `.swp` o implementaciones
  alternativas con esos sufijos que hubiera que eliminar.

Base reproducida: 10/10 tests, `svelte-check` con 0 errores y 8 warnings.
Existían intent/commit, Sharp/SHA-256, worker facial, moderación y outbox.
La existencia de ese código no se trató como una tarea validada.

## Hallazgos recuperados y continuación

| Área | Hallazgo en el estado recuperado | Resultado local |
| --- | --- | --- |
| SQL/RLS/RPC | Guard staff con `NULL NOT IN` abierto; commit invocable con metadatos del cliente; grants de claves. | Guards NULL cerrados, revocación PUBLIC/columnas/sobrecargas, RPC sensibles solo servidor, actor verificado. |
| Claves internas | Tablas/RPC exponían object keys y errores crudos; presign legacy confiaba en filas editables. | Proyección explícita, cliente privilegiado solo servidor, mensajes controlados, endpoints débiles retirados. |
| Integridad | Límites/estado y cuotas no estaban suficientemente protegidos en DB/concurrencia. | Constraints, tipos, SHA/MIME/tamaño/dimensiones revalidados, cuotas serializadas y keyset con desempate. |
| R2 | Staging sobrescribible, límite solo posterior y copia TOCTOU; una ruta antigua evitaba el pipeline. | PUT write-once con tipo/tamaño firmados, ETag/stream acotado, original desde bytes verificados, sin posts por legacy. |
| Borrado | Snapshot incompleto, reservas parciales/cascadas y PUT tardío podían dejar objetos. | Ledger antes de PUT, snapshots/cascadas, limpieza diferida, tombstones, reconciliación y borrado durable de portadas. |
| Worker | Sin heartbeat; nombre de worker insuficiente; escrituras posteriores a borrado/lease. | Token por claim, heartbeat, locks/fences inicial/final con reloj real, generaciones únicas y recuperación auditada. |
| SQL del worker | Parámetros usados solo en `jsonb_build_object` podían carecer de tipo. | Casts explícitos preparados; prueba estática que evita reintroducirlos sin tipo. |
| TLS | `rejectUnauthorized: false`. | TLS y hostname verificados, CA opcional; rechazo de overrides `ssl*` en URL. |
| Portadas | NULL convertido en público y originales accesibles por bucket público. | Privado por defecto, selección explícita, lectura autorizada, migración durable preparada a R2 privado. |
| EXIF | Solo comprobación limitada de derivadas. | Prueba con orientación y EXIF/GPS; originales privados conservados; derivados/imagenes de perfil recodificados sin metadatos. |
| Facial | Dos `resize()` en la misma cadena Sharp anulaban la reducción real del pixelado. | Reducción materializada, desenfoque de respaldo, redetección de copia y thumbnail, bloqueo ante fallo. |
| Moderación | Paginación sin navegación completa; errores podían parecer cola vacía. | Cursores en HTTP/SQL/UI, lookahead antes de firmar, errores explícitos y panel de dead-letter. |
| Verificación | Arnés legacy leía `.env` y contactaba servicios; no había evidencia de R18. | Runner offline aislado y pruebas de guards, rutas, SDK, worker, imágenes y contrato SQL estático. |

## Archivos cambiados en esta recuperación

Los cambios que ya estaban en Git al inicio se preservaron; esta lista
identifica los archivos editados/añadidos por esta continuación, no atribuye
todo el diff desde HEAD a esta sesión.

### Aplicación

- `src/lib/server/media.js`, `media.test.js`, `mediaDb.js`, `r2.js`,
  `profileImages.js`, `admin.js`.
- `src/lib/media/client.js`, `pagination.js`, `pagination.test.js`, `r2Config.js`.
- `src/lib/upload/r2Upload.js`.
- `src/routes/+page.server.js`.
- `src/routes/api/media/{upload-intent,upload-commit,upload-abort,owner,public,
  delete,delete-cover,covers,presign,upload}/+server.js`.
- `src/routes/api/upload/r2/+server.js`.
- `src/routes/moderacion/+page.server.js`, `+page.svelte`.
- `src/routes/perfil/+page.svelte`, `src/routes/perfil/[id]/+page.svelte`.

### Worker, SQL y verificación

- `worker/index.js`: conserva el arranque separado de la lógica recuperada,
  que se trasladó y endureció en `worker/jobs.js`.
- `worker/processing.js`, `processing.test.js`, `jobs.test.js`, `lease.js`,
  `lease.test.js`, `config.js`, `Dockerfile`, `README.md`.
- `supabase-media-pipeline.sql`, `supabase-media-pipeline-verify.sql`.
- `package.json`, `svelte.config.js`, `vite.config.js`, `vitest.config.js`.
- `scripts/offline.mjs`, `offline-guard.cjs`, `test-upload-security.mjs`.
- `tests/{media-routes,media-sql-contract,profile-images,moderation,r2,offline,
  auth-identity}.test.js` y fixtures de entorno **sintéticos**.
- `MEDIA_PIPELINE.md` y este documento.

## Resultados reales

Verificación final consolidada del 2026-11-08:

| Comando/comprobación | Resultado real |
| --- | --- |
| `npm run test:security` | **110/110 tests en 12 archivos**, sin skips ni errores sin manejar; 31,66 s. |
| `npm run check:offline` | **0 errores y 8 warnings** en 4 archivos, los mismos observados en la base. |
| `npm run build:offline` | **Correcto**, cliente y SSR; último build en 50,93 s. |
| `git diff --check` | Sin errores de whitespace en los cambios versionados. |
| `git diff --no-index --check` sobre archivos nuevos relevantes | 46 archivos comprobados, sin diagnósticos. Se distingue el exit 1 normal de diff de un error de whitespace. |
| `npm --offline --ignore-scripts ls --depth=0` | Exit 0, sin paquetes ausentes/invalid; 2 paquetes `extraneous` conservados. |
| Rama/HEAD/index al cierre | Misma rama y HEAD recuperados; ningún cambio staged ni commit nuevo. |

Las 110 pruebas incluyen 6 de imagen con modelos locales reales, 5 de firma/
lectura con el SDK R2 real y valores sintéticos, 11 contratos SQL estáticos y
los casos de rutas, identidad, paginación, leases y recuperación con dobles.
`npm test` y `npm run test:security` ejecutan la misma suite offline.

Resultados obtenidos durante las etapas y errores corregidos:

- Base: 10/10 tests; ejecución intermedia completa: 95/95.
- Rutas/SQL/worker se verificaron por grupos después de las modificaciones.
- 6 pruebas faciales/EXIF con Sharp y modelos locales reales pasaron.
- Los checks de etapa y la comprobación final terminaron sin errores de tipos.
- Los dos builds offline completos pasaron; el último incluye los cambios finales.
- La firma real del SDK inicialmente intentó leer configuración AWS
  compartida: el guard bloqueó credenciales y produjo 2 tests fallidos y una
  rejection sin manejar. Se fijó la configuración R2 explícita y se amplió el
  guard; el rerun focalizado pasó 7/7, sin errores sin manejar.
- Se corrigieron también errores de tipado en los nuevos fixtures y un doble
  defectuoso de R2; no quedan en el último check.

Las pruebas SQL son **estáticas**; las de jobs usan dobles de pg/R2. Ninguna
sentencia SQL se ha ejecutado y no se han probado locks reales de PostgreSQL.

### Warnings conocidos

- `Login.svelte`: 2 labels sin asociación.
- `MediaGrid.svelte`: botón anidado, foco de diálogo y captions de vídeo (3).
- `terminos/+page.svelte`: selector CSS sin uso (1).
- `usuarios/+page.svelte`: interacción/teclado en un `li` (2).
- Build: datos Baseline/Browserslist antiguos, chunk vacío del ejemplo Sverdle
  y adapter-auto sin plataforma detectada en el entorno offline.
- Git: avisos LF → CRLF en archivos que ya tenían esa condición.
- Dependencias instaladas: `@emnapi/runtime@1.11.3` y
  `@img/sharp-wasm32@0.35.5` figuran como extraneous. No se eliminaron ni se
  reinstaló `node_modules`; `package-lock.json` conserva el trabajo previo.
- Dos mensajes stderr de tests son fallos deliberados de almacenamiento/cola,
  con texto controlado; no representan peticiones a servicios reales.

## SQL preparado, no ejecutado

- `supabase-media-pipeline.sql`: migración transaccional/idempotente del
  pipeline existente, cierre de privilegios, integridad, nuevas firmas,
  leases, limpieza, retención, migración de portadas y recuperación de jobs.
  Conserva las sobrecargas antiguas sin permisos de navegador.
- `supabase-media-pipeline-verify.sql`: comprobación de RLS, privilegios
  efectivos (incluidas columnas/sobrecargas) y guard NULL, con ROLLBACK.
- Los otros scripts SQL preexistentes se conservaron; no se ha supuesto que
  estén aplicados ni que describan fielmente la base remota actual.

## Pendientes que requieren staging

1. Aplicar/reaplicar el SQL en una copia con datos representativos y comprobar
   sintaxis, idempotencia, constraints, grants efectivos, RLS y firmas PostgREST.
   Una constraint que detecte datos contradictorios debe detener la operación;
   revisar esas filas antes de decidir su corrección.
2. JWT reales de dos dueñas, fan, baneada, moderadora, admin y anónimo: probar
   lecturas directas, RPC antiguas/nuevas, roles NULL, metadatos falsificados y
   escalamiento de permisos de profiles/media_staff/admin_users.
3. CORS/PUT reales: Content-Length automático del navegador, Content-Type,
   If-None-Match, replay, exceso de tamaño, ETag y bucket privado inaccesible sin
   firma. Verificar ámbitos R2 y clave de servidor sin exponerlos al frontend.
4. Dos workers: kills durante detección/PUT/COMMIT, lease caducada, heartbeat
   interrumpido, mismo workerId, borrado/rechazo/cascada concurrentes,
   tombstones reaparecidos y recuperación de dead-letter sin duplicaciones.
5. Completar la migración de portadas heredadas y comprobar que las fuentes
   públicas desaparezcan realmente, incluidas cachés/CDN y referencias
   compartidas. No prometer privacidad retrospectiva solo por cambiar RLS.
   Revisar trabajos con GIF/rutas inválidas/objetos antiguos que no se migren.
6. TLS real con CA/hostname correcto e incorrecto; latencias, timeouts y
   recursos del worker. El Dockerfile no está validado construyéndolo aquí.
7. Corpus facial representativo y revisión visual de todas las derivadas.
   Redetectar con los mismos modelos no garantiza anonimización absoluta.
8. Retención a 30 días, consumo de colas, inventario de huérfanos anteriores al
   ledger, lifecycle de staging, monitorización de dead-letter y limpieza a
   escala. Medir el barrido rotativo de 500 objetos por trabajo. Auditar también
   tablas/URLs históricas de `media` y `user_photos`: no se han migrado ni
   borrado automáticamente como parte de esta recuperación.
9. Navegación real de más de una página, empates temporales, borrados y
   moderación entre páginas; configuración de despliegue de app/worker y corte
   coordinado con las firmas RPC nuevas.

## Continuidad y veredicto

No se hicieron commits, reset/clean/revert ni descartes. No se leyeron archivos
dotenv ni se ejecutaron Docker, SQL o despliegues. Se conservaron las imágenes
ya eliminadas, los demás cambios ajenos a esta revisión y los archivos nuevos
preexistentes.

**Veredicto: APTO PARA VALIDACIÓN EN STAGING.**

El endurecimiento local tiene pruebas reproducibles. Staging permanece **sin
validar**: SQL, permisos efectivos, CORS/R2, certificados, concurrencia y datos
históricos requieren las comprobaciones anteriores. La app necesita la clave
de servicio solo en servidor y un corte coordinado con el nuevo contrato SQL;
no se ha supuesto que esa configuración ya exista.
