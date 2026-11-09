import { createHash } from 'node:crypto';
import sharp from 'sharp';
import { json } from '@sveltejs/kit';
import { mediaServerQuery } from './mediaDb';
import { authFailure, cleanText, inspectPhoto, isUuid, readJson, safeRpcMessage, verifiedUserId } from './media';
import { createPresignedDownload, createPresignedUpload, getObjectBytes, putObjectBytes, publicUrl } from './r2';
import { ALLOWED_PHOTO_TYPES, MAX_PHOTO_BYTES, MAX_PHOTO_PIXELS } from '$lib/media/constants';

/** @param {unknown} error */
function rpcFailure(error) {
	const code = /** @type {{code?: string}} */ (error)?.code;
	return json({ error: safeRpcMessage(error) ?? 'El servicio de imagenes no esta disponible.' }, {
		status: code === '42501' ? 403 : code === '42900' ? 429 : code === '22023' ? 400 : code === '23514' ? 409 : 503
	});
}

/** La via de compatibilidad solo acepta avatares/portadas, nunca posts. */
/** @type {import('@sveltejs/kit').RequestHandler} */
export async function profileImageUpload({ request, locals }) {
	const denied = authFailure(locals);
	if (denied) return denied;
	const body = await readJson(request);
	if (body?.folder === 'posts') return json({ error: 'Usa el pipeline de fotografias /api/media/upload-intent.' }, { status: 410 });
	if (!body || !['avatars', 'covers'].includes(String(body.folder))) return json({ error: 'Destino no permitido.' }, { status: 400 });
	const purpose = body.folder === 'avatars' ? 'avatar' : 'cover';
	const userId = verifiedUserId(locals);
	const visibility = purpose === 'avatar' ? 'publico' : body.visibility ?? 'privado';
	if (!['publico', 'privado'].includes(String(visibility))) return json({ error: 'Visibilidad invalida.' }, { status: 400 });
	const action = body.action ?? 'upload';
	if (action === 'upload') {
		const size = Number(body.fileSize);
		if (!ALLOWED_PHOTO_TYPES.includes(String(body.contentType)) || !Number.isSafeInteger(size) || size <= 0) {
			return json({ error: 'Solo se permiten fotos estaticas JPEG, PNG o WebP.' }, { status: 400 });
		}
		if (size > MAX_PHOTO_BYTES) return json({ error: 'La imagen supera los 10 MB.' }, { status: 413 });
		const { data, error } = await mediaServerQuery((db) => db.rpc('media_create_upload_intent', {
			p_actor_id: userId, p_purpose: purpose, p_file_name: cleanText(body.fileName, 200),
			p_mime_type: body.contentType, p_declared_size: size
		}));
		if (error || !data) return rpcFailure(error);
		try {
			const signedUrl = await createPresignedUpload(data.object_key, 'private', data.mime_type, 900, true, size);
			return json({ key: data.intent_id, signedUrl, action: 'upload' }, { status: 201, headers: { 'Cache-Control': 'private, no-store' } });
		} catch {
			// El intent ya tiene limpieza durable, aunque no llegue a emitirse el PUT.
			return rpcFailure(null);
		}
	}
	if (!isUuid(body.key) || !['commit', 'discard'].includes(String(action))) {
		return json({ error: 'Accion o intento de imagen invalido.' }, { status: 400 });
	}
	const { data: intent, error: readError } = await mediaServerQuery((db) => db.from('media_upload_intents')
		.select('id, object_key, status, purpose, mime_type, declared_size, expires_at, result_metadata')
		.eq('id', body.key).eq('user_id', userId).eq('purpose', purpose).maybeSingle());
	if (readError) return rpcFailure(readError);
	if (!intent) return json({ error: 'Intento no encontrado.' }, { status: 404 });
	if (action === 'discard') {
		const { error } = await locals.supabase.rpc('media_abort_upload_intent', { p_intent_id: intent.id });
		return error ? rpcFailure(error) : json({ ok: true }, { status: 202 });
	}
	if (intent.status === 'committed' && intent.result_metadata) return json(intent.result_metadata, { headers: { 'Cache-Control': 'private, no-store' } });
	if (intent.status !== 'created' || Date.parse(intent.expires_at) <= Date.now()) return json({ error: 'El intento ya no esta disponible.' }, { status: 409 });
	let canonical;
	try {
		const bytes = await getObjectBytes(intent.object_key, MAX_PHOTO_BYTES, 'private');
		if (bytes.length !== Number(intent.declared_size)) throw new Error('size');
		await inspectPhoto(bytes, intent.mime_type);
		canonical = await sharp(bytes, { limitInputPixels: MAX_PHOTO_PIXELS, failOn: 'warning' })
			.rotate().toColourspace('srgb').removeAlpha().webp({ quality: 90 }).toBuffer();
		if (canonical.length > MAX_PHOTO_BYTES) throw new Error('size');
	} catch {
		// No abortar automaticamente ante un fallo de almacenamiento transitorio.
		return json({ error: 'No se pudo validar la imagen del almacenamiento.' }, { status: 422 });
	}
	const { data: target, error: prepareError } = await mediaServerQuery((db) => db.rpc('media_prepare_profile_image', { p_actor_id: userId, p_intent_id: intent.id }));
	if (prepareError || !target) return rpcFailure(prepareError);
	try {
		await putObjectBytes(target.object_key, canonical, 'image/webp', target.bucket);
	} catch { return rpcFailure(null); }
	const { data, error } = await mediaServerQuery((db) => db.rpc('media_commit_profile_image', {
		p_actor_id: userId, p_intent_id: intent.id, p_sha256: createHash('sha256').update(canonical).digest('hex'),
		p_byte_size: canonical.length, p_visibility: visibility,
		p_public_url: purpose === 'avatar' ? publicUrl(target.object_key) : null
	}));
	return error || !data ? rpcFailure(error) : json(data, { headers: { 'Cache-Control': 'private, no-store' } });
}

/** @param {any} row @returns {Promise<string | null>} */
export async function coverReadUrl(row) {
	// Las portadas privadas heredadas se ocultan hasta completar su traslado.
	if (row.visibilidad !== 'publico' && row.storage_bucket !== 'private') return null;
	const stored = /** @type {unknown} */ (row.storage_path ?? row.public_url);
	if (typeof stored !== 'string') return null;
	let key = stored;
	try {
		if (/^https?:\/\//i.test(key)) key = decodeURIComponent(new URL(key).pathname.slice(1));
		if (!key.startsWith(`covers/${row.user_id}/`) || key.split('/').some((part) => !part || part === '.' || part === '..')) return null;
		if (!['private', 'public'].includes(row.storage_bucket)) return null;
		return await createPresignedDownload(key, row.storage_bucket, 300);
	} catch { return null; }
}

/** @param {string} userId @param {string | null} viewerId */
export async function coverItems(userId, viewerId) {
	const { data, error } = await mediaServerQuery((db) => {
		let query = db.from('user_banners').select('id, user_id, storage_path, storage_bucket, public_url, orden, visibilidad')
			.eq('user_id', userId).order('orden', { ascending: true }).order('id', { ascending: true }).limit(100);
		if (viewerId !== userId) query = query.eq('visibilidad', 'publico');
		return query;
	});
	if (error) return { items: [], error: true };
	const rows = (Array.isArray(data) ? data : []).filter((row) => row.user_id === userId && (row.visibilidad === 'publico' || viewerId === userId));
	return { error: false, items: await Promise.all(rows.map(async (row) => ({
		id: row.id, orden: row.orden, visibilidad: row.visibilidad, public_url: await coverReadUrl(row)
	}))) };
}
