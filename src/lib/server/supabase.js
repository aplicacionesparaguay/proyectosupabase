// src/lib/server/supabase.js
// Cliente de Supabase para el servidor (usa cookies HTTP).
import { createServerClient } from '@supabase/ssr';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
	throw new Error('Missing Supabase server environment variables.');
}

/**
 * @param {import('@sveltejs/kit').Cookies} cookies
 */
export function createSupabaseServerClient(cookies) {
	return createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
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
			},
		},
	});
}
