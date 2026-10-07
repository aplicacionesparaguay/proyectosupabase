-- ============================================================
-- PARTE 1 · REGISTRO Y AUTENTICACIÓN
-- Ejecutar en: Supabase Dashboard > SQL Editor
-- Es IDEMPOTENTE: se puede ejecutar varias veces sin romper nada.
--
-- Qué hace:
--   1. Garantiza que profiles.role exista con DEFAULT 'fan'
--   2. Crea el trigger handle_new_user sobre auth.users
--   3. Inserta el profile faltante de los usuarios ya existentes
--   4. Asegura la política RLS de INSERT para el propio usuario
--
-- NO usa service_role desde el frontend: todo pasa por auth.uid().
-- NO duplica el email en profiles (el email vive en auth.users).
-- ============================================================

-- ------------------------------------------------------------
-- 0) Índice único en profiles.id (necesario para ON CONFLICT)
-- ------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS profiles_id_unique ON public.profiles (id);

-- ------------------------------------------------------------
-- 1) role: toda usuario nueva nace como 'fan'
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'role'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN role TEXT NOT NULL DEFAULT 'fan';
  END IF;
END $$;

UPDATE public.profiles SET role = 'fan' WHERE role IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_attrdef d
    JOIN pg_class c ON c.oid = d.adrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = d.adnum
    WHERE n.nspname = 'public' AND c.relname = 'profiles' AND a.attname = 'role'
  ) THEN
    ALTER TABLE public.profiles ALTER COLUMN role SET DEFAULT 'fan';
  END IF;
END $$;

-- ------------------------------------------------------------
-- 2) display_name: única columna de nombre que usa la app.
--    No se agregan columnas antiguas (nombre, email, avatar_url...).
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'display_name'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN display_name TEXT;
  END IF;
END $$;

-- ------------------------------------------------------------
-- 3) Trigger: crea la fila en profiles al crearse el usuario
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, role, display_name)
  VALUES (
    NEW.id,
    'fan',
    COALESCE(
      NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'display_name'), ''),
      NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'nombre'), ''),
      NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'full_name'), ''),
      NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'name'), ''),
      NULLIF(SPLIT_PART(COALESCE(NEW.email, ''), '@', 1), ''),
      'Usuario'
    )
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- ------------------------------------------------------------
-- 4) Backfill: perfiles de los usuarios que ya existían
-- ------------------------------------------------------------
INSERT INTO public.profiles (id, role, display_name)
SELECT
  u.id,
  'fan',
  COALESCE(
    NULLIF(BTRIM(u.raw_user_meta_data ->> 'display_name'), ''),
    NULLIF(BTRIM(u.raw_user_meta_data ->> 'nombre'), ''),
    NULLIF(SPLIT_PART(COALESCE(u.email, ''), '@', 1), ''),
    'Usuario'
  )
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)
ON CONFLICT (id) DO NOTHING;

-- ------------------------------------------------------------
-- 5) RLS: cada usuario autenticado puede insertar su propio perfil
--    (respaldo del cliente si el trigger no estuviera activo)
-- ------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- ============================================================
-- Verificación (debería devolver 1 fila con role = 'fan')
--   SELECT u.id, u.email, p.role
--   FROM auth.users u
--   LEFT JOIN public.profiles p ON p.id = u.id
--   WHERE p.id IS NULL;
-- ============================================================
