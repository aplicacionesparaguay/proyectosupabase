-- ============================================================
-- ESQUEMA COMPLETO PARA "AGUA EN LA BOCA" - SUPABASE
-- Ejecutar en: Supabase Dashboard > SQL Editor
-- ============================================================

-- 1. Tabla profiles (perfil principal de usuario)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE,
  nombre TEXT,
  email TEXT,
  bio TEXT,
  avatar_url TEXT,
  fecha_nacimiento DATE,
  ciudad TEXT,
  pais TEXT,
  whatsapp TEXT,
  twitter_url TEXT,
  instagram_url TEXT,
  website_url TEXT,
  direccion TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Tabla users (extensión de auth para profile_pic - usado por UploadPhoto.svelte)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  profile_pic TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Tabla photos (galería simple - UserGallery.svelte)
CREATE TABLE IF NOT EXISTS photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL,
  description TEXT,
  filename TEXT NOT NULL,
  file_key TEXT,
  mime_type TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Tabla comments (comentarios en galería simple)
CREATE TABLE IF NOT EXISTS comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  photo_id UUID NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Tabla user_banners (banners rotativos de perfil)
CREATE TABLE IF NOT EXISTS user_banners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  storage_path TEXT,
  public_url TEXT,
  orden INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Tabla user_photos (álbum completo con fotos y videos + censura facial)
CREATE TABLE IF NOT EXISTS user_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  storage_path TEXT,
  public_url TEXT NOT NULL,
  filename TEXT NOT NULL,
  orden INT DEFAULT 0,
  titulo TEXT,
  descripcion TEXT,
  thumbnail_url TEXT,
  mime_type TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Tabla photo_comments (comentarios en álbum de perfil)
CREATE TABLE IF NOT EXISTS photo_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  photo_id UUID NOT NULL REFERENCES user_photos(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  comentario TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Tabla countries (selector de países)
CREATE TABLE IF NOT EXISTS countries (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  code TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insertar países de ejemplo
INSERT INTO countries (name, code) VALUES 
  ('Paraguay', 'PY'),
  ('Argentina', 'AR'),
  ('Brasil', 'BR'),
  ('Uruguay', 'UY'),
  ('Chile', 'CL'),
  ('Bolivia', 'BO'),
  ('Estados Unidos', 'US'),
  ('España', 'ES')
ON CONFLICT DO NOTHING;

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

-- Habilitar RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_banners ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE photo_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE countries ENABLE ROW LEVEL SECURITY;

-- PROFILES
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;
CREATE POLICY "Users can insert own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- USERS
DROP POLICY IF EXISTS "Users can view own user" ON users;
CREATE POLICY "Users can view own user" ON users
  FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own user" ON users;
CREATE POLICY "Users can update own user" ON users
  FOR UPDATE USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert own user" ON users;
CREATE POLICY "Users can insert own user" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);

-- PHOTOS (galería simple)
DROP POLICY IF EXISTS "Users can manage own photos" ON photos;
CREATE POLICY "Users can manage own photos" ON photos
  FOR ALL USING (auth.uid() = user_id);

-- COMMENTS (galería simple)
DROP POLICY IF EXISTS "Users can manage own comments" ON comments;
CREATE POLICY "Users can manage own comments" ON comments
  FOR ALL USING (auth.uid() = user_id);

-- USER_BANNERS
DROP POLICY IF EXISTS "Users can manage own banners" ON user_banners;
CREATE POLICY "Users can manage own banners" ON user_banners
  FOR ALL USING (auth.uid() = user_id);

-- USER_PHOTOS (álbum completo)
DROP POLICY IF EXISTS "Users can manage own album photos" ON user_photos;
CREATE POLICY "Users can manage own album photos" ON user_photos
  FOR ALL USING (auth.uid() = user_id);

-- PHOTO_COMMENTS
DROP POLICY IF EXISTS "Users can manage own photo comments" ON photo_comments;
CREATE POLICY "Users can manage own photo comments" ON photo_comments
  FOR ALL USING (auth.uid() = user_id);

-- COUNTRIES (lectura pública)
DROP POLICY IF EXISTS "Public read countries" ON countries;
CREATE POLICY "Public read countries" ON countries
  FOR SELECT USING (true);

-- ============================================================
-- STORAGE BUCKETS (ejecutar si usas Supabase Storage como fallback)
-- ============================================================

-- Nota: Estos buckets se crean mejor desde el Dashboard de Supabase > Storage
-- O con permisos de admin via SQL:
-- INSERT INTO storage.buckets (id, name, public) VALUES
--   ('profiles', 'profiles', true),
--   ('photos', 'photos', true),
--   ('banners', 'banners', true),
--   ('user-photos', 'user-photos', true)
-- ON CONFLICT DO NOTHING;

-- Políticas de storage (ejecutar después de crear buckets):
-- CREATE POLICY "Users can upload own profile" ON storage.objects
--   FOR INSERT WITH CHECK (bucket_id = 'profiles' AND auth.uid()::text = (storage.foldername(name))[1]);
-- CREATE POLICY "Users can upload own photos" ON storage.objects
--   FOR INSERT WITH CHECK (bucket_id = 'photos' AND auth.uid()::text = (storage.foldername(name))[1]);
-- CREATE POLICY "Users can upload own banners" ON storage.objects
--   FOR INSERT WITH CHECK (bucket_id = 'banners' AND auth.uid()::text = (storage.foldername(name))[1]);
-- CREATE POLICY "Users can upload own album photos" ON storage.objects
--   FOR INSERT WITH CHECK (bucket_id = 'user-photos' AND auth.uid()::text = (storage.foldername(name))[1]);
-- CREATE POLICY "Public read profiles" ON storage.objects FOR SELECT USING (bucket_id = 'profiles');
-- CREATE POLICY "Public read photos" ON storage.objects FOR SELECT USING (bucket_id = 'photos');
-- CREATE POLICY "Public read banners" ON storage.objects FOR SELECT USING (bucket_id = 'banners');
-- CREATE POLICY "Public read user-photos" ON storage.objects FOR SELECT USING (bucket_id = 'user-photos');

-- ============================================================
-- FUNCIONES ÚTILES
-- ============================================================

-- Función para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers para updated_at
DROP TRIGGER IF EXISTS update_profiles_updated_at ON profiles;
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();