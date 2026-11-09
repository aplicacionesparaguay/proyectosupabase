-- =====================================================================
-- AguaEnLaBoca · PARTE 4 · PANEL DE ADMINISTRACION Y SOLICITUD DE CREADORA
-- =====================================================================
-- Ejecutar en: Supabase Dashboard > SQL Editor
--
-- NO EJECUTAR TODAVIA: este archivo es la migracion PENDIENTE. Revisar y
-- aplicar de forma controlada (copia de seguridad antes).
--
-- QUE HACE
--   1. Deja la base de `admin_users` y `creator_requests` en el estado que
--      espera el panel /admin.
--   2. CORRIGE `protect_profile()`: la version anterior restauraba el rol
--      anterior en silencio, de modo que el navegador creia haber cambiado el
--      rol y la base no lo habia hecho. Ahora el cambio de rol, de bloqueo o
--      de verificacion SOLO puede ocurrir dentro de una funcion
--      SECURITY DEFINER autorizada; cualquier otro intento falla con error.
--   3. Crea las funciones RPC que usa el panel:
--        · my_admin_role()               -> rol de quien esta conectado
--        · admin_list_profiles()         -> perfiles con rol y estado
--        · admin_set_creator_role()      -> admin unicamente
--        · admin_set_banned()            -> admin y moderacion
--        · admin_list_creator_requests() -> cola de solicitudes (admin)
--        · admin_list_user_media()       -> galeria de una creadora
--   4. Aplica minimo privilegio: `role`, `is_banned` e `is_verified` dejan
--      de ser escribibles por el navegador, y las funciones quedan cerradas a
--      `PUBLIC`.
--
-- QUE NO HACE
--   · NO toca la logica de privacidad: la galeria sigue siendo privada y
--     los portadas publicos siguen servidos igual.
--   · NO implementa pagos, suscripciones ni chat.
--   · NO usa `service_role` en ningun sitio.
--   · NO concede el primer admin: eso sigue siendo manual (ver BLOQUE 10).
--
-- IDEMPOTENCIA
--   Reejecutable. Las tablas usan CREATE TABLE IF NOT EXISTS, las funciones
--   CREATE OR REPLACE, las policies se reemplazan con DROP + CREATE dentro de
--   la misma transaccion y los triggers se recrean de forma controlada.
--
-- SEGURIDAD
--   · Todo cambio de `profiles.role` pasa por una funcion SECURITY DEFINER
--     con `search_path = ''` que comprueba `is_admin()` DENTRO de la base.
--   · El trigger exige DOS condiciones a la vez:
--       (a) la variable transaccional `app.admin_authorized_role_change` vale
--           'on', y la fija solo la funcion autorizada;
--       (b) la sentencia se ejecuta con los privilegios del dueno de la
--           tabla, no con los de `authenticated`.
--     La (b) impide que alguien falsifique la variable (a) desde una sesion
--     normal: falsificarla no cambia el rol con el que corre la sentencia.
--   · `SECURITY DEFINER` + `search_path = ''` evita el secuestro de funciones
--     por objetos del esquema `public`.
--
-- PRERREQUISITOS
--   · `supabase-part1-auth.sql` ejecutado (profiles con `role`).
--   · `supabase-part2-admin.sql` ejecutado (admin_users, creator_requests,
--     is_admin, is_moderator, approve/reject_creator_request).
--   · Este archivo NO depende de que el anterior se haya aplicado: recrea
--     lo que falta. Si el anterior SI se aplico, el resultado es el mismo.
-- =====================================================================

BEGIN;

-- =====================================================================
-- BLOQUE 1 · admin_users
-- =====================================================================
-- Misma forma que en supabase-part2-admin.sql. Se repite aqui para que este
-- archivo sea autonomo: si `admin_users` no existe todavia, se crea.

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

CREATE UNIQUE INDEX IF NOT EXISTS admin_users_user_id_active_key
  ON public.admin_users (user_id)
  WHERE active;

CREATE INDEX IF NOT EXISTS admin_users_role_idx
  ON public.admin_users (role);

-- =====================================================================
-- BLOQUE 2 · creator_requests
-- =====================================================================
-- Misma forma que en supabase-part2-admin.sql. Idempotente.

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

-- Una sola solicitud pendiente por usuario.
CREATE UNIQUE INDEX IF NOT EXISTS creator_requests_one_pending_per_user
  ON public.creator_requests (user_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS creator_requests_status_idx
  ON public.creator_requests (status);

CREATE INDEX IF NOT EXISTS creator_requests_user_created_idx
  ON public.creator_requests (user_id, created_at DESC);

-- =====================================================================
-- BLOQUE 3 · Funciones de autorizacion
-- =====================================================================
-- `is_admin()` y `is_moderator()` leen `admin_users` con los privilegios del
-- dueno de la funcion (SECURITY DEFINER): el cliente no puede leer
-- `admin_users` directamente, pero la base si puede consultarlo por ellas.

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


-- Rol efectivo de la sesion actual: 'admin' | 'moderator' | NULL.
-- El panel la usa para decidir que puede ver cada persona.
CREATE OR REPLACE FUNCTION public.my_admin_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT a.role
  FROM public.admin_users a
  WHERE a.user_id = auth.uid()
    AND a.active
    AND a.role IN ('admin', 'moderator')
  LIMIT 1;
$fn$;

-- =====================================================================
-- BLOQUE 4 · protect_profile() CORREGIDO
-- =====================================================================
-- Que hacia antes:
--   La version anterior de `protect_profile()` "restauraba el rol anterior":
--   si alguien escribia `role`, el trigger lo devolvia a su valor previo SIN
--   lanzar error. Desde el navegador eso era indistinguible de un exito: la
--   interfaz deia "ya eres creadora" y la base seguia con `role = 'fan'`.
--
-- Que hace ahora:
--   · `role`, `is_banned` e `is_verified` NO se pueden cambiar desde una
--     sesion normal. El intento falla con 42501 y un mensaje claro, en lugar
--     de ignorarse en silencio.
--   · El cambio autorizado llega por una variable transaccional
--     (`app.admin_authorized_role_change`) que solo fija la funcion
--     SECURITY DEFINER de administracion, dentro de la misma transaccion.
--   · Ademas, la sentencia tiene que ejecutarse con los privilegios del
--     dueno de la tabla. Una sesion normal corre como `authenticated`, asi
--     que ni siquiera falsificando la variable podria hacer el cambio.
--   · En el INSERT, el rol se fuerza a 'fan' y el bloqueo y la verificacion a
--     false: una cuenta nueva no puede nacer creadora, bloqueada ni verificada.
--
-- La correccion NO abre la auto-promocion: al contrario, convierte un
-- silencio peligroso en un error explicito.

-- Se eliminan los triggers antiguos de proteccion, sean cuales sean sus
-- nombres: se localizan por la funcion que ejecutan, no por su nombre.
DO $do$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.profiles'::regclass
      AND NOT t.tgisinternal
      AND p.proname = 'protect_profile'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.profiles', r.tgname);
    RAISE NOTICE 'Trigger de proteccion eliminado: %', r.tgname;
  END LOOP;
END;
$do$;

DROP FUNCTION IF EXISTS public.protect_profile();

-- SECURITY INVOKER a proposito: el trigger tiene que ver el rol con el que
-- corre la SENTENCIA (la de la funcion SECURITY DEFINER o el de la sesion
-- normal). Con SECURITY DEFINER veria siempre al dueno y la comprobacion
-- no serviria de nada.
CREATE OR REPLACE FUNCTION public.protect_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $fn$
DECLARE
  v_authorized boolean;
  v_elevated   boolean;
  v_owner      name;
BEGIN
  -- `current_setting(..., true)` devuelve NULL si la variable no existe: en
  -- ese caso no hay autorizacion y el cambio se rechaza.
  v_authorized := COALESCE(
    current_setting('app.admin_authorized_role_change', true),
    'off'
  ) = 'on';

  -- El dueno de la tabla es quien puede escribir `role` de verdad. Se acepta
  -- tambien a los roles que lo heredan (por ejemplo, un rol que sea miembro
  -- del dueno) y a los superusuarios, que pueden hacer lo que quieran desde
  -- el SQL Editor.
  SELECT pg_catalog.pg_get_userbyid(c.relowner)
    INTO v_owner
  FROM pg_catalog.pg_class c
  WHERE c.oid = 'public.profiles'::regclass;

  v_elevated :=
       (current_user = v_owner)
    OR pg_catalog.pg_has_role(current_user, v_owner, 'MEMBER')
    OR EXISTS (
      SELECT 1
      FROM pg_catalog.pg_roles r
      WHERE r.rolname = current_user
        AND r.rolsuper
    );

  -- Las dos condiciones a la vez. La variable sola no basta: una sesion
  -- normal podria falsificarla, pero no puede ejecutar la sentencia con
  -- los privilegios del dueno.
  IF NOT (v_authorized AND v_elevated) THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.role IS DISTINCT FROM 'fan' THEN
        RAISE EXCEPTION
          'Una cuenta nueva se crea siempre con rol ''fan''. Solicita ser creadora para cambiarlo.'
          USING ERRCODE = '42501';
      END IF;

      IF COALESCE(NEW.is_banned, false) <> false THEN
        RAISE EXCEPTION 'Una cuenta nueva no puede empezar bloqueada.'
          USING ERRCODE = '42501';
      END IF;

      IF COALESCE(NEW.is_verified, false) <> false THEN
        RAISE EXCEPTION 'Una cuenta nueva no puede empezar verificada.'
          USING ERRCODE = '42501';
      END IF;
    ELSE
      IF NEW.role IS DISTINCT FROM OLD.role THEN
        RAISE EXCEPTION
          'El rol no se puede cambiar desde la aplicacion. Solicita ser creadora o pide a una administradora que lo haga.'
          USING ERRCODE = '42501';
      END IF;

      IF NEW.is_banned IS DISTINCT FROM OLD.is_banned THEN
        RAISE EXCEPTION
          'El estado de bloqueo solo lo puede cambiar una administradora o moderadora.'
          USING ERRCODE = '42501';
      END IF;

      IF NEW.is_verified IS DISTINCT FROM OLD.is_verified THEN
        RAISE EXCEPTION
          'La verificacion solo la puede cambiar una administradora.'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_protect_profile
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.protect_profile();


-- El mismo trigger cubre el INSERT: una cuenta nueva nace como 'fan'.
CREATE TRIGGER trg_protect_profile_insert
BEFORE INSERT ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.protect_profile();

-- =====================================================================
-- BLOQUE 5 · Funciones de administracion
-- =====================================================================
-- Todas son SECURITY DEFINER con `search_path = ''` y comprueban el rol
-- DENTRO de la base. El panel valida tambien en el servidor: son dos capas
-- distintas y las dos hacen falta.

-- Listado de perfiles para el panel. Lo pueden ver administradoras y
-- moderadoras. No expone email ni telefono: la tabla `profiles` no los tiene.
CREATE OR REPLACE FUNCTION public.admin_list_profiles(
  p_role text DEFAULT NULL,
  p_limit integer DEFAULT 200
)
RETURNS TABLE (
  id                uuid,
  display_name      text,
  username          text,
  role              text,
  is_banned         boolean,
  is_verified       boolean,
  subscription_price numeric,
  city              text,
  country_code      text,
  avatar_key        text,
  created_at        timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado: se requiere iniciar sesion'
      USING ERRCODE = '28000';
  END IF;

  IF NOT (public.is_admin() OR public.is_moderator()) THEN
    RAISE EXCEPTION 'Se requiere rol admin o moderator activo'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.display_name,
    p.username,
    p.role,
    COALESCE(p.is_banned, false),
    COALESCE(p.is_verified, false),
    p.subscription_price::numeric,
    p.city,
    p.country_code,
    p.avatar_key,
    p.created_at
  FROM public.profiles p
  WHERE (p_role IS NULL OR p.role = p_role)
  ORDER BY p.created_at DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 500);
END;
$fn$;


-- Cambio de rol. SOLO administradoras (no moderadoras).
--
-- Reglas:
--   · `new_role` tiene que ser 'fan' o 'creator'.
--   · No se puede cambiar el rol propio: evita que una administradora se
--     quede sin permisos por error y que el panel se auto-promueva.
--   · No se puede cambiar el rol de una cuenta con permiso administrativo
--     activo: el rol de aplicacion y el permiso de administracion son
--     cosas distintas y no se mezclan.
--   · La actualizacion va marcada con la variable transaccional que
--     `protect_profile()` exige, de modo que el trigger la deja pasar.
CREATE OR REPLACE FUNCTION public.admin_set_creator_role(
  target_user_id uuid,
  new_role text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado: se requiere iniciar sesion'
      USING ERRCODE = '28000';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Se requiere rol admin activo'
      USING ERRCODE = '42501';
  END IF;

  IF new_role IS NULL OR new_role NOT IN ('fan', 'creator') THEN
    RAISE EXCEPTION 'Rol no valido: solo ''fan'' o ''creator'''
      USING ERRCODE = '22023';
  END IF;

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'Falta el usuario objetivo'
      USING ERRCODE = '22023';
  END IF;

  IF target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'No puedes cambiar tu propio rol'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.admin_users a
    WHERE a.user_id = target_user_id
      AND a.active
  ) THEN
    RAISE EXCEPTION
      'Esa cuenta tiene permiso administrativo activo: su rol de aplicacion no se cambia desde aqui'
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = target_user_id
  ) THEN
    RAISE EXCEPTION 'El perfil % no existe', target_user_id
      USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('app.admin_authorized_role_change', 'on', true);

  UPDATE public.profiles
     SET role = new_role,
         updated_at = now()
   WHERE id = target_user_id;

  PERFORM set_config('app.admin_authorized_role_change', 'off', true);
END;
$fn$;


-- Bloqueo y desbloqueo. Administradoras y moderadoras.
--
-- Reglas:
--   · No se puede bloquear a una cuenta con permiso administrativo activo.
--   · No se puede bloquear a una misma.
CREATE OR REPLACE FUNCTION public.admin_set_banned(
  target_user_id uuid,
  banned boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado: se requiere iniciar sesion'
      USING ERRCODE = '28000';
  END IF;

  IF NOT (public.is_admin() OR public.is_moderator()) THEN
    RAISE EXCEPTION 'Se requiere rol admin o moderator activo'
      USING ERRCODE = '42501';
  END IF;

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'Falta el usuario objetivo'
      USING ERRCODE = '22023';
  END IF;

  IF target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'No puedes cambiar tu propio estado de bloqueo'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.admin_users a
    WHERE a.user_id = target_user_id
      AND a.active
  ) THEN
    RAISE EXCEPTION
      'Esa cuenta tiene permiso administrativo activo: no se puede bloquear'
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = target_user_id
  ) THEN
    RAISE EXCEPTION 'El perfil % no existe', target_user_id
      USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('app.admin_authorized_role_change', 'on', true);

  UPDATE public.profiles
     SET is_banned = COALESCE(banned, false),
         updated_at = now()
   WHERE id = target_user_id;

  PERFORM set_config('app.admin_authorized_role_change', 'off', true);
END;
$fn$;


-- Cola de solicitudes. SOLO administradoras.
--
-- La policy de SELECT de `creator_requests` deja ver a cada persona sus
-- propias solicitudes y nada mas: sin esta funcion, una administradora que
-- use la clave publica del navegador no veria la cola.
CREATE OR REPLACE FUNCTION public.admin_list_creator_requests(
  p_status text DEFAULT 'pending'
)
RETURNS TABLE (
  id               uuid,
  user_id          uuid,
  status           text,
  message          text,
  rejection_reason text,
  created_at       timestamptz,
  display_name     text,
  username         text,
  current_role     text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado: se requiere iniciar sesion'
      USING ERRCODE = '28000';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Se requiere rol admin activo'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    cr.id,
    cr.user_id,
    cr.status,
    cr.message,
    cr.rejection_reason,
    cr.created_at,
    p.display_name,
    p.username,
    p.role
  FROM public.creator_requests cr
  LEFT JOIN public.profiles p ON p.id = cr.user_id
  WHERE (p_status IS NULL OR cr.status = p_status)
  ORDER BY cr.created_at ASC
  LIMIT 200;
END;
$fn$;


-- Galeria de una creadora, para que el panel pueda comprobar las fotos
-- subidas. Devuelve la CLAVE del objeto, no una URL: la URL firmada la
-- genera el servidor de la aplicacion, que es quien tiene las credenciales
-- de R2. Administradoras y moderadoras.
CREATE OR REPLACE FUNCTION public.admin_list_user_media(
  target_user_id uuid
)
RETURNS TABLE (
  id           uuid,
  filename     text,
  storage_path text,
  mime_type    text,
  byte_size    bigint,
  estado       text,
  visibilidad  text,
  created_at   timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado: se requiere iniciar sesion'
      USING ERRCODE = '28000';
  END IF;

  IF NOT (public.is_admin() OR public.is_moderator()) THEN
    RAISE EXCEPTION 'Se requiere rol admin o moderator activo'
      USING ERRCODE = '42501';
  END IF;

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'Falta el usuario objetivo'
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  SELECT
    up.id,
    up.filename,
    up.storage_path,
    up.mime_type,
    up.byte_size,
    up.estado,
    up.visibilidad,
    up.created_at
  FROM public.user_photos up
  WHERE up.user_id = target_user_id
  ORDER BY up.created_at DESC
  LIMIT 100;
END;
$fn$;

-- =====================================================================
-- BLOQUE 6 · Aprobar y rechazar solicitudes
-- =====================================================================

-- Cantidad de publicaciones de una creadora.
--
-- Es un dato de cuenta (cuanto publica), no el contenido: la galeria sigue
-- siendo privada y las fotos no se exponen. Se ofrece como funcion y no como
-- una policy de SELECT porque asi se puede contar las filas de otra persona
-- sin leerlas ni firmarlas.
CREATE OR REPLACE FUNCTION public.public_media_count(
  target_user_id uuid
)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT count(*)::bigint
  FROM public.user_photos up
  WHERE up.user_id = target_user_id
    AND COALESCE(up.estado, 'listo') = 'listo';
$fn$;

-- Se recrean aqui para que el archivo sea autonomo. Mismo contrato que en
-- supabase-part2-admin.sql: solo administradoras, y el cambio de rol ocurre
-- dentro de la funcion, que es el unico sitio autorizado para escribirlo.

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
    RAISE EXCEPTION 'No autenticado: se requiere iniciar sesion'
      USING ERRCODE = '28000';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Se requiere rol admin activo'
      USING ERRCODE = '42501';
  END IF;

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
      'La solicitud ya esta en estado "%" y no se puede aprobar',
      v_status
      USING ERRCODE = '22023';
  END IF;

  SELECT p.role, COALESCE(p.is_banned, false)
    INTO v_role, v_banned
  FROM public.profiles p
  WHERE p.id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El profile % no existe', v_user_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_banned THEN
    RAISE EXCEPTION
      'El usuario esta baneado: no se puede aprobar'
      USING ERRCODE = '22023';
  END IF;

  IF v_role = 'creator' THEN
    RAISE EXCEPTION
      'El profile ya tiene role=creator (estado inconsistente): requiere revision manual'
      USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('app.admin_authorized_role_change', 'on', true);

  UPDATE public.profiles
     SET role = 'creator',
         updated_at = now()
   WHERE id = v_user_id;

  PERFORM set_config('app.admin_authorized_role_change', 'off', true);

  UPDATE public.creator_requests
     SET status      = 'approved',
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         updated_at  = now()
   WHERE id = request_id;
END;
$fn$;


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
    RAISE EXCEPTION 'No autenticado: se requiere iniciar sesion'
      USING ERRCODE = '28000';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Se requiere rol admin activo'
      USING ERRCODE = '42501';
  END IF;

  IF rejection_reason IS NULL OR btrim(rejection_reason) = '' THEN
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
      'La solicitud ya esta en estado "%" y no se puede rechazar',
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

-- =====================================================================
-- BLOQUE 7 · Privilegios: minimo privilegio
-- =====================================================================

-- `admin_users` no se puede leer ni escribir desde la aplicacion.
REVOKE ALL
ON TABLE public.admin_users
FROM anon, authenticated;

-- `creator_requests`: la persona solo puede insertar su propia solicitud
-- (con RLS) y consultar las suyas. Ni UPDATE ni DELETE: no se puede
-- auto-aprobar ni borrar el historial.
REVOKE ALL
ON TABLE public.creator_requests
FROM anon, authenticated;

GRANT SELECT, INSERT
ON TABLE public.creator_requests
TO authenticated;

-- Las funciones se cierran a PUBLIC y se abren solo a `authenticated`.
-- `anon` no llega a ninguna: sin sesion no hay nada que administrar.
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_moderator() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_request_creator() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.my_admin_role() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_profiles(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_creator_role(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_banned(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_creator_requests(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_user_media(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.public_media_count(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_creator_request(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reject_creator_request(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_moderator() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_request_creator() TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_admin_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_profiles(text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_creator_role(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_banned(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_creator_requests(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_user_media(uuid) TO authenticated;
-- El conteo es publico: lo puede pedir cualquiera, incluso sin sesion.
GRANT EXECUTE ON FUNCTION public.public_media_count(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_creator_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_creator_request(uuid, text) TO authenticated;

-- =====================================================================
-- BLOQUE 8 · `profiles.role` deja de ser escribible por el navegador
-- =====================================================================
-- Tercera capa, a proposito:
--   1. La policy RLS limita las filas (solo la propia), pero no los campos.
--   2. El trigger `protect_profile()` rechaza el cambio no autorizado.
--   3. Esta capa: el privilegio de escritura sobre las columnas protegidas
--      se retira al rol `authenticated`.
--
-- En PostgreSQL los privilegios de columna SON ADITIVOS: revocar
-- `UPDATE(role)` no sirve mientras la tabla conserve `UPDATE` a nivel de
-- tabla. Por eso se revoca el privilegio de tabla y se concede columna por
-- columna, excepto las protegidas.
--
-- La lista se calcula con `information_schema`, de modo que una columna nueva
-- que se anada a `profiles` mas adelante no deja al usuario sin poder
-- escribirla.

DO $do$
DECLARE
  r record;
  cols text;
BEGIN
  -- Privilegio de tabla: se retiran los completos.
  EXECUTE 'REVOKE UPDATE ON TABLE public.profiles FROM authenticated';
  EXECUTE 'REVOKE INSERT ON TABLE public.profiles FROM authenticated';

  -- UPDATE: solo sobre las columnas que no estan protegidas.
  cols := NULL;
  FOR r IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name NOT IN ('role', 'is_banned', 'is_verified')
    ORDER BY ordinal_position
  LOOP
    cols := cols || quote_ident(r.column_name) || ', ';
  END LOOP;

  IF cols IS NOT NULL AND cols <> '' THEN
    cols := left(cols, length(cols) - 2);
    EXECUTE format(
      'GRANT UPDATE (%s) ON TABLE public.profiles TO authenticated',
      cols
    );
    RAISE NOTICE 'profiles: UPDATE concedido por columna salvo role, is_banned e is_verified';
  END IF;

  -- INSERT: se concede por columna y `role` queda fuera. El trigger
  -- `trg_protect_profile_insert` fuerza ademas el rol a 'fan'.
  cols := NULL;
  FOR r IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name <> 'role'
    ORDER BY ordinal_position
  LOOP
    cols := cols || quote_ident(r.column_name) || ', ';
  END LOOP;

  IF cols IS NOT NULL AND cols <> '' THEN
    cols := left(cols, length(cols) - 2);
    EXECUTE format(
      'GRANT INSERT (%s) ON TABLE public.profiles TO authenticated',
      cols
    );
    RAISE NOTICE 'profiles: INSERT concedido por columna sin role';
  END IF;
END;
$do$;

-- =====================================================================
-- BLOQUE 9 · Chequeo de coherencia (NO modifica datos)
-- =====================================================================
-- Si `public.profiles` tuviera FORCE ROW LEVEL SECURITY, el dueno de las
-- funciones (que no es `authenticated`) podria no ver la tabla y la
-- migracion fallaria al ejecutar. Se avisa antes de seguir.

DO $do$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['profiles', 'admin_users', 'creator_requests']
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = f
        AND c.relforcerowsecurity
    ) THEN
      RAISE EXCEPTION
        'public.% tiene FORCE ROW LEVEL SECURITY. Las funciones SECURITY DEFINER de esta migracion no podrian leerla/escribirla. Revisar manualmente antes de continuar.',
        f;
    END IF;
  END LOOP;
END;
$do$;

COMMIT;

-- =====================================================================
-- BLOQUE 10 · Primer admin (NO EJECUTAR TODAVIA)
-- =====================================================================
-- Mientras `admin_users` este vacia, /admin no deja pasar a nadie y las
-- solicitudes se quedan en cola. El primer admin se crea desde el SQL
-- Editor, con las credenciales de la base:
--
-- 1. Buscar el UUID real:
--
--    SELECT u.id, u.email, p.role
--    FROM auth.users u
--    LEFT JOIN public.profiles p ON p.id = u.id
--    WHERE u.email = 'correo@ejemplo.com';
--
-- 2. Crear el PRIMER ADMIN:
--
--    INSERT INTO public.admin_users (user_id, role, active, created_at, created_by, updated_at)
--    VALUES ('<UUID_REAL>', 'admin', true, now(), '<UUID_REAL>', now());
--
-- 3. Comprobar:
--
--    SELECT au.user_id, au.role, au.active, u.email
--    FROM public.admin_users au
--    JOIN auth.users u ON u.id = au.user_id
--    WHERE au.active;
--
-- 4. Crear MODERADORES despues:
--
--    INSERT INTO public.admin_users (user_id, role, active, created_at, created_by, updated_at)
--    VALUES ('<UUID_MOD>', 'moderator', true, now(), '<UUID_ADMIN>', now());
--
-- 5. Cambios manuales de rol desde el SQL Editor (el trigger exige la
--    variable de autorizacion):
--
--    SET app.admin_authorized_role_change = 'on';
--    UPDATE public.profiles SET role = 'creator' WHERE id = '<UUID>';
--
-- =====================================================================
-- BLOQUE 11 · Verificacion (solo lectura, despues del COMMIT)
-- =====================================================================

-- 11.1 Triggers sobre profiles
SELECT tgname, tgrelid::regclass AS tabla, pg_get_triggerdef(oid) AS definicion
FROM pg_trigger
WHERE tgrelid = 'public.profiles'::regclass
  AND NOT tgisinternal;

-- 11.2 La funcion de proteccion
SELECT p.proname, pg_get_functiondef(p.oid) AS cuerpo
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'protect_profile';

-- 11.3 Privilegios de columna sobre profiles
SELECT table_name, column_name, grantee, privilege_type
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY column_name, grantee, privilege_type;

-- 11.4 Privilegios de tabla sobre profiles
SELECT table_name, grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY grantee, privilege_type;

-- 11.5 EXECUTE de las funciones de administracion
SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE specific_schema = 'public'
  AND routine_name IN (
    'is_admin', 'is_moderator', 'my_admin_role', 'can_request_creator',
    'admin_list_profiles', 'admin_set_creator_role', 'admin_set_banned',
    'admin_list_creator_requests', 'admin_list_user_media',
    'approve_creator_request', 'reject_creator_request'
  )
ORDER BY routine_name, grantee;

-- 11.6 Seguridad de las funciones
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS argumentos,
       p.prosecdef AS security_definer,
       p.proconfig AS search_path
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'is_admin', 'is_moderator', 'my_admin_role', 'can_request_creator',
    'admin_list_profiles', 'admin_set_creator_role', 'admin_set_banned',
    'admin_list_creator_requests', 'admin_list_user_media',
    'approve_creator_request', 'reject_creator_request', 'protect_profile'
  )
ORDER BY p.proname;

-- 11.7 Administradores activos
SELECT au.user_id, au.role, au.active, u.email
FROM public.admin_users au
JOIN auth.users u ON u.id = au.user_id
WHERE au.active;
