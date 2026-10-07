// src/lib/supabaseClient.js
// Cliente Supabase compartido.
//
// Usa @supabase/ssr para que la sesión del navegador se persista en COOKIES y
// no en localStorage. Eso es lo que permite que createServerClient (en
// hooks.server.js) lea la misma sesión y event.locals.getSession() funcione.
//
// Se mantiene la API exportada: `supabase` y `getCurrentSession()`.
import { browser } from '$app/environment';
import { createBrowserClient } from '@supabase/ssr';
import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';

const supabaseUrl = PUBLIC_SUPABASE_URL;
const supabaseKey = PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseKey) {
  throw new Error(
    'Missing Supabase environment variables. Make sure PUBLIC_SUPABASE_URL and PUBLIC_SUPABASE_ANON_KEY are set.'
  );
}

/**
 * Se construye un cliente distinto según el runtime:
 *
 * - Navegador: createBrowserClient de @supabase/ssr. Ignora `auth.storage` y
 *   persiste la sesión en cookies (document.cookie), que el navegador envía al
 *   servidor en cada request. createServerClient las lee en hooks.server.js.
 *
 * - Servidor: createClient de @supabase/supabase-js con persistencia
 *   desactivada. Aquí no hay cookies de request ni document.cookie, así que el
 *   cliente SSR no puede funcionar; las rutas server-side deben usar
 *   `event.locals.supabase` en lugar de este módulo.
 */
export const supabase = browser
  ? createBrowserClient(supabaseUrl, supabaseKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        // createBrowserClient de @supabase/ssr fuerza flowType: 'pkce'.
        // Dejamos el canje del ?code= como única tarea de
        // src/routes/auth/callback/+page.svelte. Si esto fuese `true`,
        // supabase-js intentaría intercambiar el mismo código PKCE en
        // _initialize() y competiría con el callback.
        detectSessionInUrl: false
      }
    })
  : createClient(supabaseUrl, supabaseKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false
      }
    });

export async function getCurrentSession() {
  return await supabase.auth.getSession();
}