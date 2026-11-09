import { json } from '@sveltejs/kit';
import { createPresignedUpload } from '$lib/server/r2';
import { mediaServerQuery } from '$lib/server/mediaDb';
import {
	authFailure,
	cleanText,
	readJson,
	safeRpcMessage,
	verifiedUserId
} from '$lib/server/media';
import { ALLOWED_PHOTO_TYPES, MAX_PHOTO_BYTES } from '$lib/media/constants';

/** @type {import('./$types').RequestHandler} */
export async function POST({ request, locals }) {
	const denied = authFailure(locals);
	if (denied) return denied;

	const body = await readJson(request);
	if (!body) return json({ error: 'La peticion debe ser JSON valido.' }, { status: 400 });

	const fileName = cleanText(body.fileName, 200);
	const contentType = cleanText(body.contentType, 100);
	const declaredSize = Number(body.declaredSize);

	if (!ALLOWED_PHOTO_TYPES.includes(contentType)) {
		return json({ error: 'Solo se permiten fotos JPEG, PNG o WebP.' }, { status: 400 });
	}

	if (!Number.isSafeInteger(declaredSize) || declaredSize <= 0) {
		return json({ error: 'El archivo esta vacio o su tamano es invalido.' }, { status: 400 });
	}

	if (declaredSize > MAX_PHOTO_BYTES) {
		return json(
			{ error: `La foto supera el maximo de ${MAX_PHOTO_BYTES / (1024 * 1024)} MB.` },
			{ status: 413 }
		);
	}

	const { data, error } = await mediaServerQuery((db) => db.rpc('media_create_upload_intent', {
		p_actor_id: verifiedUserId(locals),
		p_purpose: 'gallery',
		p_file_name: fileName,
		p_mime_type: contentType,
		p_declared_size: Math.floor(declaredSize)
	}));

	if (error || !data) {
		const message = safeRpcMessage(error);
		const code = typeof error?.code === 'string' ? error.code : '';
		const status = code === '42501' ? 403 : code === '28000' ? 401 : code === '42900' ? 429 : code === '22023' ? 400 : 503;

		if (!message) console.error('media_create_upload_intent no disponible');
		return json({ error: message ?? 'No se pudo iniciar la subida.' }, { status });
	}

	const intent =
		/** @type {{ intent_id: string, object_key: string, mime_type: string, max_bytes: number, expires_at: string }} */ (
			data
		);

	let uploadUrl;

	try {
			uploadUrl = await createPresignedUpload(intent.object_key, 'private', intent.mime_type, 900, true, declaredSize);
	} catch (uploadError) {
		console.error('No se pudo firmar la subida');

		try {
			await locals.supabase.rpc('media_abort_upload_intent', {
				p_intent_id: intent.intent_id
			});
		} catch {
			// La limpieza es best-effort: el worker tambien recoge intents expirados.
		}

		return json(
			{ error: 'El almacenamiento no esta disponible. Intenta de nuevo en unos minutos.' },
			{ status: 503 }
		);
	}

	return json(
		{
			intentId: intent.intent_id,
			uploadUrl,
			maxBytes: Number(intent.max_bytes),
			expiresAt: intent.expires_at,
			userId: verifiedUserId(locals)
		},
		{ status: 201, headers: { 'Cache-Control': 'private, no-store' } }
	);
}
