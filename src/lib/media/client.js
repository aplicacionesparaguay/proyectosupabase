import {
	ALLOWED_PHOTO_TYPES,
	MAX_PHOTO_BYTES,
	MAX_TITLE_LENGTH,
	MAX_DESCRIPTION_LENGTH,
	PHOTO_EXTENSIONS,
	maxPhotoBytesLabel
} from './constants';

/**
 * @typedef {Object} MediaAsset
 * @property {string} id
 * @property {string} upload_status
 * @property {string} processing_status
 * @property {string} moderation_status
 * @property {string | null} title
 * @property {string | null} description
 * @property {string | null} original_filename
 * @property {string} mime_type
 * @property {number} byte_size
 * @property {number | null} width
 * @property {number | null} height
 * @property {number} faces_detected
 * @property {string | null} protection_mode
 * @property {number | null} protection_strength
 * @property {string | null} verification_status
 * @property {string | null} rejection_reason
 * @property {string | null} previewUrl
 * @property {string | null} fullUrl
 * @property {boolean} originalAvailable
 * @property {string} created_at
 */

/**
 * @param {File} file
 * @returns {string}
 */
export function validatePhotoFile(file) {
	if (!ALLOWED_PHOTO_TYPES.includes(file.type)) {
		const isGif = /\.gif$/i.test(file.name);
		const isHeic = /\.hei[cf]$/i.test(file.name);
		const isVideo = /\.(mp4|webm|mov|avi)$/i.test(file.name);

		if (isGif) return 'Las imagenes animadas no estan permitidas. Usa una foto JPG, PNG o WebP.';
		if (isHeic) return 'HEIC no es compatible. Exporta la foto a JPG o WebP.';
		if (isVideo) return 'Los videos no forman parte de esta galeria. Sube una foto.';
		return 'Solo se permiten fotos JPG, PNG o WebP.';
	}

	const extensions =
		PHOTO_EXTENSIONS[/** @type {keyof typeof PHOTO_EXTENSIONS} */ (file.type)] ?? [];
	const lowerName = file.name.toLowerCase();

	if (!extensions.some((extension) => lowerName.endsWith(extension))) {
		return 'La extension del archivo no coincide con su tipo.';
	}

	if (file.size <= 0) return 'El archivo esta vacio.';

	if (file.size > MAX_PHOTO_BYTES) {
		return `La foto supera el maximo de ${maxPhotoBytesLabel()}.`;
	}

	return '';
}

/**
 * @param {string} url
 * @param {Record<string, unknown>} body
 * @returns {Promise<Record<string, any>>}
 */
async function requestJson(url, body) {
	const response = await fetch(url, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify(body)
	});

	let result = /** @type {Record<string, any>} */ ({});

	try {
		result = await response.json();
	} catch {
		if (!response.ok) throw new Error(`Error del servidor (${response.status}).`);
	}

	if (!response.ok) {
		const error = new Error(result?.error || `Error del servidor (${response.status}).`);
		// @ts-expect-error status es informativo para la UI.
		error.status = response.status;
		throw error;
	}

	return result;
}

/**
 * @param {string} intentId
 */
async function abortIntent(intentId) {
	try {
		await requestJson('/api/media/upload-abort', { intentId });
	} catch {
		// La limpieza es best-effort: el worker tambien procesa intents
		// expirados. No se oculta el error original de la subida.
	}
}

/**
 * @param {string} url
 * @param {File} file
 * @param {(percent: number) => void} [onProgress]
 * @param {AbortSignal} [signal]
 * @returns {Promise<void>}
 */
function putObject(url, file, onProgress, signal) {
	return new Promise((resolve, reject) => {
		const xhr = new XMLHttpRequest();

		const abort = () => xhr.abort();

		if (signal) {
			if (signal.aborted) {
				reject(new Error('Subida cancelada'));
				return;
			}
			signal.addEventListener('abort', abort, { once: true });
		}

		const clean = () => signal?.removeEventListener('abort', abort);

		xhr.upload.addEventListener('progress', (event) => {
			if (event.lengthComputable && event.total > 0) {
				onProgress?.(Math.round((event.loaded / event.total) * 100));
			}
		});

		xhr.addEventListener('load', () => {
			clean();
			if (xhr.status >= 200 && xhr.status < 300) {
				resolve();
				return;
			}
			reject(new Error(`No se pudo subir la foto (${xhr.status}).`));
		});

		xhr.addEventListener('error', () => {
			clean();
			reject(new Error('No se pudo conectar con el almacenamiento.'));
		});

		xhr.addEventListener('abort', () => {
			clean();
			reject(new Error('Subida cancelada'));
		});

		xhr.open('PUT', url);
		xhr.setRequestHeader('Content-Type', file.type);
		xhr.setRequestHeader('If-None-Match', '*');
		xhr.send(file);
	});
}

/**
 * Sube una foto al staging privado y la registra en el pipeline.
 *
 * El servidor decide la clave, valida el objeto real y crea el trabajo de
 * procesamiento. El cliente nunca obtiene credenciales ni una ruta elegida
 * por el.
 *
 * @param {File} file
 * @param {{ title?: string, description?: string, onProgress?: (percent: number) => void, signal?: AbortSignal }} [options]
 * @returns {Promise<MediaAsset>}
 */
export async function uploadPhoto(file, options = {}) {
	const { title = '', description = '', onProgress, signal } = options;

	const clientError = validatePhotoFile(file);
	if (clientError) throw new Error(clientError);
	if (signal?.aborted) throw new Error('Subida cancelada');

	onProgress?.(0);

	const intent = await requestJson('/api/media/upload-intent', {
		fileName: file.name,
		contentType: file.type,
		declaredSize: file.size
	});

	const intentId = String(intent.intentId ?? '');
	const uploadUrl = String(intent.uploadUrl ?? '');

	if (!intentId || !uploadUrl) {
		if (intentId) await abortIntent(intentId);
		throw new Error('El servidor no devolvio una intencion de subida valida.');
	}

	let uploaded = false;

	try {
		await putObject(uploadUrl, file, onProgress, signal);
		uploaded = true;

		const result = await requestJson('/api/media/upload-commit', {
			intentId,
			title: title.slice(0, MAX_TITLE_LENGTH),
			description: description.slice(0, MAX_DESCRIPTION_LENGTH)
		});

		onProgress?.(100);

		return /** @type {MediaAsset} */ (result.asset);
	} catch (error) {
		const status = /** @type {{ status?: unknown }} */ (error)?.status;

		// Un fallo 5xx del commit es transitorio: se conserva el staging para
		// que la limpieza programada lo retire, nunca se descarta una subida
		// que puede haberse registrado.
		if (!uploaded || (typeof status === 'number' && status < 500)) {
			await abortIntent(intentId);
		}

		throw error;
	}
}

/**
 * @param {string} mediaId
 * @returns {Promise<{ ok: boolean, message?: string }>}
 */
export async function deleteMedia(mediaId) {
	if (!mediaId) return { ok: false, message: 'Falta el identificador del archivo.' };

	try {
		await requestJson('/api/media/delete', { mediaId });
		return { ok: true };
	} catch (error) {
		return {
			ok: false,
			message: error instanceof Error ? error.message : 'No se pudo eliminar la foto.'
		};
	}
}

/**
 * @param {{limit?: number, cursor?: string | null}} [options]
 * @returns {Promise<{items: MediaAsset[], nextCursor: string | null}>}
 */
export async function loadOwnerMediaPage(options = {}) {
	const params = new URLSearchParams({ limit: String(options.limit ?? 40) });
	if (options.cursor) params.set('cursor', options.cursor);
	const response = await fetch(`/api/media/owner?${params}`, { headers: { Accept: 'application/json' } });
	const result = await response.json().catch(() => ({}));

	if (!response.ok) {
		throw new Error(result?.error || `No se pudo cargar la galeria (${response.status}).`);
	}

	return { items: Array.isArray(result.items) ? result.items : [], nextCursor: typeof result.nextCursor === 'string' ? result.nextCursor : null };
}

/** @returns {Promise<MediaAsset[]>} */
export async function loadOwnerMedia() { return (await loadOwnerMediaPage()).items; }

/** @param {string} userId @returns {Promise<any[]>} */
export async function loadCovers(userId) {
	const response = await fetch(`/api/media/covers?user_id=${encodeURIComponent(userId)}`);
	const result = await response.json().catch(() => ({}));
	if (!response.ok) throw new Error(result?.error ?? 'No se pudieron cargar las portadas.');
	return Array.isArray(result.items) ? result.items : [];
}

/**
 * @param {string} userId
 * @param {{ limit?: number, offset?: number, cursor?: string | null }} [options]
 * @returns {Promise<{items: MediaAsset[], nextCursor: string | null}>}
 */
export async function loadPublicMediaPage(userId, options = {}) {
	const params = new URLSearchParams({
		user_id: userId,
		limit: String(options.limit ?? 40),
		offset: String(options.offset ?? 0)
	});
	if (options.cursor) params.set('cursor', options.cursor);

	const response = await fetch(`/api/media/public?${params.toString()}`, {
		headers: { Accept: 'application/json' }
	});
	const result = await response.json().catch(() => ({}));

	if (!response.ok) {
		throw new Error(result?.error || `No se pudo cargar la galeria (${response.status}).`);
	}

	return { items: Array.isArray(result.items) ? result.items : [], nextCursor: typeof result.nextCursor === 'string' ? result.nextCursor : null };
}

/** @param {string} userId @param {{limit?: number, offset?: number}} [options] @returns {Promise<MediaAsset[]>} */
export async function loadPublicMedia(userId, options = {}) { return (await loadPublicMediaPage(userId, options)).items; }

/**
 * @param {string} status
 * @returns {string}
 */
export function moderationLabel(status) {
	if (status === 'approved') return 'Aprobada';
	if (status === 'pending_review') return 'Pendiente de revision';
	if (status === 'rejected') return 'Rechazada';
	if (status === 'blocked') return 'Bloqueada por seguridad';
	return 'Pendiente';
}

/**
 * @param {string} status
 * @returns {string}
 */
export function moderationClass(status) {
	if (status === 'approved') return 'text-emerald-300';
	if (status === 'pending_review') return 'text-amber-300';
	if (status === 'rejected') return 'text-red-300';
	if (status === 'blocked') return 'text-red-300';
	return 'text-pink-300/60';
}
