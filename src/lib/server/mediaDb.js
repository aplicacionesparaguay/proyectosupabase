import { createClient } from '@supabase/supabase-js';
import { env } from '$env/dynamic/private';
import { PUBLIC_SUPABASE_URL } from '$env/static/public';

/** @type {import('@supabase/supabase-js').SupabaseClient | undefined} */
let client;

/**
 * Solo para operaciones del pipeline que contienen claves internas.
 * Cada llamador debe filtrar propietario/estado o pasar el actor VERIFICADO.
 * Nunca se instala una sesion de usuario en este cliente privilegiado.
 *
 * @param {(db: import('@supabase/supabase-js').SupabaseClient) => PromiseLike<{ data: any, error: any }>} query
 * @returns {Promise<{ data: any, error: any }>}
 */
export async function mediaServerQuery(query) {
	try {
		if (!env.SUPABASE_SERVICE_ROLE_KEY) {
			return { data: null, error: { code: 'MEDIA_SERVER_UNAVAILABLE' } };
		}
		client ??= createClient(PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
			auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
		});
		return await query(client);
	} catch {
		// Los errores del SDK pueden contener cabeceras, claves o URLs: no se serializan.
		return { data: null, error: { code: 'MEDIA_SERVER_UNAVAILABLE' } };
	}
}
