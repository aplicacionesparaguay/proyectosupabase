import { json } from '@sveltejs/kit';
import { authFailure, isUuid, readJson, safeRpcMessage } from '$lib/server/media';

/**
 * POST /api/media/delete
 *
 * Solicita el borrado de una fotografia propia. La fila se marca como
 * eliminada de inmediato (deja de aparecer en la galeria) y el borrado real
 * de los objetos se encola como trabajo durable. El endpoint no borra objetos
 * de R2 de forma sincrona: si el worker falla, el trabajo se reintenta.
 *
 * @type {import('./$types').RequestHandler}
 */
export async function POST({ request, locals }) {
	const denied = authFailure(locals);
	if (denied) return denied;

	const body = await readJson(request);
	const mediaId = body?.mediaId;

	if (!isUuid(mediaId)) {
		return json({ error: 'Identificador de archivo invalido.' }, { status: 400 });
	}

	const { error } = await locals.supabase.rpc('media_request_delete', {
		p_media_id: mediaId
	});

	if (error) {
		const message = safeRpcMessage(error);
		const code = typeof error.code === 'string' ? error.code : '';
		const status = code === 'P0002' ? 404 : code === '28000' ? 401 : code === '42501' ? 403 : 400;

		if (!message) console.error('media_request_delete no disponible');
		return json({ error: message ?? 'No se pudo eliminar la foto.' }, { status });
	}

	return json({ ok: true, queued: true }, { status: 202 });
}
