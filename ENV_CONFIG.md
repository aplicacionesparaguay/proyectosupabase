# Configuración de Variables de Entorno

Para que la aplicación funcione correctamente, necesitas crear un archivo `.env` en la raíz del proyecto con las siguientes variables:

```bash
# Variables de entorno para Supabase
VITE_SUPABASE_URL=tu_supabase_url_aqui
VITE_SUPABASE_ANON_KEY=tu_supabase_anon_key_aqui
```

## Cómo obtener estas variables:

1. Ve a tu proyecto en [Supabase Dashboard](https://supabase.com/dashboard)
2. Ve a Settings > API
3. Copia el "Project URL" para `VITE_SUPABASE_URL`
4. Copia el "anon/public" key para `VITE_SUPABASE_ANON_KEY`

## Verificación:

Una vez configurado el `.env`, reinicia el servidor de desarrollo:

```bash
npm run dev
```

Si las variables no están configuradas, verás un error en la consola indicando que faltan las variables de entorno.