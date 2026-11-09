import { json } from '@sveltejs/kit';
import { authFailure, isUuid, readJson, safeRpcMessage } from '$lib/server/media';

/** @type {import('./$types').RequestHandler} */
export async function POST({ request, locals }) {
	const denied = authFailure(locals);
	if (denied) return denied;

	const body = await readJson(request);
	const intentId = body?.intentId;

	if (!isUuid(intentId)) {
		return json({ error: 'Intento de subida invalido.' }, { status: 400 });
	}

	const { error } = await locals.supabase.rpc('media_abort_upload_intent', {
		p_intent_id: intentId
	});

	if (error) {
		const message = safeRpcMessage(error);
		const code = typeof error.code === 'string' ? error.code : '';
		const status = code === 'P0002' ? 404 : code === '23505' ? 409 : 400;

		if (!message) console.error('media_abort_upload_intent no disponible');
		return json({ error: message ?? 'No se pudo descartar la subida.' }, { status });
	}

	return json({ ok: true });
}
