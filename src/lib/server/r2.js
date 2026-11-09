// src/lib/server/r2.js
// Cloudflare R2: SOLO se importa desde el servidor.
// Las claves secretas nunca se exponen al navegador.
import { env } from '$env/dynamic/private';
import {
	S3Client,
	PutObjectCommand,
	GetObjectCommand,
	DeleteObjectCommand,
	HeadObjectCommand,
	CopyObjectCommand
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { R2_CLIENT_OPTIONS } from '$lib/media/r2Config';

const R2_ACCOUNT_ID = env.R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = env.R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = env.R2_SECRET_ACCESS_KEY;
export const R2_PUBLIC_BUCKET = env.R2_PUBLIC_BUCKET || 'aguaenlaboca-public';

export const R2_PRIVATE_BUCKET = env.R2_PRIVATE_BUCKET || 'aguaenlaboca-private';
export const R2_PUBLIC_URL = env.R2_PUBLIC_URL || '';

/** @type {import('@aws-sdk/client-s3').S3Client | null} */
let client = null;

function assertConfig() {
	if (!R2_ACCOUNT_ID || !R2_ACCESS_KEY_ID || !R2_SECRET_ACCESS_KEY) {
		throw new Error(
			'Faltan credenciales de R2 en el servidor. Configura R2_ACCOUNT_ID, R2_ACCESS_KEY_ID y R2_SECRET_ACCESS_KEY.'
		);
	}
}

export function getR2Client() {
	assertConfig();
	if (!client) {
		client = new S3Client({
			...R2_CLIENT_OPTIONS,
			endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
			// Igual que el endpoint legado: evita que el navegador tenga que
			// reproducir un checksum que AWS SDK anade a la URL prefirmada.
			requestChecksumCalculation: 'WHEN_REQUIRED',
			credentials: {
				accessKeyId: /** @type {string} */ (R2_ACCESS_KEY_ID),
				secretAccessKey: /** @type {string} */ (R2_SECRET_ACCESS_KEY)
			}
		});
	}
	return client;
}

/** @param {'public'|'private'} bucket */
function bucketName(bucket) {
	if (bucket === 'private') return R2_PRIVATE_BUCKET;
	if (bucket === 'public') return R2_PUBLIC_BUCKET;
	throw new Error('Bucket no permitido.');
}

/**
 * URL firmada para subir un objeto (el navegador sube directo a R2).
 * @param {string} key
 * @param {'public'|'private'} bucket
 * @param {string} contentType
 * @param {number} expiresIn segundos
 * @param {boolean} writeOnce
 * @param {number} [contentLength]
 */
export async function createPresignedUpload(
	key,
	bucket = 'public',
	contentType = 'application/octet-stream',
	expiresIn = 900,
	writeOnce = false,
	contentLength
) {
	const command = new PutObjectCommand({
		Bucket: bucketName(bucket),
		Key: key,
		ContentType: contentType,
		...(contentLength !== undefined ? { ContentLength: contentLength } : {}),
		...(writeOnce ? { IfNoneMatch: '*' } : {})
	});
	return getSignedUrl(getR2Client(), command, {
		expiresIn,
		signableHeaders: new Set(['content-type', ...(writeOnce ? ['if-none-match'] : []), ...(contentLength !== undefined ? ['content-length'] : [])])
	});
}

/**
 * URL firmada para leer un objeto (contenido privado del paywall).
 * @param {string} key
 * @param {'public'|'private'} bucket
 * @param {number} expiresIn segundos
 */
export async function createPresignedDownload(key, bucket = 'private', expiresIn = 300) {
	const command = new GetObjectCommand({
		Bucket: bucketName(bucket), Key: key, ResponseCacheControl: 'private, no-store'
	});
	return getSignedUrl(getR2Client(), command, { expiresIn });
}

/**
 * Elimina un objeto de R2.
 * @param {string} key
 * @param {'public'|'private'} bucket
 */
export async function deleteObject(key, bucket = 'public') {
	const command = new DeleteObjectCommand({ Bucket: bucketName(bucket), Key: key });
	return getR2Client().send(command, { abortSignal: AbortSignal.timeout(30000) });
}

/**
 * URL pública de un objeto del bucket público.
 * @param {string} key
 */
export function publicUrl(key) {
	if (!R2_PUBLIC_URL) {
		throw new Error('R2_PUBLIC_URL no está configurada en el servidor.');
	}
	return `${R2_PUBLIC_URL.replace(/\/+$/, '')}/${key}`;
}

export class ObjectTooLargeError extends Error {
	constructor(message = 'El objeto supera el tamano maximo permitido.') {
		super(message);
		this.name = 'ObjectTooLargeError';
	}
}

/**
 * Metadatos del objeto (tamano, tipo y ETag) sin descargarlo.
 * @param {string} key
 * @param {'public'|'private'} bucket
 */
export async function headObject(key, bucket = 'private') {
	const command = new HeadObjectCommand({ Bucket: bucketName(bucket), Key: key });
	return getR2Client().send(command, { abortSignal: AbortSignal.timeout(30000) });
}

/**
 * Descarga un objeto completo con un limite duro de bytes. El limite se
 * comprueba antes (HeadObject) y durante la lectura, porque Content-Length
 * puede faltar o mentir.
 *
 * @param {string} key
 * @param {number} maxBytes
 * @param {'public'|'private'} bucket
 * @returns {Promise<Buffer>}
 */
export async function getObjectBytes(key, maxBytes, bucket = 'private') {
	const head = await headObject(key, bucket);

	if (typeof head.ContentLength === 'number' && head.ContentLength > maxBytes) {
		throw new ObjectTooLargeError();
	}

	const response = await getR2Client().send(
		new GetObjectCommand({ Bucket: bucketName(bucket), Key: key, IfMatch: head.ETag }),
		{ abortSignal: AbortSignal.timeout(30000) }
	);

	if (!response.Body) {
		throw new Error('El objeto no tiene contenido.');
	}

	/** @type {Buffer[]} */
	const chunks = [];
	let total = 0;

	const body = /** @type {AsyncIterable<Uint8Array>} */ (response.Body);

	for await (const chunk of body) {
		const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
		total += buffer.length;

		if (total > maxBytes) {
			throw new ObjectTooLargeError();
		}

		chunks.push(buffer);
	}

	return Buffer.concat(chunks, total);
}

/**
 * Copia un objeto dentro del mismo bucket sin descargarlo al servidor.
 * @param {string} sourceKey
 * @param {string} targetKey
 * @param {string} contentType
 * @param {'public'|'private'} bucket
 */
export async function copyObject(sourceKey, targetKey, contentType, bucket = 'private') {
	const bucketValue = bucketName(bucket);

	const command = new CopyObjectCommand({
		Bucket: bucketValue,
		CopySource: `/${bucketValue}/${sourceKey}`,
		Key: targetKey,
		ContentType: contentType,
		MetadataDirective: 'REPLACE'
	});

	return getR2Client().send(command);
}

/**
 * Sube bytes generados por el servidor (copias protegidas y miniaturas).
 * @param {string} key
 * @param {Buffer} body
 * @param {string} contentType
 * @param {'public'|'private'} bucket
 */
export async function putObjectBytes(key, body, contentType, bucket = 'private') {
	const command = new PutObjectCommand({
		Bucket: bucketName(bucket),
		Key: key,
		Body: body,
		ContentType: contentType,
		CacheControl: 'private, no-store'
	});

	return getR2Client().send(command, { abortSignal: AbortSignal.timeout(30000) });
}
