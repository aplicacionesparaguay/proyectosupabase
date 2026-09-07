# Supabase SQL Files - Agua En La Boca

## Archivos

| Archivo | Descripción | Cuándo usar |
|---------|-------------|-------------|
| `schema.sql` | **Esquema completo corregido y optimizado** | Primera vez / BD nueva |
| `migration_v2.sql` | **Migraciones incrementales** | Si ya tienes la BD creada con el schema anterior |
| `seed.sql` | **Datos de prueba** | Desarrollo / Testing local |

---

## Orden de Ejecución

### Opción A: Base de datos nueva (recomendado)
```bash
# 1. Ejecutar schema.sql completo en Supabase Dashboard → SQL Editor
# 2. (Opcional) Ejecutar seed.sql para datos de prueba
```

### Opción B: Base de datos existente con schema anterior
```bash
# 1. Ejecutar migration_v2.sql (aplica solo los cambios/faltantes)
# 2. Verificar que no hay errores
# 3. (Opcional) Ejecutar seed.sql
```

---

## Qué corrige `schema.sql` vs anterior

| Problema | Fix aplicado |
|----------|--------------|
| `precio >= 0` en suscripciones | → `precio > 0` |
| Faltaban triggers `updated_at` en suscripciones, pagos, comments | ✅ Agregados |
| Función `is_subscriber` parámetro incorrecto | ✅ `creator_uuid` coincide con policy |
| Policy `profiles_update` permitía cambiar `is_creator`, `is_online` | ✅ Bloqueados con `with check` |
| Policy `media_update` permitía cambiar `user_id`, `bucket`, `storage_key` | ✅ Bloqueados |
| Policy `suscripciones_update` permitía cambiar `creator_id`, `subscriber_id` | ✅ Bloqueados |
| `pagos` solo owner, sin service_role para webhooks | ✅ Policies `service_role` |
| Faltaban índices compuestos para queries frecuentes | ✅ Agregados |
| Bucket check en código usaba `'public'/'private'` vs nombres reales | ✅ Documentado y RPC `can_access_media` |
| Sin funciones RPC para queries complejas | ✅ `get_public_feed`, `get_profile_with_media`, `can_access_media` |
| `concepto` en pagos solo 2 valores | ✅ Agregado `'compra_contenido'` |
| `metadata` jsonb en pagos para datos extra | ✅ Agregado |

---

## Uso de las Funciones RPC (desde frontend)

```javascript
// Feed público aleatorio (home page)
const { data: feed } = await supabase.rpc('get_public_feed', { 
  limit_count: 20, 
  offset_count: 0 
});

// Perfil completo con media (página /perfil/[id])
const { data: profileData } = await supabase.rpc('get_profile_with_media', { 
  target_user_id: 'uuid-del-usuario' 
});

// Verificar acceso antes de generar signed URL (api/media/presign)
const { data: canAccess } = await supabase.rpc('can_access_media', { 
  media_uuid: 'uuid-del-media' 
});
```

---

## Variables de Entorno Requeridas

```env
# Supabase (ya las tienes)
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...

# R2 (solo servidor - en .env o Vercel/Cloudflare env vars)
R2_ACCOUNT_ID=...
R2_ACCESS_KEY_ID=...
R2_SECRET_ACCESS_KEY=...
R2_PUBLIC_BUCKET=aguaenlaboca-public
R2_PRIVATE_BUCKET=aguaenlaboca-private
R2_PUBLIC_URL=https://pub-xxxxx.r2.dev  # URL pública del bucket público
```

---

## Testing Local

```bash
# 1. Levantar Supabase local (opcional)
supabase start

# 2. Push schema a local
supabase db reset  # ejecuta todo schema.sql + seed.sql si está en supabase/seed.sql

# 3. O ejecutar manualmente en Dashboard SQL Editor
```

---

## Verificaciones Post-Deploy

```sql
-- Verificar tablas
select * from public.profiles;
select * from public.media;
select * from public.suscripciones;
select * from public.pagos;
select * from public.comments;

-- Verificar funciones
select public.is_subscriber('creator-uuid-aqui');
select public.can_access_media('media-uuid-aqui');
select * from public.get_public_feed(5);
select * from public.get_profile_with_media('user-uuid-aqui');

-- Verificar RLS (como usuario autenticado)
-- En Supabase Dashboard → Authentication → Impersonate user → SQL Editor
select * from public.media where es_privado = true;  -- debería ser 0 sin suscripción
```

---

## Rollback (si algo sale mal)

```sql
-- Eliminar todo (CUIDADO: borra datos)
drop schema public cascade;
create schema public;
grant all on schema public to postgres, anon, authenticated, service_role;
-- Luego re-ejecutar schema.sql
```