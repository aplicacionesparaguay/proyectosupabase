-- ============================================================
-- PARTE 3 · CREADORAS — ubicación pública y catálogo de países
-- Proyecto: "Agua en la Boca"
-- ============================================================
-- OBJETIVO
--   Habilitar el listado público de CREADORAS en el Home con
--   ciudad y país, sin exponer información administrativa.
--
-- ATOMICIDAD
--   Todo corre dentro de una única transacción (BEGIN/COMMIT).
--   Si cualquier sentencia falla, PostgreSQL revierte la
--   migración completa y no queda nada a medias.
--
-- PRERREQUISITO (ya cumplido a mano)
--   public.countries con code sin duplicados.
--   Verificado por lectura: 8 filas, 8 códigos únicos, 0 nulos.
--
-- QUÉ HACE
--   1. countries_code_key      UNIQUE (code)
--   2. profiles.city           TEXT   ADD COLUMN IF NOT EXISTS
--   3. profiles.country_code   TEXT   ADD COLUMN IF NOT EXISTS
--   4. profiles_country_code_fkey -> countries(code) ON UPDATE CASCADE
--
-- QUÉ NO HACE
--   - NO crea índices. La base ya tiene
--       profiles_role_idx ON profiles(role) WHERE role = 'creator'
--     que cubre el filtro del Home. No se duplica ni se reemplaza.
--   - NO modifica RLS ni políticas.
--   - NO modifica auth / triggers.
--   - NO toca subscription_price, is_banned, email ni teléfono.
--   - NO borra ni deduplica filas de countries.
--   - NO usa DROP, ni EXCEPTION, ni RAISE WARNING.
--
-- IDEMPOTENCIA
--   Reejecutable. Las columnas usan ADD COLUMN IF NOT EXISTS; los
--   constraints se crean solo si no existe ya uno equivalente.
--   Un UNIQUE ya presente bajo cualquier nombre se respeta: no se
--   agrega un segundo UNIQUE redundante sobre code.
--
-- HISTORIAL
--   countries llegó a tener 24 filas (3 copias de 8 países) porque
--   el seed de supabase-schema.sql usaba `ON CONFLICT DO NOTHING`
--   sin objetivo sobre una columna sin ninguna restricción UNIQUE,
--   y el archivo se ejecutó 3 veces. Se corrigió a mano conservando
--   la fila más antigua de cada code; las 16 eliminadas eran
--   idénticas en code/name y ninguna tabla referenciaba
--   countries.id. El seed ahora usa ON CONFLICT (code).
-- ============================================================


BEGIN;


-- ============================================================
-- BLOQUE 1 · UNIQUE en countries.code
-- ============================================================
-- Debe correr antes que la FK (bloque 4): una FOREIGN KEY necesita
-- un índice único en la columna referenciada.
--
-- countries_code_key es el nombre que Postgres asigna por defecto
-- a un UNIQUE, para que quede estable y legible.
--
-- Detección por estructura, no por nombre: busca CUALQUIER
-- constraint UNIQUE de una sola columna cuya columna sea
-- exactamente countries.code. Eso ya cubre el caso de que se
-- llame countries_code_key y también el de que exista con otro
-- nombre. Si se encuentra alguno, no se crea nada más.


DO $do$
DECLARE
  v_existente text;
BEGIN
  SELECT k.conname
    INTO v_existente
  FROM pg_constraint k
  JOIN pg_class c     ON c.oid = k.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'countries'
    AND k.contype = 'u'
    AND array_length(k.conkey, 1) = 1
    AND k.conkey[1] = (
      SELECT attnum
        FROM pg_attribute
       WHERE attrelid = c.oid
         AND attname = 'code'
         AND NOT attisdropped
    )
  LIMIT 1;

  IF v_existente IS NOT NULL THEN
    RAISE NOTICE
      'countries.code ya tiene el UNIQUE "%": no se crea otro', v_existente;
    RETURN;
  END IF;

  -- Sin UNIQUE previo. Si quedaran duplicados, esta sentencia
  -- falla con 23502 y toda la transacción se revierte: es el
  -- comportamiento correcto, porque el dato debe estar limpio
  -- antes de declarar la restricción.
  ALTER TABLE public.countries
    ADD CONSTRAINT countries_code_key UNIQUE (code);

  RAISE NOTICE 'countries_code_key creado sobre countries(code)';
END
$do$;


-- ============================================================
-- BLOQUE 2 · profiles.city
-- ============================================================
-- Ciudad de la creadora. Texto libre: las ciudades no están
-- catalogadas en ninguna tabla del proyecto.
--   NULL = la creadora no indicó ciudad


ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS city TEXT;


-- ============================================================
-- BLOQUE 3 · profiles.country_code
-- ============================================================
-- Código de país (PY, AR, BR...). El nombre NO se duplica aquí:
-- vive en countries.name y se resuelve por código. Ver
-- src/routes/+page.server.js, que arma un mapa code -> name.


ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS country_code TEXT;


-- ============================================================
-- BLOQUE 4 · FK profiles.country_code -> countries(code)
-- ============================================================
-- Detección por estructura, igual que en el bloque 1: cualquier
-- FOREIGN KEY sobre profiles.country_code, sin importar su nombre.
-- Si existe, no se crea otra.
--
-- ON UPDATE CASCADE: si algún día se corrige un código ISO, el
-- perfil sigue apuntando al país correcto.
--
-- Nullable en ambos lados: countries.code admite NULL y
-- profiles.country_code también, así que una creadora sin país
-- queda en NULL sin violar la FK.


DO $do$
DECLARE
  v_existente text;
BEGIN
  SELECT k.conname
    INTO v_existente
  FROM pg_constraint k
  JOIN pg_class c     ON c.oid = k.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = 'profiles'
    AND k.contype = 'f'
    AND array_length(k.conkey, 1) = 1
    AND k.conkey[1] = (
      SELECT attnum
        FROM pg_attribute
       WHERE attrelid = c.oid
         AND attname = 'country_code'
         AND NOT attisdropped
    )
  LIMIT 1;

  IF v_existente IS NOT NULL THEN
    RAISE NOTICE
      'profiles.country_code ya tiene la FK "%": no se crea otra', v_existente;
    RETURN;
  END IF;

  ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_country_code_fkey
    FOREIGN KEY (country_code)
    REFERENCES public.countries (code)
    ON UPDATE CASCADE;

  RAISE NOTICE 'profiles_country_code_fkey creado sobre countries(code)';
END
$do$;


COMMIT;


-- ============================================================
-- BLOQUE 5 · Verificación (solo lectura, no modifica nada)
-- ============================================================
-- Corre esto DESPUÉS del COMMIT, por separado.
--
-- Esperado: city = t, country_code = t
--
--   SELECT column_name, data_type, is_nullable
--     FROM information_schema.columns
--    WHERE table_schema = 'public' AND table_name = 'profiles'
--      AND column_name IN ('city', 'country_code')
--    ORDER BY column_name;
--
-- Esperado: countries_code_key y profiles_country_code_fkey con
--            convalidated = t
--
--   SELECT conname, contype, convalidated, pg_get_constraintdef(oid)
--     FROM pg_constraint
--    WHERE conrelid IN ('public.countries'::regclass,
--                       'public.profiles'::regclass)
--      AND contype IN ('u', 'f');
--
-- Esperado: profiles_role_idx sigue siendo el ÚNICO índice parcial
--            de creadoras, intacto
--
--   SELECT indexname, indexdef FROM pg_indexes
--    WHERE schemaname = 'public' AND tablename = 'profiles';
--
-- --------------------------------------------------------
-- NOTAS DE OPERACIÓN
-- --------------------------------------------------------
-- 1) BEGIN/COMMIT explícito. El editor SQL de Supabase ejecuta
--    cada lote por separado, así que la transacción es necesaria
--    para que un fallo a mitad de camino no deje columnas sin FK.
--    Nota: si esta migración se aplicara con una herramienta que
--    ya envuelve todo en su propia transacción, habría que quitar
--    el BEGIN/COMMIT para no anidar.
--
-- 2) ALTER TABLE pide ACCESS EXCLUSIVE sobre countries y profiles.
--    Con la base en producción, la transacción puede esperar locks
--    si hay tráfico concurrente sobre esas tablas.
--
-- 3) PostgREST cachea el esquema. Si más adelante se decide usar
--    el embed countries(name), habría que recargar el schema
--    cache. El Home actual no lo necesita: resuelve el país con
--    su propia consulta a countries.
--
-- 4) SEED DE PRUEBA — documentado, NO ejecutar automáticamente.
--    Requiere una creadora real, que a su vez requiere haber
--    corrido supabase-part2-admin.sql (approve_creator_request).
--
--      UPDATE public.profiles
--         SET city = 'Asunción', country_code = 'PY'
--       WHERE id = '<uuid-de-una-creadora-real>';