-- ============================================================================
--  Agua En La Boca · Migraciones Incrementales (v2)
--  Ejecutar DESPUÉS del schema.sql base si ya tienes la BD creada
-- ============================================================================

-- ----------------------------------------------------------------------------
-- MIGRATION: Agregar índices faltantes
-- ----------------------------------------------------------------------------
create index if not exists profiles_username_idx on public.profiles (username);
create index if not exists profiles_is_creator_idx on public.profiles (is_creator) where is_creator = true;
create index if not exists profiles_is_online_idx on public.profiles (is_online) where is_online = true;

create index if not exists media_tipo_user_idx on public.media (tipo, user_id);
create index if not exists media_created_at_idx on public.media (created_at desc);

create index if not exists comments_created_at_idx on public.comments (created_at desc);

create index if not exists suscripciones_status_idx on public.suscripciones (status) where status = 'activa';

create index if not exists pagos_reference_idx on public.pagos (reference);
create index if not exists pagos_created_at_idx on public.pagos (created_at desc);

-- ----------------------------------------------------------------------------
-- MIGRATION: Agregar columnas faltantes a pagos
-- ----------------------------------------------------------------------------
alter table public.pagos 
  add column if not exists metadata jsonb default '{}',
  add column if not exists concepto_check text;

-- Actualizar constraint de concepto para incluir 'compra_contenido'
alter table public.pagos drop constraint if exists pagos_concepto_check;
alter table public.pagos add constraint pagos_concepto_check 
  check (concepto in ('suscripcion', 'tips', 'compra_contenido'));

-- Corregir precio en suscripciones (> 0 en lugar de >= 0)
alter table public.suscripciones drop constraint if exists suscripciones_precio_check;
alter table public.suscripciones add constraint suscripciones_precio_check check (precio > 0);

-- ----------------------------------------------------------------------------
-- MIGRATION: Agregar triggers updated_at faltantes
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- MIGRATION: Recrear función is_subscriber con parámetro correcto
-- ----------------------------------------------------------------------------
drop function if exists public.is_subscriber(uuid);
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

-- ----------------------------------------------------------------------------
-- MIGRATION: Agregar función helper is_media_owner
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- MIGRATION: Actualizar policy profiles_update_propio para proteger campos sensibles
-- ----------------------------------------------------------------------------
drop policy if exists "profiles_update_propio" on public.profiles;
create policy "profiles_update_propio"
  on public.profiles for update
  using (auth.uid() = id)
  with check (
    auth.uid() = id
    and (new.is_creator = old.is_creator)
    and (new.is_online = old.is_online)
    and (new.created_at = old.created_at)
  );

-- ----------------------------------------------------------------------------
-- MIGRATION: Actualizar policy media_update_propia para proteger campos inmutables
-- ----------------------------------------------------------------------------
drop policy if exists "media_update_propia" on public.media;
create policy "media_update_propia"
  on public.media for update
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (new.user_id = old.user_id)
    and (new.bucket = old.bucket)
    and (new.storage_key = old.storage_key)
  );

-- ----------------------------------------------------------------------------
-- MIGRATION: Actualizar policy suscripciones_update_parte
-- ----------------------------------------------------------------------------
drop policy if exists "suscripciones_update_parte" on public.suscripciones;
create policy "suscripciones_update_parte"
  on public.suscripciones for update
  using (auth.uid() = creator_id or auth.uid() = subscriber_id)
  with check (
    (auth.uid() = creator_id or auth.uid() = subscriber_id)
    and (new.creator_id = old.creator_id)
    and (new.subscriber_id = old.subscriber_id)
  );

-- ----------------------------------------------------------------------------
-- MIGRATION: Agregar policies para service_role en pagos
-- ----------------------------------------------------------------------------
drop policy if exists "pagos_insert_service_role" on public.pagos;
create policy "pagos_insert_service_role"
  on public.pagos for insert with check (auth.role() = 'service_role');

drop policy if exists "pagos_update_service_role" on public.pagos;
create policy "pagos_update_service_role"
  on public.pagos for update using (auth.role() = 'service_role');

-- ----------------------------------------------------------------------------
-- MIGRATION: Agregar funciones RPC
-- ----------------------------------------------------------------------------
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
  order by random()
  limit limit_count offset offset_count;
$$;

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

grant execute on function public.get_public_feed(int, int) to anon, authenticated;
grant execute on function public.get_profile_with_media(uuid) to anon, authenticated;
grant execute on function public.can_access_media(uuid) to anon, authenticated;