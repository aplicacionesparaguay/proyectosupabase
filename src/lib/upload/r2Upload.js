/**
 * Cliente de subida a Cloudflare R2 mediante URLs prefirmadas.
 *
 * Avatar/portada: intent opaco -> PUT a staging privado -> commit servidor.
 * El servidor valida tamano y tipo antes de firmar, y vuelve a
 * decodificar el objeto y elimina EXIF en `commit`. Solo tras
 * ese commit se considera el archivo subido: nunca se marca como completo
 * antes de la confirmacion real.
 *
 * Las claves las genera el servidor. El cliente no elige ruta ni nombre, y
 * nunca recibe una credencial de R2: solo recibe URLs prefirmadas de vida corta.
 */

/** Limites por tipo. Deben coincidir con los del endpoint (que es la autoridad). */
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
export const MAX_VIDEO_BYTES = 100 * 1024 * 1024;

/** Maximo de archivos por tanda. */
export const MAX_FILES_PER_BATCH = 10;

/** Carpetas permitidas. Deben coincidir con ALLOWED_FOLDERS del endpoint. */
export const R2_FOLDERS = Object.freeze({
	avatar: 'avatars',
	cover: 'covers',
	post: 'posts'
});

/**
 * Tipos aceptados. HEIC, MOV y AVI se rechazan: no hay soporte real de
 * decodificacion en navegador, asi que se avisa antes de subir.
 *
 * @type {ReadonlySet<string>}
 */
const ALLOWED_CONTENT_TYPES = new Set([
	'image/jpeg',
	'image/png',
	'image/webp'
]);

/** Extensiones aceptadas por cada tipo, para validar el nombre del archivo. */
const EXTENSION_BY_TYPE = Object.freeze({
	'image/jpeg': ['.jpg', '.jpeg'],
	'image/png': ['.png'],
	'image/webp': ['.webp'],
	'image/gif': ['.gif'],
	'video/mp4': ['.mp4'],
	'video/webm': ['.webm']
});

/**
 * @param {string | null | undefined} contentType
 * @returns {boolean}
 */
export function isVideoType(contentType) {
	return typeof contentType === 'string' && contentType.startsWith('video/');
}

/**
 * Limite de tamano que aplica a un tipo de archivo.
 * @param {string | null | undefined} contentType
 * @returns {number}
 */
export function maxBytesFor(contentType) {
	return isVideoType(contentType) ? MAX_VIDEO_BYTES : MAX_IMAGE_BYTES;
}

/**
 * @param {number} bytes
 * @returns {string}
 */
function toMb(bytes) {
	return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * Valida en el cliente lo que el servidor volvera a validar. Sirve para dar
 * feedback inmediato, no como seguridad: el cliente puede falsear cualquiera de
 * estos datos y el servidor los ignora.
 *
 * @param {File} file
 * @returns {string} mensaje de error, o cadena vacia si el archivo es valido
 */
export function validateMediaFile(file) {
	if (!ALLOWED_CONTENT_TYPES.has(file.type)) {
		const isHeic = /\.hei[cf]$/i.test(file.name);
		const isMov = /\.mov$/i.test(file.name);
		const isAvi = /\.avi$/i.test(file.name);

		if (isHeic) return 'HEIC no es compatible con los navegadores. Exporta la foto a JPG o PNG.';
		if (isMov) return 'MOV no se reproduce en el navegador. Usa MP4 o WebM.';
		if (isAvi) return 'AVI no se reproduce en el navegador. Usa MP4 o WebM.';

		return 'Solo se permiten fotos estaticas JPG, PNG o WebP.';
	}

	// La extension debe concordar con el MIME declarado: evita subir un
	// `.txt` renombrado a `.jpg` con tipo de imagen.
	const allowedExt = /** @type {Record<string, string[]>} */ (EXTENSION_BY_TYPE)[file.type] ?? [];
	const name = file.name.toLowerCase();
	if (!allowedExt.some((/** @type {string} */ ext) => name.endsWith(ext))) {
		return `La extension del archivo no coincide con su tipo (${file.type}).`;
	}

	if (file.size <= 0) {
		return 'El archivo esta vacio.';
	}

	const limit = maxBytesFor(file.type);
	if (file.size > limit) {
		return `El archivo pesa ${toMb(file.size)}. El maximo para ${isVideoType(file.type) ? 'video' : 'imagen'} es ${toMb(limit)}.`;
	}

	return '';
}

/**
 * @typedef {Object} UploadResult
 * @property {string} key identificador opaco del intento confirmado
 * @property {number} byteSize tamano verificado por el servidor
 * @property {string} contentType tipo verificado por el servidor
 * @property {boolean} isVideo
 * @property {'public' | 'private'} bucket bucket donde quedo el objeto
 * @property {string | null} publicUrl URL permanente solo para recursos publicos; null en galeria
 */

/**
 * Sube un archivo a R2.
 *
 * @param {File} file
 * @param {string} folder una de R2_FOLDERS
 * @param {{ onProgress?: (percent: number) => void, signal?: AbortSignal, visibility?: string }} [options]
 * @returns {Promise<UploadResult>}
 */
export async function uploadMedia(file, folder, options = {}) {
	const { onProgress, signal, visibility = 'privado' } = options;

	const clientError = validateMediaFile(file);
	if (clientError) throw new Error(clientError);

	if (signal?.aborted) throw new Error('Subida cancelada');

	const { signedUrl, key } = /** @type {{ signedUrl: string, key: string }} */ (
		await requestApi({
			action: 'upload',
			folder,
			fileName: file.name,
			contentType: file.type,
			fileSize: file.size,
			visibility
		})
	);

	if (!signedUrl || !key) {
		throw new Error('El servidor no devolvio una URL de subida valida.');
	}

	await putObject(/** @type {string} */ (signedUrl), file, onProgress, signal);

	// El commit es la confirmacion real: el servidor comprueba el objeto y
	// devuelve sus metadatos. Un archivo no esta subido hasta que esto pasa.
	const commit = /** @type {{
		key: string,
		byteSize: number,
		contentType: string,
		isVideo: boolean,
		bucket: 'public' | 'private',
		publicUrl: string | null
	}} */ (await requestApi({ action: 'commit', folder, key, contentType: file.type, visibility }));

	onProgress?.(100);

	return {
		key: commit.key ?? key,
		byteSize: commit.byteSize,
		contentType: commit.contentType,
		isVideo: commit.isVideo,
		bucket: commit.bucket,
		publicUrl: commit.publicUrl
	};
}

/**
 * Pide una URL de lectura de corta duracion para un archivo propio.
 *
 * @param {string} key
 * @param {string} folder
 * @returns {Promise<string>}
 */
export async function signMediaUrl(key, folder) {
	const result = await requestApi({ action: 'sign', folder, key });

	if (!result.url) throw new Error('No se pudo generar la URL de lectura.');

	return /** @type {string} */ (result.url);
}

/**
 * Elimina una portada del perfil. El borrado ocurre en el servidor.
 * @param {string} bannerId
 * @returns {Promise<{ ok: boolean, message?: string, retryable?: boolean }>}
 */
export async function deleteCoverPhoto(bannerId) {
	if (!bannerId) return { ok: false, message: 'Falta el identificador de la portada.' };

	try {
		const response = await fetch('/api/media/delete-cover', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ banner_id: bannerId })
		});

		const result = await response.json().catch(() => ({}));

		if (!response.ok) {
			return {
				ok: false,
				message: result?.error || `No se pudo eliminar la portada (${response.status}).`,
				retryable: Boolean(result?.reintentable)
			};
		}

		return { ok: true };
	} catch {
		return { ok: false, message: 'No se pudo contactar con el servidor.', retryable: true };
	}
}

/**
 * Descarta un objeto recien subido cuyo registro en la base de datos fallo.
 *
 * Es una operacion de limpieza, no de borrado de galeria: el archivo nunca
 * llego a estar registrado, asi que no hay fila que consultar. Aun asi exige
 * sesion y el servidor comprueba que la clave pertenezca a quien la envia.
 *
 * @param {string} key
 * @returns {Promise<boolean>}
 */
export async function discardUnregisteredObject(key) {
	if (!key) return false;

	try {
		await requestApi({ action: 'discard', folder: 'posts', key });
		return true;
	} catch {
		return false;
	}
}

/**
 * Elimina un archivo de la galeria.
 *
 * El borrado lo hace el servidor (`/api/media/delete`), no el navegador. La
 * razon es doble: el DELETE directo contra R2 falla por CORS porque el bucket
 * privado no necesita permitirlo, y ademas el servidor puede comprobar que el
 * archivo es de esta usuaria antes de tocar nada.
 *
 * Acepta el identificador de la fila, no la clave del objeto: el cliente no
 * decide que se borra.
 *
 * @param {string} photoId id de la fila en `user_photos`
 * @returns {Promise<{ ok: boolean, message?: string, retryable?: boolean }>}
 */
export async function deleteGalleryPhoto(photoId) {
	if (!photoId) return { ok: false, message: 'Falta el identificador del archivo.' };

	try {
		const response = await fetch('/api/media/delete', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ photo_id: photoId })
		});

		const result = await response.json().catch(() => ({}));

		if (!response.ok) {
			return {
				ok: false,
				message: result?.error || `No se pudo eliminar (${response.status}).`,
				retryable: Boolean(result?.reintentable)
			};
		}

		return { ok: true };
	} catch {
		return {
			ok: false,
			message: 'No se pudo contactar con el servidor.',
			retryable: true
		};
	}
}

/**
 * Habla con el endpoint de subida.
 * @param {Record<string, unknown>} payload
 * @returns {Promise<Record<string, any>>}
 */
async function requestApi(payload) {
	const response = await fetch('/api/upload/r2', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify(payload)
	});

	let result = /** @type {Record<string, any>} */ ({});

	try {
		result = await response.json();
	} catch {
		if (!response.ok) throw new Error(`Error del servidor (${response.status}).`);
	}

	if (!response.ok) {
		throw new Error(result?.error || `Error del servidor (${response.status}).`);
	}

	return result;
}

/**
 * PUT a R2 con progreso real y soporte de cancelacion.
 *
 * @param {string} url
 * @param {File} file
 * @param {((percent: number) => void) | undefined} onProgress
 * @param {AbortSignal | undefined} signal
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

		xhr.upload.addEventListener('progress', (e) => {
			// Sin `lengthComputable` no hay porcentaje real que mostrar: es
			// preferible Callbacks vacios que inventar una barra de progreso.
			if (e.lengthComputable && e.total > 0) {
				onProgress?.(Math.round((e.loaded / e.total) * 100));
			}
		});

		xhr.addEventListener('load', () => {
			clean();
			if (xhr.status >= 200 && xhr.status < 300) {
				resolve();
			} else {
				reject(new Error(`Error subiendo a R2 (${xhr.status}).`));
			}
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
 * Wrapper de compatibilidad: mantiene el nombre previo para no romper los
 * componentes que ya lo usan (avatar y portada).
 *
 * @param {File} file
 * @param {string} folder
 * @param {{ onProgress?: (percent: number) => void }} [options]
 * @returns {Promise<{ key: string, publicUrl: string }>}
 */
export async function uploadToR2(file, folder, options = {}) {
	const result = await uploadMedia(file, folder, options);

	// En recursos publicos el commit devuelve la URL permanente; en la galeria
	// privada devuelve null y habria que firmarla. Se mantiene el campo por
	// compatibilidad con los componentes que lo consumen.
	return { key: result.key, publicUrl: result.publicUrl ?? '' };
}

/**
 * @param {File} file
 * @returns {string} mensaje de error, o cadena vacia
 */
export function validateImageFile(file) {
	return validateMediaFile(file);
}

/**
 * Limite historico. Se mantiene exportado porque otros componentes lo usan
 * todavia; el valor autoritativo sale del endpoint.
 * @deprecated Usar `maxBytesFor`.
 */
export const MAX_UPLOAD_BYTES = MAX_IMAGE_BYTES;
