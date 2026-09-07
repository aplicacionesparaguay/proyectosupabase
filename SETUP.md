# Configuración definitiva — Supabase + Cloudflare R2

Arquitectura del proyecto:

| Servicio            | Qué guarda                                        |
| ------------------- | ------------------------------------------------- |
| **Supabase**        | Auth (registro/login) + datos relacionales        |
| **Cloudflare R2**   | Fotos y videos (2 buckets: público y privado)     |

El esquema SQL está en [`supabase/schema.sql`](supabase/schema.sql).

---

## Parte 1 · Supabase (auth + datos)

1. Crea un proyecto en https://supabase.com/dashboard (o reutiliza `wmxfzeacojtgasfmznum`).
2. Abre **SQL Editor** → pega el contenido de `supabase/schema.sql` → **Run**.
   Crea: `profiles`, `media`, `comments`, `suscripciones`, `pagos`, triggers,
   funciones y políticas RLS.
3. **Authentication → Sign In / Providers**: deja activado **Email**.
4. **Authentication → URL Configuration**:
   - Site URL: `http://localhost:5173`
   - Redirect URLs: `http://localhost:5173/**` y la URL de producción (`https://tu-dominio.com/**`)
5. Copia las credenciales en **Settings → API**:
   - `Project URL` → `VITE_SUPABASE_URL`
   - `anon public key` → `VITE_SUPABASE_ANON_KEY`

Verifica: al registrarte un usuario, la fila en `profiles` se crea sola (trigger `on_auth_user_created`).

---

## Parte 2 · Cloudflare R2 (fotos y videos)

### 2.1 Crear los buckets

En **Cloudflare Dashboard → R2**:

1. **Create bucket** → `aguaenlaboca-public`
   - Contenido accesible sin login: avatares, banners y vistas previas.
2. **Create bucket** → `aguaenlaboca-private`
   - Contenido de pago (paywall). Se sirve con **URLs firmadas** generadas en el servidor.

### 2.2 Dominio público para `aguaenlaboca-public`

Entra al bucket `aguaenlaboca-public` → **Settings → Custom Domains**:

- Conecta un dominio propio, p. ej. `cdn.aguaenlaboca.com` (requiere añadir el CNAME en el DNS).
- ⚠️ Para desarrollo puedes usar el subdominio temporal `r2.dev`:
  bucket → **Settings → Public access** → *"Generate r2.dev subdomain"*.
  Da una URL tipo `https://pub-xxxxxxxxxxxxxxxxxxxx.r2.dev`.

La URL base que uses pasa a ser `R2_PUBLIC_URL`.

### 2.3 Crear las claves de API

**R2 → Manage R2 API Tokens → Create API Token**:

- Permisos: **Object Read & Write**
- Bucket scope: **`aguaenlaboca-public`** y **`aguaenlaboca-private`**
- Duración: permanente
- Copia **Access Key ID** y **Secret Access Key**.

El **Account ID** está en la URL del dashboard (`dash.cloudflare.com/<ACCOUNT_ID>/r2`)
o en la página principal de R2. P.ej. `5d3f...`.

> ⚠️ El Secret Access Key de R2 **nunca** debe ir con prefijo `VITE_` (se expondría en el navegador). Solo se usa en el servidor.

---

## Parte 3 · Variables de entorno

Reemplaza `.env` (y crea los valores en el dashboard del hosting):

```env
# ---------- Supabase (client, pública) ----------
VITE_SUPABASE_URL=https://wmxfzeacojtgasfmznum.supabase.co
VITE_SUPABASE_ANON_KEY=tu_anon_key

# ---------- Cloudflare R2 (SOLO SERVIDOR) ----------
R2_ACCOUNT_ID=tu_account_id
R2_ACCESS_KEY_ID=tu_access_key_id
R2_SECRET_ACCESS_KEY=tu_secret_access_key
R2_PUBLIC_BUCKET=aguaenlaboca-public
R2_PRIVATE_BUCKET=aguaenlaboca-private
R2_PUBLIC_URL=https://cdn.aguaenlaboca.com
```

En **Vercel**: Settings → Environment Variables → añade las R2 como variables privadas
(no expuestas al cliente). Localmente viven en `.env`.

---

## Parte 4 · Flujo de subida/servido (con el código actualizado)

1. **Subida**: el cliente pide un *presigned PUT* a una ruta de servidor
   (`src/routes/api/upload/+server.js`), que usa las claves R2. El navegador sube
   directo a R2 sin exponer secretos.
2. **Metadatos**: la app inserta una fila en `media` (`user_id`, `tipo`,
   `bucket`, `storage_key`, `public_url`, `es_privado`).
3. **Contenido público**: `<img src="https://cdn.aguaenlaboca.com/{key}">`.
4. **Contenido privado (paywall)**: el servidor genera una *presigned URL*
   (firma por la clave privada) y solo si `is_subscriber(creator_id)` es true.
5. **RLS**: aunque alguien consiga una URL, la tabla `media` bloquea la lectura
   de filas privadas a no suscriptores.

---

## Checklist final

- [ ] `supabase/schema.sql` ejecutado sin errores
- [ ] Email provider activado y Redirect URLs configuradas
- [ ] Buckets `aguaenlaboca-public` y `aguaenlaboca-private` creados
- [ ] Dominio público (o r2.dev) en el bucket public
- [ ] API token R2 con Read/Write en ambos buckets
- [ ] `.env` con Supabase (VITE_) y R2 (sin VITE_)
- [ ] Registrar un usuario de prueba → se crea su fila en `profiles`
