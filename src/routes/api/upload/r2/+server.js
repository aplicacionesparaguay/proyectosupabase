import {
	S3Client,
	PutObjectCommand,
	DeleteObjectCommand,
	HeadObjectCommand
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { json } from '@sveltejs/kit';
import {
	R2_ACCOUNT_ID,
	R2_ACCESS_KEY_ID,
	R2_SECRET_ACCESS_KEY,
	R2_PUBLIC_BUCKET,
	R2_PUBLIC_URL
} from '$env/static/private';

/**
 * Carpetas permitidas. El nombre de usuario NUNCA forma parte del path:
 * la autoridad es siempre el user_id de la sesion.
 */
const ALLOWED_FOLDERS = new Set(['avatars', 'covers', 'posts']);

const ALLOWED_CONTENT_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);

/** Limite autoritativo: 10 MB. */
const MAX_FILE_SIZE = 10 * 1024 * 1024;

const r2Client = new S3Client({
	region: 'auto',
	endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
	// El AWS SDK v3 anade `x-amz-checksum-crc32` a las URLs prefirmadas por
	// defecto, y el navegador no puede replicar ese valor. Sin esto, el PUT
	// falla con "The provided upload does not satisfy the specified checksum".
	requestChecksumCalculation: 'WHEN_REQUIRED',
	credentials: {
		accessKeyId: R2_ACCESS_KEY_ID,
		secretAccessKey: R2_SECRET_ACCESS_KEY
	}
});

/**
 * Base publica de R2 sin barra final. Se importa desde `$env/static/private`
 * a proposito: la URL publica se resuelve EXCLUSIVAMENTE en el servidor para
 * que ningun componente dependa de una variable expuesta al bundle del
 * navegador.
 */
const R2_PUBLIC_BASE = R2_PUBLIC_URL.replace(/\/+$/, '');

/**
 * Construye la URL publica de una clave. Solo el servidor la produce.
 * @param {string} key
 * @returns {string}
 */
function buildPublicUrl(key) {
	return `${R2_PUBLIC_BASE}/${key}`;
}

/**
 * @param {string} fileName
 * @returns {string}
 */
function sanitizeFileName(fileName) {
	const safe = fileName.replace(/[^a-zA-Z0-9._-]/g, '_');
	// Sin extension no hay forma de validar el tipo real del objeto.
	return safe.slice(-120);
}

/**
 * @param {string} userId
 * @param {string} fileName
 * @param {string} folder
 * @returns {string}
 */
function generateUploadKey(userId, fileName, folder) {
	return `${folder}/${userId}/${Date.now()}_${sanitizeFileName(fileName)}`;
}

/**
 * Una clave es operable solo si pertenece al usuario autenticado y a la
 * carpeta esperada. Esto es lo que impide borrar o leer archivos ajenos.
 * @param {unknown} key
 * @param {string} userId
 * @param {string} folder
 * @returns {boolean}
 */
function isOwnedKey(key, userId, folder) {
	if (typeof key !== 'string' || key.length === 0 || key.length > 512) return false;

	// Sin traversal: ninguna clave puede contener .. ni salir de la carpeta.
	if (key.includes('..') || key.startsWith('/') || key.includes('\\')) return false;

	return key.startsWith(`${folder}/${userId}/`);
}

/**
 * @param {unknown} value
 * @returns {number}
 */
function parseFileSize(value) {
	const size = typeof value === 'string' ? Number(value) : value;

	if (typeof size !== 'number' || !Number.isFinite(size)) return NaN;

	return Math.floor(size);
}

export async function POST({ request, locals }) {
	const session = await locals.getSession();

	if (!session?.user) {
		return json({ error: 'No autorizado' }, { status: 401 });
	}

	try {
		const {
			fileName,
			contentType,
			folder,
			action = 'upload',
			key: requestedKey,
			fileSize
		} = await request.json();

		if (!ALLOWED_FOLDERS.has(folder)) {
			return json({ error: 'Carpeta no permitida' }, { status: 400 });
		}

		if (!['upload', 'commit', 'delete'].includes(action)) {
			return json({ error: 'Accion no permitida' }, { status: 400 });
		}

		const userId = session.user.id;

		// ------------------------------------------------------------------
		// DELETE
		// ------------------------------------------------------------------
		if (action === 'delete') {
			if (!isOwnedKey(requestedKey, userId, folder)) {
				return json({ error: 'No autorizado para eliminar este archivo' }, { status: 403 });
			}

			const command = new DeleteObjectCommand({
				Bucket: R2_PUBLIC_BUCKET,
				Key: /** @type {string} */ (requestedKey)
			});

			const signedUrl = await getSignedUrl(r2Client, command, {
				expiresIn: 300
			});

			return json({
				signedUrl,
				key: requestedKey,
				action: 'delete'
			});
		}

		// ------------------------------------------------------------------
		// COMMIT: verificacion server-side del objeto ya subido
		// ------------------------------------------------------------------
		if (action === 'commit') {
			if (!isOwnedKey(requestedKey, userId, folder)) {
				return json({ error: 'Clave no autorizada' }, { status: 403 });
			}

			if (contentType && !ALLOWED_CONTENT_TYPES.has(contentType)) {
				return json({ error: 'Tipo de archivo no permitido' }, { status: 400 });
			}

			/** @type {import('@aws-sdk/client-s3').HeadObjectCommandOutput} */
			let head;

			try {
				head = await r2Client.send(
					new HeadObjectCommand({
						Bucket: R2_PUBLIC_BUCKET,
						Key: /** @type {string} */ (requestedKey)
					})
				);
			} catch {
				return json({ error: 'No se pudo verificar el archivo subido' }, { status: 400 });
			}

			const problems = [];

			const actualSize = head.ContentLength ?? 0;

			if (actualSize <= 0) {
				problems.push('el archivo esta vacio');
			} else if (actualSize > MAX_FILE_SIZE) {
				problems.push('el archivo supera los 10 MB');
			}

			const actualType = head.ContentType ?? '';

			if (!ALLOWED_CONTENT_TYPES.has(actualType)) {
				problems.push(`el tipo real (${actualType || 'desconocido'}) no esta permitido`);
			} else if (contentType && actualType !== contentType) {
				problems.push('el tipo real no coincide con el declarado');
			}

			if (problems.length > 0) {
				// El objeto es invalido: se elimina y no se devuelve URL publica.
				await r2Client.send(
					new DeleteObjectCommand({
						Bucket: R2_PUBLIC_BUCKET,
						Key: /** @type {string} */ (requestedKey)
					})
				);

				return json({ error: `Archivo rechazado: ${problems.join(', ')}.` }, { status: 400 });
			}

			return json({
				publicUrl: buildPublicUrl(/** @type {string} */ (requestedKey)),
				key: requestedKey,
				byteSize: actualSize,
				contentType: actualType,
				action: 'commit'
			});
		}

		// ------------------------------------------------------------------
		// UPLOAD
		// ------------------------------------------------------------------
		if (!fileName || typeof fileName !== 'string') {
			return json({ error: 'fileName es requerido' }, { status: 400 });
		}

		if (!contentType || typeof contentType !== 'string') {
			return json({ error: 'contentType es requerido' }, { status: 400 });
		}

		if (!ALLOWED_CONTENT_TYPES.has(contentType)) {
			return json({ error: 'Tipo de archivo no permitido' }, { status: 400 });
		}

		const declaredSize = parseFileSize(fileSize);

		if (Number.isNaN(declaredSize)) {
			return json({ error: 'fileSize es requerido' }, { status: 400 });
		}

		if (declaredSize <= 0) {
			return json({ error: 'El archivo esta vacio' }, { status: 400 });
		}

		// Rechazo temprano. La comprobacion que manda es el commit con HeadObject,
		// porque el cliente puede falsear este numero.
		if (declaredSize > MAX_FILE_SIZE) {
			return json({ error: 'El archivo supera los 10 MB' }, { status: 413 });
		}

		const key = generateUploadKey(userId, fileName, folder);

		// Sin Metadata ni ContentLength en la firma: si se incluyen, el
		// navegador tendria que replicar esas cabeceras o la firma no cuadra.
		// La verificacion real se hace en el commit con HeadObject.
		const command = new PutObjectCommand({
			Bucket: R2_PUBLIC_BUCKET,
			Key: key,
			ContentType: contentType
		});

		const signedUrl = await getSignedUrl(r2Client, command, {
			expiresIn: 300
		});

		return json({
			signedUrl,
			key,
			maxFileSize: MAX_FILE_SIZE,
			action: 'upload'
		});
	} catch (error) {
		console.error('R2 presigned URL error:', error);

		return json({ error: 'Error generando URL prefirmada' }, { status: 500 });
	}
}
