/**
 * Cliente de subida a Cloudflare R2 mediante URLs prefirmadas.
 *
 * La URL publica NUNCA se construye en el navegador: el endpoint
 * `/api/upload/r2` la calcula en el servidor con `R2_PUBLIC_URL` y la
 * devuelve ya formed. Aqui solo se consume `result.publicUrl`.
 *
 * El limite de 10 MB se valida en el cliente para dar feedback rapido, pero
 * la autoridad es el servidor: `POST /api/upload/r2` valida `fileSize` antes de
 * firmar y la accion `commit` verifica el objeto real en R2 con HeadObject
 * (tamano + Content-Type) y lo borra si no cumple.
 */

/** Limite autoritativo de 10 MB, replicado desde el endpoint. */
export const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

/** Carpetas permitidas. Deben coincidir con ALLOWED_FOLDERS del endpoint. */
export const R2_FOLDERS = Object.freeze({
	avatar: 'avatars',
	cover: 'covers',
	post: 'posts'
});

/** @type {ReadonlySet<string>} */
const IMAGE_CONTENT_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);

/**
 * Formatea bytes en MB para los mensajes de error.
 * @param {number} bytes
 * @returns {string}
 */
function toMb(bytes) {
	return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * Valida en el cliente lo que el servidor volvera a validar. Sirve para UX,
 * no como seguridad: un cliente puede falsear cualquiera de estos valores.
 * @param {File} file
 * @returns {string} mensaje de error, o cadena vacia si es valido
 */
export function validateImageFile(file) {
	if (!IMAGE_CONTENT_TYPES.has(file.type)) {
		return 'Solo se permiten imagenes JPG, PNG, WEBP o GIF.';
	}

	if (file.size <= 0) {
		return 'El archivo esta vacio.';
	}

	if (file.size > MAX_UPLOAD_BYTES) {
		return `El archivo pesa ${toMb(file.size)}. El maximo permitido es ${toMb(MAX_UPLOAD_BYTES)}.`;
	}

	return '';
}

/**
 * @typedef {Object} UploadResult
 * @property {string} key clave del objeto dentro del bucket
 * @property {string} publicUrl URL publica calculada por el servidor
 */

/**
 * Sube un archivo a R2: pide la URL prefirmada, hace el PUT y confirma la
 * subida contra el servidor.
 *
 * @param {File} file
 * @param {string} folder una de R2_FOLDERS
 * @param {{ onProgress?: (percent: number) => void }} [options]
 * @returns {Promise<UploadResult>}
 */
export async function uploadToR2(file, folder, options = {}) {
	const { onProgress } = options;

	const clientError = validateImageFile(file);
	if (clientError) throw new Error(clientError);

	const { signedUrl, key } = await requestPresignedUrl({
		action: 'upload',
		folder,
		fileName: file.name,
		contentType: file.type,
		fileSize: file.size
	});

	if (!signedUrl || !key) {
		throw new Error('Respuesta invalida del servidor al pedir la URL de subida.');
	}

	// PUT a la URL prefirmada tal cual la devuelve el servidor. No se le
	// anaden parametros: cualquier query extra invalidaria la firma.
	await putObject(/** @type {string} */ (signedUrl), file, onProgress);

	// Commit: el servidor comprueba el objeto real en R2 (HeadObject) y solo
	// entonces devuelve la URL publica autorizada.
	const { publicUrl } = await requestPresignedUrl({
		action: 'commit',
		folder,
		key,
		contentType: file.type
	});

	onProgress?.(100);

	return { key, publicUrl };
}

/**
 * Pide al endpoint una URL prefirmada o el resultado de un commit.
 * @param {Record<string, unknown>} payload
 * @returns {Promise<Record<string, any>>}
 */
async function requestPresignedUrl(payload) {
	const response = await fetch('/api/upload/r2', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify(payload)
	});

	let result = /** @type {Record<string, any>} */ ({});

	try {
		result = await response.json();
	} catch {
		if (!response.ok) {
			throw new Error(`Error del servidor (${response.status}).`);
		}
	}

	if (!response.ok) {
		throw new Error(result?.error || `Error del servidor (${response.status}).`);
	}

	return result;
}

/**
 * PUT a R2 con progreso.
 * @param {string} url
 * @param {File} file
 * @param {((percent: number) => void) | undefined} onProgress
 * @returns {Promise<void>}
 */
function putObject(url, file, onProgress) {
	return new Promise((resolve, reject) => {
		const xhr = new XMLHttpRequest();

		xhr.upload.addEventListener('progress', (e) => {
			if (e.lengthComputable) {
				onProgress?.(Math.round((e.loaded / e.total) * 100));
			}
		});

		xhr.addEventListener('load', () => {
			if (xhr.status >= 200 && xhr.status < 300) {
				resolve();
			} else {
				reject(new Error(`Error subiendo a R2: ${xhr.status} ${xhr.statusText}`));
			}
		});

		xhr.addEventListener('error', () => reject(new Error('Error de red subiendo a R2')));
		xhr.addEventListener('abort', () => reject(new Error('Subida cancelada')));

		xhr.open('PUT', url);
		xhr.setRequestHeader('Content-Type', file.type);
		xhr.send(file);
	});
}

/**
 * Solicita la URL prefirmada de borrado. El servidor valida que la clave
 * pertenezca al usuario y a la carpeta; nunca se borra nada sin esa validacion.
 *
 * @param {string} key
 * @param {string} folder
 * @returns {Promise<boolean>} true si R2 confirmo el borrado
 */
export async function deleteR2Object(key, folder) {
	if (!key) return false;

	try {
		const response = await fetch('/api/upload/r2', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ action: 'delete', folder, key })
		});

		if (!response.ok) return false;

		const result = await response.json();
		const signedUrl = result?.signedUrl;

		if (!signedUrl) return false;

		await fetch(signedUrl, { method: 'DELETE' });

		return true;
	} catch {
		return false;
	}
}
