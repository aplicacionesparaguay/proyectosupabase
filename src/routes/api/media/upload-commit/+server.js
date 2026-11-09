import { json } from '@sveltejs/kit';
import { getObjectBytes, ObjectTooLargeError } from '$lib/server/r2';
import { mediaServerQuery } from '$lib/server/mediaDb';
import {
	authFailure,
	cleanText,
	inspectPhoto,
	isUuid,
	readJson,
	safeRpcMessage,
	verifiedUserId
} from '$lib/server/media';
import { MAX_DESCRIPTION_LENGTH, MAX_PHOTO_BYTES, MAX_TITLE_LENGTH } from '$lib/media/constants';

/**
 * @param {import('@sveltejs/kit').RequestEvent['locals']} locals
 * @param {string} intentId
 */
async function abortQuietly(locals, intentId) {
	try {
		await locals.supabase.rpc('media_abort_upload_intent', { p_intent_id: intentId });
	} catch {
		// La cola de limpieza del worker tambien recoge los intents expirados.
	}
}

/** @type {import('./$types').RequestHandler} */
export async function POST({ request, locals }) {
	const denied = authFailure(locals);
	if (denied) return denied;

	const userId = verifiedUserId(locals);
	const body = await readJson(request);
	const intentId = /** @type {string} */ (body?.intentId);

	if (!isUuid(intentId)) {
		return json({ error: 'Intento de subida invalido.' }, { status: 400 });
	}

	const { data: intent, error: intentError } = await mediaServerQuery((db) => db
		.from('media_upload_intents')
		.select('id, object_key, mime_type, status, media_id, expires_at, declared_size')
		.eq('id', intentId)
		.eq('user_id', userId)
		.maybeSingle());

	if (intentError) {
		return json({ error: 'No se pudo verificar la subida.' }, { status: 503 });
	}

	if (!intent) {
		return json({ error: 'Intento de subida no encontrado.' }, { status: 404 });
	}

	if (intent.status === 'committed' && intent.media_id) {
		const { data: existing } = await mediaServerQuery((db) => db
			.from('media_assets')
			.select(
				'id, upload_status, processing_status, moderation_status, title, description, created_at'
			)
			.eq('id', intent.media_id)
			.eq('owner_id', userId)
			.maybeSingle());

		if (existing) {
			return json({ asset: existing, duplicate: true });
		}
	}

	if (intent.status !== 'created') {
		return json({ error: 'El intento de subida ya no esta disponible.' }, { status: 409 });
	}
	if (!Number.isFinite(Date.parse(intent.expires_at)) || Date.parse(intent.expires_at) <= Date.now()) {
		await abortQuietly(locals, intentId);
		return json({ error: 'El intento de subida expiro.' }, { status: 409 });
	}

	let bytes;

	try {
		bytes = await getObjectBytes(intent.object_key, MAX_PHOTO_BYTES, 'private');
	} catch (readError) {
		if (readError instanceof ObjectTooLargeError) {
			await abortQuietly(locals, intentId);
			return json(
				{ error: `La foto supera el maximo de ${MAX_PHOTO_BYTES / (1024 * 1024)} MB.` },
				{ status: 413 }
			);
		}

		const name = /** @type {{ name?: string }} */ (readError)?.name;

		if (name === 'NoSuchKey' || name === 'NotFound') {
			await abortQuietly(locals, intentId);
			return json(
				{ error: 'El archivo no llego al almacenamiento. Vuelve a intentarlo.' },
				{ status: 400 }
			);
		}

		console.error('No se pudo leer el objeto de staging');
		return json(
			{ error: 'El almacenamiento no esta disponible. Intenta de nuevo en unos minutos.' },
			{ status: 503 }
		);
	}

	let inspected;
	if (bytes.length !== Number(intent.declared_size)) {
		await abortQuietly(locals, intentId);
		return json({ error: 'El tamano real no coincide con el declarado.' }, { status: 422 });
	}

	try {
		inspected = await inspectPhoto(bytes, intent.mime_type);
	} catch (inspectionError) {
		await abortQuietly(locals, intentId);

		return json(
			{
				error: 'La foto no es una imagen estatica valida del tipo declarado.'
			},
			{ status: 422 }
		);
	}

	const title = cleanText(body?.title, MAX_TITLE_LENGTH);
	const description = cleanText(body?.description, MAX_DESCRIPTION_LENGTH);

	const { data, error } = await mediaServerQuery((db) => db.rpc('media_commit_upload', {
		p_actor_id: userId,
		p_intent_id: intentId,
		p_sha256: inspected.sha256,
		p_byte_size: bytes.length,
		p_width: inspected.width,
		p_height: inspected.height,
		p_title: title,
		p_description: description
	}));

	if (error || !data) {
		const message = safeRpcMessage(error);
		const code = typeof error?.code === 'string' ? error.code : '';
		const status =
			code === '42900' ? 429 : code === '42501'
				? 403
				: code === '28000'
					? 401
					: code === '57014' || code === '23505' || code === '23514'
						? 409
						: code === '22023' || code === 'P0002'
							? 400
							: 503;

		if (!message) console.error('media_commit_upload no disponible');
		return json({ error: message ?? 'No se pudo registrar la foto.' }, { status });
	}

	return json({ asset: data }, { status: 201, headers: { 'Cache-Control': 'private, no-store' } });
}
