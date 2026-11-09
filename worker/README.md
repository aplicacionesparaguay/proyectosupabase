# Worker de fotografías — Revisión 18

Estado: código comprobable localmente; **worker no iniciado, SQL no ejecutado y
staging no validado en esta recuperación**. Ver `../REVISION_18.md`.

## Estructura y ejecución futura

- `index.js`: arranque explícito, modelos, bucle, señales y cierre de recursos.
- `jobs.js`: lógica recuperada del worker, con dependencias pg/R2 inyectables.
  Importarlo para probar no abre conexiones ni inicia procesamiento.
- `lease.js`: heartbeat sin solapamientos, cancelación al perder ownership y
  espera del heartbeat pendiente antes de considerar éxito.
- `config.js`: PostgreSQL con TLS verificado y timeouts acotados.
- `processing.js`: detección/protección facial y saneamiento de imágenes.

En un entorno de staging configurado y autorizado, el comando de arranque es
`npm run worker`. No carga automáticamente archivos dotenv.

Variables esperadas (nombres, sin valores reales):

- `DATABASE_URL`: URL PostgreSQL sin parámetros `ssl*`.
- `DATABASE_CA_PEM`: opcional, CA de confianza si el certificado no encadena a
  las CA del sistema. `rejectUnauthorized` permanece en `true`.
- `DATABASE_SSL`: si se proporciona, solo se admite `true`. No se admite
  `no-verify`, `sslmode=require` que sustituya la configuración ni archivos
  sslkey/sslcert indicados en la URL.
- Credenciales R2 y `R2_PRIVATE_BUCKET`/`R2_PUBLIC_BUCKET`, con ámbitos mínimos
  para privado y migración/limpieza del público. No hay fallback a perfiles AWS.
- `WORKER_ID` opcional; el token de lease nuevo es el fence, no el nombre.
- `WORKER_LEASE_SECONDS`: 60–3600, por defecto 300. Heartbeat cada tercio.
- `WORKER_DB_POOL`: 2–8, por defecto 4, para permitir heartbeat concurrente.
- `WORKER_POLL_MS`: por defecto 2000. Mantenimiento como máximo una vez/minuto.
- `FACE_MODEL_DIR`: por defecto `node_modules/@vladmandic/face-api/model`.

El Dockerfile se conserva y copia los módulos compartidos necesarios. **No se
ha construido ni ejecutado una imagen**, ni se ha comprobado su entorno Linux.

## Trabajos y garantías locales

| Trabajo | Finalidad |
| --- | --- |
| `process` | Verificar bytes, conservar original, proteger/verificar copia y thumbnail; dejar `pending_review`. |
| `delete_staging` | Limpiar tras expiración real del PUT y conservar una fuente recuperable cuando sea necesario. |
| `delete_protected` | Retirar derivadas de una foto rechazada, incluidas reservas parciales. |
| `purge_original` | Purgar tras la retención; no purgar una foto pendiente/aprobada. |
| `delete_all` | Retirar snapshot y objetos del ledger tras borrado/cascada. |
| `delete_profile_orphan` | Retirar avatar/portada que ya no tenga referencias, en su bucket real. |
| `migrate_cover` | Sanear portada heredada pública, moverla a privado y encolar retirada de la fuente. |
| `reconcile` | Recorrer 500 objetos conocidos por antigüedad, detectar faltantes, generaciones huérfanas y reapariciones de tombstones. |

Claim y recuperación usan `SKIP LOCKED`. Heartbeat, éxito, fallo y escrituras
comprueban token, worker y vigencia; un fence final usa reloj real. Las claves
de derivadas/migración incluyen generación; el original se escribe desde el
buffer ya verificado y no mediante una segunda copia de staging mutable.

Una reserva del ledger se confirma **antes** de escribir. Una caída entre PUT y
COMMIT deja un objeto conocido. Borrados y reconciliación son idempotentes;
una clave tombstoned no se reutiliza. Las operaciones R2 duran como máximo
30 s por llamada; pg tiene límites de conexión, statement e idle transaction.

Las llamadas externas acotadas que escriben manteniendo el lock del job/asset
serializan el borrado. Se debe medir esta estrategia con dos workers reales,
latencia R2 y caídas de conexión en staging; los dobles no prueban locks reales.

Al agotar reintentos el trabajo queda `dead`. Staff lo consulta en
`/moderacion` y puede reencolarlo con un motivo auditado. El worker nunca
aprueba automáticamente ni transforma un fallo facial en publicación.

## Pruebas locales

`npm test -- worker/jobs.test.js worker/lease.test.js worker/processing.test.js`
usa el runner offline del proyecto. Las pruebas de imagen ejecutan modelos
locales reales; las de pg/R2 inyectan dobles y no ejecutan SQL ni peticiones.
La firma de URLs se prueba aparte con el SDK real y credenciales sintéticas.

La detección facial no es una garantía absoluta de anonimización. Falta
validar el corpus real (rostros pequeños, perfiles, oclusiones, orientación,
grupos y miniaturas) y el comportamiento ante fallos de infraestructura.
