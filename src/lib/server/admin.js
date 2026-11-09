// src/lib/server/admin.js
// Autorizacion del panel de administracion.
//
// La decision se toma SIEMPRE en el servidor y usando la sesion de la
// persona (locals.supabase usa la anon key + las cookies de sesion). No se
// usa `service_role`: la base sigue aplicando RLS y cada RPC comprueba el
// rol por su cuenta.
//
// Si la funcion `my_admin_role()` no existe todavia en la base (migracion
// pendiente), el resultado es `null`: el panel se queda cerrado en lugar de
// dejar pasar a cualquiera.
import { error, redirect } from '@sveltejs/kit';

/**
 * Rol administrativo de la sesion actual.
 * @param {import('@sveltejs/kit').RequestEvent['locals']} locals
 * @returns {Promise<'admin' | 'moderator' | null>}
 */
export async function resolveAdminRole(locals) {
	try {
		const { data, error: rpcError } = await locals.supabase.rpc('my_admin_role');

		if (rpcError || data === null || data === undefined) return null;

		return data === 'admin' || data === 'moderator' ? data : null;
	} catch {
		return null;
	}
}

/**
 * Rol de moderacion del pipeline de media. Es independiente de
 * `my_admin_role()` para que el panel de fotos funcione aunque la migracion
 * administrativa antigua no este aplicada.
 *
 * @param {import('@sveltejs/kit').RequestEvent['locals']} locals
 * @returns {Promise<'admin' | 'moderator' | null>}
 */
export async function resolveMediaRole(locals) {
	try {
		const { data, error: rpcError } = await locals.supabase.rpc('media_admin_role');

		if (rpcError || data === null || data === undefined) return null;

		return data === 'admin' || data === 'moderator' ? data : null;
	} catch {
		return null;
	}
}

/**
 * Exige sesion con permisos de moderacion de fotos.
 * @param {import('@sveltejs/kit').RequestEvent['locals']} locals
 * @returns {Promise<{ user: { id: string }, mediaRole: 'admin' | 'moderator' }>}
 */
export async function requireMediaStaff(locals) {
	if (locals.auth?.status === 'error') {
		error(503, 'La verificacion de sesion no esta disponible temporalmente.');
	}

	const session = await locals.getSession();

	if (locals.auth?.status !== 'verified' || !session?.user || !locals.auth?.userId || session.user.id !== locals.auth.userId) {
		redirect(302, '/login');
	}

	const mediaRole = await resolveMediaRole(locals);

	if (!mediaRole) {
		error(403, 'No tenes permisos para moderar fotografias.');
	}

	return { user: { ...session.user, id: locals.auth.userId }, mediaRole };
}

/**
 * Exige sesion con permisos administrativos. Corta la peticion si no la hay.
 * @param {import('@sveltejs/kit').RequestEvent['locals']} locals
 * @returns {Promise<{ user: { id: string }, adminRole: 'admin' | 'moderator' }>}
 */
export async function requireAdmin(locals) {
	// Fallo temporal de la verificacion: no se redirige (eso ocultaria el
	// problema) ni se autoriza; se corta con 503.
	if (locals.auth?.status === 'error') {
		error(503, 'La verificacion de sesion no esta disponible temporalmente.');
	}

	// getSession() devuelve la sesion SOLO si hooks.server.js verifico la
	// identidad; una cookie forjada o caducada cae aqui como "sin sesion".
	const session = await locals.getSession();

	if (!session?.user || !locals.auth?.userId) {
		redirect(302, '/login');
	}

	const adminRole = await resolveAdminRole(locals);

	if (!adminRole) {
		error(403, 'No tenés permisos de administracion.');
	}

	// El `id` devuelto es SIEMPRE el sub verificado, no el de la cookie.
	return { user: { ...session.user, id: locals.auth.userId }, adminRole };
}
