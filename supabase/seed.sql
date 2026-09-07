-- ============================================================================
--  Agua En La Boca · Datos de Prueba (Seed)
--  Ejecutar DESPUÉS del schema.sql para poblar la BD con datos de desarrollo
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) USUARIOS DE PRUEBA EN AUTH (requiere service_role o dashboard)
-- ----------------------------------------------------------------------------
-- NOTA: Estos inserts en auth.users solo funcionan con service_role key
-- En Supabase Dashboard: Authentication → Users → "Create new user" manualmente
-- O usar: supabase.auth.admin.createUser() desde server

-- Usuarios de prueba (ejecutar en SQL Editor con service_role):
-- insert into auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
-- values
--   ('11111111-1111-1111-1111-111111111111', 'admin@test.com', crypt('admin123', gen_salt('bf')), now(), '{"username": "admin", "nombre": "Admin"}'::jsonb),
--   ('22222222-2222-2222-2222-222222222222', 'creadora1@test.com', crypt('creadora123', gen_salt('bf')), now(), '{"username": "luna_bella", "nombre": "Luna Bella"}'::jsonb),
--   ('33333333-3333-3333-3333-333333333333', 'creadora2@test.com', crypt('creadora123', gen_salt('bf')), now(), '{"username": "mia_rose", "nombre": "Mia Rose"}'::jsonb),
--   ('44444444-4444-4444-4444-444444444444', 'fan1@test.com', crypt('fan123', gen_salt('bf')), now(), '{"username": "fan_carlos", "nombre": "Carlos Fan"}'::jsonb),
--   ('55555555-5555-5555-5555-555555555555', 'fan2@test.com', crypt('fan123', gen_salt('bf')), now(), '{"username": "fan_ana", "nombre": "Ana Fan"}'::jsonb);

-- ----------------------------------------------------------------------------
-- 2) PERFILES (se crean automáticamente via trigger handle_new_user)
--    Pero podemos actualizar campos extra aquí:
-- ----------------------------------------------------------------------------
update public.profiles set
  bio = 'Administradora de la plataforma 💕',
  pais = 'Paraguay',
  ciudad = 'Asunción',
  is_creator = false,
  avatar_url = 'https://api.dicebear.com/7.x/avataaars/svg?seed=admin'
where id = '11111111-1111-1111-1111-111111111111';

update public.profiles set
  bio = 'Creadora de contenido exclusivo 🌙✨\nSuscríbete para ver todo mi contenido sin censura',
  pais = 'Paraguay',
  ciudad = 'Asunción',
  is_creator = true,
  twitter_url = 'https://twitter.com/luna_bella',
  instagram_url = 'https://instagram.com/luna_bella',
  avatar_url = 'https://api.dicebear.com/7.x/avataaars/svg?seed=luna',
  website_url = 'https://luna.example.com'
where id = '22222222-2222-2222-2222-222222222222';

update public.profiles set
  bio = 'Tu chica favorita 💋\nContenido nuevo cada semana',
  pais = 'Argentina',
  ciudad = 'Buenos Aires',
  is_creator = true,
  twitter_url = 'https://twitter.com/mia_rose',
  instagram_url = 'https://instagram.com/mia_rose',
  avatar_url = 'https://api.dicebear.com/7.x/avataaars/svg?seed=mia'
where id = '33333333-3333-3333-3333-333333333333';

update public.profiles set
  bio = 'Fan de las mejores creadoras 😍',
  pais = 'Paraguay',
  ciudad = 'Ciudad del Este',
  avatar_url = 'https://api.dicebear.com/7.x/avataaars/svg?seed=carlos'
where id = '44444444-4444-4444-4444-444444444444';

update public.profiles set
  bio = 'Me encanta apoyar a las chicas 💖',
  pais = 'Brasil',
  ciudad = 'São Paulo',
  avatar_url = 'https://api.dicebear.com/7.x/avataaars/svg?seed=ana'
where id = '55555555-5555-5555-5555-555555555555';

-- ----------------------------------------------------------------------------
-- 3) BANNERS DE PRUEBA (usando placeholder images)
-- ----------------------------------------------------------------------------
insert into public.media (id, user_id, tipo, bucket, storage_key, public_url, orden, es_privado) values
  -- Luna Bella banners
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'banner', 'public', '22222222-2222-2222-2222-222222222222/banner1.jpg', 'https://picsum.photos/seed/luna-banner1/1200/800', 0, false),
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'banner', 'public', '22222222-2222-2222-2222-222222222222/banner2.jpg', 'https://picsum.photos/seed/luna-banner2/1200/800', 1, false),
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'banner', 'public', '22222222-2222-2222-2222-222222222222/banner3.jpg', 'https://picsum.photos/seed/luna-banner3/1200/800', 2, false),
  
  -- Mia Rose banners
  (gen_random_uuid(), '33333333-3333-3333-3333-333333333333', 'banner', 'public', '33333333-3333-3333-3333-333333333333/banner1.jpg', 'https://picsum.photos/seed/mia-banner1/1200/800', 0, false),
  (gen_random_uuid(), '33333333-3333-3333-3333-333333333333', 'banner', 'public', '33333333-3333-3333-3333-333333333333/banner2.jpg', 'https://picsum.photos/seed/mia-banner2/1200/800', 1, false);

-- ----------------------------------------------------------------------------
-- 4) CONTENIDO MEDIA (fotos y videos mixtos público/privado)
-- ----------------------------------------------------------------------------
-- Helper: UUIDs fijos para referenciar en suscripciones/comentarios
do $$
declare
  luna_photo1 uuid := gen_random_uuid();
  luna_photo2 uuid := gen_random_uuid();
  luna_video1 uuid := gen_random_uuid();
  luna_private1 uuid := gen_random_uuid();
  luna_private2 uuid := gen_random_uuid();
  mia_photo1 uuid := gen_random_uuid();
  mia_photo2 uuid := gen_random_uuid();
  mia_video1 uuid := gen_random_uuid();
  mia_private1 uuid := gen_random_uuid();
begin
  -- Luna Bella - Contenido público
  insert into public.media (id, user_id, tipo, bucket, storage_key, public_url, titulo, descripcion, orden, es_privado) values
    (luna_photo1, '22222222-2222-2222-2222-222222222222', 'photo', 'public', '22222222-2222-2222-2222-222222222222/photo1.jpg', 'https://picsum.photos/seed/luna-photo1/800/1000', 'Selfie matutina ☀️', 'Empezando el día con buena energía', 0, false),
    (luna_photo2, '22222222-2222-2222-2222-222222222222', 'photo', 'public', '22222222-2222-2222-2222-222222222222/photo2.jpg', 'https://picsum.photos/seed/luna-photo2/800/1000', 'En la playa 🏖️', 'Día perfecto de sol', 1, false),
    (luna_video1, '22222222-2222-2222-2222-222222222222', 'video', 'public', '22222222-2222-2222-2222-222222222222/video1.mp4', 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4', 'Video baile 💃', 'Practicando coreo nueva', 2, false),
    
    -- Luna Bella - Contenido PRIVADO (paywall)
    (luna_private1, '22222222-2222-2222-2222-222222222222', 'photo', 'private', '22222222-2222-2222-2222-222222222222/private1.jpg', null, 'Contenido exclusivo 🔥', 'Solo para suscriptores VIP', 3, true),
    (luna_private2, '22222222-2222-2222-2222-222222222222', 'video', 'private', '22222222-2222-2222-2222-222222222222/private2.mp4', null, 'Video completo 🎬', 'Versión extendida sin censura', 4, true),
    
    -- Mia Rose - Contenido público
    (mia_photo1, '33333333-3333-3333-3333-333333333333', 'photo', 'public', '33333333-3333-3333-3333-333333333333/photo1.jpg', 'https://picsum.photos/seed/mia-photo1/800/1000', 'Outfit del día 👗', 'Nuevo vestido favorito', 0, false),
    (mia_photo2, '33333333-3333-3333-3333-333333333333', 'photo', 'public', '33333333-3333-3333-3333-333333333333/photo2.jpg', 'https://picsum.photos/seed/mia-photo2/800/1000', 'Mirror selfie 📸', '', 1, false),
    (mia_video1, '33333333-3333-3333-3333-333333333333', 'video', 'public', '33333333-3333-3333-3333-333333333333/video1.mp4', 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4', 'GRWM ✨', 'Get ready with me', 2, false),
    
    -- Mia Rose - Contenido PRIVADO
    (mia_private1, '33333333-3333-3333-3333-333333333333', 'photo', 'private', '33333333-3333-3333-3333-333333333333/private1.jpg', null, 'Set exclusivo 🌹', 'Fotos artísticas solo fans', 3, true);
    
  -- Thumbnails para videos (públicos)
  update public.media set 
    thumbnail_key = storage_key || '_thumb.jpg',
    thumbnail_url = public_url || '_thumb.jpg'
  where tipo = 'video' and bucket = 'public';
end $$;

-- ----------------------------------------------------------------------------
-- 5) SUSCRIPCIONES DE PRUEBA
-- ----------------------------------------------------------------------------
-- Carlos (fan1) suscrito a Luna Bella
insert into public.suscripciones (creator_id, subscriber_id, plan, precio, status) values
  ('22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444444', 'mensual', 9.99, 'activa');

-- Ana (fan2) suscrita a ambas creadoras
insert into public.suscripciones (creator_id, subscriber_id, plan, precio, status) values
  ('22222222-2222-2222-2222-222222222222', '55555555-5555-5555-5555-555555555555', 'mensual', 9.99, 'activa'),
  ('33333333-3333-3333-3333-333333333333', '55555555-5555-5555-5555-555555555555', 'mensual', 14.99, 'activa');

-- ----------------------------------------------------------------------------
-- 6) PAGOS DE PRUEBA
-- ----------------------------------------------------------------------------
insert into public.pagos (user_id, concepto, monto, metodo, status, reference, metadata) values
  ('44444444-4444-4444-4444-444444444444', 'suscripcion', 9.99, 'stripe', 'completado', 'pi_test_luna_carlos_001', '{"creator_id": "22222222-2222-2222-2222-222222222222", "plan": "mensual"}'::jsonb),
  ('55555555-5555-5555-5555-555555555555', 'suscripcion', 9.99, 'stripe', 'completado', 'pi_test_luna_ana_001', '{"creator_id": "22222222-2222-2222-2222-222222222222", "plan": "mensual"}'::jsonb),
  ('55555555-5555-5555-5555-555555555555', 'suscripcion', 14.99, 'mercadopago', 'completado', 'mp_test_mia_ana_001', '{"creator_id": "33333333-3333-3333-3333-333333333333", "plan": "premium"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'tips', 25.00, 'stripe', 'completado', 'pi_test_tip_carlos_001', '{"from_user": "44444444-4444-4444-4444-444444444444"}'::jsonb);

-- ----------------------------------------------------------------------------
-- 7) COMENTARIOS DE PRUEBA
-- ----------------------------------------------------------------------------
insert into public.comments (media_id, user_id, content) 
select m.id, '44444444-4444-4444-4444-444444444444', '¡Te ves hermosa! 😍'
from public.media m where m.user_id = '22222222-2222-2222-2222-222222222222' and m.tipo = 'photo' and m.es_privado = false limit 1;

insert into public.comments (media_id, user_id, content) 
select m.id, '55555555-5555-5555-5555-555555555555', 'Me encanta tu contenido 💕'
from public.media m where m.user_id = '22222222-2222-2222-2222-222222222222' and m.tipo = 'photo' and m.es_privado = false limit 1;

insert into public.comments (media_id, user_id, content) 
select m.id, '44444444-4444-4444-4444-444444444444', 'Esa coreo está increíble 🔥'
from public.media m where m.user_id = '22222222-2222-2222-2222-222222222222' and m.tipo = 'video' and m.es_privado = false limit 1;

insert into public.comments (media_id, user_id, content) 
select m.id, '55555555-5555-5555-5555-555555555555', 'Qué lindo outfit ✨'
from public.media m where m.user_id = '33333333-3333-3333-3333-333333333333' and m.tipo = 'photo' and m.es_privado = false limit 1;

-- ----------------------------------------------------------------------------
-- 8) VERIFICACIONES
-- ----------------------------------------------------------------------------
-- Verificar que todo se insertó correctamente:
-- select 'profiles' as tabla, count(*) from public.profiles
-- union all select 'media', count(*) from public.media
-- union all select 'suscripciones', count(*) from public.suscripciones
-- union all select 'pagos', count(*) from public.pagos
-- union all select 'comments', count(*) from public.comments;

-- Probar función is_subscriber:
-- select public.is_subscriber('22222222-2222-2222-2222-222222222222'); -- debería dar true para fan1 y fan2

-- Probar función can_access_media:
-- select public.can_access_media(id) from public.media where user_id = '22222222-2222-2222-2222-222222222222' and es_privado = true;

-- Probar RPC get_public_feed:
-- select * from public.get_public_feed(10);