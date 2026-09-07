-- ============================================================================
--  Agua En La Boca · Esquema Corregido y Optimizado (Supabase)
--  Ejecutar en Supabase Dashboard → SQL Editor
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Extensiones
-- ----------------------------------------------------------------------------
create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";

-- ----------------------------------------------------------------------------
-- 1) PROFILES  ·  Una fila por usuario de auth
-- ----------------------------------------------------------------------------
drop table if exists public.profiles cascade;

create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  email             text,
  username          text unique,
  nombre            text,
  bio               text not null default '',
  avatar_key        text,                -- R2 key en bucket público: {userId}/avatar.{ext}
  avatar_url        text,                -- URL pública del avatar (cacheable)
  fecha_nacimiento  date,
  pais              text,
  ciudad            text,
  whatsapp          text,
  twitter_url       text,
  instagram_url     text,
  website_url       text,
  direccion         text,
  is_creator        boolean not null default false,
  is_online         boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.profiles is 'Perfiles públicos de usuarios y creadoras';

create index profiles_username_idx on public.profiles (username);
create index profiles_is_creator_idx on public.profiles (is_creator) where is_creator = true;
create index profiles_is_online_idx on public.profiles (is_online) where is_online = true;

-- ----------------------------------------------------------------------------
-- 2) MEDIA  ·  Todo el contenido subido
-- ----------------------------------------------------------------------------
drop table if exists public.media cascade;

create table public.media (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  tipo          text not null check (tipo in ('avatar', 'banner', 'photo', 'video')),
  bucket        text not null check (bucket in ('public', 'private')),
  storage_key   text not null,          -- R2 key: {userId}/{uuid}.{ext}
  public_url    text,                   -- solo para bucket public
  thumbnail_key text,                   -- para videos / carátulas censuradas
  thumbnail_url text,
  titulo        text,
  descripcion   text,
  orden         int  not null default 0,
  es_privado    boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (user_id, storage_key)
);

create index media_user_id_idx on public.media (user_id);
create index media_tipo_user_idx on public.media (tipo, user_id);
create index media_privado_idx on public.media (es_privado) where es_privado = true;
create index media_created_at_idx on public.media (created_at desc);

-- ----------------------------------------------------------------------------
-- 3) COMMENTS  ·  Comentarios sobre contenido
-- ----------------------------------------------------------------------------
drop table if exists public.comments cascade;

create table public.comments (
  id          uuid primary key default gen_random_uuid(),
  media_id    uuid not null references public.media (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  content     text not null check (char_length(content) between 1 and 1000),
  created_at  timestamptz not null default now()
);

create index comments_media_id_idx on public.comments (media_id);
create index comments_user_id_idx on public.comments (user_id);
create index comments_created_at_idx on public.comments (created_at desc);

-- ----------------------------------------------------------------------------
-- 4) SUSCRIPCIONES  ·  Seguidores de creadoras / acceso al contenido de pago
-- ----------------------------------------------------------------------------
drop table if exists public.suscripciones cascade;

create table public.suscripciones (
  id            uuid primary key default gen_random_uuid(),
  creator_id    uuid not null references public.profiles (id) on delete cascade,
  subscriber_id uuid not null references public.profiles (id) on delete cascade,
  plan          text not null default 'mensual',
  precio        numeric not null default 9.99 check (precio > 0),
  status        text not null default 'activa'
                check (status in ('activa', 'pausada', 'cancelada')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (creator_id, subscriber_id)
);

create index suscripciones_creator_idx on public.suscripciones (creator_id);
create index suscripciones_subscriber_idx on public.suscripciones (subscriber_id);
create index suscripciones_status_idx on public.suscripciones (status) where status = 'activa';

-- ----------------------------------------------------------------------------
-- 5) PAGOS  ·  Registro de pagos (suscripciones, tips, etc.)
-- ----------------------------------------------------------------------------
drop table if exists public.pagos cascade;

create table public.pagos (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  concepto    text not null default 'suscripcion'
              check (concepto in ('suscripcion', 'tips', 'compra_contenido')),
  monto       numeric not null check (monto > 0),
  metodo      text not null default 'stripe',
  status      text not null default 'pendiente'
              check (status in ('pendiente', 'completado', 'rechazado', 'reembolsado')),
  reference   text,               -- ID externo de la pasarela (Stripe payment_intent_id, etc.)
  metadata    jsonb default '{}', -- datos extra: plan, creator_id, etc.
  created_at  timestamptz not null default now()
);

create index pagos_user_id_idx on public.pagos (user_id);
create index pagos_status_idx on public.pagos (status);
create index pagos_reference_idx on public.pagos (reference);
create index pagos_created_at_idx on public.pagos (created_at desc);

-- ============================================================================
-- 6) FUNCIONES AUXILIARES
-- ============================================================================

-- Crea el perfil automáticamente al registrarse un usuario
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, username, nombre)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Mantiene updated_at al día (genérica para cualquier tabla)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists media_updated_at on public.media;
create trigger media_updated_at
  before update on public.media
  for each row execute function public.set_updated_at();

drop trigger if exists suscripciones_updated_at on public.suscripciones;
create trigger suscripciones_updated_at
  before update on public.suscripciones
  for each row execute function public.set_updated_at();

drop trigger if exists pagos_updated_at on public.pagos;
create trigger pagos_updated_at
  before update on public.pagos
  for each row execute function public.set_updated_at();

drop trigger if exists comments_updated_at on public.comments;
create trigger comments_updated_at
  before update on public.comments
  for each row execute function public.set_updated_at();

-- ¿El usuario actual es suscriptor activo de una creadora?
-- CORREGIDO: Parámetro coincide con uso en policy (user_id = creator_id)
create or replace function public.is_subscriber(creator_uuid uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1 from public.suscripciones s
    where s.creator_id     = creator_uuid
      and s.subscriber_id  = auth.uid()
      and s.status         = 'activa'
  );
$$;

-- Función helper: ¿Es owner del media?
create or replace function public.is_media_owner(media_uuid uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1 from public.media m
    where m.id = media_uuid
      and m.user_id = auth.uid()
  );
$$;

-- ============================================================================
-- 7) ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- ---------- PROFILES ----------
alter table public.profiles enable row level security;

-- Público: cualquiera puede ver perfiles (para grid, búsqueda)
create policy "profiles_select_publico"
  on public.profiles for select using (true);

-- Solo owner puede insertar su perfil (handle_new_user lo hace via trigger)
create policy "profiles_insert_propio"
  on public.profiles for insert with check (auth.uid() = id);

-- Owner actualiza su perfil (EXCLUYE campos sensibles)
create policy "profiles_update_propio"
  on public.profiles for update
  using (auth.uid() = id)
  with check (
    auth.uid() = id
    and (new.is_creator = old.is_creator)      -- no puede auto-promocionarse
    and (new.is_online = old.is_online)        -- is_online se maneja por backend
    and (new.created_at = old.created_at)      -- created_at inmutable
  );

create policy "profiles_delete_propio"
  on public.profiles for delete using (auth.uid() = id);

-- ---------- MEDIA ----------
alter table public.media enable row level security;

-- SELECT: Público ve todo no privado. Owner ve todo. Suscriptores activos ven privado de su creadora.
create policy "media_select_por_acceso"
  on public.media for select
  using (
    (es_privado = false)
    or (user_id = auth.uid())
    or public.is_subscriber(user_id)
  );

-- INSERT: Solo owner de la cuenta
create policy "media_insert_propia"
  on public.media for insert with check (auth.uid() = user_id);

-- UPDATE: Solo owner (no puede cambiar user_id, bucket, storage_key)
create policy "media_update_propia"
  on public.media for update
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (new.user_id = old.user_id)
    and (new.bucket = old.bucket)
    and (new.storage_key = old.storage_key)
  );

create policy "media_delete_propia"
  on public.media for delete using (auth.uid() = user_id);

-- ---------- COMMENTS ----------
alter table public.comments enable row level security;

create policy "comments_select_publico"
  on public.comments for select using (true);

create policy "comments_insert_autenticado"
  on public.comments for insert with check (auth.uid() = user_id);

create policy "comments_update_propio"
  on public.comments for update using (auth.uid() = user_id);

create policy "comments_delete_propio"
  on public.comments for delete using (auth.uid() = user_id);

-- ---------- SUSCRIPCIONES ----------
alter table public.suscripciones enable row level security;

-- Creator ve sus suscriptores. Subscriber ve sus suscripciones.
create policy "suscripciones_select_propias"
  on public.suscripciones for select
  using (auth.uid() = creator_id or auth.uid() = subscriber_id);

-- Solo subscriber puede crear su suscripción
create policy "suscripciones_insert_suscriptor"
  on public.suscripciones for insert with check (auth.uid() = subscriber_id);

-- Creator o subscriber pueden actualizar (cancelar, pausar)
create policy "suscripciones_update_parte"
  on public.suscripciones for update
  using (auth.uid() = creator_id or auth.uid() = subscriber_id)
  with check (
    (auth.uid() = creator_id or auth.uid() = subscriber_id)
    and (new.creator_id = old.creator_id)
    and (new.subscriber_id = old.subscriber_id)
  );

create policy "suscripciones_delete_parte"
  on public.suscripciones for delete
  using (auth.uid() = creator_id or auth.uid() = subscriber_id);

-- ---------- PAGOS ----------
alter table public.pagos enable row level security;

-- Owner ve sus pagos
create policy "pagos_select_propio"
  on public.pagos for select using (auth.uid() = user_id);

-- Sistema (service_role) inserta pagos via webhooks
create policy "pagos_insert_service_role"
  on public.pagos for insert with check (auth.role() = 'service_role');

-- Solo service_role puede actualizar status (webhooks de Stripe/MP)
create policy "pagos_update_service_role"
  on public.pagos for update using (auth.role() = 'service_role');

-- ============================================================================
-- 8) FUNCIONES RPC PARA OPERACIONES COMPLEJAS (Server-side)
-- ============================================================================

-- Obtener feed público con banners (optimizado)
create or replace function public.get_public_feed(limit_count int default 50, offset_count int default 0)
returns table (
  id uuid, nombre text, fecha_nacimiento date, pais text, ciudad text,
  is_online boolean, avatar_url text, banner_urls text[]
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    p.id, p.nombre, p.fecha_nacimiento, p.pais, p.ciudad,
    p.is_online, p.avatar_url,
    coalesce(
      array_agg(m.public_url order by m.orden) filter (where m.public_url is not null),
      '{}'
    ) as banner_urls
  from public.profiles p
  left join public.media m
    on m.user_id = p.id
   and m.tipo = 'banner'
   and m.bucket = 'public'
   and m.es_privado = false
  group by p.id
  order by random()  -- aleatorio para "discovery"
  limit limit_count offset offset_count;
$$;

-- Obtener perfil completo con media (respetando RLS)
create or replace function public.get_profile_with_media(target_user_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_build_object(
    'profile', to_jsonb(p),
    'banners', (
      select jsonb_agg(to_jsonb(m) order by m.orden)
      from public.media m
      where m.user_id = p.id
        and m.tipo = 'banner'
    ),
    'media', (
      select jsonb_agg(to_jsonb(m) order by m.orden)
      from public.media m
      where m.user_id = p.id
        and m.tipo != 'banner'
    )
  )
  from public.profiles p
  where p.id = target_user_id;
$$;

-- Verificar acceso a contenido privado (para API presign)
create or replace function public.can_access_media(media_uuid uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1 from public.media m
    where m.id = media_uuid
      and (
        m.es_privado = false
        or m.user_id = auth.uid()
        or public.is_subscriber(m.user_id)
      )
  );
$$;

-- ============================================================================
-- 9) DATOS SEMILLA OPCIONALES (descomentar para testing)
-- ============================================================================

-- insert into auth.users (id, email, encrypted_password, email_confirmed_at)
-- values
--   ('00000000-0000-0000-0000-000000000001', 'creadora@test.com', crypt('123456', gen_salt('bf')), now()),
--   ('00000000-0000-0000-0000-000000000002', 'fan@test.com', crypt('123456', gen_salt('bf')), now());
--
-- insert into public.profiles (id, email, username, nombre, is_creator)
-- values
--   ('00000000-0000-0000-0000-000000000001', 'creadora@test.com', 'creadora', 'Creadora Test', true),
--   ('00000000-0000-0000-0000-000000000002', 'fan@test.com', 'fan', 'Fan Test', false);
--
-- insert into public.suscripciones (creator_id, subscriber_id)
-- values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002');

-- ============================================================================
-- 10) VERIFICACIONES RÁPIDAS POST-DEPLOY
-- ============================================================================
-- select * from public.profiles;
-- select public.is_subscriber('00000000-0000-0000-0000-000000000001');
-- select public.can_access_media('some-media-uuid');
-- select * from public.get_public_feed(10);
-- select * from public.get_profile_with_media('00000000-0000-0000-0000-000000000001');