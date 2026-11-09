import { json } from '@sveltejs/kit';
import { authFailure, isUuid, readJson, safeRpcMessage } from '$lib/server/media';

/** @type {import('./$types').RequestHandler} */
export async function POST({ request, locals }) {
	const denied = authFailure(locals);
	if (denied) return denied;
	const body = await readJson(request);
	if (!isUuid(body?.banner_id)) return json({ error: 'Identificador de portada invalido.' }, { status: 400 });
	const { error } = await locals.supabase.rpc('media_request_delete_cover', { p_banner_id: body?.banner_id });
	if (error) return json({ error: safeRpcMessage(error) ?? 'No se pudo retirar la portada.' }, { status: 400 });
	return json({ ok: true, queued: true }, { status: 202 });
}
