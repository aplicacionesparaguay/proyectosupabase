// src/routes/admin/+page.server.js
// Panel de administracion: se valida en el servidor y las mutaciones pasan
// por funciones RPC que vuelven a comprobar el rol DENTRO de la base.
//
// El navegador nunca llama a estas RPCs por su cuenta: las acciones del
// formulario viajan al servidor y el servidor las invoca con la sesion de la
// persona. Asi, aunque alguien falsee el HTML, la base sigue mandando.
import { fail } from '@sveltejs/kit';
import { requireAdmin } from '$lib/server/admin';
import { createPresignedDownload } from '$lib/server/r2';

/**
 * @typedef {Object} PerfilAdmin
 * @property {string} id
 * @property {string | null} display_name
 * @property {string | null} username
 * @property {string | null} role
 * @property {boolean | null} is_banned
 * @property {boolean | null} is_verified
 * @property {number | null} subscription_price
 * @property {string | null} city
 * @property {string | null} country_code
 * @property {string | null} avatar_key
 * @property {string | null} created_at
 */

/** @type {import('./$types').PageServerLoad} */
export async function load({ locals, url }) {
	const { user, adminRole } = await requireAdmin(locals);

	const selectedId = url.searchParams.get('user');
	const selectedIsUuid = typeof selectedId === 'string' && /^[0-9a-f-]{36}$/i.test(selectedId);

	// 1) Perfiles. La RPC filtra por lo que la persona puede ver.
	const { data: profileRows, error: profilesError } = await locals.supabase.rpc(
		'admin_list_profiles',
		{ p_role: null, p_limit: 200 }
	);

	/** @type {PerfilAdmin[]} */
	const profiles = Array.isArray(profileRows) ? profileRows : [];

	// 2) Cola de solicitudes: solo las administradoras pueden verla.
	/** @type {any[]} */
	let requests = [];
	let requestsError = '';

	if (adminRole === 'admin') {
		const { data: requestRows, error: requestError } = await locals.supabase.rpc(
			'admin_list_creator_requests',
			{ p_status: 'pending' }
		);

		if (requestError) {
			requestsError = requestError.message;
		} else {
			requests = Array.isArray(requestRows) ? requestRows : [];
		}
	}

	// 3) Galeria de la creadora seleccionada, para comprobar las fotos
	//    subidas.
	//
	//    Administradoras: RPC con la clave del objeto (`storage_path`), y el
	//    servidor firma una URL de lectura de corta duracion.
	//    Moderadoras: RPC de solo metadatos, SIN la clave: sin `storage_path`
	//    no se puede firmar nada, asi que el contenido privado de pago no
	//    queda accesible a moderacion.
	/** @type {any[]} */
	let media = [];
	let mediaError = '';
	let mediaRestricted = false;
	let selectedProfile = null;

	if (selectedIsUuid) {
		selectedProfile = profiles.find((p) => p.id === selectedId) ?? null;

		const isAdmin = adminRole === 'admin';

		const { data: mediaRows, error: mediaQueryError } = await locals.supabase.rpc(
			isAdmin ? 'admin_list_user_media' : 'moderator_list_user_media',
			{ target_user_id: selectedId }
		);

		if (mediaQueryError) {
			mediaError = mediaQueryError.message;
		} else {
			const rows = Array.isArray(mediaRows) ? mediaRows : [];

			media = await Promise.all(
				rows.map(async (row) => {
					/** @type {string | null} */
					let url = null;

					// Solo las administradoras reciben la clave del objeto, y
					// aun asi la clave tiene que pertenecer a la cuenta que
					// se esta mirando: nada de firmar rutas ajenas.
					const storagePath = row.storage_path;

					if (
						isAdmin &&
						typeof storagePath === 'string' &&
						storagePath.startsWith(`posts/${selectedId}/`)
					) {
						try {
							url = await createPresignedDownload(storagePath, 'private', 300);
						} catch {
							url = null;
						}
					} else if (isAdmin) {
						mediaRestricted = true;
					}

					return {
						id: row.id,
						filename: row.filename,
						mime_type: row.mime_type,
						byte_size: row.byte_size,
						estado: row.estado,
						visibilidad: row.visibilidad,
						created_at: row.created_at,
						url
					};
				})
			);
		}
	}

	return {
		adminRole,
		adminUserId: user.id,
		profiles,
		profilesError: profilesError?.message ?? '',
		requests,
		requestsError,
		media,
		mediaError,
		mediaRestricted,
		selectedId: selectedId ?? '',
		selectedProfile
	};
}

/**
 * Lee un campo de texto del formulario.
 * @param {FormData} data
 * @param {string} key
 * @returns {string}
 */
function field(data, key) {
	const value = data.get(key);
	return typeof value === 'string' ? value.trim() : '';
}

/**
 * Un id de cuenta tiene que parecer un UUID: evita mandar basura a la base.
 * @param {string} value
 * @returns {boolean}
 */
function isUuid(value) {
	return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

export const actions = {
	/**
	 * Cambia el rol de una cuenta. Solo administradoras.
	 */
	setRole: async ({ request, locals }) => {
		const { adminRole } = await requireAdmin(locals);

		if (adminRole !== 'admin') {
			return fail(403, { message: 'Solo las administradoras pueden cambiar el rol.' });
		}

		const data = await request.formData();
		const userId = field(data, 'user_id');
		const newRole = field(data, 'role');

		if (!userId || !isUuid(userId) || (newRole !== 'fan' && newRole !== 'creator')) {
			return fail(400, { message: 'Datos invalidos.' });
		}

		const { error: rpcError } = await locals.supabase.rpc('admin_set_creator_role', {
			target_user_id: userId,
			new_role: newRole
		});

		if (rpcError) {
			return fail(400, { message: rpcError.message });
		}

		return {
			ok: true,
			message: newRole === 'creator' ? 'La cuenta ya es creadora.' : 'La cuenta vuelve a ser fan.'
		};
	},

	/**
	 * Bloquea o desbloquea una cuenta. Administradoras y moderadoras.
	 */
	setBanned: async ({ request, locals }) => {
		await requireAdmin(locals);

		const data = await request.formData();
		const userId = field(data, 'user_id');
		const banned = field(data, 'banned') === 'true';

		if (!userId || !isUuid(userId)) {
			return fail(400, { message: 'Falta la cuenta.' });
		}

		const { error: rpcError } = await locals.supabase.rpc('admin_set_banned', {
			target_user_id: userId,
			banned
		});

		if (rpcError) {
			return fail(400, { message: rpcError.message });
		}

		return {
			ok: true,
			message: banned ? 'Cuenta bloqueada.' : 'Cuenta desbloqueada.'
		};
	},

	/**
	 * Aprueba una solicitud de creadora. Solo administradoras.
	 */
	approveRequest: async ({ request, locals }) => {
		const { adminRole } = await requireAdmin(locals);

		if (adminRole !== 'admin') {
			return fail(403, { message: 'Solo las administradoras pueden aprobar solicitudes.' });
		}

		const data = await request.formData();
		const requestId = field(data, 'request_id');

		if (!requestId || !isUuid(requestId)) {
			return fail(400, { message: 'Falta la solicitud.' });
		}

		const { error: rpcError } = await locals.supabase.rpc('approve_creator_request', {
			request_id: requestId
		});

		if (rpcError) {
			return fail(400, { message: rpcError.message });
		}

		return { ok: true, message: 'Solicitud aprobada.' };
	},

	/**
	 * Rechaza una solicitud de creadora. Solo administradoras.
	 */
	rejectRequest: async ({ request, locals }) => {
		const { adminRole } = await requireAdmin(locals);

		if (adminRole !== 'admin') {
			return fail(403, { message: 'Solo las administradoras pueden rechazar solicitudes.' });
		}

		const data = await request.formData();
		const requestId = field(data, 'request_id');
		const reason = field(data, 'reason');

		if (!requestId || !isUuid(requestId)) {
			return fail(400, { message: 'Falta la solicitud.' });
		}

		if (!reason) {
			return fail(400, { message: 'Se requiere un motivo de rechazo.' });
		}

		const { error: rpcError } = await locals.supabase.rpc('reject_creator_request', {
			request_id: requestId,
			rejection_reason: reason
		});

		if (rpcError) {
			return fail(400, { message: rpcError.message });
		}

		return { ok: true, message: 'Solicitud rechazada.' };
	}
};
