# Pipeline de fotografías — Revisión 18

Estado de recuperación, pruebas y pendientes: [REVISION_18.md](REVISION_18.md).
**El SQL está preparado y no se ha ejecutado. No se ha conectado con Supabase/R2,
arrancado el worker, ejecutado Docker ni desplegado durante esta recuperación.**

## Contrato de seguridad

- La identidad procede de `hooks.server.js`, con `getClaims`; el id de la
  cookie y `user_metadata` no autorizan operaciones del pipeline.
- Tablas con claves/ledger e intents no son legibles ni escribibles por
  `anon`/`authenticated`. Se revocan también permisos por columna, PUBLIC y
  todas las sobrecargas antiguas de las RPC del pipeline.
- Las RPC que devuelven claves o aceptan metadatos verificados son exclusivas
  de `service_role`. El servidor les pasa el actor ya verificado. Las RPC de
  borrar, moderar y recuperar trabajos comprueban identidad/rol en PostgreSQL.
- `mediaDb.js` es exclusivo del servidor, no instala sesiones de usuario y
  requiere `SUPABASE_SERVICE_ROLE_KEY`. Sin configuración, falla cerrado.
  No se ha consultado ni configurado ninguna clave real en esta sesión.
- Las respuestas proyectan campos explícitos, sin claves de objeto separadas
  ni mensajes crudos de PostgreSQL, Sharp o R2. Una URL firmada sí contiene el
  localizador del objeto: sigue siendo una capacidad de lectura temporal y no
  debe registrarse ni compartirse.

## Galería

1. `POST /api/media/upload-intent`: creadora activa, JPEG/PNG/WebP estático,
   máximo 10 MiB y 50 millones de píxeles; 20 reservas/hora y 500 assets activos.
   La cuota se serializa y se comprueba de nuevo al confirmar.
2. El intent registra el staging y su limpieza **antes** de emitir el PUT.
   La firma dura 900 s y obliga a `Content-Type`, tamaño exacto e
   `If-None-Match: *`. El navegador envía este último encabezado; el agente de
   usuario calcula `Content-Length` al enviar el `File`.
3. `POST /api/media/upload-commit`: lee exclusivamente el intent de la cuenta,
   limita el stream, decodifica la foto real, normaliza orientación, comprueba
   tamaño/MIME/píxeles y calcula SHA-256. El navegador no decide estos valores.
4. El worker verifica otra vez hash, tamaño, MIME y dimensiones; escribe como
   original los bytes que verificó, sin volver a copiar una clave mutable.
5. SSD MobileNetV1 + Tiny Face Detector detectan y verifican. El pixelado
   materializa la reducción antes de ampliar; si es insuficiente se prueba
   desenfoque. También se verifica el thumbnail. Si falla, se bloquea la foto.
6. Las derivadas no transportan EXIF/GPS, ICC ni XMP. El original privado se
   conserva como fuente original; su acceso por la dueña tras rechazo se audita.
7. Solo una revisión humana puede pasar a `approved`. Cola, aprobación y
   rechazo tienen guard de staff que deniega también `NULL`, bloqueo de fila y
   una decisión única por foto. Las cuentas baneadas no aparecen en el listado
   ni en el contador públicos.
8. Galería propia, pública y cola usan cursores `(created_at, id)`, límite
   1–100 y una fila de lookahead antes de firmar. El offset heredado está
   acotado; no puede combinarse con cursor. La interfaz permite continuar.

Las URLs GET duran 300 s y las respuestas/objetos nuevos llevan `no-store`.
Borrar o rechazar impide emitir URLs nuevas; una URL ya emitida puede seguir
funcionando hasta caducar. No hay garantía de revocación instantánea de copias
ya descargadas por un navegador.

## Avatares y portadas

- `/api/upload/r2` conserva la interfaz de compatibilidad solo para avatares y
  portadas. `posts` devuelve 410: no existe una subida paralela que evite la
  galería moderada. `/api/media/upload` y `/api/media/presign` están retirados.
- Todas las entradas pasan por intent y staging privados, comprobación de
  imagen completa y recodificación WebP sin EXIF. El PUT del navegador nunca
  apunta al objeto final.
- Avatar: imagen de perfil pública. Portada: objeto final **siempre privado**,
  con visibilidad `privado` por defecto y elección explícita `publico` en la UI.
  Máximo 20 portadas activas; el servidor registra la fila y el ledger.
- Home y perfil solo obtienen portadas autorizadas a través del servidor, con
  URLs firmadas. La propietaria puede ver sus propias portadas privadas.
  `public_url` no decide visibilidad; los NULL heredados se tratan como privados.
- El SQL encola `migrate_cover` para portadas antiguas de bucket público.
  El worker reserva una generación, copia WebP saneado a privado, cambia la
  fila y encola la retirada de la fuente pública comprobando otras referencias.
  Las portadas privadas heredadas se ocultan mientras sigan físicamente en
  público. GIF, rutas desconocidas o archivos inválidos pueden requerir
  recuperación manual de ese trabajo; nunca se declara la migración exitosa
  por el mero hecho de haberla encolado.
- La protección facial/moderación anterior corresponde a la galería; las
  imágenes de perfil conservan su finalidad de avatar/portada, con privacidad
  y saneamiento de metadatos propios.

## Borrado, recuperación y retención

- Borrar galería oculta la fila y encola el snapshot del ledger, incluidas
  generaciones reservadas/parciales. El worker no puede volver a publicar un
  asset borrado. Los DELETE físicos y cascadas conservan snapshots de limpieza.
- Borrar portada oculta la fila dentro de la transacción y encola su limpieza;
  HTTP 202 no significa que R2 ya haya confirmado el borrado.
- Rechazo: se retiran derivadas y se encola purga del original a 30 días.
  Bloqueo facial: no se publica y se programa también esa retención.
- Staging: la limpieza espera la expiración del intent más 5 minutos. Si falta
  recuperar el original de un asset confirmado, se difiere sin consumir
  intentos hasta su recuperación o la ventana de conservación de 30 días.
- Leases con token único, heartbeat y fencing antes/después de escrituras;
  `clock_timestamp()` evita usar un reloj congelado dentro de la transacción.
  Las escrituras R2 están acotadas, las derivadas tienen clave por generación y
  las reservas se confirman antes de PUT para sobrevivir a una caída.
- Reintentos con backoff, tombstones, reconciliación rotativa del ledger y
  dead-letter. `/moderacion` muestra hasta 50 trabajos agotados y permite
  reencolarlos con motivo y auditoría, conservando payload/idempotencia.
- La reconciliación revisa objetos conocidos por el ledger. El inventario de
  huérfanos anteriores a este pipeline y una regla lifecycle para staging son
  comprobaciones operativas pendientes en R2, no pruebas realizadas aquí.

## Configuración para una futura validación en staging

1. Revisar datos y respaldos antes de aplicar `supabase-media-pipeline.sql` en
   staging. Las constraints estrictas pueden detenerlo si existen filas
   contradictorias; no se corrigen ni borran silenciosamente esos datos.
2. Revisar y ejecutar allí `supabase-media-pipeline-verify.sql`. Comprueba
   privilegios efectivos, sobrecargas y guards NULL y termina en ROLLBACK.
   No sustituye pruebas con JWT reales de dos propietarias, fan, baneada y staff.
3. Aprovisionar explícitamente `media_staff` con una cuenta de pruebas. Ya no
   se asigna un rol administrativo a un UUID hardcodeado. Si existe
   `admin_users`, los roles activos de esa tabla también se reconocen; revisar
   ambas fuentes al retirar privilegios.
4. App: configuración Supabase pública, `SUPABASE_SERVICE_ROLE_KEY` solo en
   servidor y variables R2 existentes (`R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
   `R2_SECRET_ACCESS_KEY`, buckets privado/público y `R2_PUBLIC_URL` para avatar).
5. Bucket privado sin URL pública. CORS limitado al origen de staging, con
   PUT/GET/HEAD según uso y encabezados `Content-Type` e `If-None-Match`.
   Comprobar en navegador/R2 la firma de `Content-Length` y que un segundo PUT
   no sobrescriba. No conceder DELETE al navegador.
6. El token R2 del worker necesita escribir privado y leer/retirar fuentes de
   portada/avatares en público. Verificar ámbitos reales; no se han consultado.
7. PostgreSQL del worker con TLS y validación de certificado/hostname. Si se
   necesita CA privada, proporcionar `DATABASE_CA_PEM`; se rechazan opciones
   `ssl*` en la URL que puedan sustituir esta política. Ver `worker/README.md`.
8. Coordinar SQL, aplicación y worker: las firmas RPC y el contrato legacy han
   cambiado. No mezclar un worker/app antiguos con este esquema.

## Verificación local segura

```bash
npm test
npm run test:security
npm run check:offline
npm run build:offline
```

Los dos comandos de tests son alias del mismo conjunto offline. El runner
limpia el entorno heredado, desactiva la carga dotenv, usa fixtures sintéticos
y bloquea archivos de secretos, sockets y fetch. No arranca servicios. Los
modelos y el ejemplo facial se leen del paquete ya instalado en disco.

`scripts/test-upload-security.mjs` se conserva como arnés histórico inactivo;
ya no lee `.env` y no es evidencia de Revisión 18. Su contrato de endpoints
necesita adaptación antes de cualquier uso futuro contra staging.

Resultados reales y riesgos pendientes: [REVISION_18.md](REVISION_18.md).
