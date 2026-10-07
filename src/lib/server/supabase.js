// src/lib/server/supabase.js
// Cliente de Supabase para el servidor (usa cookies HTTP).
// Las variables PUBLIC_* son seguras para el servidor Y el navegador.
import { createServerClient } from '@supabase/ssr';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';

/**
 * @param {import('@sveltejs/kit').Cookies} cookies
 */
export function createSupabaseServerClient(cookies) {
	return createServerClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
		cookies: {
			getAll() {
				return cookies.getAll();
			},
			setAll(cookiesToSet) {
				try {
					cookiesToSet.forEach(({ name, value, options }) =>
						cookies.set(name, value, { path: '/', ...options })
					);
				} catch {
					// Llamado desde un componente de servidor sin respuesta:
					// se puede ignorar, la sesión se refresca con `getUser()`.
				}
			}
		}
	});
}
