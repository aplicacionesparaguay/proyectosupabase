-- =====================================================================
-- AguaEnLaBoca · Galeria privada (upload de fotos y videos)
-- =====================================================================
-- Añade a `user_photos` las columnas que necesita la galeria privada y
-- ajusta las politicas RLS para que:
--
--   · la propietaria pueda leer, escribir y borrar sus archivos;
--   · nadie mas pueda verlos;
--   · los INSERT/UPDATE no permitan atribuir un archivo a otra cuenta.
--
-- Es idempotente: se puede ejecutar mas de una vez sin romper nada.
-- NO modifica `profiles`, ni autenticacion, ni los triggers de proteccion
-- (`trg_protect_profile` / `trg_protect_profile_insert`).
--
-- Ejecutar en el SQL Editor de Supabase.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Columnas nuevas
-- ---------------------------------------------------------------------
-- `byte_size`  : tamano real verificado por el servidor tras la subida.
-- `estado`     : 'subiendo' | 'listo' | 'fallido'. Permite distinguir lo
--                que aun no termino de procesarse de lo que ya esta listo.
-- `visibilidad`: 'publico' | 'privado'. En esta fase la galeria es privada,
--                asi que el valor por defecto es 'privado'.
--
-- Las tres son idempotentes y no destruyen datos: solo anaden informacion.
ALTER TABLE public.user_photos
  ADD COLUMN IF NOT EXISTS byte_size bigint;

ALTER TABLE public.user_photos
  ADD COLUMN IF NOT EXISTS estado text;

ALTER TABLE public.user_photos
  ADD COLUMN IF NOT EXISTS visibilidad text;

-- Valores por defecto. Se aplican despues de anadir la columna para no
-- reescribir filas en tablas con datos.
ALTER TABLE public.user_photos
  ALTER COLUMN estado      SET DEFAULT 'listo',
  ALTER COLUMN visibilidad SET DEFAULT 'privado';

-- Backfill explicito: si la tabla tuviera filas de antes, estas columnas
-- quedarian a NULL y el NOT NULL de abajo fallaria.
UPDATE public.user_photos SET estado      = 'listo'   WHERE estado      IS NULL;
UPDATE public.user_photos SET visibilidad = 'privado' WHERE visibilidad IS NULL;

ALTER TABLE public.user_photos
  ALTER COLUMN estado      SET NOT NULL,
  ALTER COLUMN visibilidad SET NOT NULL;

-- ---------------------------------------------------------------------
-- 1-bis. `public_url` debe admitir NULL
-- ---------------------------------------------------------------------
-- El esquema declara `public_url TEXT NOT NULL` (supabase-schema.sql L70).
-- Eso es incompatible con la galeria privada: un archivo guardado en el
-- bucket privado NO tiene URL publica, y su clave vive en `storage_path`.
--
-- Quitar el NOT NULL solo RELAJA la restriccion: no borra ni modifica ningun
-- valor existente. Las filas que ya tengan URL la conservan intacta.
--
-- Es idempotente: si la columna ya permitia NULL, el comando no hace nada.
ALTER TABLE public.user_photos
  ALTER COLUMN public_url DROP NOT NULL;

-- Restricciones de integridad: solo valores validos.
ALTER TABLE public.user_photos
  DROP CONSTRAINT IF EXISTS user_photos_estado_check;
ALTER TABLE public.user_photos
  ADD CONSTRAINT user_photos_estado_check
  CHECK (estado IN ('subiendo', 'listo', 'fallido'));

ALTER TABLE public.user_photos
  DROP CONSTRAINT IF EXISTS user_photos_visibilidad_check;
ALTER TABLE public.user_photos
  ADD CONSTRAINT user_photos_visibilidad_check
  CHECK (visibilidad IN ('publico', 'privado'));

-- ---------------------------------------------------------------------
-- 2. Indice
-- ---------------------------------------------------------------------
-- La galeria siempre filtra por `user_id`. Sin indice, PostgREST hace un
-- seq scan sobre toda la tabla en cada carga.
CREATE INDEX IF NOT EXISTS user_photos_user_id_idx
  ON public.user_photos (user_id);

CREATE INDEX IF NOT EXISTS user_photos_user_created_idx
  ON public.user_photos (user_id, created_at DESC);

-- ---------------------------------------------------------------------
-- 3. Politicas RLS
-- ---------------------------------------------------------------------
-- La politica actual es `FOR ALL USING (auth.uid() = user_id)`, sin WITH
-- CHECK explicito. Para `INSERT` y `UPDATE`, PostgreSQL usa el USING como
-- comprobacion implicita, asi que hoy no hay una via conocida para robar una
-- fila ajena. Aun asi se sustituye por una politica por operacion porque:
--
--   · hace explicito el requisito de propiedad en la fila RESULTANTE
--     (WITH CHECK), que es lo que impide reasignar `user_id`;
--   · evita depender de un comportamiento implicito que una edicion futura
--     podria romper;
--   · deja claro que no hay lectura publica: la galeria es privada.
--
-- DROP + CREATE con el mismo nombre es un reemplazo atomico dentro de la
-- transaccion: no hay ventana en la que la tabla quede sin politica.
-- ---------------------------------------------------------------------

ALTER TABLE public.user_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own album photos" ON public.user_photos;

-- Solo la propietaria ve sus archivos, incluidos los privados.
DROP POLICY IF EXISTS "photos_owner_read" ON public.user_photos;
CREATE POLICY "photos_owner_read" ON public.user_photos
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- INSERT: la fila debe pertenecer a quien la crea.
-- WITH CHECK evalua la fila RESULTANTE: no se puede atribuir a otra cuenta.
DROP POLICY IF EXISTS "photos_owner_insert" ON public.user_photos;
CREATE POLICY "photos_owner_insert" ON public.user_photos
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- UPDATE: propiedad ANTES (USING) y DESPUES (WITH CHECK) del cambio.
-- El WITH CHECK es lo que impide reasignar `user_id` a otra cuenta.
DROP POLICY IF EXISTS "photos_owner_update" ON public.user_photos;
CREATE POLICY "photos_owner_update" ON public.user_photos
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- DELETE: solo la propietaria.
DROP POLICY IF EXISTS "photos_owner_delete" ON public.user_photos;
CREATE POLICY "photos_owner_delete" ON public.user_photos
  FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- Nota: no hay politica para `anon`. Un visitante sin sesion no puede leer
-- ninguna fila de esta tabla, que es exactamente lo que exige una galeria
-- privada. `authenticated` tampoco puede leer archivos ajenos: las unicas
-- politicas de SELECT comparan `auth.uid()` con `user_id`.

-- ---------------------------------------------------------------------
-- 4. Verificacion posterior
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_policies int;
  v_trigger  text;
BEGIN
  SELECT count(*) INTO v_policies
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'user_photos'
    AND policyname IN (
      'photos_owner_read',
      'photos_owner_insert',
      'photos_owner_update',
      'photos_owner_delete'
    );

  IF v_policies <> 4 THEN
    RAISE WARNING 'Se esperaban 4 politicas y hay %. Revisa el estado.', v_policies;
  END IF;

  RAISE NOTICE 'user_photos: % politicas de propietario instaladas', v_policies;
  RAISE NOTICE 'user_photos: % filas totales', (SELECT count(*) FROM public.user_photos);

  -- Los triggers de proteccion del perfil no deben haber cambiado.
  SELECT string_agg(tgname, ', ' ORDER BY tgname) INTO v_trigger
  FROM pg_trigger
  WHERE tgrelid = 'public.profiles'::regclass
    AND NOT tgisinternal
    AND tgname LIKE 'trg_protect_profile%';

  RAISE NOTICE 'Triggers de proteccion de profiles: %', COALESCE(v_trigger, 'NINGUNO (revisar)');
END $$;

COMMIT;

-- =====================================================================
-- Rollback (no ejecutado)
-- ---------------------------------------------------------------------
-- Advertencia: reponer `public_url TEXT NOT NULL` SOLO es seguro si la tabla
-- no tiene filas de galeria privada. En ese caso fallaria el ALTER por
-- valores NULL. Si ya se han subido archivos, deja `public_url` nullable:
-- volver a ponerlo NOT NULL requiere primerorellenar o eliminar esas filas.
--
-- BEGIN;
--   DROP POLICY IF EXISTS "photos_owner_read"   ON public.user_photos;
--   DROP POLICY IF EXISTS "photos_owner_insert" ON public.user_photos;
--   DROP POLICY IF EXISTS "photos_owner_update" ON public.user_photos;
--   DROP POLICY IF EXISTS "photos_owner_delete" ON public.user_photos;
--   CREATE POLICY "Users can manage own album photos" ON public.user_photos
--     FOR ALL USING (auth.uid() = user_id);
--   DROP INDEX IF EXISTS public.user_photos_user_id_idx;
--   DROP INDEX IF EXISTS public.user_photos_user_created_idx;
--   -- Las columnas byte_size / estado / visibilidad NO se borran: son datos.
--   -- public_url vuelve a NOT NULL solo si no hay filas privadas:
--   -- UPDATE public.user_photos SET public_url = '' WHERE public_url IS NULL;
--   -- ALTER TABLE public.user_photos ALTER COLUMN public_url SET NOT NULL;
-- COMMIT;
-- =====================================================================