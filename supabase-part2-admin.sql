BEGIN;

-- ============================================================================
-- BLOQUE 0 · Helper updated_at
-- Se reutiliza si ya existe.
-- ============================================================================

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'update_updated_at_column'
  ) THEN

    CREATE FUNCTION public.update_updated_at_column()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $fn$
    BEGIN
      NEW.updated_at = now();
      RETURN NEW;
    END;
    $fn$;

  END IF;
END
$do$;


-- ============================================================================
-- BLOQUE 1 · admin_users
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.admin_users (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL,
  role        text        NOT NULL,
  active      boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid,
  updated_at  timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT admin_users_role_check
    CHECK (role IN ('admin', 'moderator')),

  CONSTRAINT admin_users_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES public.profiles(id)
    ON DELETE CASCADE,

  CONSTRAINT admin_users_created_by_fkey
    FOREIGN KEY (created_by)
    REFERENCES public.profiles(id)
    ON DELETE SET NULL
);

COMMENT ON TABLE public.admin_users
  IS 'Permisos administrativos. Solo el propietario escribe aqui (SQL).';

COMMENT ON COLUMN public.admin_users.user_id
  IS 'profiles.id del usuario con permiso.';

COMMENT ON COLUMN public.admin_users.role
  IS 'admin | moderator';

COMMENT ON COLUMN public.admin_users.created_by
  IS 'profiles.id de quien concedió el permiso.';


-- Un solo permiso ACTIVO por usuario.
-- Permite conservar historial de permisos desactivados.
CREATE UNIQUE INDEX IF NOT EXISTS admin_users_user_id_active_key
  ON public.admin_users (user_id)
  WHERE active;


-- Búsquedas por rol.
CREATE INDEX IF NOT EXISTS admin_users_role_idx
  ON public.admin_users (role);


-- updated_at automático.
DROP TRIGGER IF EXISTS admin_users_set_updated_at
ON public.admin_users;

CREATE TRIGGER admin_users_set_updated_at
BEFORE UPDATE ON public.admin_users
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();


-- ============================================================================
-- BLOQUE 2 · creator_requests
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.creator_requests (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid        NOT NULL,
  status           text        NOT NULL DEFAULT 'pending',
  message          text,
  rejection_reason text,
  reviewed_by      uuid,
  reviewed_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT creator_requests_status_check
    CHECK (status IN ('pending', 'approved', 'rejected')),

  CONSTRAINT creator_requests_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES public.profiles(id)
    ON DELETE CASCADE,

  CONSTRAINT creator_requests_reviewed_by_fkey
    FOREIGN KEY (reviewed_by)
    REFERENCES public.profiles(id)
    ON DELETE SET NULL,

  CONSTRAINT creator_requests_review_state_check
    CHECK (
      (
        status = 'pending'
        AND reviewed_by IS NULL
        AND reviewed_at IS NULL
        AND rejection_reason IS NULL
      )
      OR
      (
        status = 'approved'
        AND reviewed_by IS NOT NULL
        AND reviewed_at IS NOT NULL
      )
      OR
      (
        status = 'rejected'
        AND reviewed_by IS NOT NULL
        AND reviewed_at IS NOT NULL
        AND rejection_reason IS NOT NULL
      )
    )
);

COMMENT ON TABLE public.creator_requests
  IS 'Solicitudes para convertirse en creator.';

COMMENT ON COLUMN public.creator_requests.status
  IS 'pending | approved | rejected';

COMMENT ON COLUMN public.creator_requests.rejection_reason
  IS 'Obligatorio cuando status = rejected.';


-- Solo una solicitud pendiente por usuario.
CREATE UNIQUE INDEX IF NOT EXISTS creator_requests_one_pending_per_user
  ON public.creator_requests (user_id)
  WHERE status = 'pending';


-- Cola de revisión.
CREATE INDEX IF NOT EXISTS creator_requests_status_idx
  ON public.creator_requests (status);


-- Historial del usuario.
CREATE INDEX IF NOT EXISTS creator_requests_user_created_idx
  ON public.creator_requests (user_id, created_at DESC);


-- updated_at automático.
DROP TRIGGER IF EXISTS creator_requests_set_updated_at
ON public.creator_requests;

CREATE TRIGGER creator_requests_set_updated_at
BEFORE UPDATE ON public.creator_requests
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();


-- ============================================================================
-- BLOQUE 3 · Funciones de autorización
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_users a
    WHERE a.user_id = auth.uid()
      AND a.active
      AND a.role = 'admin'
  );
$fn$;


CREATE OR REPLACE FUNCTION public.is_moderator()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_users a
    WHERE a.user_id = auth.uid()
      AND a.active
      AND a.role IN ('admin', 'moderator')
  );
$fn$;


CREATE OR REPLACE FUNCTION public.can_request_creator()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid()
      AND COALESCE(p.role, 'fan') <> 'creator'
      AND COALESCE(p.is_banned, false) = false
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.creator_requests cr
    WHERE cr.user_id = auth.uid()
      AND cr.status = 'pending'
  );
$fn$;


-- ============================================================================
-- BLOQUE 4 · Aprobar solicitud
-- ============================================================================

CREATE OR REPLACE FUNCTION public.approve_creator_request(
  request_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user_id uuid;
  v_status  text;
  v_role    text;
  v_banned  boolean;
BEGIN

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado: se requiere iniciar sesión'
      USING ERRCODE = '28000';
  END IF;


  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Se requiere rol admin activo'
      USING ERRCODE = '42501';
  END IF;


  -- Bloquea la solicitud durante toda la operación.
  SELECT cr.user_id, cr.status
    INTO v_user_id, v_status
  FROM public.creator_requests cr
  WHERE cr.id = request_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitud no encontrada: %', request_id
      USING ERRCODE = 'P0002';
  END IF;


  IF v_status <> 'pending' THEN
    RAISE EXCEPTION
      'La solicitud ya está en estado "%" y no se puede aprobar',
      v_status
      USING ERRCODE = '22023';
  END IF;


  -- Bloquea también el profile para evitar carreras.
  SELECT p.role,
         COALESCE(p.is_banned, false)
    INTO v_role,
         v_banned
  FROM public.profiles p
  WHERE p.id = v_user_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION 'El profile % no existe', v_user_id
      USING ERRCODE = 'P0002';
  END IF;


  IF v_banned THEN
    RAISE EXCEPTION
      'El usuario está baneado: no se puede aprobar'
      USING ERRCODE = '22023';
  END IF;


  IF v_role = 'creator' THEN
    RAISE EXCEPTION
      'El profile ya tiene role=creator (estado inconsistente): requiere revisión manual'
      USING ERRCODE = '22023';
  END IF;


  -- Cambio de rol exclusivamente dentro de esta función.
  UPDATE public.profiles
     SET role = 'creator',
         updated_at = now()
   WHERE id = v_user_id;


  -- Registrar la aprobación.
  UPDATE public.creator_requests
     SET status      = 'approved',
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         updated_at  = now()
   WHERE id = request_id;

END;
$fn$;


-- ============================================================================
-- BLOQUE 5 · Rechazar solicitud
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reject_creator_request(
  request_id       uuid,
  rejection_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_status text;
BEGIN

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado: se requiere iniciar sesión'
      USING ERRCODE = '28000';
  END IF;


  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Se requiere rol admin activo'
      USING ERRCODE = '42501';
  END IF;


  IF rejection_reason IS NULL
     OR btrim(rejection_reason) = '' THEN

    RAISE EXCEPTION 'Se requiere un motivo de rechazo'
      USING ERRCODE = '22023';

  END IF;


  SELECT cr.status
    INTO v_status
  FROM public.creator_requests cr
  WHERE cr.id = request_id
  FOR UPDATE;


  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitud no encontrada: %', request_id
      USING ERRCODE = 'P0002';
  END IF;


  IF v_status <> 'pending' THEN
    RAISE EXCEPTION
      'La solicitud ya está en estado "%" y no se puede rechazar',
      v_status
      USING ERRCODE = '22023';
  END IF;


  UPDATE public.creator_requests
     SET status           = 'rejected',
         rejection_reason = btrim(rejection_reason),
         reviewed_by      = auth.uid(),
         reviewed_at      = now(),
         updated_at       = now()
   WHERE id = request_id;

END;
$fn$;


-- ============================================================================
-- BLOQUE 6 · RLS
-- ============================================================================

ALTER TABLE public.admin_users
ENABLE ROW LEVEL SECURITY;


-- admin_users:
-- NO hay policies.
-- Ningún usuario de la aplicación puede leer/escribir directamente.
DROP POLICY IF EXISTS "admin_users_select_own"
ON public.admin_users;

DROP POLICY IF EXISTS "admin_users_insert_own"
ON public.admin_users;

DROP POLICY IF EXISTS "admin_users_update_own"
ON public.admin_users;

DROP POLICY IF EXISTS "admin_users_delete_own"
ON public.admin_users;


ALTER TABLE public.creator_requests
ENABLE ROW LEVEL SECURITY;


DROP POLICY IF EXISTS "creator_requests_select_own"
ON public.creator_requests;

CREATE POLICY "creator_requests_select_own"
ON public.creator_requests
FOR SELECT
TO authenticated
USING (
  auth.uid() = user_id
);


DROP POLICY IF EXISTS "creator_requests_insert_own_pending"
ON public.creator_requests;

CREATE POLICY "creator_requests_insert_own_pending"
ON public.creator_requests
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND status = 'pending'
  AND reviewed_by IS NULL
  AND reviewed_at IS NULL
  AND rejection_reason IS NULL
  AND public.can_request_creator()
);


-- ============================================================================
-- BLOQUE 7 · Privilegios
-- ============================================================================

-- admin_users no puede ser manipulado desde la aplicación.
REVOKE ALL
ON TABLE public.admin_users
FROM anon, authenticated;


-- creator_requests sí puede ser creada/consultada por el usuario,
-- siempre limitada por RLS.
REVOKE ALL
ON TABLE public.creator_requests
FROM anon, authenticated;

GRANT SELECT, INSERT
ON TABLE public.creator_requests
TO authenticated;


-- Las funciones de autorización solo pueden ser llamadas
-- por usuarios autenticados.
REVOKE ALL
ON FUNCTION public.is_admin()
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.is_moderator()
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.can_request_creator()
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.approve_creator_request(uuid)
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.reject_creator_request(uuid, text)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.is_admin()
TO authenticated;

GRANT EXECUTE
ON FUNCTION public.is_moderator()
TO authenticated;

GRANT EXECUTE
ON FUNCTION public.can_request_creator()
TO authenticated;

GRANT EXECUTE
ON FUNCTION public.approve_creator_request(uuid)
TO authenticated;

GRANT EXECUTE
ON FUNCTION public.reject_creator_request(uuid, text)
TO authenticated;


-- ============================================================================
-- BLOQUE 8 · Defensa contra FORCE ROW LEVEL SECURITY
-- ============================================================================

DO $do$
DECLARE
  f text;
BEGIN

  FOREACH f IN ARRAY
    ARRAY['profiles', 'admin_users', 'creator_requests']
  LOOP

    IF EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n
        ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = f
        AND c.relforcerowsecurity
    ) THEN

      RAISE EXCEPTION
        'public.% tiene FORCE ROW LEVEL SECURITY. Las funciones SECURITY DEFINER de esta migración no podrían leerla/escribirla. Revisar manualmente antes de continuar.',
        f;

    END IF;

  END LOOP;

END;
$do$;


-- ============================================================================
-- FIN DE MIGRACIÓN
-- ============================================================================

COMMIT;


-- ============================================================================
-- BLOQUE 9 · CONSULTAS DE VERIFICACIÓN
-- EJECUTAR DESPUÉS DEL COMMIT
-- ============================================================================


-- 9.1 admin_users
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'admin_users'
ORDER BY ordinal_position;


-- 9.2 creator_requests
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'creator_requests'
ORDER BY ordinal_position;


-- 9.3 Foreign keys
SELECT
  tc.table_name,
  tc.constraint_name,
  kcu.column_name,
  ccu.table_schema || '.' || ccu.table_name AS references,
  rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON kcu.constraint_name = tc.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints rc
  ON rc.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
  AND tc.table_name IN (
    'admin_users',
    'creator_requests'
  )
ORDER BY
  tc.table_name,
  tc.constraint_name;


-- 9.4 CHECK constraints
SELECT
  conrelid::regclass AS tabla,
  conname,
  pg_get_constraintdef(oid) AS definicion
FROM pg_constraint
WHERE contype = 'c'
  AND connamespace = 'public'::regnamespace
  AND conrelid::regclass::text IN (
    'admin_users',
    'creator_requests'
  )
ORDER BY
  1,
  2;


-- 9.5 Índices
SELECT
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    'admin_users',
    'creator_requests'
  )
ORDER BY
  tablename,
  indexname;


-- 9.6 RLS
SELECT
  c.relname AS tabla,
  c.relrowsecurity AS rls_habilitado,
  c.relforcerowsecurity AS rls_forzado
FROM pg_class c
JOIN pg_namespace n
  ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
    'admin_users',
    'creator_requests',
    'profiles'
  )
ORDER BY 1;


-- 9.7 Policies
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'admin_users',
    'creator_requests'
  )
ORDER BY
  tablename,
  policyname;


-- 9.8 Seguridad de funciones
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS argumentos,
  p.proowner::regrole AS owner,
  p.prosecdef AS security_definer,
  p.proconfig AS search_path,
  p.provolatile AS volatility
FROM pg_proc p
JOIN pg_namespace n
  ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'is_admin',
    'is_moderator',
    'can_request_creator',
    'approve_creator_request',
    'reject_creator_request',
    'update_updated_at_column'
  )
ORDER BY p.proname;


-- 9.9 EXECUTE
SELECT
  routine_name,
  grantee,
  privilege_type
FROM information_schema.routine_privileges
WHERE specific_schema = 'public'
  AND routine_name IN (
    'is_admin',
    'is_moderator',
    'can_request_creator',
    'approve_creator_request',
    'reject_creator_request'
  )
ORDER BY
  routine_name,
  grantee;


-- 9.10 Privilegios de tablas
SELECT
  table_name,
  grantee,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name IN (
    'admin_users',
    'creator_requests'
  )
  AND grantee IN (
    'anon',
    'authenticated',
    'PUBLIC'
  )
ORDER BY
  table_name,
  grantee,
  privilege_type;


-- 9.11 Trigger de Parte 1 intacto
SELECT
  tgname,
  tgrelid::regclass AS tabla_afectada,
  pg_get_triggerdef(oid) AS definicion,
  tgenabled
FROM pg_trigger
WHERE NOT tgisinternal
  AND tgname = 'on_auth_user_created';


-- 9.12 handle_new_user() intacta
SELECT
  p.proname,
  pg_get_functiondef(p.oid) AS cuerpo
FROM pg_proc p
JOIN pg_namespace n
  ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'handle_new_user';


-- 9.13 profiles_id_unique intacto
SELECT
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'profiles'
  AND indexname = 'profiles_id_unique';


-- 9.14 profiles
SELECT
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'profiles'
ORDER BY ordinal_position;


-- 9.15 Triggers nuevos
SELECT
  tgname,
  tgrelid::regclass AS tabla,
  pg_get_triggerdef(oid) AS definicion
FROM pg_trigger
WHERE NOT tgisinternal
  AND tgname IN (
    'admin_users_set_updated_at',
    'creator_requests_set_updated_at'
  );


-- ============================================================================
-- BLOQUE 10 · PRIMER ADMIN
-- NO EJECUTAR TODAVÍA
-- ============================================================================

-- 1. Buscar UUID real:
--
-- SELECT
--   u.id,
--   u.email,
--   p.role,
--   p.is_banned
-- FROM auth.users u
-- LEFT JOIN public.profiles p
--   ON p.id = u.id
-- WHERE u.email = 'correo@ejemplo.com';


-- 2. Crear PRIMER ADMIN exclusivamente desde SQL Editor:
--
-- INSERT INTO public.admin_users
--   (user_id, role, active, created_at, created_by, updated_at)
-- VALUES
--   (
--     '<UUID_REAL_DEL_USUARIO>',
--     'admin',
--     true,
--     now(),
--     '<UUID_REAL_DEL_USUARIO>',
--     now()
--   );


-- 3. Comprobar:
--
-- SELECT
--   au.user_id,
--   au.role,
--   au.active,
--   u.email
-- FROM public.admin_users au
-- JOIN auth.users u
--   ON u.id = au.user_id
-- WHERE au.active;


-- 4. Crear MODERADOR en el futuro:
--
-- INSERT INTO public.admin_users
--   (user_id, role, active, created_at, created_by, updated_at)
-- VALUES
--   (
--     '<UUID_REAL_DEL_USUARIO>',
--     'moderator',
--     true,
--     now(),
--     '<UUID_DEL_ADMIN_QUE_LO_CONCEDE>',
--     now()
--   );


-- 5. Desactivar permiso conservando historial:
--
-- UPDATE public.admin_users
-- SET
--   active = false,
--   updated_at = now()
-- WHERE user_id = '<UUID_REAL_DEL_USUARIO>'
--   AND active;
