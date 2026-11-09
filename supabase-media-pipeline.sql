-- =====================================================================
-- AguaEnLaBoca - Media Pipeline / Revision 18 (PREPARADO, NO EJECUTADO)
-- =====================================================================
-- Migracion NUEVA, independiente y transaccional.
--
-- No reemplaza ni modifica destructivamente los esquemas anteriores.
-- No usa supabase/schema.sql como esquema de produccion.
--
-- QUE IMPLEMENTA
--   1. Separacion de estados: subida, procesamiento y moderacion.
--   2. Intenciones de subida con staging privado y expiracion.
--   3. Ledger de objetos de almacenamiento.
--   4. Outbox de trabajos con leases, reintentos y backoff.
--   5. Auditoria de operaciones.
--   6. Tombstones para claves borradas.
--   7. Moderacion humana con una sola decision por fotografia.
--   8. Galeria publica exclusivamente con fotos aprobadas.
--   9. Retencion del original rechazado durante 30 dias.
--  10. RLS y permisos minimos.
--
-- PRERREQUISITOS
--   - public.profiles con role, is_banned e is_verified.
--   - public.user_banners (se conserva la visibilidad explicita existente).
--   - Extension pgcrypto o gen_random_uuid() nativo de PostgreSQL 13+.
--
-- APLICAR EN: Supabase Dashboard > SQL Editor.
-- REVISAR ANTES DE EJECUTAR. Hacer copia de seguridad.
--
-- IDEMPOTENCIA
--   CREATE TABLE/INDEX IF NOT EXISTS, CREATE OR REPLACE FUNCTION,
--   DROP + CREATE para policies y triggers, INSERT ... ON CONFLICT.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Helpers generales
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.media_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.media_touch_updated_at() IS
  'Actualiza updated_at en las tablas del pipeline de media.';

-- ---------------------------------------------------------------------
-- 1. Staff de moderacion
-- ---------------------------------------------------------------------
-- Tabla propia para que el pipeline de media no dependa de que la
-- migracion administrativa antigua este aplicada. Si public.admin_users
-- existe, media_admin_role() tambien lo consulta.
--
-- No se concede ningun privilegio a anon/authenticated. El alta de staff
-- se hace desde SQL Editor (ver MEDIA_PIPELINE.md).
CREATE TABLE IF NOT EXISTS public.media_staff (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role       text NOT NULL CHECK (role IN ('admin', 'moderator')),
  active     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.media_staff ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trg_media_staff_updated_at ON public.media_staff;
CREATE TRIGGER trg_media_staff_updated_at
BEFORE UPDATE ON public.media_staff
FOR EACH ROW EXECUTE FUNCTION public.media_touch_updated_at();

-- El alta de staff es explicita. No se asignan privilegios a un UUID fijo.

-- ---------------------------------------------------------------------
-- 2. media_assets
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.media_assets (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id              uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title                 text,
  description           text,
  original_filename     text,
  mime_type             text NOT NULL,
  byte_size             bigint NOT NULL CHECK (byte_size > 0),
  width                 integer CHECK (width IS NULL OR width > 0),
  height                integer CHECK (height IS NULL OR height > 0),
  upload_status         text NOT NULL DEFAULT 'pending',
  processing_status     text NOT NULL DEFAULT 'queued',
  moderation_status     text NOT NULL DEFAULT 'pending',
  visibility            text NOT NULL DEFAULT 'private',
  faces_detected        integer NOT NULL DEFAULT 0 CHECK (faces_detected >= 0),
  original_key          text,
  protected_key         text,
  thumb_key             text,
  sha256_original       text,
  sha256_protected      text,
  detector_name         text,
  detector_version      text,
  protection_mode       text NOT NULL DEFAULT 'pixelate',
  protection_strength   integer NOT NULL DEFAULT 100,
  verification_status   text NOT NULL DEFAULT 'pending',
  processing_error      text,
  rejection_reason      text,
  reviewed_by           uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at           timestamptz,
  processed_at          timestamptz,
  original_deleted_at   timestamptz,
  deleted_at            timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT media_assets_upload_status_check
    CHECK (upload_status IN ('pending', 'committed', 'rejected', 'deleted')),
  CONSTRAINT media_assets_processing_status_check
    CHECK (processing_status IN ('queued', 'processing', 'protected', 'failed', 'deleted')),
  CONSTRAINT media_assets_moderation_status_check
    CHECK (moderation_status IN ('pending', 'pending_review', 'approved', 'rejected', 'blocked', 'deleted')),
  CONSTRAINT media_assets_visibility_check
    CHECK (visibility IN ('private', 'public')),
  CONSTRAINT media_assets_protection_mode_check
    CHECK (protection_mode IN ('pixelate', 'blur')),
  CONSTRAINT media_assets_protection_strength_check
    CHECK (protection_strength BETWEEN 1 AND 100),
  CONSTRAINT media_assets_verification_status_check
    CHECK (verification_status IN ('pending', 'passed', 'failed')),
  CONSTRAINT media_assets_sha256_original_check
    CHECK (sha256_original IS NULL OR sha256_original ~ '^[0-9a-f]{64}$'),
  CONSTRAINT media_assets_sha256_protected_check
    CHECK (sha256_protected IS NULL OR sha256_protected ~ '^[0-9a-f]{64}$'),
  CONSTRAINT media_assets_approved_fields_check
    CHECK (
      moderation_status <> 'approved'
      OR (
        processing_status = 'protected'
        AND verification_status = 'passed'
        AND protected_key IS NOT NULL
        AND deleted_at IS NULL
      )
    ),
  CONSTRAINT media_assets_rejected_reason_check
    CHECK (moderation_status <> 'rejected' OR rejection_reason IS NOT NULL)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.media_assets'::regclass
      AND conname = 'media_assets_public_requires_approved'
  ) THEN
    ALTER TABLE public.media_assets
      ADD CONSTRAINT media_assets_public_requires_approved
      CHECK (visibility <> 'public' OR moderation_status = 'approved');
  END IF;
END $$;

-- Integridad independiente de los endpoints (tambien para escrituras del worker).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.media_assets'::regclass AND conname = 'media_assets_metadata_r18') THEN
    ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_metadata_r18 CHECK (
      mime_type IN ('image/jpeg', 'image/png', 'image/webp')
      AND byte_size BETWEEN 1 AND 10485760
      AND width IS NOT NULL AND height IS NOT NULL
      AND width::bigint * height::bigint <= 50000000
      AND sha256_original IS NOT NULL
      AND (original_key IS NULL OR starts_with(original_key, 'originals/' || owner_id::text || '/' || id::text || '/'))
      AND (protected_key IS NULL OR starts_with(protected_key, 'protected/' || owner_id::text || '/' || id::text || '/'))
      AND (thumb_key IS NULL OR starts_with(thumb_key, 'thumbs/' || owner_id::text || '/' || id::text || '/'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.media_assets'::regclass AND conname = 'media_assets_review_ready_r18') THEN
    ALTER TABLE public.media_assets ADD CONSTRAINT media_assets_review_ready_r18 CHECK (
      moderation_status NOT IN ('pending_review', 'approved') OR (
        upload_status = 'committed' AND processing_status = 'protected'
        AND verification_status = 'passed' AND protected_key IS NOT NULL
        AND thumb_key IS NOT NULL AND sha256_protected IS NOT NULL
        AND detector_name IS NOT NULL AND detector_version IS NOT NULL
        AND processed_at IS NOT NULL AND deleted_at IS NULL
      )
    );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS media_assets_owner_created_idx
  ON public.media_assets (owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS media_assets_owner_keyset_idx
  ON public.media_assets (owner_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS media_assets_review_keyset_idx
  ON public.media_assets (created_at, id)
  WHERE moderation_status = 'pending_review' AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS media_assets_public_idx
  ON public.media_assets (created_at DESC)
  WHERE moderation_status = 'approved'
    AND visibility = 'public'
    AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS media_assets_pending_review_idx
  ON public.media_assets (created_at ASC)
  WHERE moderation_status = 'pending_review'
    AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS media_assets_processing_idx
  ON public.media_assets (processing_status, created_at)
  WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS media_assets_original_key_uidx
  ON public.media_assets (original_key)
  WHERE original_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS media_assets_protected_key_uidx
  ON public.media_assets (protected_key)
  WHERE protected_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS media_assets_thumb_key_uidx
  ON public.media_assets (thumb_key)
  WHERE thumb_key IS NOT NULL;

DROP TRIGGER IF EXISTS trg_media_assets_updated_at ON public.media_assets;
CREATE TRIGGER trg_media_assets_updated_at
BEFORE UPDATE ON public.media_assets
FOR EACH ROW EXECUTE FUNCTION public.media_touch_updated_at();

-- ---------------------------------------------------------------------
-- 3. media_upload_intents
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.media_upload_intents (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  object_key      text NOT NULL UNIQUE,
  original_filename text,
  mime_type       text NOT NULL,
  declared_size   bigint NOT NULL CHECK (declared_size > 0),
  max_size        bigint NOT NULL CHECK (max_size > 0),
  status          text NOT NULL DEFAULT 'created',
  media_id        uuid REFERENCES public.media_assets(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,
  committed_at    timestamptz,
  aborted_at      timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT media_upload_intents_status_check
    CHECK (status IN ('created', 'committed', 'aborted', 'expired')),
  CONSTRAINT media_upload_intents_expiry_check
    CHECK (expires_at > created_at)
);

ALTER TABLE public.media_upload_intents
  ADD COLUMN IF NOT EXISTS original_filename text;
ALTER TABLE public.media_upload_intents
  ADD COLUMN IF NOT EXISTS purpose text NOT NULL DEFAULT 'gallery';
ALTER TABLE public.media_upload_intents
  ADD COLUMN IF NOT EXISTS result_metadata jsonb;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.media_upload_intents'::regclass AND conname = 'media_upload_intents_purpose_check') THEN
    ALTER TABLE public.media_upload_intents ADD CONSTRAINT media_upload_intents_purpose_check
      CHECK (purpose IN ('gallery', 'avatar', 'cover'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS media_upload_intents_user_created_idx
  ON public.media_upload_intents (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS media_upload_intents_expiry_idx
  ON public.media_upload_intents (expires_at)
  WHERE status = 'created';

DROP TRIGGER IF EXISTS trg_media_upload_intents_updated_at ON public.media_upload_intents;
CREATE TRIGGER trg_media_upload_intents_updated_at
BEFORE UPDATE ON public.media_upload_intents
FOR EACH ROW EXECUTE FUNCTION public.media_touch_updated_at();

-- ---------------------------------------------------------------------
-- 4. storage_objects (ledger)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.storage_objects (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket      text NOT NULL,
  object_key  text NOT NULL,
  kind        text NOT NULL,
  media_id    uuid REFERENCES public.media_assets(id) ON DELETE SET NULL,
  state       text NOT NULL DEFAULT 'pending',
  sha256      text,
  byte_size   bigint,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz,
  CONSTRAINT storage_objects_bucket_check
    CHECK (bucket IN ('private', 'public')),
  CONSTRAINT storage_objects_kind_check
    CHECK (kind IN ('staging', 'original', 'protected', 'thumb', 'avatar', 'cover')),
  CONSTRAINT storage_objects_state_check
    CHECK (state IN ('pending', 'present', 'deleted', 'missing')),
  CONSTRAINT storage_objects_sha256_check
    CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT storage_objects_key_unique
    UNIQUE (bucket, object_key)
);

ALTER TABLE public.storage_objects DROP CONSTRAINT IF EXISTS storage_objects_kind_check;
ALTER TABLE public.storage_objects ADD CONSTRAINT storage_objects_kind_check
  CHECK (kind IN ('staging', 'original', 'protected', 'thumb', 'avatar', 'cover'));

CREATE INDEX IF NOT EXISTS storage_objects_media_idx
  ON public.storage_objects (media_id);
CREATE INDEX IF NOT EXISTS storage_objects_state_idx
  ON public.storage_objects (state);
CREATE INDEX IF NOT EXISTS storage_objects_reconcile_idx
  ON public.storage_objects (updated_at, id);

DROP TRIGGER IF EXISTS trg_storage_objects_updated_at ON public.storage_objects;
CREATE TRIGGER trg_storage_objects_updated_at
BEFORE UPDATE ON public.storage_objects
FOR EACH ROW EXECUTE FUNCTION public.media_touch_updated_at();

-- ---------------------------------------------------------------------
-- 5. media_jobs (outbox durable)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.media_jobs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind              text NOT NULL,
  media_id          uuid REFERENCES public.media_assets(id) ON DELETE SET NULL,
  payload           jsonb NOT NULL DEFAULT '{}'::jsonb,
  idempotency_key   text NOT NULL UNIQUE,
  status            text NOT NULL DEFAULT 'pending',
  attempts          integer NOT NULL DEFAULT 0,
  max_attempts      integer NOT NULL DEFAULT 8,
  run_after         timestamptz NOT NULL DEFAULT now(),
  locked_by         text,
  locked_until      timestamptz,
  lease_token       uuid,
  heartbeat_at      timestamptz,
  last_error        text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  completed_at      timestamptz,
  CONSTRAINT media_jobs_kind_check
    CHECK (kind IN ('process', 'delete_staging', 'delete_protected', 'purge_original', 'delete_all', 'reconcile', 'delete_profile_orphan', 'migrate_cover')),
  CONSTRAINT media_jobs_status_check
    CHECK (status IN ('pending', 'processing', 'done', 'dead')),
  CONSTRAINT media_jobs_attempts_check
    CHECK (attempts >= 0 AND max_attempts > 0)
);

ALTER TABLE public.media_jobs ADD COLUMN IF NOT EXISTS lease_token uuid;
ALTER TABLE public.media_jobs ADD COLUMN IF NOT EXISTS heartbeat_at timestamptz;
ALTER TABLE public.media_jobs DROP CONSTRAINT IF EXISTS media_jobs_kind_check;
ALTER TABLE public.media_jobs ADD CONSTRAINT media_jobs_kind_check
  CHECK (kind IN ('process', 'delete_staging', 'delete_protected', 'purge_original', 'delete_all', 'reconcile', 'delete_profile_orphan', 'migrate_cover'));

CREATE INDEX IF NOT EXISTS media_jobs_expired_lease_idx
  ON public.media_jobs (locked_until) WHERE status = 'processing';
CREATE INDEX IF NOT EXISTS media_jobs_claim_idx
  ON public.media_jobs (status, run_after, created_at)
  WHERE status IN ('pending', 'processing');
CREATE INDEX IF NOT EXISTS media_jobs_media_idx
  ON public.media_jobs (media_id, created_at DESC);
CREATE INDEX IF NOT EXISTS media_jobs_dead_idx
  ON public.media_jobs (updated_at, id) WHERE status = 'dead';

DROP TRIGGER IF EXISTS trg_media_jobs_updated_at ON public.media_jobs;
CREATE TRIGGER trg_media_jobs_updated_at
BEFORE UPDATE ON public.media_jobs
FOR EACH ROW EXECUTE FUNCTION public.media_touch_updated_at();

-- Recuperacion de intents creados por el MVP antes de tener limpieza al crear.
INSERT INTO public.storage_objects (bucket, object_key, kind, media_id, state)
SELECT 'private', object_key, 'staging', media_id, 'pending' FROM public.media_upload_intents
ON CONFLICT (bucket, object_key) DO NOTHING;
INSERT INTO public.media_jobs (kind, media_id, payload, run_after, idempotency_key)
SELECT 'delete_staging', media_id, jsonb_build_object('bucket', 'private', 'object_key', object_key),
  expires_at + interval '5 minutes', 'expire:' || id::text FROM public.media_upload_intents
ON CONFLICT (idempotency_key) DO NOTHING;

-- ---------------------------------------------------------------------
-- 6. media_reviews
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.media_reviews (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  media_id     uuid NOT NULL REFERENCES public.media_assets(id) ON DELETE CASCADE,
  reviewer_id  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  decision     text NOT NULL,
  reason       text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT media_reviews_decision_check
    CHECK (decision IN ('approved', 'rejected')),
  CONSTRAINT media_reviews_one_per_media UNIQUE (media_id),
  CONSTRAINT media_reviews_reason_check
    CHECK (decision <> 'rejected' OR (reason IS NOT NULL AND length(btrim(reason)) >= 3))
);

-- ---------------------------------------------------------------------
-- 7. media_audit_log
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.media_audit_log (
  id          bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  actor_id    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action      text NOT NULL,
  media_id    uuid,
  metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS media_audit_log_media_idx
  ON public.media_audit_log (media_id, created_at DESC);
CREATE INDEX IF NOT EXISTS media_audit_log_actor_idx
  ON public.media_audit_log (actor_id, created_at DESC);

-- ---------------------------------------------------------------------
-- 8. object_tombstones
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.object_tombstones (
  bucket      text NOT NULL,
  object_key  text NOT NULL,
  media_id    uuid,
  reason      text,
  deleted_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (bucket, object_key)
);

-- ---------------------------------------------------------------------
-- 9. user_banners: privacidad por defecto
-- ---------------------------------------------------------------------
-- NULL no expresa consentimiento para publicar. Se conservan los valores
-- explicitos y solo se completa la visibilidad desconocida como privada.
ALTER TABLE public.user_banners
  ADD COLUMN IF NOT EXISTS visibilidad text;
-- Las filas antiguas conservan su ubicacion publica. Las nuevas portadas
-- se escriben explicitamente en el bucket privado y no tienen URL permanente.
ALTER TABLE public.user_banners ADD COLUMN IF NOT EXISTS storage_bucket text NOT NULL DEFAULT 'public';
ALTER TABLE public.user_banners ALTER COLUMN public_url DROP NOT NULL;

UPDATE public.user_banners
SET visibilidad = 'privado'
WHERE visibilidad IS NULL;

ALTER TABLE public.user_banners
  ALTER COLUMN visibilidad SET DEFAULT 'privado';

ALTER TABLE public.user_banners
  ALTER COLUMN visibilidad SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.user_banners'::regclass
      AND conname = 'user_banners_visibilidad_check'
  ) THEN
    ALTER TABLE public.user_banners
      ADD CONSTRAINT user_banners_visibilidad_check
      CHECK (visibilidad IN ('publico', 'privado'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.user_banners'::regclass AND conname = 'user_banners_private_storage_r18') THEN
    ALTER TABLE public.user_banners ADD CONSTRAINT user_banners_private_storage_r18 CHECK (
      storage_bucket IN ('public', 'private') AND (
        storage_bucket <> 'private' OR (public_url IS NULL AND storage_path IS NOT NULL
          AND starts_with(storage_path, 'covers/' || user_id::text || '/'))
      )
    );
  END IF;
END $$;

DROP POLICY IF EXISTS user_banners_public_read ON public.user_banners;
CREATE INDEX IF NOT EXISTS user_banners_owner_order_idx ON public.user_banners (user_id, orden, id);
ALTER TABLE public.user_banners ENABLE ROW LEVEL SECURITY;
-- Una policy RESTRICTIVE limita tambien cualquier policy permisiva heredada.
DROP POLICY IF EXISTS user_banners_visibility_guard ON public.user_banners;
CREATE POLICY user_banners_visibility_guard ON public.user_banners
  AS RESTRICTIVE FOR SELECT TO anon, authenticated
  USING (visibilidad = 'publico' OR user_id = (SELECT auth.uid()));
CREATE POLICY user_banners_public_read
  ON public.user_banners
  FOR SELECT
  TO anon, authenticated
  USING (visibilidad = 'publico');

-- ---------------------------------------------------------------------
-- 10. Funciones de autorizacion
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.media_is_active_creator(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = p_user_id
      AND p.role = 'creator'
      AND p.is_banned IS NOT TRUE
  );
$$;

CREATE OR REPLACE FUNCTION public.media_actor_role(p_actor_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid  uuid := p_actor_id;
  v_role text;
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = v_uid AND p.is_banned IS NOT TRUE
  ) THEN
    RETURN NULL;
  END IF;

  IF to_regclass('public.media_staff') IS NOT NULL THEN
    EXECUTE
      'SELECT role FROM public.media_staff WHERE user_id = $1 AND active IS TRUE LIMIT 1'
      INTO v_role
      USING v_uid;

    IF v_role IN ('admin', 'moderator') THEN
      RETURN v_role;
    END IF;
  END IF;

  IF to_regclass('public.admin_users') IS NOT NULL THEN
    BEGIN
      EXECUTE
        'SELECT role FROM public.admin_users WHERE user_id = $1 AND active IS TRUE LIMIT 1'
        INTO v_role
        USING v_uid;

      IF v_role IN ('admin', 'moderator') THEN
        RETURN v_role;
      END IF;
    EXCEPTION WHEN undefined_column OR undefined_table THEN
      NULL;
    END;
  END IF;

  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.media_admin_role()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$ SELECT public.media_actor_role(auth.uid()); $$;

CREATE OR REPLACE FUNCTION public.media_require_actor_staff(p_actor_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_role text := public.media_actor_role(p_actor_id);
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('admin', 'moderator') THEN
    RAISE EXCEPTION 'Se requiere rol admin o moderator activo' USING ERRCODE = '42501';
  END IF;
  RETURN v_role;
END;
$$;

CREATE OR REPLACE FUNCTION public.media_require_staff()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_role text := public.media_admin_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('admin', 'moderator') THEN
    RAISE EXCEPTION 'Se requiere rol admin o moderator activo'
      USING ERRCODE = '42501';
  END IF;
  RETURN v_role;
END;
$$;

CREATE OR REPLACE FUNCTION public.media_record_audit(
  p_actor_id uuid,
  p_action   text,
  p_media_id uuid,
  p_metadata jsonb
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  INSERT INTO public.media_audit_log (actor_id, action, media_id, metadata)
  VALUES (p_actor_id, p_action, p_media_id, COALESCE(p_metadata, '{}'::jsonb));
$$;

-- ---------------------------------------------------------------------
-- 11. RPC de subida
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.media_create_upload_intent(
  p_actor_id      uuid,
  p_file_name     text,
  p_mime_type     text,
  p_declared_size bigint,
  p_purpose      text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid       uuid := p_actor_id;
  v_intent_id uuid := gen_random_uuid();
  v_ext       text;
  v_key       text;
  v_recent    integer;
  v_assets    integer;
  v_max_size  bigint := 10485760;
  v_expires   timestamptz := now() + interval '30 minutes';
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000';
  END IF;

  IF p_purpose IS NULL OR p_purpose NOT IN ('gallery', 'avatar', 'cover') THEN
    RAISE EXCEPTION 'Destino de imagen invalido' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = v_uid AND p.is_banned IS NOT TRUE)
     OR (p_purpose = 'gallery' AND NOT public.media_is_active_creator(v_uid)) THEN
    RAISE EXCEPTION 'Se requiere una cuenta de creadora activa'
      USING ERRCODE = '42501';
  END IF;

  -- Serializa las reservas de una misma cuenta para que los limites no
  -- puedan excederse mediante peticiones concurrentes.
  PERFORM pg_advisory_xact_lock(hashtextextended('media-upload:' || v_uid::text, 0));

  IF p_declared_size IS NULL OR p_declared_size <= 0 OR p_declared_size > v_max_size THEN
    RAISE EXCEPTION 'Tamano de archivo invalido' USING ERRCODE = '22023';
  END IF;

  v_ext := CASE lower(COALESCE(p_mime_type, ''))
    WHEN 'image/jpeg' THEN 'jpg'
    WHEN 'image/png'  THEN 'png'
    WHEN 'image/webp' THEN 'webp'
    ELSE NULL
  END;

  IF v_ext IS NULL THEN
    RAISE EXCEPTION 'Solo se permiten imagenes JPEG, PNG o WebP'
      USING ERRCODE = '22023';
  END IF;

  SELECT count(*)
    INTO v_recent
  FROM public.media_upload_intents i
  WHERE i.user_id = v_uid
    AND i.created_at > now() - interval '1 hour';

  IF v_recent >= 20 THEN
    RAISE EXCEPTION 'Demasiadas subidas en la ultima hora. Intenta mas tarde.'
      USING ERRCODE = '42900';
  END IF;

  SELECT count(*)
    INTO v_assets
  FROM public.media_assets a
  WHERE a.owner_id = v_uid
    AND a.deleted_at IS NULL;

  SELECT v_assets + count(*) INTO v_assets
  FROM public.media_upload_intents i
  WHERE i.user_id = v_uid AND i.status = 'created' AND i.expires_at > now();

  IF p_purpose = 'gallery' AND v_assets >= 500 THEN
    RAISE EXCEPTION 'Limite de archivos activos alcanzado'
      USING ERRCODE = '42900';
  END IF;
  IF p_purpose = 'cover' AND (
    (SELECT count(*) FROM public.user_banners b WHERE b.user_id = v_uid)
    + (SELECT count(*) FROM public.media_upload_intents i WHERE i.user_id = v_uid
       AND i.purpose = 'cover' AND i.status = 'created' AND i.expires_at > now())
  ) >= 20 THEN
    RAISE EXCEPTION 'Limite de portadas alcanzado' USING ERRCODE = '42900';
  END IF;

  v_key := 'staging/' || v_uid::text || '/' || v_intent_id::text || '.' || v_ext;

  INSERT INTO public.media_upload_intents
    (id, user_id, object_key, original_filename, mime_type, declared_size, max_size, expires_at, purpose)
  VALUES
    (
      v_intent_id,
      v_uid,
      v_key,
      NULLIF(left(btrim(COALESCE(p_file_name, '')), 200), ''),
      lower(p_mime_type),
      p_declared_size,
      v_max_size,
      v_expires,
      p_purpose
    );

  -- El ledger y la limpieza existen ANTES de emitir la URL de PUT, incluso
  -- si el navegador desaparece sin llamar a commit/abort.
  INSERT INTO public.storage_objects (bucket, object_key, kind, state)
  VALUES ('private', v_key, 'staging', 'pending');

  INSERT INTO public.media_jobs (kind, payload, run_after, idempotency_key)
  VALUES ('delete_staging', jsonb_build_object('bucket', 'private', 'object_key', v_key),
          v_expires + interval '5 minutes', 'expire:' || v_intent_id::text)
  ON CONFLICT (idempotency_key) DO NOTHING;

  PERFORM public.media_record_audit(
    v_uid,
    'upload_intent_created',
    NULL,
    jsonb_build_object(
      'intent_id', v_intent_id,
      'mime_type', lower(p_mime_type),
      'declared_size', p_declared_size,
      'file_name', left(COALESCE(p_file_name, ''), 200)
    )
  );

  RETURN jsonb_build_object(
    'intent_id', v_intent_id,
    'object_key', v_key,
    'mime_type', lower(p_mime_type),
    'max_bytes', v_max_size,
    'expires_at', v_expires
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.media_abort_upload_intent(p_intent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_intent public.media_upload_intents%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT *
    INTO v_intent
  FROM public.media_upload_intents i
  WHERE i.id = p_intent_id
    AND i.user_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Intento de subida no encontrado' USING ERRCODE = 'P0002';
  END IF;

  IF v_intent.status = 'committed' THEN
    RAISE EXCEPTION 'El archivo ya fue registrado y no se puede descartar'
      USING ERRCODE = '23505';
  END IF;

  IF v_intent.status = 'aborted' THEN
    RETURN jsonb_build_object('ok', true, 'already_aborted', true);
  END IF;

  UPDATE public.media_upload_intents
  SET status = 'aborted', aborted_at = now()
  WHERE id = v_intent.id;

  INSERT INTO public.media_jobs
    (kind, media_id, payload, run_after, idempotency_key)
  VALUES
    (
      'delete_staging',
      NULL,
      jsonb_build_object('bucket', 'private', 'object_key', v_intent.object_key),
      greatest(now(), v_intent.expires_at + interval '5 minutes'),
      'abort:' || v_intent.id::text
    )
  ON CONFLICT (idempotency_key) DO NOTHING;

  PERFORM public.media_record_audit(
    v_uid,
    'upload_intent_aborted',
    NULL,
    jsonb_build_object('intent_id', v_intent.id)
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.media_commit_upload(
  p_actor_id   uuid,
  p_intent_id  uuid,
  p_sha256     text,
  p_byte_size  bigint,
  p_width      integer,
  p_height     integer,
  p_title      text DEFAULT NULL,
  p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid        uuid := p_actor_id;
  v_intent     public.media_upload_intents%ROWTYPE;
  v_asset      public.media_assets%ROWTYPE;
  v_media_id   uuid := gen_random_uuid();
  v_ext        text;
  v_original   text;
  v_sha        text := lower(COALESCE(p_sha256, ''));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000';
  END IF;

  IF NOT public.media_is_active_creator(v_uid) THEN
    RAISE EXCEPTION 'Se requiere una cuenta de creadora activa' USING ERRCODE = '42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('media-upload:' || v_uid::text, 0));

  IF v_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Hash SHA-256 invalido' USING ERRCODE = '22023';
  END IF;

  SELECT *
    INTO v_intent
  FROM public.media_upload_intents i
  WHERE i.id = p_intent_id
    AND i.user_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Intento de subida no encontrado' USING ERRCODE = 'P0002';
  END IF;

  IF v_intent.status = 'committed' AND v_intent.media_id IS NOT NULL THEN
    SELECT *
      INTO v_asset
    FROM public.media_assets a
    WHERE a.id = v_intent.media_id
      AND a.owner_id = v_uid;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'id', v_asset.id,
        'upload_status', v_asset.upload_status,
        'processing_status', v_asset.processing_status,
        'moderation_status', v_asset.moderation_status,
        'duplicate', true
      );
    END IF;
  END IF;

  IF v_intent.purpose <> 'gallery' THEN
    RAISE EXCEPTION 'El intento no pertenece a la galeria' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(*) FROM public.media_assets WHERE owner_id = v_uid AND deleted_at IS NULL) >= 500 THEN
    RAISE EXCEPTION 'Limite de archivos activos alcanzado' USING ERRCODE = '42900';
  END IF;

  IF v_intent.status <> 'created' THEN
    RAISE EXCEPTION 'El intento de subida ya no esta disponible'
      USING ERRCODE = '23514';
  END IF;

  IF now() > v_intent.expires_at THEN
    -- No escribir y luego lanzar: RAISE revertiria esas escrituras.
    -- La limpieza ya fue encolada al crear el intent.
    RAISE EXCEPTION 'El intento de subida expiro' USING ERRCODE = '57014';
  END IF;

  IF p_byte_size IS NULL OR p_byte_size <= 0 OR p_byte_size > v_intent.max_size
     OR p_byte_size <> v_intent.declared_size THEN
    RAISE EXCEPTION 'Tamano real invalido' USING ERRCODE = '22023';
  END IF;

  IF p_width IS NULL OR p_height IS NULL OR p_width <= 0 OR p_height <= 0
     OR p_width::bigint * p_height::bigint > 50000000 THEN
    RAISE EXCEPTION 'Dimensiones invalidas' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.object_tombstones t
    WHERE t.bucket = 'private'
      AND t.object_key = v_intent.object_key
  ) THEN
    RAISE EXCEPTION 'El objeto fue descartado y no puede registrarse'
      USING ERRCODE = '23514';
  END IF;

  v_ext := CASE lower(v_intent.mime_type)
    WHEN 'image/jpeg' THEN 'jpg'
    WHEN 'image/png'  THEN 'png'
    WHEN 'image/webp' THEN 'webp'
    ELSE NULL
  END;

  IF v_ext IS NULL THEN
    RAISE EXCEPTION 'Tipo MIME no soportado' USING ERRCODE = '22023';
  END IF;

  v_original :=
    'originals/' || v_uid::text || '/' || v_media_id::text || '/' ||
    left(v_sha, 16) || '.' || v_ext;

  INSERT INTO public.media_assets
    (
      id, owner_id, title, description, original_filename, mime_type,
      byte_size, width, height, upload_status, processing_status,
      moderation_status, visibility, original_key, sha256_original
    )
  VALUES
    (
      v_media_id,
      v_uid,
      NULLIF(left(btrim(COALESCE(p_title, '')), 120), ''),
      NULLIF(left(btrim(COALESCE(p_description, '')), 1000), ''),
      v_intent.original_filename,
      lower(v_intent.mime_type),
      p_byte_size,
      p_width,
      p_height,
      'committed',
      'queued',
      'pending',
      'private',
      v_original,
      v_sha
    );

  INSERT INTO public.storage_objects
    (bucket, object_key, kind, media_id, state, sha256, byte_size)
  VALUES
    ('private', v_intent.object_key, 'staging', v_media_id, 'present', v_sha, p_byte_size),
    ('private', v_original, 'original', v_media_id, 'pending', v_sha, p_byte_size)
  ON CONFLICT (bucket, object_key) DO UPDATE
  SET
    media_id = EXCLUDED.media_id,
    kind = EXCLUDED.kind,
    state = EXCLUDED.state,
    sha256 = EXCLUDED.sha256,
    byte_size = EXCLUDED.byte_size;

  UPDATE public.media_upload_intents
  SET status = 'committed', media_id = v_media_id, committed_at = now()
  WHERE id = v_intent.id;

  INSERT INTO public.media_jobs (kind, media_id, payload, idempotency_key)
  VALUES (
    'process',
    v_media_id,
    jsonb_build_object('media_id', v_media_id),
    'process:' || v_media_id::text
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  PERFORM public.media_record_audit(
    v_uid,
    'media_committed',
    v_media_id,
    jsonb_build_object(
      'intent_id', v_intent.id,
      'byte_size', p_byte_size,
      'width', p_width,
      'height', p_height,
      'sha256_original', v_sha
    )
  );

  RETURN jsonb_build_object(
    'id', v_media_id,
    'upload_status', 'committed',
    'processing_status', 'queued',
    'moderation_status', 'pending',
    'duplicate', false
  );
END;
$$;

-- El nombre original se guarda en el intento y lo usa el commit.
-- El cliente no puede cambiar la clave, el propietario ni el MIME.

-- ---------------------------------------------------------------------
-- 12. RPC de propietaria y galeria publica
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.media_request_delete(p_media_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid          uuid := auth.uid();
  v_asset        public.media_assets%ROWTYPE;
  v_staging_key  text;
  v_objects      jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000';
  END IF;

  SELECT *
    INTO v_asset
  FROM public.media_assets a
  WHERE a.id = p_media_id
    AND a.owner_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Archivo no encontrado' USING ERRCODE = 'P0002';
  END IF;

  IF v_asset.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'already_deleted', true);
  END IF;

  SELECT object_key
    INTO v_staging_key
  FROM public.media_upload_intents i
  WHERE i.media_id = v_asset.id
    AND i.status = 'committed'
  ORDER BY i.committed_at DESC NULLS LAST
  LIMIT 1;

  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_objects FROM (
    SELECT o.bucket, o.kind, o.object_key FROM public.storage_objects o
    WHERE o.media_id = v_asset.id AND o.state <> 'deleted'
    UNION
    SELECT 'private', k.kind, k.object_key FROM (VALUES
      ('original', v_asset.original_key), ('protected', v_asset.protected_key),
      ('thumb', v_asset.thumb_key), ('staging', v_staging_key)
    ) AS k(kind, object_key) WHERE k.object_key IS NOT NULL
  ) x;

  UPDATE public.media_assets
  SET
    deleted_at = now(),
    visibility = 'private',
    moderation_status = 'deleted',
    processing_status = 'deleted',
    upload_status = 'deleted',
    protected_key = NULL,
    thumb_key = NULL,
    original_key = NULL
  WHERE id = v_asset.id;

  INSERT INTO public.media_jobs (kind, media_id, payload, idempotency_key)
  VALUES (
    'delete_all',
    v_asset.id,
    jsonb_build_object('objects', v_objects),
    'delete_all:' || v_asset.id::text
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  PERFORM public.media_record_audit(
    v_uid,
    'media_delete_requested',
    v_asset.id,
    jsonb_build_object('previous_moderation_status', v_asset.moderation_status)
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

-- Un DELETE fisico (incluida la cascada de auth.users) conserva un snapshot
-- durable ANTES de que las FK pongan media_id a NULL en jobs/ledger.
CREATE OR REPLACE FUNCTION public.media_before_asset_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE v_objects jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(x), '[]'::jsonb) INTO v_objects FROM (
    SELECT o.bucket, o.kind, o.object_key FROM public.storage_objects o WHERE o.media_id = OLD.id
    UNION
    SELECT 'private', k.kind, k.object_key FROM (VALUES
      ('original', OLD.original_key), ('protected', OLD.protected_key), ('thumb', OLD.thumb_key)
    ) AS k(kind, object_key) WHERE k.object_key IS NOT NULL
  ) x;
  INSERT INTO public.media_jobs (kind, payload, idempotency_key)
  VALUES ('delete_all', jsonb_build_object('objects', v_objects), 'physical_delete:' || OLD.id::text)
  ON CONFLICT (idempotency_key) DO NOTHING;
  RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS trg_media_before_asset_delete ON public.media_assets;
CREATE TRIGGER trg_media_before_asset_delete BEFORE DELETE ON public.media_assets
FOR EACH ROW EXECUTE FUNCTION public.media_before_asset_delete();

CREATE OR REPLACE FUNCTION public.media_log_owner_original_access(p_media_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_asset public.media_assets%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN false;
  END IF;

  SELECT *
    INTO v_asset
  FROM public.media_assets a
  WHERE a.id = p_media_id
    AND a.owner_id = v_uid
    AND a.original_key IS NOT NULL
    AND a.original_deleted_at IS NULL
    AND a.deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  PERFORM public.media_record_audit(
    v_uid,
    'owner_original_access',
    v_asset.id,
    jsonb_build_object('moderation_status', v_asset.moderation_status)
  );

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.public_approved_media_count(target_user_id uuid)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT count(*)
  FROM public.media_assets a
  WHERE a.owner_id = target_user_id
    AND a.moderation_status = 'approved'
    AND a.visibility = 'public'
    AND a.processing_status = 'protected'
    AND a.verification_status = 'passed'
    AND a.deleted_at IS NULL
    AND public.media_is_active_creator(a.owner_id);
$$;

CREATE OR REPLACE FUNCTION public.public_media_list(
  p_user_id uuid,
  p_limit   integer DEFAULT 40,
  p_offset  integer DEFAULT 0,
  p_after_created_at timestamptz DEFAULT NULL,
  p_after_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id            uuid,
  owner_id      uuid,
  title         text,
  description   text,
  mime_type     text,
  width         integer,
  height        integer,
  thumb_key     text,
  protected_key text,
  created_at    timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    a.id,
    a.owner_id,
    a.title,
    a.description,
    a.mime_type,
    a.width,
    a.height,
    a.thumb_key,
    a.protected_key,
    a.created_at
  FROM public.media_assets a
  WHERE a.owner_id = p_user_id
    AND a.moderation_status = 'approved'
    AND a.visibility = 'public'
    AND a.processing_status = 'protected'
    AND a.verification_status = 'passed'
    AND a.deleted_at IS NULL
    AND public.media_is_active_creator(a.owner_id)
    AND (p_after_created_at IS NULL OR (a.created_at, a.id) < (p_after_created_at, p_after_id))
  ORDER BY a.created_at DESC, a.id DESC
  LIMIT greatest(1, least(COALESCE(p_limit, 40), 101))
  OFFSET greatest(0, COALESCE(p_offset, 0));
$$;

-- ---------------------------------------------------------------------
-- 13. RPC de moderacion
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.media_moderation_queue(
  p_actor_id uuid,
  p_limit  integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_after_created_at timestamptz DEFAULT NULL,
  p_after_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id                  uuid,
  owner_id            uuid,
  display_name        text,
  username            text,
  title               text,
  mime_type           text,
  byte_size           bigint,
  width               integer,
  height              integer,
  faces_detected      integer,
  detector_name       text,
  detector_version    text,
  protection_mode     text,
  protection_strength integer,
  verification_status text,
  protected_key       text,
  thumb_key           text,
  created_at          timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM public.media_require_actor_staff(p_actor_id);

  RETURN QUERY
  SELECT
    a.id,
    a.owner_id,
    p.display_name,
    p.username,
    a.title,
    a.mime_type,
    a.byte_size,
    a.width,
    a.height,
    a.faces_detected,
    a.detector_name,
    a.detector_version,
    a.protection_mode,
    a.protection_strength,
    a.verification_status,
    a.protected_key,
    a.thumb_key,
    a.created_at
  FROM public.media_assets a
  LEFT JOIN public.profiles p ON p.id = a.owner_id
  WHERE a.moderation_status = 'pending_review'
    AND a.processing_status = 'protected'
    AND a.verification_status = 'passed'
    AND a.protected_key IS NOT NULL
    AND a.deleted_at IS NULL
    AND (p_after_created_at IS NULL OR (a.created_at, a.id) > (p_after_created_at, p_after_id))
  ORDER BY a.created_at ASC, a.id ASC
  LIMIT greatest(1, least(COALESCE(p_limit, 50), 101))
  OFFSET greatest(0, COALESCE(p_offset, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.media_staff_list_owner_media(
  p_actor_id uuid,
  p_owner_id uuid,
  p_limit    integer DEFAULT 100,
  p_offset   integer DEFAULT 0
)
RETURNS TABLE (
  id                uuid,
  owner_id          uuid,
  title             text,
  mime_type         text,
  byte_size         bigint,
  width             integer,
  height            integer,
  upload_status     text,
  processing_status text,
  moderation_status text,
  verification_status text,
  protected_key     text,
  thumb_key         text,
  rejection_reason  text,
  created_at        timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM public.media_require_actor_staff(p_actor_id);

  RETURN QUERY
  SELECT
    a.id,
    a.owner_id,
    a.title,
    a.mime_type,
    a.byte_size,
    a.width,
    a.height,
    a.upload_status,
    a.processing_status,
    a.moderation_status,
    a.verification_status,
    a.protected_key,
    a.thumb_key,
    a.rejection_reason,
    a.created_at
  FROM public.media_assets a
  WHERE a.owner_id = p_owner_id
    AND a.deleted_at IS NULL
  ORDER BY a.created_at DESC, a.id DESC
  LIMIT greatest(1, least(COALESCE(p_limit, 100), 200))
  OFFSET greatest(0, COALESCE(p_offset, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.media_approve(p_media_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_role  text := public.media_require_staff();
  v_asset public.media_assets%ROWTYPE;
BEGIN
  SELECT *
    INTO v_asset
  FROM public.media_assets a
  WHERE a.id = p_media_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Archivo no encontrado' USING ERRCODE = 'P0002';
  END IF;

  IF v_asset.moderation_status <> 'pending_review' THEN
    RAISE EXCEPTION 'La fotografia no esta pendiente de revision'
      USING ERRCODE = '23514';
  END IF;

  IF NOT public.media_is_active_creator(v_asset.owner_id) THEN
    RAISE EXCEPTION 'La cuenta de la propietaria no esta activa' USING ERRCODE = '42501';
  END IF;

  IF v_asset.processing_status <> 'protected'
     OR v_asset.verification_status <> 'passed'
      OR v_asset.protected_key IS NULL
     OR v_asset.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'La fotografia no tiene una copia protegida verificada'
      USING ERRCODE = '23514';
  END IF;

  IF EXISTS (SELECT 1 FROM public.media_reviews r WHERE r.media_id = v_asset.id) THEN
    RAISE EXCEPTION 'La fotografia ya tiene una decision registrada'
      USING ERRCODE = '23505';
  END IF;

  UPDATE public.media_assets
  SET
    moderation_status = 'approved',
    visibility = 'public',
    reviewed_by = v_uid,
    reviewed_at = now(),
    rejection_reason = NULL
  WHERE id = v_asset.id;

  INSERT INTO public.media_reviews (media_id, reviewer_id, decision)
  VALUES (v_asset.id, v_uid, 'approved');

  PERFORM public.media_record_audit(
    v_uid,
    'media_approved',
    v_asset.id,
    jsonb_build_object('reviewer_role', v_role)
  );

  RETURN jsonb_build_object('ok', true, 'status', 'approved');
END;
$$;

CREATE OR REPLACE FUNCTION public.media_reject(p_media_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_role     text := public.media_require_staff();
  v_asset    public.media_assets%ROWTYPE;
  v_reason   text := btrim(COALESCE(p_reason, ''));
  v_payload  jsonb;
BEGIN
  IF length(v_reason) < 3 OR length(v_reason) > 500 THEN
    RAISE EXCEPTION 'El motivo de rechazo debe tener entre 3 y 500 caracteres'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
    INTO v_asset
  FROM public.media_assets a
  WHERE a.id = p_media_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Archivo no encontrado' USING ERRCODE = 'P0002';
  END IF;

  IF v_asset.moderation_status <> 'pending_review' THEN
    RAISE EXCEPTION 'La fotografia no esta pendiente de revision'
      USING ERRCODE = '23514';
  END IF;

  IF EXISTS (SELECT 1 FROM public.media_reviews r WHERE r.media_id = v_asset.id) THEN
    RAISE EXCEPTION 'La fotografia ya tiene una decision registrada'
      USING ERRCODE = '23505';
  END IF;

  v_payload := jsonb_build_object(
    'objects', jsonb_build_array(
      jsonb_build_object('bucket', 'private', 'kind', 'protected', 'object_key', v_asset.protected_key),
      jsonb_build_object('bucket', 'private', 'kind', 'thumb', 'object_key', v_asset.thumb_key)
    )
  );

  UPDATE public.media_assets
  SET
    moderation_status = 'rejected',
    visibility = 'private',
    rejection_reason = v_reason,
    reviewed_by = v_uid,
    reviewed_at = now(),
    protected_key = NULL,
    thumb_key = NULL
  WHERE id = v_asset.id;

  INSERT INTO public.media_reviews (media_id, reviewer_id, decision, reason)
  VALUES (v_asset.id, v_uid, 'rejected', v_reason);

  INSERT INTO public.media_jobs (kind, media_id, payload, idempotency_key)
  VALUES (
    'delete_protected',
    v_asset.id,
    v_payload,
    'reject_protected:' || v_asset.id::text
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  INSERT INTO public.media_jobs (kind, media_id, payload, run_after, idempotency_key)
  VALUES (
    'purge_original',
    v_asset.id,
    jsonb_build_object(
      'bucket', 'private',
      'object_key', v_asset.original_key,
      'retention_days', 30
    ),
    now() + interval '30 days',
    'reject_original:' || v_asset.id::text
  )
  ON CONFLICT (idempotency_key) DO NOTHING;

  PERFORM public.media_record_audit(
    v_uid,
    'media_rejected',
    v_asset.id,
    jsonb_build_object(
      'reviewer_role', v_role,
      'reason', v_reason,
      'retention_days', 30
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'status', 'rejected'
  );
END;
$$;

-- ---------------------------------------------------------------------
-- 14. Imagenes de perfil: staging privado, derivadas sin EXIF y ledger durable
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.media_prepare_profile_image(p_actor_id uuid, p_intent_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE v_i public.media_upload_intents%ROWTYPE; v_key text; v_bucket text;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = p_actor_id AND p.is_banned IS NOT TRUE) THEN
    RAISE EXCEPTION 'Cuenta no activa' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_i FROM public.media_upload_intents WHERE id = p_intent_id AND user_id = p_actor_id FOR UPDATE;
  IF NOT FOUND OR v_i.status <> 'created' OR v_i.purpose NOT IN ('avatar', 'cover') OR v_i.expires_at <= now() THEN
    RAISE EXCEPTION 'Intento de imagen no disponible' USING ERRCODE = '23514';
  END IF;
  v_key := CASE v_i.purpose WHEN 'avatar' THEN 'avatars/' ELSE 'covers/' END || p_actor_id::text || '/' || v_i.id::text || '.webp';
  v_bucket := CASE v_i.purpose WHEN 'avatar' THEN 'public' ELSE 'private' END;
  IF EXISTS (SELECT 1 FROM public.object_tombstones WHERE bucket = v_bucket AND object_key = v_key) THEN
    RAISE EXCEPTION 'Objeto eliminado' USING ERRCODE = '23514';
  END IF;
  INSERT INTO public.storage_objects (bucket, object_key, kind, state)
  VALUES (v_bucket, v_key, v_i.purpose, 'pending') ON CONFLICT (bucket, object_key) DO NOTHING;
  INSERT INTO public.media_jobs (kind, payload, run_after, idempotency_key)
  VALUES ('delete_profile_orphan', jsonb_build_object('bucket', v_bucket, 'object_key', v_key, 'kind', v_i.purpose, 'user_id', p_actor_id),
    greatest(now() + interval '1 hour', v_i.expires_at + interval '5 minutes'), 'profile_orphan:' || v_i.id::text)
  ON CONFLICT (idempotency_key) DO NOTHING;
  RETURN jsonb_build_object('object_key', v_key, 'bucket', v_bucket);
END;
$$;

CREATE OR REPLACE FUNCTION public.media_commit_profile_image(
  p_actor_id uuid, p_intent_id uuid, p_sha256 text, p_byte_size bigint,
  p_public_url text, p_visibility text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE v_i public.media_upload_intents%ROWTYPE; v_key text; v_bucket text; v_result jsonb; v_old_url text; v_old_key text;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = p_actor_id AND p.is_banned IS NOT TRUE) THEN
    RAISE EXCEPTION 'Cuenta no activa' USING ERRCODE = '42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('media-upload:' || p_actor_id::text, 0));
  SELECT * INTO v_i FROM public.media_upload_intents WHERE id = p_intent_id AND user_id = p_actor_id FOR UPDATE;
  IF NOT FOUND OR v_i.purpose NOT IN ('avatar', 'cover') THEN
    RAISE EXCEPTION 'Intento no encontrado' USING ERRCODE = 'P0002';
  END IF;
  IF v_i.status = 'committed' THEN RETURN v_i.result_metadata; END IF;
  IF v_i.status <> 'created' OR v_i.expires_at <= now() THEN
    RAISE EXCEPTION 'Intento no disponible' USING ERRCODE = '23514';
  END IF;
  IF p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' OR p_byte_size IS NULL OR p_byte_size NOT BETWEEN 1 AND 10485760
     OR p_visibility IS NULL OR p_visibility NOT IN ('publico', 'privado') THEN
    RAISE EXCEPTION 'Metadatos invalidos' USING ERRCODE = '22023';
  END IF;
  v_key := CASE v_i.purpose WHEN 'avatar' THEN 'avatars/' ELSE 'covers/' END || p_actor_id::text || '/' || v_i.id::text || '.webp';
  v_bucket := CASE v_i.purpose WHEN 'avatar' THEN 'public' ELSE 'private' END;
  PERFORM 1 FROM public.storage_objects WHERE bucket = v_bucket AND object_key = v_key AND state = 'pending' FOR UPDATE;
  IF NOT FOUND OR EXISTS (SELECT 1 FROM public.object_tombstones WHERE bucket = v_bucket AND object_key = v_key) THEN
    RAISE EXCEPTION 'Falta la reserva del objeto' USING ERRCODE = '23514';
  END IF;
  IF v_i.purpose = 'cover' THEN
    IF (SELECT count(*) FROM public.user_banners WHERE user_id = p_actor_id) >= 20 THEN
      RAISE EXCEPTION 'Limite de portadas alcanzado' USING ERRCODE = '42900';
    END IF;
    INSERT INTO public.user_banners (id, user_id, storage_path, storage_bucket, public_url, visibilidad, orden)
    SELECT v_i.id, p_actor_id, v_key, 'private', NULL, p_visibility, COALESCE(max(b.orden), -1) + 1
    FROM public.user_banners b WHERE b.user_id = p_actor_id;
  ELSE
    IF p_public_url IS NULL OR p_public_url !~ '^https://[^/]+/' OR right(p_public_url, length(v_key)) <> v_key THEN
      RAISE EXCEPTION 'URL de avatar invalida' USING ERRCODE = '22023';
    END IF;
    SELECT avatar_key INTO v_old_url FROM public.profiles WHERE id = p_actor_id FOR UPDATE;
    UPDATE public.profiles SET avatar_key = p_public_url WHERE id = p_actor_id;
    v_old_key := regexp_replace(COALESCE(v_old_url, ''), '^https://[^/]+/', '');
    IF EXISTS (SELECT 1 FROM public.storage_objects WHERE bucket = 'public' AND object_key = v_old_key AND kind = 'avatar') THEN
      INSERT INTO public.media_jobs (kind, payload, idempotency_key)
      VALUES ('delete_profile_orphan', jsonb_build_object('bucket', 'public', 'object_key', v_old_key, 'kind', 'avatar', 'user_id', p_actor_id),
        'old_avatar:' || v_old_key) ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;
  END IF;
  UPDATE public.storage_objects SET state = 'present', sha256 = p_sha256, byte_size = p_byte_size
  WHERE bucket = v_bucket AND object_key = v_key;
  v_result := jsonb_build_object('key', v_i.id, 'byteSize', p_byte_size, 'contentType', 'image/webp',
    'isVideo', false, 'bucket', v_bucket, 'publicUrl', CASE WHEN v_i.purpose = 'avatar' THEN p_public_url ELSE NULL END);
  UPDATE public.media_upload_intents SET status = 'committed', committed_at = now(), result_metadata = v_result WHERE id = v_i.id;
  PERFORM public.media_record_audit(p_actor_id, 'profile_image_committed', NULL,
    jsonb_build_object('intent_id', v_i.id, 'purpose', v_i.purpose, 'visibility', p_visibility));
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.media_before_cover_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE v_key text := regexp_replace(COALESCE(OLD.storage_path, OLD.public_url, ''), '^https?://[^/]+/', '');
BEGIN
  IF v_key <> '' THEN
    IF NOT starts_with(v_key, 'covers/' || OLD.user_id::text || '/') OR v_key LIKE '%/../%' OR v_key LIKE '%/./%' THEN
      RAISE EXCEPTION 'La portada requiere reconciliacion de almacenamiento' USING ERRCODE = '23514';
    END IF;
    INSERT INTO public.media_jobs (kind, payload, idempotency_key)
    VALUES ('delete_profile_orphan', jsonb_build_object('bucket', OLD.storage_bucket, 'kind', 'cover', 'object_key', v_key, 'user_id', OLD.user_id),
      'delete_cover:' || OLD.id::text) ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;
  RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS trg_media_before_cover_delete ON public.user_banners;
CREATE TRIGGER trg_media_before_cover_delete BEFORE DELETE ON public.user_banners
FOR EACH ROW EXECUTE FUNCTION public.media_before_cover_delete();

-- Migracion durable de portadas heredadas: el worker copia bytes saneados
-- al bucket privado antes de retirar la copia publica. No se adivina visibilidad.
INSERT INTO public.media_jobs (kind, payload, idempotency_key)
SELECT 'migrate_cover', jsonb_build_object('banner_id', b.id), 'migrate_cover:' || b.id::text
FROM public.user_banners b WHERE b.storage_bucket = 'public'
ON CONFLICT (idempotency_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.media_request_delete_cover(p_banner_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado' USING ERRCODE = '28000'; END IF;
  DELETE FROM public.user_banners WHERE id = p_banner_id AND user_id = auth.uid();
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------
-- 15. Dead-letter: lectura sin payload/claves y recuperacion staff auditada
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.media_dead_jobs(p_limit integer DEFAULT 50)
RETURNS TABLE (id uuid, kind text, media_id uuid, attempts integer, max_attempts integer, last_error text, updated_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM public.media_require_staff();
  RETURN QUERY SELECT j.id, j.kind, j.media_id, j.attempts, j.max_attempts,
    'El trabajo requiere recuperacion manual.'::text, j.updated_at
  FROM public.media_jobs j WHERE j.status = 'dead'
  ORDER BY j.updated_at, j.id LIMIT greatest(1, least(COALESCE(p_limit, 50), 100));
END;
$$;

CREATE OR REPLACE FUNCTION public.media_retry_dead_job(p_job_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE v_role text := public.media_require_staff(); v_job public.media_jobs%ROWTYPE;
BEGIN
  IF length(btrim(COALESCE(p_reason, ''))) NOT BETWEEN 3 AND 500 THEN
    RAISE EXCEPTION 'Motivo de recuperacion invalido' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_job FROM public.media_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'dead' THEN
    RAISE EXCEPTION 'El trabajo no esta en dead-letter' USING ERRCODE = '23514';
  END IF;
  IF v_job.kind = 'process' THEN
    PERFORM 1 FROM public.media_assets a WHERE a.id = v_job.media_id
      AND a.deleted_at IS NULL AND a.moderation_status = 'pending' FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'El archivo ya no puede reprocesarse' USING ERRCODE = '23514';
    END IF;
    UPDATE public.media_assets SET processing_status = 'queued', processing_error = NULL
    WHERE id = v_job.media_id;
  END IF;
  UPDATE public.media_jobs SET status = 'pending', attempts = 0, run_after = now(),
    locked_by = NULL, locked_until = NULL, lease_token = NULL, heartbeat_at = NULL,
    last_error = NULL, completed_at = NULL WHERE id = v_job.id;
  PERFORM public.media_record_audit(auth.uid(), 'dead_job_retried', v_job.media_id,
    jsonb_build_object('job_id', v_job.id, 'previous_attempts', v_job.attempts, 'reason', btrim(p_reason), 'role', v_role));
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------
-- 16. RLS y permisos
-- ---------------------------------------------------------------------

ALTER TABLE public.media_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.media_upload_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.media_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.media_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.storage_objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.media_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.object_tombstones ENABLE ROW LEVEL SECURITY;

-- Ninguna tabla con claves/ledger es una API para el navegador, ni siquiera
-- para su propietaria. Se revocan tambien grants por columna y PUBLIC.
DO $$
DECLARE v_table text; v_columns text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'media_assets', 'media_upload_intents', 'media_reviews', 'media_jobs',
    'storage_objects', 'media_audit_log', 'object_tombstones', 'media_staff', 'user_banners'
  ] LOOP
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated', v_table);
    SELECT string_agg(quote_ident(attname), ', ') INTO v_columns
    FROM pg_attribute WHERE attrelid = format('public.%I', v_table)::regclass
      AND attnum > 0 AND NOT attisdropped;
    EXECUTE format('REVOKE SELECT (%1$s), INSERT (%1$s), UPDATE (%1$s), REFERENCES (%1$s) ON TABLE public.%2$I FROM PUBLIC, anon, authenticated', v_columns, v_table);
    EXECUTE format('DROP POLICY IF EXISTS media_client_deny ON public.%I', v_table);
    EXECUTE format('CREATE POLICY media_client_deny ON public.%I AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false)', v_table);
  END LOOP;
END $$;
REVOKE ALL ON SEQUENCE public.media_audit_log_id_seq FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.media_assets, public.media_upload_intents, public.user_banners TO service_role;

DROP POLICY IF EXISTS media_assets_owner_read ON public.media_assets;
CREATE POLICY media_assets_owner_read
  ON public.media_assets
  FOR SELECT
  TO authenticated
  USING (owner_id = auth.uid());

DROP POLICY IF EXISTS media_upload_intents_owner_read ON public.media_upload_intents;
CREATE POLICY media_upload_intents_owner_read
  ON public.media_upload_intents
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS media_reviews_owner_read ON public.media_reviews;
CREATE POLICY media_reviews_owner_read
  ON public.media_reviews
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.media_assets a
      WHERE a.id = media_reviews.media_id
        AND a.owner_id = auth.uid()
    )
  );

-- Sin policies de escritura: todas las mutaciones pasan por RPC
-- SECURITY DEFINER o por el worker con privilegios de servidor.

-- Se cierran TODAS las sobrecargas, incluidas las firmas del MVP que puedan
-- seguir instaladas. No se borran funciones ni datos de una instalacion previa.
DO $$
DECLARE v_function regprocedure;
BEGIN
  FOR v_function IN
    SELECT p.oid::regprocedure FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN (
      'media_touch_updated_at', 'media_is_active_creator', 'media_actor_role',
      'media_admin_role', 'media_require_staff', 'media_require_actor_staff', 'media_record_audit',
      'media_create_upload_intent', 'media_abort_upload_intent', 'media_commit_upload',
      'media_request_delete', 'media_log_owner_original_access', 'public_approved_media_count',
      'public_media_list', 'media_moderation_queue', 'media_staff_list_owner_media',
      'media_approve', 'media_reject', 'media_before_asset_delete', 'media_dead_jobs', 'media_retry_dead_job',
      'media_prepare_profile_image', 'media_commit_profile_image', 'media_before_cover_delete', 'media_request_delete_cover'
    )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role', v_function);
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.media_admin_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.media_create_upload_intent(uuid, text, text, bigint, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.media_abort_upload_intent(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.media_commit_upload(uuid, uuid, text, bigint, integer, integer, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.media_request_delete(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.media_log_owner_original_access(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.public_approved_media_count(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_media_list(uuid, integer, integer, timestamptz, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.media_moderation_queue(uuid, integer, integer, timestamptz, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.media_staff_list_owner_media(uuid, uuid, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.media_approve(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.media_reject(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.media_dead_jobs(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.media_retry_dead_job(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.media_prepare_profile_image(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.media_commit_profile_image(uuid, uuid, text, bigint, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.media_request_delete_cover(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 17. Verificacion estructural (no acredita permisos ni staging)
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_tables integer;
  v_funcs  integer;
BEGIN
  SELECT count(*)
    INTO v_tables
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name IN (
      'media_assets',
      'media_upload_intents',
      'media_jobs',
      'storage_objects',
      'media_reviews',
      'media_audit_log',
      'object_tombstones',
      'media_staff'
    );

  SELECT count(DISTINCT p.proname)
    INTO v_funcs
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'media_create_upload_intent',
      'media_abort_upload_intent',
      'media_commit_upload',
      'media_request_delete',
      'media_moderation_queue',
      'media_approve',
      'media_reject',
      'public_media_list',
      'public_approved_media_count'
    );

  IF v_tables <> 8 THEN
    RAISE EXCEPTION 'Se esperaban 8 tablas del pipeline y hay %', v_tables;
  END IF;

  IF v_funcs <> 9 THEN
    RAISE EXCEPTION 'Se esperaban 9 funciones del pipeline y hay %', v_funcs;
  END IF;

  RAISE NOTICE 'Media pipeline: % tablas propias y % RPC principales presentes; falta validar privilegios y staging.', v_tables, v_funcs;
  RAISE NOTICE 'Alta de staff: INSERT INTO public.media_staff (user_id, role) VALUES (''<UUID>'', ''moderator'');';
END $$;

COMMIT;
