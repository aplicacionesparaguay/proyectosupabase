-- =====================================================================
-- AguaEnLaBoca · PARTE 4 (CORREGIDA) · PANEL DE ADMINISTRACION
-- =====================================================================
-- Archivo NUEVO e INDEPENDIENTE. NO reemplaza a
-- `supabase-part4-admin-panel.sql`, que queda como version original para
-- comparar.
--
-- Ejecutar en: Supabase Dashboard > SQL Editor
--
-- NO EJECUTAR TODAVIA: migracion PENDIENTE. Revisar y aplicar de forma
-- controlada (copia de seguridad antes).
--
-- QUE CORRIGE RESPECTO DE LA VERSION ORIGINAL
--   C1  `creator_requests` y `admin_users` quedan con RLS habilitado y con
--       policies propias. La version original creaba las tablas pero delegaba
--       las policies en part2: si ese archivo no estaba aplicado, la tabla
--       quedaba sin RLS y con SELECT/INSERT para todo usuario autenticado.
--   C2  `public_media_count` pasa a PL/pgSQL: en LANGUAGE sql el cuerpo se
--       valida al crear la funcion y la migracion entera abortaba si
--       `public.user_photos` no existia.
--   C3  El administrador existente `8f3eb06b-510a-439c-bba5-c7ba84e04254` se
--       reconoce y se asegura de forma idempotente: no se duplica, no se crea
--       otro administrador y NO se escribe `profiles.role = 'admin'`.
--   A4  Se elimina el `DROP FUNCTION` peligroso. La proteccion vive en una
--       funcion NUEVA (`protect_profile_fields`). Los triggers que usaban la
--       funcion vieja en OTRAS tablas siguen intactos.
--   A5  Las policies de `profiles` se recrean con `WITH CHECK` valido
--       (una policy RLS no puede comparar OLD con NEW: eso solo existe en
--       triggers). La proteccion por columna la dan los privilegios y el
--       trigger, no la policy.
--   A6  Bloque de aserciones que ABORTA la transaccion si quedan
--       privilegios excesivos, RLS desactivado, functions accesibles para
--       `anon` o policies incompletas.
--   A7  Los moderadores quedan separados del acceso administrativo: una RPC
--       de solo metadatos. El contenido privado de pago solo lo ve un
--       administrador.
--   B1  INSERT y UPDATE sobre `profiles` concedidos por columna: `role`,
--       `is_banned`, `is_verified` (y `subscription_price` al insertar) quedan
--       fuera del alcance de `authenticated`.
--   B3  El encabezado ya no afirma cosas que el archivo no cumple.
--
-- CORRECCIONES DE ESTA REVISION
--   D1  Los privilegios por columna se revocan EXPLICITAMENTE, no solo a
--       nivel de tabla. En PostgreSQL el privilegio de columna es aditivo
--       con el de tabla: revocar `UPDATE` de tabla NO elimina un
--       `GRANT UPDATE(role)` hecho a nivel de columna. Ahora se revocan las
--       dos capas y se vuelve a conceder solo lo necesario.
--   D2  `authenticated` no puede modificar `profiles.id`, `profiles.created_at`
--       ni `profiles.updated_at`. `updated_at` lo mantiene el trigger
--       `update_profiles_updated_at` de la base.
--   D3  Las policies de `creator_requests` se crean DESPUES de
--       `can_request_creator()` (BLOQUE 9, no BLOQUE 2). PostgreSQL valida
--       las funciones que aparecen en el `WITH CHECK` de una policy al
--       crearla: con el orden anterior, el archivo fallaba al aplicarse en
--       una base donde `supabase-part2-admin.sql` no estuviera ya ejecutado.
--   D4  Las aserciones comprueban tambien los privilegios HEREDADOS (roles de
--       los que `authenticated` es miembro) y que los privilegios que la app
--       NECESITA sigan existiendo: si un REVOKE de mas dejara a la usuaria
--       sin poder guardar su bio, la migracion aborta en vez de dejarla
--       rota.
--   D5  La lista de columnas del GRANT se arma con `string_agg`. Antes se
--       armaba con `cols := NULL; cols := cols || ...`, y en SQL
--       `NULL || 'x'` es NULL: `cols` se quedaba siempre en NULL, el
--       `IF cols IS NOT NULL` no se cumplia y el GRANT NUNCA se ejecutaba.
--       Con el privilege de tabla revocado, eso dejaba a la aplicacion sin
--       poder editar el perfil ni registrarse.
--   D6  Se revocan tambien los INSERT residuales sobre `created_at` y
--       `updated_at` cuando la columna tiene DEFAULT: sin ese revoke, un
--       `GRANT INSERT(created_at)` historico permitiria fijar la fecha de
--       alta a mano.
--   D7  Se revoca DELETE de tabla a `authenticated` (la aplicacion no borra
--       perfiles) y se comprueba con una asercion que aborte la migracion.
--   E1  Las policies de escritura que existen de verdad en la base son
--       `profiles_update_own` y `profiles_insert_own`: se eliminan y se
--       recrean las canonicas con ese mismo nombre. Ademas se hace un
--       barrido de TODA policy de escritura de `profiles` (UPDATE, INSERT o
--       ALL), porque las policies permisivas se combinan con OR y una policy
--       vieja mas ancha seguiria concediendo acceso.
--   E2  La concesion por columna pasa a una lista EXPLICITA y cerrada
--       (`v_allowed_insert` / `v_allowed_update`), sacada de las escrituras
--       verificadas en `src/`. Antes se concedia todo lo que no estuviera
--       protegido, con lo que una columna nueva heredaba permiso sin
--       querer.
--   E3  Las aserciones comprueban la lista EXACTA: recorren todas las
--       columnas de `profiles` y fallan si `authenticated` puede escribir
--       alguna que no este en la lista, y si falta alguna que si esta.
--   F1  `bio` esta en la lista de INSERT: el upsert de
--       src/routes/perfil/+page.svelte envia `id`, `display_name` y `bio` en
--       la misma sentencia, y PostgreSQL exige privilegio de INSERT en
--       TODAS las columnas nombradas. Sin el, guardar el perfil fallaba
--       con "permission denied for column bio".
--   F2  Se corrige una asercion que exigia la policy "Users can insert own
--       profile" cuando el BLOQUE 9 la elimina y crea `profiles_insert_own`:
--       la migracion abortaba siempre. En su lugar se comprueba que
--       `profiles_update_own` tenga `WITH CHECK`, que es la garantia de RLS
--       sobre la identidad de la fila ahora que `id` tiene UPDATE.
--   F3  `id` conserva privilegio de UPDATE (lo necesita el upsert) y la
--       14.6 ya no lo lista como prohibido: la identidad la protegen el
--       trigger y el `WITH CHECK` de la policy.
--   F4  Las protecciones por columna se comprueban una a una en el BLOQUE 11
--       y en la 14.6-quater: en INSERT, `role`, `is_banned`, `is_verified`,
--       `subscription_price`, `created_at` y `updated_at`; en UPDATE,
--       `created_at` y `updated_at`. `bio` queda expresamente concedido en
--       INSERT (lo necesita el upsert del perfil).
--   F1  `bio` entra en la lista de INSERT: el upsert del perfil
--       (`src/routes/perfil/+page.svelte`) envia `(id, display_name, bio)` y
--       PostgreSQL exige INSERT en todas las columnas nombradas.
--   F2  `id` entra en la lista de UPDATE: PostgREST genera
--       `ON CONFLICT (id) DO UPDATE SET id = EXCLUDED.id, ...`, que tambien
--       exige UPDATE. La identidad sigue protegida por el trigger
--       `protect_profile_fields()` (nuevo `NEW.id IS DISTINCT FROM OLD.id`)
--       y por el `WITH CHECK (auth.uid() = id)` de la policy.
--
-- QUE NO HACE
--   · NO toca la logica de privacidad: la galeria sigue siendo privada y los
--     portadas publicos siguen servidos igual.
--   · NO implementa pagos, suscripciones ni chat.
--   · NO usa `service_role` en ningun sitio.
--   · NO usa `CASCADE` para eliminar nada.
--   · NO borra ni reescribe filas de datos existentes.
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
-- COMPATIBILIDAD
--   · Las funciones no asumen columnas que puedan faltar: donde una columna es
--     opcional (`city`, `country_code`, `byte_size`, `estado`, `visibilidad`)
--     se lee con `to_jsonb(fila) ->> 'columna'`, que devuelve NULL si la
--     columna no existe, en lugar de referenciarla y romper la compilacion.
--   · El BLOQUE 0 verifica antes de tocar nada que existan las tablas y
--     columnas realmente necesarias, y avisa de las opcionales que falten.
--
-- PRERREQUISITOS
--   · `public.profiles` con `role`, `is_banned` e `is_verified`
--     (supabase-part1-auth.sql).
--   · `public.user_photos` (supabase-schema.sql). Opcional: si no esta, el
--     panel funciona pero la galeria y el contador no.
-- =====================================================================

BEGIN;

-- =====================================================================
-- BLOQUE 0 · Verificacion previa (solo lectura, aborta si falta algo
--             imprescindible)
-- =====================================================================
-- Se comprueba ANTES de tocar nada. Si falta una tabla o columna que el
-- modelo de seguridad necesita, se aborta con un mensaje exacto en lugar de
-- dejar el esquema a medias.

DO $do$
DECLARE
  v_missing text;
BEGIN
  -- ---- Tablas imprescindibles -------------------------------------------
  IF to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION
      'Falta la tabla public.profiles. Aplica antes supabase-part1-auth.sql.';
  END IF;

  -- ---- Columnes imprescindibles de profiles ------------------------------
  SELECT string_agg(c.column_name, ', ')
    INTO v_missing
  FROM unnest(ARRAY['id','role','is_banned','is_verified']) AS c(column_name)
  WHERE NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = c.column_name
  );

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION
      'public.profiles no tiene las columnas: %. Sin ellas no se puede proteger el rol.',
      v_missing;
  END IF;

  -- ---- Objetos que ya pueden existir: se verifica que sean compatibles ---
  IF to_regclass('public.admin_users') IS NOT NULL THEN
    SELECT string_agg(c.column_name, ', ')
      INTO v_missing
    FROM unnest(ARRAY['user_id','role','active']) AS c(column_name)
    WHERE NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'admin_users'
        AND column_name = c.column_name
    );

    IF v_missing IS NOT NULL THEN
      RAISE EXCEPTION
        'public.admin_users ya existe pero sin las columnas: %. No se modifica: revisa a mano.',
        v_missing;
    END IF;
  END IF;

  IF to_regclass('public.creator_requests') IS NOT NULL THEN
    SELECT string_agg(c.column_name, ', ')
      INTO v_missing
    FROM unnest(ARRAY['id','user_id','status','reviewed_by','reviewed_at','rejection_reason']) AS c(column_name)
    WHERE NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'creator_requests'
        AND column_name = c.column_name
    );

    IF v_missing IS NOT NULL THEN
      RAISE EXCEPTION
        'public.creator_requests ya existe pero sin las columnas: %. No se modifica: revisa a mano.',
        v_missing;
    END IF;
  END IF;

  -- ---- Opcionales: solo se avisa -----------------------------------------
  IF to_regclass('public.user_photos') IS NULL THEN
    RAISE WARNING
      'public.user_photos no existe: el panel funcionara, pero la galeria y el contador de publicaciones no.';
  ELSE
    SELECT string_agg(c.column_name, ', ')
      INTO v_missing
    FROM unnest(ARRAY['id','user_id','storage_path','filename','mime_type','created_at']) AS c(column_name)
    WHERE NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'user_photos'
        AND column_name = c.column_name
    );

    IF v_missing IS NOT NULL THEN
      RAISE WARNING
        'public.user_photos no tiene las columnas: %. La galeria del panel no funcionara.', v_missing;
    END IF;
  END IF;

  -- `city` y `country_code` se leen de forma tolerante (to_jsonb), asi que
  -- su ausencia no rompe nada: solo se avisa.
  SELECT string_agg(c.column_name, ', ')
    INTO v_missing
  FROM unnest(ARRAY['city','country_code']) AS c(column_name)
  WHERE NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = c.column_name
  );

  IF v_missing IS NOT NULL THEN
    RAISE NOTICE
      'public.profiles no tiene: %. Se mostraran como vacias.', v_missing;
  END IF;

  -- El alta de cuenta inserta `id` y `display_name`, y NO `created_at` ni
  -- `updated_at`: si esas columnas fueran NOT NULL y no tuvieran DEFAULT, el
  -- INSERT fallaria siempre. No es un problema de privilegios (no lo arregla
  -- esta migracion), pero conviene avisar antes de aplicar.
  SELECT string_agg(c.column_name, ', ')
    INTO v_missing
  FROM unnest(ARRAY['created_at','updated_at']) AS c(column_name)
  WHERE EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = c.column_name
      AND is_nullable = 'NO'
      AND column_default IS NULL
  );

  IF v_missing IS NOT NULL THEN
    RAISE WARNING
      'public.profiles: % es NOT NULL y no tiene DEFAULT: el alta de cuenta fallara. Anade un DEFAULT antes de aplicar.',
      v_missing;
  END IF;
END;
$do$;

-- =====================================================================
-- BLOQUE 1 · admin_users
-- =====================================================================
-- Misma forma que en supabase-part2-admin.sql, pero CON RLS: aunque alguien
-- concediera un privilegio por error, sin policy no hay filas visibles.

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

-- RLS activado y SIN policies para `anon`/`authenticated`: nadie lee esta
-- tabla desde la aplicacion. Solo lo hacen las funciones SECURITY DEFINER,
-- que corren con los privilegios del dueno.
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

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

-- ---- RLS -------------------------------------------------------------
-- Se habilita SIEMPRE, exista o no la tabla antes. Con RLS y sin policies
-- la tabla queda en modo denegar: nadie lee ni escribe hasta que se creen las
-- policies.
--
-- LAS POLICIES se crean en el BLOQUE 9, DESPUES de las funciones de
-- autorizacion: `creator_requests_insert_own_pending` usa
-- `public.can_request_creator()`, y PostgreSQL valida las funciones que
-- aparecen en el `WITH CHECK` al crear la policy. Si la policy se creara
-- antes que la funcion, la migracion fallaria con "function
-- public.can_request_creator() does not exist" en cualquier base donde
-- `supabase-part2-admin.sql` no estuviera aplicado.

ALTER TABLE public.creator_requests ENABLE ROW LEVEL SECURITY;

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
-- BLOQUE 4 · Proteccion del perfil
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
--   · En el INSERT, el rol se exige como 'fan' y el bloqueo y la verificacion
--     como false: una cuenta nueva no puede nacer creadora, bloqueada ni
--     verificada. Si el valor no es el esperado la sentencia FALLA (no se
--     corrige en silencio).
--
-- POR QUE NO SE BORRA LA FUNCION VIEJA
--   La version original hacia `DROP FUNCTION public.protect_profile()`. Eso
--   podia abortar toda la migracion si esa funcion estaba usada por un
--   trigger de OTRA tabla, y ademas dejaba una sobrecarga si su aridad era
--   distinta. Aqui no se borra nada: se crea una funcion NUEVA con otro
--   nombre y se reapuntan SOLO los triggers de `public.profiles`. Los
--   triggers de otras tablas que usen la funcion vieja siguen intactos.

-- Se reapuntan los triggers de `public.profiles` que usaban la funcion vieja.
-- Se localizan por la FUNCION que ejecutan, no por su nombre, asi que
-- funciona tanto si se llaman `trg_protect_profile` como de otra forma.
-- Solo se tocan los de `profiles`: los de otras tablas no se mueven.
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
      AND p.proname LIKE 'protect_profile%'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.profiles', r.tgname);
    RAISE NOTICE 'Trigger reapuntado (funcion anterior): %', r.tgname;
  END LOOP;

  -- La funcion vieja NO se borra (puede estar usada por triggers de otras
  -- tablas), pero se le cierra el privilegio EXECUTE a PUBLIC: una funcion
  -- de trigger no se puede llamar por RPC, pero deja de estar expuesta.
  FOR r IN
    SELECT p.oid,
           n.nspname,
           p.proname,
           pg_catalog.pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname LIKE 'protect_profile%'
      AND p.proname <> 'protect_profile_fields'
  LOOP
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC',
      r.nspname, r.proname, r.args
    );
    RAISE NOTICE 'EXECUTE revocado a PUBLIC en % (se conserva la funcion)', r.proname;
  END LOOP;
END;
$do$;

-- SECURITY INVOKER a proposito: el trigger tiene que ver el rol con el que
-- corre la SENTENCIA (la de la funcion SECURITY DEFINER o el de la sesion
-- normal). Con SECURITY DEFINER veria siempre al dueno y la comprobacion
-- no serviria de nada.
CREATE OR REPLACE FUNCTION public.protect_profile_fields()
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
  -- tambien a los roles que lo heredan y a los superusuarios, que pueden
  -- hacer lo que quieran desde el SQL Editor.
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
      -- `id` no se puede cambiar. La policy RLS ya lo exige con
      -- `WITH CHECK (auth.uid() = id)`, pero el trigger lo vuelve a
      -- comprobar: es la unica defensa que no depende de que las policies
      -- esten bien escritas.
      --
      -- El privilegio de UPDATE sobre `id` SI se concede (PostgREST genera
      -- `ON CONFLICT (id) DO UPDATE SET id = EXCLUDED.id, ...` en el upsert
      -- del perfil, y sin el el guardado del perfil fallaria). Como aqui
      -- NEW.id y OLD.id son el mismo valor, esta comprobacion no molesta:
      -- solo rechaza un cambio real de identidad.
      IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'El id del perfil no se puede cambiar.'
          USING ERRCODE = '42501';
      END IF;

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

CREATE TRIGGER trg_protect_profile_fields
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.protect_profile_fields();


-- El mismo trigger cubre el INSERT: una cuenta nueva nace como 'fan'.
CREATE TRIGGER trg_protect_profile_fields_insert
BEFORE INSERT ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.protect_profile_fields();

-- =====================================================================
-- BLOQUE 5 · Funciones de administracion
-- =====================================================================
-- Todas son SECURITY DEFINER con `search_path = ''` y comprueban el rol
-- DENTRO de la base. El panel valida tambien en el servidor: son dos capas
-- distintas y las dos hacen falta.

-- Listado de perfiles para el panel. Lo pueden ver administradoras y
-- moderadoras. No expone email ni telefono: la tabla `profiles` no los tiene.
-- `city` y `country_code` se leen de forma tolerante: pueden no existir.
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
    to_jsonb(p) ->> 'city',
    to_jsonb(p) ->> 'country_code',
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
--     `protect_profile_fields()` exige, de modo que el trigger la deja pasar.
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


-- GALERIA · ACCESO ADMINISTRATIVO COMPLETO.
--
-- Solo administradoras. Devuelve la CLAVE del objeto (`storage_path`), que es
-- lo que necesita el servidor de la aplicacion para firmar una URL de
-- lectura. Con la clave en mano, el servidor puede servir el contenido
-- privado de pago de esa creadora.
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

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Se requiere rol admin activo'
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
    NULLIF(to_jsonb(up) ->> 'byte_size', '')::bigint,
    to_jsonb(up) ->> 'estado',
    to_jsonb(up) ->> 'visibilidad',
    up.created_at
  FROM public.user_photos up
  WHERE up.user_id = target_user_id
  ORDER BY up.created_at DESC
  LIMIT 100;
END;
$fn$;


-- GALERIA · PERMISOS DE MODERACION.
--
-- Administradoras y moderadoras, pero SOLO metadatos: NO devuelve
-- `storage_path`. Sin la clave del objeto no se puede firmar una URL de
-- lectura, asi que un moderador NO puede ver el contenido privado de pago
-- de una creadora. Puede ver que existen archivos, de que tipo y de cuando.
CREATE OR REPLACE FUNCTION public.moderator_list_user_media(
  target_user_id uuid
)
RETURNS TABLE (
  id           uuid,
  filename     text,
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
    up.mime_type,
    NULLIF(to_jsonb(up) ->> 'byte_size', '')::bigint,
    to_jsonb(up) ->> 'estado',
    to_jsonb(up) ->> 'visibilidad',
    up.created_at
  FROM public.user_photos up
  WHERE up.user_id = target_user_id
  ORDER BY up.created_at DESC
  LIMIT 100;
END;
$fn$;

-- =====================================================================
-- BLOQUE 6 · Aprobar y rechazar solicitudes + conteo publico
-- =====================================================================

-- Cantidad de publicaciones de una creadora.
--
-- Es un dato de cuenta (cuanto publica), no el contenido: la galeria sigue
-- siendo privada y las fotos no se exponen. Se ofrece como funcion y no como
-- una policy de SELECT porque asi se puede contar las filas de otra persona
-- sin leerlas ni firmarlas.
--
-- PL/pgSQL y no SQL a proposito: el cuerpo de una funcion SQL se valida al
-- crearla, y si `public.user_photos` no existiera la migracion entera
-- abortaba. En PL/pgSQL la comprobacion es perezosa.
CREATE OR REPLACE FUNCTION public.public_media_count(
  target_user_id uuid
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_count bigint;
BEGIN
  SELECT count(*)::bigint
    INTO v_count
  FROM public.user_photos up
  WHERE up.user_id = target_user_id
    AND COALESCE(to_jsonb(up) ->> 'estado', 'listo') = 'listo';

  RETURN v_count;
END;
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

-- `admin_users`: ni lectura ni escritura desde la aplicacion. Con RLS
-- activado (BLOQUE 1) y sin policies, tampoco hay filas visibles.
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

-- `profiles`: `anon` solo lee. La escritura la hacen las RPC y el trigger de
-- `auth.users`, que corren con los privilegios del dueno.
REVOKE ALL
ON TABLE public.profiles
FROM anon;

GRANT SELECT
ON TABLE public.profiles
TO anon;

-- Las funciones se cierran a PUBLIC y a `anon`, y se abren solo a
-- `authenticated`. Sin sesion no hay nada que administrar.
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_moderator() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_request_creator() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.my_admin_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_profiles(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_creator_role(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_banned(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_creator_requests(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_user_media(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.moderator_list_user_media(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.public_media_count(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_creator_request(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reject_creator_request(uuid, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_moderator() TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_request_creator() TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_admin_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_profiles(text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_creator_role(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_banned(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_creator_requests(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_user_media(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moderator_list_user_media(uuid) TO authenticated;
-- El conteo es publico: lo puede pedir cualquiera, incluso sin sesion.
-- No expone contenido, solo un numero.
GRANT EXECUTE ON FUNCTION public.public_media_count(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_creator_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_creator_request(uuid, text) TO authenticated;

-- =====================================================================
-- BLOQUE 8 · Privilegios por columna sobre `profiles`
-- =====================================================================
-- Capas de defensa:
--   1. La policy RLS limita las FILAS (solo la propia). No puede limitar
--      columnas: una policy RLS no tiene acceso a OLD ni a NEW (eso solo
--      existe en los triggers), asi que comparar `old.role` con `new.role`
--      dentro de una policy NO es PostgreSQL valido.
--   2. Los PRIVILEGIOS por columna quitan `role`, `is_banned` e
--      `is_verified` del alcance de `authenticated`.
--   3. El TRIGGER `protect_profile_fields()` rechaza el cambio no autorizado.
--
-- En PostgreSQL los privilegios de columna SON ADITIVOS respecto a los de
-- tabla: revocar `UPDATE` de tabla NO elimina un `GRANT UPDATE(role)` que
-- se haya hecho a nivel de columna, y al reves. Por eso aqui se hacen LAS
-- DOS COSAS, y en este orden:
--
--   1. REVOKE a nivel de tabla: quita el privilegio general.
--   2. REVOKE a nivel de columna, columna por columna: elimina cualquier
--      privilegio residual o heredado sobre las columnas protegidas.
--   3. GRANT por columna: concede solo lo que la app necesita de verdad.
--
-- No se depende del REVOKE de tabla: sin el paso 2, un `GRANT UPDATE(role)`
-- preexisting seguiria vigente y `role` volveria a ser escribible desde el
-- navegador.
--
-- La lista se calcula con `information_schema`, de modo que una columna nueva
-- que se anada a `profiles` mas adelante no deja al usuario sin poder
-- escribirla.

DO $do$
DECLARE
  r record;
  cols text;
  -- LISTA CERRADA de columnas escribibles por `authenticated`. No se concede
  -- nada automaticamente: si mañana se añade una columna a `profiles`, esta
  -- migracion NO le da permiso hasta que se escriba aqui a mano.
  --
  -- Las columnas salen de las escrituras verificadas en `src/`:
  --   · alta de cuenta    -> src/lib/authProfile.js
  --                         (INSERT: id, display_name)
  --   · upsert del perfil -> src/routes/perfil/+page.svelte
  --                         (INSERT: id, display_name, bio)
  --                         (UPDATE: id, display_name, bio)
  --   · edicion           -> src/routes/configuracion/+page.svelte
  --                         (UPDATE: display_name, username, bio, subscription_price)
  --   · avatar            -> src/routes/perfil/+page.svelte y
  --                         src/lib/components/UploadPhoto.svelte
  --                         (UPDATE: avatar_key)
  --
  -- `bio` entra en la lista de INSERT por el upsert del perfil: PostgREST
  -- traduce el upsert en `INSERT INTO profiles (id, display_name, bio)`, y
  -- PostgreSQL exige privilegio de INSERT en TODAS las columnas nombradas.
  -- Sin `bio` en la lista, guardar el perfil fallaria con "permission denied
  -- for column bio".
  --
  -- `id` entra en la lista de UPDATE por el mismo motivo: PostgREST genera
  -- `ON CONFLICT (id) DO UPDATE SET id = EXCLUDED.id, display_name = ...,
  -- bio = ...` y PostgreSQL exige UPDATE en cada columna del SET. Que el `id`
  -- no se pueda cambiar de verdad lo garantizan el trigger
  -- `protect_profile_fields()` y el `WITH CHECK (auth.uid() = id)` de la
  -- policy, no el privilegio.
  v_allowed_insert text[] := ARRAY['id', 'display_name', 'bio'];
  v_allowed_update text[] := ARRAY[
    'id', 'display_name', 'username', 'bio', 'subscription_price', 'avatar_key'
  ];
BEGIN
  -- =====================================================================
  -- Paso 1 · Privilegio de tabla: se retiran los generales.
  -- =====================================================================
  EXECUTE 'REVOKE UPDATE ON TABLE public.profiles FROM authenticated';
  EXECUTE 'REVOKE INSERT ON TABLE public.profiles FROM authenticated';
  -- DELETE: la aplicacion no borra perfiles en ningun punto (no hay baja de
  -- cuenta). Sin este REVOKE, `authenticated` conservaria el DELETE de tabla
  -- aunque no exista policy que lo permita.
  EXECUTE 'REVOKE DELETE ON TABLE public.profiles FROM authenticated';

  -- =====================================================================
  -- Paso 2 · Privilegios por columna: se eliminan los residuales.
  -- =====================================================================
  -- UPDATE: columnas protegidas. `created_at` no se puede falsear y
  -- `updated_at` lo mantiene el trigger de la base
  -- (`update_profiles_updated_at`), no la aplicacion.
  --
  -- `id` NO esta en esta lista: se concede UPDATE sobre `id` porque el
  -- upsert del perfil lo necesita (PostgREST genera
  -- `ON CONFLICT (id) DO UPDATE SET id = EXCLUDED.id, ...`). Lo que impide
  -- cambiar la identidad es el trigger `protect_profile_fields()` y el
  -- `WITH CHECK (auth.uid() = id)` de la policy, no el privilegio.
  FOR r IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name IN ('role', 'is_banned', 'is_verified', 'created_at', 'updated_at')
    ORDER BY ordinal_position
  LOOP
    EXECUTE format(
      'REVOKE UPDATE (%I) ON TABLE public.profiles FROM authenticated',
      r.column_name
    );
    RAISE NOTICE 'profiles: UPDATE revocado por columna en %', r.column_name;
  END LOOP;

  -- INSERT: columnas protegidas. `subscription_price` entra aqui: una
  -- cuenta nueva no se crea con un precio puesto.
  FOR r IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name IN ('role', 'is_banned', 'is_verified', 'subscription_price')
    ORDER BY ordinal_position
  LOOP
    EXECUTE format(
      'REVOKE INSERT (%I) ON TABLE public.profiles FROM authenticated',
      r.column_name
    );
    RAISE NOTICE 'profiles: INSERT revocado por columna en %', r.column_name;
  END LOOP;

  -- INSERT: `created_at` y `updated_at` SOLO cuando la columna tiene DEFAULT.
  -- Si la columna tiene valor por defecto, la base la rellena sola y el
  -- cliente no debe poder fijarla a mano (se le revocaria la fecha de alta).
  -- Si NO tiene default, la columna se concede en el Paso 3: sin ella no
  -- habria forma de dar de alta una cuenta.
  FOR r IN
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name IN ('created_at', 'updated_at')
      AND column_default IS NOT NULL
    ORDER BY ordinal_position
  LOOP
    EXECUTE format(
      'REVOKE INSERT (%I) ON TABLE public.profiles FROM authenticated',
      r.column_name
    );
    RAISE NOTICE
      'profiles: INSERT revocado por columna en % (tiene DEFAULT, la base la pone)', r.column_name;
  END LOOP;

  -- =====================================================================
  -- Paso 3 · Concesion por columna: LISTA EXPLICITA.
  -- =====================================================================
  -- La lista viene de `v_allowed_insert` / `v_allowed_update`: es cerrada y
  -- esta escrita arriba. No se concede nada sobre columnas que se anadan a
  -- `profiles` mas adelante.
  --
  -- Se arma con `string_agg` (no concatenando en un bucle): `cols := NULL;
  -- cols := cols || algo;` deja `cols` en NULL para siempre, porque en SQL
  -- `NULL || 'x'` es NULL; el `IF cols IS NOT NULL` no se cumpliria y el
  -- GRANT no se ejecutaria nunca. `string_agg` devuelve NULL solo si no
  -- queda ninguna columna que conceder.
  --
  -- Se filtran las columnas que existen de verdad: si una columna de la
  -- lista no esta en la base, se avisa y se sigue con el resto (un GRANT
  -- sobre una columna inexistente haria fallar toda la migracion).
  SELECT string_agg(quote_ident(t.c), ', ' ORDER BY t.o)
    INTO cols
  FROM unnest(v_allowed_insert) WITH ORDINALITY AS t(c, o)
  WHERE EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = t.c
  );

  IF cols IS NOT NULL THEN
    EXECUTE format(
      'GRANT INSERT (%s) ON TABLE public.profiles TO authenticated',
      cols
    );
    RAISE NOTICE 'profiles: INSERT concedido por columna a: %', cols;
  ELSE
    RAISE WARNING
      'profiles: no hay columnas que conceder para INSERT (revisa el esquema).';
  END IF;

  SELECT string_agg(quote_ident(t.c), ', ' ORDER BY t.o)
    INTO cols
  FROM unnest(v_allowed_update) WITH ORDINALITY AS t(c, o)
  WHERE EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = t.c
  );

  IF cols IS NOT NULL THEN
    EXECUTE format(
      'GRANT UPDATE (%s) ON TABLE public.profiles TO authenticated',
      cols
    );
    RAISE NOTICE 'profiles: UPDATE concedido por columna a: %', cols;
  ELSE
    RAISE WARNING
      'profiles: no hay columnas que conceder para UPDATE (revisa el esquema).';
  END IF;
END;
$do$;

-- =====================================================================
-- BLOQUE 9 · Policies de `creator_requests` y de `profiles`
-- =====================================================================
-- Las policies de `creator_requests` van PRIMERO y antes que las de
-- `profiles` por una razon de orden: `creator_requests_insert_own_pending`
-- usa `public.can_request_creator()` en su `WITH CHECK`, y PostgreSQL valida
-- las funciones que aparecen en el `WITH CHECK` al crear la policy. Como
-- `can_request_creator()` se crea en el BLOQUE 3, la policy tiene que
-- crearse despues. En la version anterior de este archivo la policy estaba
-- en el BLOQUE 2, ANTES de la funcion: en una base donde
-- `supabase-part2-admin.sql` no estuviera aplicado, la migracion fallaba con
-- "function public.can_request_creator() does not exist".
--
-- ---- Policies de `creator_requests` ------------------------------------

-- Solo se ven las solicitudes propias.
DROP POLICY IF EXISTS "creator_requests_select_own" ON public.creator_requests;

CREATE POLICY "creator_requests_select_own" ON public.creator_requests
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id
  );

-- Solo se puede insertar una solicitud propia, en estado pendiente y sin
-- datos de revision. `can_request_creator()` comprueba que no sea ya
-- creadora, que no este baneada y que no tenga otra solicitud pendiente.
DROP POLICY IF EXISTS "creator_requests_insert_own_pending" ON public.creator_requests;

CREATE POLICY "creator_requests_insert_own_pending" ON public.creator_requests
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

-- ---- Policies de `profiles` --------------------------------------------
-- LIMPIEZA DE POLICIES DE ESCRITURA.
--
-- En la base hay policies de escritura con los nombres `profiles_update_own`
-- y `profiles_insert_own`. Se eliminan y se recrean las canonicas.
--
-- Ademas se hace un barrido de TODA policy de escritura que exista en
-- `public.profiles` (cmd UPDATE, INSERT o ALL), para que no queden policies
-- duplicadas: en PostgreSQL las policies permisivas se combinan con OR, asi
-- que una policy vieja mas ancha seguiria concediendo acceso aunque exista
-- la canonica.
--
-- Las policies FOR ALL se re-crean como solo-SELECT antes de eliminarlas: si
-- se borraran tal cual, se perderia tambien su parte de lectura, que es la
-- que necesita la Home para mostrar las creadoras.
DO $do$
DECLARE
  r record;
  v_roles text;
  v_qual text;
BEGIN
  FOR r IN
    SELECT policyname, roles, qual
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND cmd = 'ALL'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.profiles', r.policyname);

    v_roles := COALESCE(array_to_string(r.roles, ', '), 'PUBLIC');
    v_qual := COALESCE(r.qual, 'true');

    EXECUTE format(
      'CREATE POLICY %I ON public.profiles FOR SELECT TO %s USING (%s)',
      r.policyname, v_roles, v_qual
    );
    RAISE NOTICE 'profiles: policy %I convertida a solo-SELECT', r.policyname;
  END LOOP;

  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND cmd IN ('UPDATE', 'INSERT')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.profiles', r.policyname);
    RAISE NOTICE 'profiles: policy de escritura eliminada: %', r.policyname;
  END LOOP;
END;
$do$;

-- Las dos policies de escritura que existen en la base.
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;

-- Nombres antiguos del esquema del repo, por si tambien estuvieran.
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;

-- Policy canonica de UPDATE: solo la propia fila y con WITH CHECK explicito
-- (la policy anterior, al omitir el WITH CHECK, reutilizaba el USING).
--
-- Lo que estas policies NO pueden hacer es comparar OLD con NEW: en
-- PostgreSQL una policy RLS no tiene acceso a OLD ni a NEW. La proteccion por
-- columna la dan los privilegios (BLOQUE 8) y el trigger (BLOQUE 4).
--
-- La policy de SELECT no se toca: la Home necesita leer los perfiles
-- publicos de las creadoras. Se deja constancia en el bloque de verificacion
-- final.
CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY profiles_insert_own ON public.profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- =====================================================================
-- BLOQUE 10 · Administrador existente (idempotente, sin duplicar)
-- =====================================================================
-- El permiso administrativo vive en `admin_users`, NO en `profiles.role`.
-- Los roles de perfil son solo 'fan' y 'creator': esta migracion no escribe
-- `profiles.role = 'admin'` en ningun sitio.
--
-- Que hace este bloque:
--   · Si el administrador ya tiene una fila ACTIVA en `admin_users`, no hace
--     NADA. No se duplica ni se modifica.
--   · Si tiene perfil pero no fila de administrador, crea UNA fila admin
--     (idempotente: si ya existe, `ON CONFLICT DO NOTHING` no hace nada).
--   · Si no tiene perfil en `public.profiles`, avisa y NO inserta (la clave
--     foranea lo impediria y abortaria la migracion).
--
-- El administrador conocido es 8f3eb06b-510a-439c-bba5-c7ba84e04254.
-- Para sumar otra persona con permisos, se inserta a mano (ver BLOQUE 13).

DO $do$
DECLARE
  v_admin constant uuid := '8f3eb06b-510a-439c-bba5-c7ba84e04254';
  v_has_profile boolean := false;
  v_has_admin    boolean := false;
  v_rows integer := 0;
BEGIN
  SELECT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = v_admin)
    INTO v_has_profile;

  SELECT EXISTS (
    SELECT 1 FROM public.admin_users a
    WHERE a.user_id = v_admin AND a.active
  )
    INTO v_has_admin;

  IF v_has_admin THEN
    RAISE NOTICE
      'El administrador % ya tiene permiso activo: no se toca nada.', v_admin;
  ELSIF v_has_profile THEN
    INSERT INTO public.admin_users
      (user_id, role, active, created_at, created_by, updated_at)
    VALUES
      (v_admin, 'admin', true, now(), v_admin, now())
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 1 THEN
      RAISE NOTICE 'Fila de administrador creada para % (no habia ninguna activa).', v_admin;
    ELSE
      RAISE NOTICE 'La fila de administrador de % ya existia: no se duplica.', v_admin;
    END IF;
  ELSE
    RAISE WARNING
      'El usuario % no tiene fila en public.profiles: no se puede crear el administrador. Revisa el UUID desde la cuenta de Supabase.',
      v_admin;
  END IF;

  -- Aviso (sin tocar datos): un rol de perfil distinto de 'fan'/'creator'
  -- no lo reconoce la aplicacion. Se corrige desde el panel con
  -- admin_set_creator_role(), no con un UPDATE manual.
  IF v_has_profile AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = v_admin
      AND COALESCE(p.role, 'fan') NOT IN ('fan', 'creator')
  ) THEN
    RAISE WARNING
      'profiles.role de % no es ''fan'' ni ''creator''. La app no reconoce ese valor; ajustalo desde el panel con admin_set_creator_role().',
      v_admin;
  END IF;
END;
$do$;

-- =====================================================================
-- BLOQUE 11 · Aserciones (ABORTAN si el esquema queda inseguro)
-- =====================================================================
-- Se ejecutan DENTRO de la transaccion: si algo falla, la migracion entera
-- se revierte y no se aplica a medias.
--
-- Comprueban:
--   · RLS activado en profiles, admin_users y creator_requests.
--   · Que `authenticated` NO conserve UPDATE/INSERT de tabla sobre profiles
--     (si los conservan, la restriccion por columna queda anulada).
--   · Que `authenticated` no pueda escribir role, is_banned ni is_verified,
--     ni insertar subscription_price, ni modificar created_at ni updated_at:
--     ni por privilegio de tabla, ni por privilegio de columna residual, ni
--     por herencia de otro rol.
--   · Que `id` siga siendo la identidad de la fila: tiene privilegio de
--     UPDATE (lo necesita el upsert del perfil), pero el trigger
--     `protect_profile_fields()` y el `WITH CHECK (auth.uid() = id)` de la
--     policy `profiles_update_own` impiden cambiarlo.
--   · Que los privilegios QUE LA APP NECESITA sigan existiendo (alta, upsert
--     del perfil y edicion legitima): si un REVOKE de mas dejara a la
--     usuaria sin poder guardar su bio, la migracion tambien aborta.
--   · Que `anon` no pueda escribir ni borrar profiles, ni ejecutar las
--     funciones administrativas.
--   · Que existan las policies de creator_requests y de profiles.
--   · Que no haya dos administradores activos para el mismo usuario.

DO $do$
DECLARE
  v_problems text := '';
  v_admin constant uuid := '8f3eb06b-510a-439c-bba5-c7ba84e04254';
  -- Misma lista cerrada que el BLOQUE 8 concede. Si se cambia alli, se
  -- cambia aqui: son la definicion de "que puede escribir la usuaria".
  -- `bio` esta en la lista de INSERT porque el upsert del perfil lo envia.
  -- `id` esta en la de UPDATE porque el upsert lo incluye en su
  -- `ON CONFLICT ... DO UPDATE SET`; que no se pueda cambiar de verdad lo
  -- comprueban el trigger y la policy (ver la asercion del trigger mas abajo).
  v_allowed_insert text[] := ARRAY['id', 'display_name', 'bio'];
  v_allowed_update text[] := ARRAY[
    'id', 'display_name', 'username', 'bio', 'subscription_price', 'avatar_key'
  ];
  v_col text;
  r record;
BEGIN
  -- ---- RLS habilitado --------------------------------------------------
  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('profiles', 'admin_users', 'creator_requests')
      AND NOT c.relrowsecurity
  LOOP
    v_problems := v_problems || 'RLS desactivado en public.' || r.relname || '; ';
  END LOOP;

  -- ---- Privilegios de tabla sobre profiles ------------------------------
  IF has_table_privilege('authenticated', 'public.profiles', 'UPDATE') THEN
    v_problems := v_problems || 'authenticated conserva UPDATE de tabla sobre profiles; ';
  END IF;

  IF has_table_privilege('authenticated', 'public.profiles', 'INSERT') THEN
    v_problems := v_problems || 'authenticated conserva INSERT de tabla sobre profiles; ';
  END IF;

  -- DELETE: la aplicacion no borra perfiles. Si authenticated conserva el
  -- privilegio de tabla, basta con una policy que lo permita para que
  -- alguien borre su propio perfil (y con ON DELETE CASCADE, su galeria).
  IF has_table_privilege('authenticated', 'public.profiles', 'DELETE') THEN
    v_problems := v_problems || 'authenticated conserva DELETE de tabla sobre profiles; ';
  END IF;

  IF has_table_privilege('anon', 'public.profiles', 'UPDATE')
     OR has_table_privilege('anon', 'public.profiles', 'INSERT')
     OR has_table_privilege('anon', 'public.profiles', 'DELETE') THEN
    v_problems := v_problems || 'anon conserva escritura sobre profiles; ';
  END IF;

  -- ---- Privilegios por columna: la lista EXACTA -------------------------
  -- La lista es cerrada (ver BLOQUE 8): `authenticated` solo puede escribir
  -- estas columnas, y NINGUNA mas.
  --
  -- `has_column_privilege` devuelve el privilegio EFECTIVO: ya tiene en
  -- cuenta el privilegio de tabla, el de columna, el heredado por membresia
  -- de roles y el que llega por PUBLIC. Por eso una sola comprobacion por
  -- columna detecta cualquier via de escritura.
  --
  -- Se recorre TODAS las columnas de `profiles`: si `authenticated` puede
  -- escribir una columna que no esta en la lista, es un problema. Asi se
  -- detecta tambien lo que se haya concedido por error o quedara de una
  -- version anterior.
  FOR r IN
    SELECT c.column_name
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'profiles'
  LOOP
    IF has_column_privilege('authenticated', 'public.profiles', r.column_name, 'UPDATE') THEN
      IF NOT (r.column_name = ANY (v_allowed_update)) THEN
        v_problems := v_problems
          || 'authenticated puede UPDATE profiles.' || r.column_name || ' (fuera de la lista permitida); ';
      END IF;
    END IF;

    IF has_column_privilege('authenticated', 'public.profiles', r.column_name, 'INSERT') THEN
      IF NOT (r.column_name = ANY (v_allowed_insert)) THEN
        v_problems := v_problems
          || 'authenticated puede INSERT profiles.' || r.column_name || ' (fuera de la lista permitida); ';
      END IF;
    END IF;
  END LOOP;

  -- ---- Privilegios HEREDADOS --------------------------------------------
  -- Si `authenticated` hereda de otro rol (por membresia), ese rol puede
  -- traer consigo privilegios sobre `profiles` que el REVOKE por columna no
  -- toca. Se comprueba rol por rol.
  FOR r IN
    SELECT g.rolname
    FROM pg_roles g
    WHERE g.rolname <> 'authenticated'
      AND pg_catalog.pg_has_role('authenticated', g.oid, 'MEMBER')
  LOOP
    FOR v_col IN
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'profiles'
        AND column_name IN ('role', 'is_banned', 'is_verified', 'id', 'created_at')
    LOOP
      IF has_column_privilege(r.rolname, 'public.profiles', v_col, 'UPDATE')
         OR has_column_privilege(r.rolname, 'public.profiles', v_col, 'INSERT') THEN
        v_problems := v_problems
          || 'rol heredado ' || r.rolname || ' puede escribir profiles.' || v_col || '; ';
      END IF;
    END LOOP;
  END LOOP;

  -- ---- Privilegios que la app NECESITA (si faltan, algo se rompio) ------
  -- Se recorre la MISMA lista que concede el BLOQUE 8: cada columna de la
  -- lista que exista en la tabla tiene que tener su privilegio, o la
  -- aplicacion se quedaria sin poder guardar el perfil.
  FOR r IN
    SELECT c.column_name
    FROM unnest(v_allowed_insert) AS c(column_name)
    WHERE EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'profiles'
        AND column_name = c.column_name
    )
  LOOP
    IF NOT has_column_privilege('authenticated', 'public.profiles', r.column_name, 'INSERT') THEN
      v_problems := v_problems
        || 'authenticated NO puede INSERT profiles.' || r.column_name || ' (el registro se romperia); ';
    END IF;
  END LOOP;

  -- Edicion legitima del perfil: nombre, usuario, bio, precio y avatar.
  FOR r IN
    SELECT c.column_name
    FROM unnest(v_allowed_update) AS c(column_name)
    WHERE EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'profiles'
        AND column_name = c.column_name
    )
  LOOP
    IF NOT has_column_privilege('authenticated', 'public.profiles', r.column_name, 'UPDATE') THEN
      v_problems := v_problems
        || 'authenticated NO puede UPDATE profiles.' || r.column_name || ' (la edicion del perfil se romperia); ';
    END IF;
  END LOOP;

  -- ---- Protecciones por columna, comprobadas una a una ------------------
  -- INSERT: estas columnas NO pueden concederse al alta. Ninguna esta en
  -- `v_allowed_insert` (que es `id`, `display_name`, `bio`), y ademas el
  -- BLOQUE 8 las revoca por columna. Se comprueba de forma explicita para
  -- que quede constancia en el log y en el codigo de la migracion.
  FOR r IN
    SELECT c.column_name
    FROM unnest(ARRAY[
      'role', 'is_banned', 'is_verified', 'subscription_price',
      'created_at', 'updated_at'
    ]) AS c(column_name)
    WHERE EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'profiles'
        AND column_name = c.column_name
    )
  LOOP
    IF has_column_privilege('authenticated', 'public.profiles', r.column_name, 'INSERT') THEN
      v_problems := v_problems
        || 'authenticated puede INSERT profiles.' || r.column_name || ' (columna protegida en el alta); ';
    END IF;
  END LOOP;

  -- UPDATE: `created_at` y `updated_at` no se pueden escribir a mano. La
  -- fecha de alta la pone la base y `updated_at` lo mantiene el trigger
  -- `update_profiles_updated_at`.
  FOR r IN
    SELECT c.column_name
    FROM unnest(ARRAY['created_at', 'updated_at']) AS c(column_name)
    WHERE EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'profiles'
        AND column_name = c.column_name
    )
  LOOP
    IF has_column_privilege('authenticated', 'public.profiles', r.column_name, 'UPDATE') THEN
      v_problems := v_problems
        || 'authenticated puede UPDATE profiles.' || r.column_name || ' (columna protegida); ';
    END IF;
  END LOOP;

  -- `id` en UPDATE: el privilegio EXISTE a proposito. El upsert de
  -- src/routes/perfil/+page.svelte lo necesita: PostgREST lo traduce en
  -- `INSERT INTO profiles (id, display_name, bio) ... ON CONFLICT (id) DO
  -- UPDATE SET id = EXCLUDED.id, display_name = ..., bio = ...` y PostgreSQL
  -- exige UPDATE sobre cada columna del SET. Sin ese privilegio, guardar el
  -- perfil fallaria con "permission denied for column id".
  --
  -- Lo que NO se puede es cambiar la identidad, y eso no depende del
  -- privilegio: lo comprueban el trigger `protect_profile_fields()`
  -- (`NEW.id IS DISTINCT FROM OLD.id`) y el `WITH CHECK (auth.uid() = id)` de
  -- la policy `profiles_update_own`. Las dos comprobaciones estan mas abajo
  -- en este mismo bloque y abortan la migracion si faltan.

  -- ---- Funciones administrativas accesibles sin sesion ------------------
  FOR r IN
    SELECT unnest(ARRAY[
      'public.is_admin()',
      'public.is_moderator()',
      'public.my_admin_role()',
      'public.can_request_creator()',
      'public.admin_list_profiles(text,integer)',
      'public.admin_set_creator_role(uuid,text)',
      'public.admin_set_banned(uuid,boolean)',
      'public.admin_list_creator_requests(text)',
      'public.admin_list_user_media(uuid)',
      'public.moderator_list_user_media(uuid)',
      'public.approve_creator_request(uuid)',
      'public.reject_creator_request(uuid,text)'
    ]) AS fn
  LOOP
    IF has_function_privilege('anon', r.fn, 'EXECUTE') THEN
      v_problems := v_problems || 'anon puede ejecutar ' || r.fn || '; ';
    END IF;
  END LOOP;

  -- ---- Policies ---------------------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'creator_requests'
      AND policyname = 'creator_requests_select_own'
  ) THEN
    v_problems := v_problems || 'falta la policy creator_requests_select_own; ';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'creator_requests'
      AND policyname = 'creator_requests_insert_own_pending'
  ) THEN
    v_problems := v_problems || 'falta la policy creator_requests_insert_own_pending; ';
  END IF;

  -- Las canonicas de profiles, con el nombre que tienen en la base.
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND policyname = 'profiles_update_own'
      AND cmd = 'UPDATE'
  ) THEN
    v_problems := v_problems || 'falta la policy profiles_update_own sobre profiles; ';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND policyname = 'profiles_insert_own'
      AND cmd = 'INSERT'
  ) THEN
    v_problems := v_problems || 'falta la policy profiles_insert_own sobre profiles; ';
  END IF;

  -- ---- El trigger que protege la identidad debe existir ------------------
  -- `id` tiene privilegio de UPDATE (lo necesita el upsert del perfil), asi
  -- que la garantia de que no se puede cambiar la identidad la tienen el
  -- trigger y la policy. Si el trigger no esta, o no comprueba `id`, la
  -- migracion aborta.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    WHERE t.tgrelid = 'public.profiles'::regclass
      AND NOT t.tgisinternal
      AND t.tgname = 'trg_protect_profile_fields'
      AND (t.tgtype & 2) = 2
      AND (t.tgtype & 16) = 16
  ) THEN
    v_problems := v_problems || 'falta el trigger trg_protect_profile_fields sobre profiles; ';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'protect_profile_fields'
      AND pg_get_functiondef(p.oid) LIKE '%NEW.id%'
  ) THEN
    v_problems := v_problems
      || 'protect_profile_fields() no comprueba el cambio de id: la identidad quedaria solo en manos de la policy; ';
  END IF;

  -- No deben quedar policies de escritura duplicadas: las permisivas se
  -- combinan con OR, asi que una policy vieja mas ancha seguiria concediendo
  -- acceso aunque exista la canonica.
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND cmd IN ('UPDATE', 'INSERT')
      AND policyname NOT IN ('profiles_update_own', 'profiles_insert_own')
  LOOP
    v_problems := v_problems
      || 'policy de escritura duplicada sobre profiles: ' || r.policyname || '; ';
  END LOOP;

  -- La policy canonica de UPDATE tiene que llevar `WITH CHECK`: es la
  -- garantia a nivel de RLS de que la fila actualizada sigue siendo la
  -- propia. Sin el, `id` (que tiene privilegio de UPDATE por el upsert)
  -- solo estaria protegido por el trigger.
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND policyname = 'profiles_update_own'
      AND cmd = 'UPDATE'
      AND with_check IS NOT NULL
  ) THEN
    v_problems := v_problems
      || 'la policy profiles_update_own no tiene WITH CHECK: la identidad quedaria solo en manos del trigger; ';
  END IF;

  -- ---- Un solo administrador activo por usuario -------------------------
  IF (
    SELECT count(*)
    FROM public.admin_users a
    WHERE a.user_id = v_admin AND a.active
  ) > 1 THEN
    v_problems := v_problems || 'hay mas de un administrador activo para ' || v_admin || '; ';
  END IF;

  -- ---- Ningun trigger ajeno puede tocar el rol --------------------------
  -- Si quedara un trigger BEFORE UPDATE sobre `profiles` cuya funcion se
  -- llame 'protect%' y no sea la nuestra, podria revertir el rol en
  -- silencio, igual que hacia la version anterior. Se aborta.
  FOR r IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = 'public.profiles'::regclass
      AND NOT t.tgisinternal
      AND (t.tgtype & 2) = 2          -- BEFORE
      AND (t.tgtype & 16) = 16        -- UPDATE
      AND p.proname LIKE 'protect%'
      AND p.proname <> 'protect_profile_fields'
  LOOP
    v_problems := v_problems || 'trigger sospechoso sobre profiles: ' || r.tgname || '; ';
  END LOOP;

  IF v_problems <> '' THEN
    RAISE EXCEPTION
      'La migracion dejo el esquema en un estado inseguro: %', v_problems;
  END IF;

  RAISE NOTICE
    'Aserciones de seguridad OK: RLS activo, privilegios por columna cerrados, policies completas.';
END;
$do$;

-- =====================================================================
-- BLOQUE 12 · Chequeo de coherencia (NO modifica datos)
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
-- BLOQUE 13 · Otras personas con permisos (NO EJECUTAR TODAVIA)
-- =====================================================================
-- Para sumar un moderador o una segunda administradora, desde el SQL Editor:
--
--    INSERT INTO public.admin_users
--      (user_id, role, active, created_at, created_by, updated_at)
--    SELECT '<UUID>', 'moderator', true, now(), '8f3eb06b-510a-439c-bba5-c7ba84e04254', now()
--    WHERE EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = '<UUID>')
--    ON CONFLICT DO NOTHING;
--
-- Para quitar un permiso SIN borrar el historial:
--
--    UPDATE public.admin_users SET active = false, updated_at = now()
--    WHERE user_id = '<UUID>' AND active;
--
-- Para cambiar el rol de aplicacion de una cuenta desde el SQL Editor, el
-- trigger exige la variable de autorizacion:
--
--    SET app.admin_authorized_role_change = 'on';
--    UPDATE public.profiles SET role = 'creator' WHERE id = '<UUID>';
--
-- =====================================================================
-- BLOQUE 14 · Verificacion (solo lectura, despues del COMMIT)
-- =====================================================================

-- 14.1 Triggers sobre profiles: revisar que solo queden los de proteccion y
--     los de updated_at.
SELECT tgname, tgrelid::regclass AS tabla, pg_get_triggerdef(oid) AS definicion
FROM pg_trigger
WHERE tgrelid = 'public.profiles'::regclass
  AND NOT tgisinternal
ORDER BY tgname;

-- 14.2 La funcion de proteccion
SELECT p.proname, pg_get_functiondef(p.oid) AS cuerpo
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('protect_profile', 'protect_profile_fields');

-- 14.3 Policies de profiles y creator_requests (SELECT NO se toco: la Home
--     necesita leer los perfiles publicos de las creadoras)
SELECT schemaname, tablename, policyname, permissive, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('profiles', 'creator_requests', 'admin_users')
ORDER BY tablename, policyname;

-- 14.4 Privilegios de columna sobre profiles
SELECT table_name, column_name, grantee, privilege_type
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY column_name, grantee, privilege_type;

-- 14.5 Privilegios de tabla sobre profiles
SELECT table_name, grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY grantee, privilege_type;

-- 14.6 Aserciones de seguridad (las que deben salir en false)
--
-- OJO: `id` NO esta en esta lista. El upsert del perfil necesita privilegio
-- de UPDATE sobre `id` (PostgREST genera `ON CONFLICT (id) DO UPDATE SET id =
-- EXCLUDED.id, ...`). Que la identidad no se pueda cambiar de verdad lo
-- garantizan el trigger `protect_profile_fields()` y el `WITH CHECK
-- (auth.uid() = id)` de la policy `profiles_update_own`. Ese permiso se
-- comprueba en la 14.6-bis (`edita_id`).
SELECT
  has_table_privilege('authenticated', 'public.profiles', 'UPDATE')         AS auth_update_tabla,
  has_table_privilege('authenticated', 'public.profiles', 'INSERT')         AS auth_insert_tabla,
  has_table_privilege('authenticated', 'public.profiles', 'DELETE')         AS auth_delete_tabla,
  has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE') AS auth_role_update,
  has_column_privilege('authenticated', 'public.profiles', 'role', 'INSERT') AS auth_role_insert,
  has_column_privilege('authenticated', 'public.profiles', 'is_banned', 'UPDATE') AS auth_banned_update,
  has_column_privilege('authenticated', 'public.profiles', 'is_verified', 'UPDATE') AS auth_verified_update,
  has_column_privilege('authenticated', 'public.profiles', 'subscription_price', 'INSERT') AS auth_price_insert,
  has_column_privilege('authenticated', 'public.profiles', 'is_banned', 'INSERT')  AS auth_banned_insert,
  has_column_privilege('authenticated', 'public.profiles', 'is_verified', 'INSERT') AS auth_verified_insert,
  has_column_privilege('authenticated', 'public.profiles', 'created_at', 'UPDATE') AS auth_created_update,
  has_column_privilege('authenticated', 'public.profiles', 'updated_at', 'UPDATE') AS auth_updated_update,
  has_column_privilege('authenticated', 'public.profiles', 'created_at', 'INSERT') AS auth_created_insert,
  has_column_privilege('authenticated', 'public.profiles', 'updated_at', 'INSERT') AS auth_updated_insert,
  has_table_privilege('anon', 'public.profiles', 'UPDATE')                  AS anon_update,
  has_table_privilege('anon', 'public.profiles', 'INSERT')                  AS anon_insert,
  has_table_privilege('anon', 'public.profiles', 'DELETE')                  AS anon_delete;

-- 14.6-bis Privilegios que la app necesita (deben salir en true).
-- Es la lista cerrada del BLOQUE 8:
--   INSERT: id, display_name, bio
--   UPDATE: id, display_name, username, bio, subscription_price, avatar_key
-- `alta_bio` es el permiso que necesita el upsert del perfil, y `edita_id` el
-- que necesita su `ON CONFLICT (id) DO UPDATE SET id = EXCLUDED.id, ...`.
SELECT
  has_column_privilege('authenticated', 'public.profiles', 'id', 'INSERT')            AS alta_id,
  has_column_privilege('authenticated', 'public.profiles', 'display_name', 'INSERT')  AS alta_nombre,
  has_column_privilege('authenticated', 'public.profiles', 'bio', 'INSERT')           AS alta_bio,
  has_column_privilege('authenticated', 'public.profiles', 'id', 'UPDATE')            AS edita_id,
  has_column_privilege('authenticated', 'public.profiles', 'display_name', 'UPDATE')  AS edita_nombre,
  has_column_privilege('authenticated', 'public.profiles', 'username', 'UPDATE')      AS edita_usuario,
  has_column_privilege('authenticated', 'public.profiles', 'bio', 'UPDATE')           AS edita_bio,
  has_column_privilege('authenticated', 'public.profiles', 'subscription_price', 'UPDATE') AS edita_precio,
  has_column_privilege('authenticated', 'public.profiles', 'avatar_key', 'UPDATE')    AS edita_avatar;

-- 14.6-quater Comprobacion puntual, en un solo sitio:
--   · `bio_insert` debe salir en TRUE (lo necesita el upsert del perfil).
--   · Las seis columnas protegidas en INSERT deben salir en FALSE.
--   · `created_at` y `updated_at` en UPDATE deben salir en FALSE.
SELECT
  has_column_privilege('authenticated', 'public.profiles', 'bio', 'INSERT')             AS bio_insert,
  has_column_privilege('authenticated', 'public.profiles', 'role', 'INSERT')            AS role_insert,
  has_column_privilege('authenticated', 'public.profiles', 'is_banned', 'INSERT')        AS banned_insert,
  has_column_privilege('authenticated', 'public.profiles', 'is_verified', 'INSERT')      AS verified_insert,
  has_column_privilege('authenticated', 'public.profiles', 'subscription_price', 'INSERT') AS price_insert,
  has_column_privilege('authenticated', 'public.profiles', 'created_at', 'INSERT')       AS created_insert,
  has_column_privilege('authenticated', 'public.profiles', 'updated_at', 'INSERT')       AS updated_insert,
  has_column_privilege('authenticated', 'public.profiles', 'created_at', 'UPDATE')       AS created_update,
  has_column_privilege('authenticated', 'public.profiles', 'updated_at', 'UPDATE')       AS updated_update;

-- 14.6-quinquies La IDENTIDAD de la fila: `id` tiene UPDATE a proposito (lo
-- necesita el upsert), pero no se puede cambiar. Se comprueba que esten las
-- dos defensas que no dependen del privilegio.
SELECT
  EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.profiles'::regclass
      AND NOT t.tgisinternal
      AND t.tgname = 'trg_protect_profile_fields'
      AND (t.tgtype & 2) = 2
      AND (t.tgtype & 16) = 16
  ) AS trigger_protege_id,
  EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'protect_profile_fields'
      AND pg_get_functiondef(p.oid) LIKE '%NEW.id%'
  ) AS trigger_comprueba_id,
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'profiles'
      AND policyname = 'profiles_update_own'
      AND with_check IS NOT NULL
  ) AS policy_tiene_with_check;

-- 14.6-ter Columnas que `authenticated` puede escribir. Solo deben aparecer
-- las de la lista cerrada del BLOQUE 8; cualquier otra es un residuo.
SELECT grantee, column_name, privilege_type
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND grantee IN ('authenticated', 'PUBLIC')
  AND privilege_type IN ('INSERT', 'UPDATE')
ORDER BY grantee, privilege_type, column_name;

-- 14.7 EXECUTE de las funciones administrativas
SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE specific_schema = 'public'
  AND routine_name IN (
    'is_admin', 'is_moderator', 'my_admin_role', 'can_request_creator',
    'admin_list_profiles', 'admin_set_creator_role', 'admin_set_banned',
    'admin_list_creator_requests', 'admin_list_user_media',
    'moderator_list_user_media', 'public_media_count',
    'approve_creator_request', 'reject_creator_request'
  )
ORDER BY routine_name, grantee;

-- 14.8 Seguridad de las funciones
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
    'moderator_list_user_media', 'public_media_count',
    'approve_creator_request', 'reject_creator_request',
    'protect_profile', 'protect_profile_fields'
  )
ORDER BY p.proname;

-- 14.9 RLS habilitado
SELECT c.relname AS tabla,
       c.relrowsecurity AS rls_habilitado,
       c.relforcerowsecurity AS rls_forzado
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('profiles', 'admin_users', 'creator_requests')
ORDER BY 1;

-- 14.10 Administradores activos (debe haber UNA fila para el UUID conocido)
SELECT au.user_id, au.role, au.active, u.email
FROM public.admin_users au
JOIN auth.users u ON u.id = au.user_id
WHERE au.active;

-- 14.11 Roles de perfil fuera de 'fan'/'creator' (deberia salir vacio)
SELECT id, display_name, username, role
FROM public.profiles
WHERE COALESCE(role, 'fan') NOT IN ('fan', 'creator');
