// src/lib/server/r2.js
// Cloudflare R2: SOLO se importa desde el servidor.
// Las claves secretas nunca se exponen al navegador.
import { env } from '$env/dynamic/private';
import {
	S3Client,
	PutObjectCommand,
	GetObjectCommand,
	DeleteObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

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

function getClient() {
	assertConfig();
	if (!client) {
		client = new S3Client({
			region: 'auto',
			endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
			credentials: {
				accessKeyId: /** @type {string} */ (R2_ACCESS_KEY_ID),
				secretAccessKey: /** @type {string} */ (R2_SECRET_ACCESS_KEY),
			},
		});
	}
	return client;
}

/** @param {'public'|'private'} bucket */
function bucketName(bucket) {
	return bucket === 'private' ? R2_PRIVATE_BUCKET : R2_PUBLIC_BUCKET;
}

/**
 * URL firmada para subir un objeto (el navegador sube directo a R2).
 * @param {string} key
 * @param {'public'|'private'} bucket
 * @param {string} contentType
 * @param {number} expiresIn segundos
 */
export async function createPresignedUpload(key, bucket = 'public', contentType = 'application/octet-stream', expiresIn = 3600) {
	const command = new PutObjectCommand({
		Bucket: bucketName(bucket),
		Key: key,
		ContentType: contentType,
	});
	return getSignedUrl(/** @type {any} */ (getClient()), command, { expiresIn });
}

/**
 * URL firmada para leer un objeto (contenido privado del paywall).
 * @param {string} key
 * @param {'public'|'private'} bucket
 * @param {number} expiresIn segundos
 */
export async function createPresignedDownload(key, bucket = 'private', expiresIn = 3600) {
	const command = new GetObjectCommand({ Bucket: bucketName(bucket), Key: key });
	return getSignedUrl(/** @type {any} */ (getClient()), command, { expiresIn });
}

/**
 * Elimina un objeto de R2.
 * @param {string} key
 * @param {'public'|'private'} bucket
 */
export async function deleteObject(key, bucket = 'public') {
	const command = new DeleteObjectCommand({ Bucket: bucketName(bucket), Key: key });
	return getClient().send(command);
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
