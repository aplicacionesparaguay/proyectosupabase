import { createHash } from 'node:crypto';
import sharp from 'sharp';
import { json } from '@sveltejs/kit';
import { MAX_PHOTO_PIXELS } from '$lib/media/constants';

const FORMAT_TO_MIME = Object.freeze({
	jpeg: 'image/jpeg',
	png: 'image/png',
	webp: 'image/webp'
});

const SAFE_RPC_MESSAGES = Object.freeze({
	'22023': 'Los datos de la peticion no son validos.',
	'23505': 'La operacion ya fue registrada.',
	'23514': 'El estado actual no permite esta operacion.',
	'28000': 'No autenticado.',
	'42501': 'No tienes permisos para esta operacion.',
	'42900': 'Limite de operaciones alcanzado. Intenta mas tarde.',
	'57014': 'La operacion expiro. Intenta de nuevo.',
	'P0002': 'Archivo o intento de subida no encontrado.'
});

const MAX_JSON_BODY_BYTES = 32 * 1024;

/**
 * @param {import('@sveltejs/kit').RequestEvent['locals']} locals
 * @returns {Response | null}
 */
export function authFailure(locals) {
	if (locals.auth?.status === 'error') {
		return json(
			{ error: 'La verificacion de sesion no esta disponible temporalmente.' },
			{ status: 503 }
		);
	}

	if (locals.auth?.status !== 'verified' || !locals.auth.userId || !locals.user || locals.user.id !== locals.auth.userId) {
		return json({ error: 'No autorizado' }, { status: 401 });
	}

	return null;
}

/**
 * @param {import('@sveltejs/kit').RequestEvent['locals']} locals
 * @returns {string}
 */
export function verifiedUserId(locals) {
	return /** @type {string} */ (locals.auth.userId);
}

/**
 * @param {Request} request
 * @returns {Promise<Record<string, unknown> | null>}
 */
export async function readJson(request) {
	const declaredLength = Number(request.headers.get('content-length'));

	if (Number.isFinite(declaredLength) && declaredLength > MAX_JSON_BODY_BYTES) {
		return null;
	}

	const body = request.body;
	if (!body) return null;

	try {
		const reader = body.getReader();
		const chunks = [];
		let total = 0;

		for (;;) {
			const { done, value } = await reader.read();
			if (done) break;

			total += value.byteLength;

			if (total > MAX_JSON_BODY_BYTES) {
				try {
					await reader.cancel();
				} catch {
					// El cuerpo ya se cerro.
				}
				return null;
			}

			chunks.push(value);
		}

		const text = new TextDecoder().decode(Buffer.concat(chunks.map((chunk) => Buffer.from(chunk))));
		const value = JSON.parse(text);

		return value && typeof value === 'object' && !Array.isArray(value) ? value : null;
	} catch {
		return null;
	}
}

/**
 * @param {unknown} value
 * @returns {boolean}
 */
export function isUuid(value) {
	return (
		typeof value === 'string' &&
		/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
	);
}

/**
 * @param {unknown} value
 * @param {number} maxLength
 * @returns {string}
 */
export function cleanText(value, maxLength) {
	if (typeof value !== 'string') return '';
	return value.trim().slice(0, maxLength);
}

/**
 * @param {unknown} error
 * @returns {string | null}
 */
export function safeRpcMessage(error) {
	if (!error || typeof error !== 'object') return null;
	const code = /** @type {{ code?: unknown }} */ (error).code;
	return typeof code === 'string' && Object.hasOwn(SAFE_RPC_MESSAGES, code)
		? SAFE_RPC_MESSAGES[/** @type {keyof typeof SAFE_RPC_MESSAGES} */ (code)] ?? null
		: null;
}

/**
 * @param {bigint | number | null | undefined} value
 * @returns {number}
 */
export function toNumber(value) {
	if (typeof value === 'number') return value;
	if (typeof value === 'string') return Number(value);
	return Number(value ?? 0);
}

/**
 * Valida que el buffer sea una imagen decodificable, estatica y del tipo
 * declarado, y devuelve su hash y dimensiones normalizadas.
 *
 * `sharp(...).rotate()` aplica la orientacion EXIF y produce las dimensiones
 * que vera la persona. El worker usa la misma normalizacion, de modo que las
 * coordenadas de los rostros y el pixelado trabajan sobre la misma geometria.
 *
 * @param {Buffer} buffer
 * @param {string} expectedMime
 * @returns {Promise<{ sha256: string, width: number, height: number, mimeType: string }>}
 */
export async function inspectPhoto(buffer, expectedMime) {
	if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
		throw new Error('La imagen esta vacia.');
	}

	const metadata = await sharp(buffer, {
		limitInputPixels: MAX_PHOTO_PIXELS,
		failOn: 'warning',
		animated: true
	}).metadata();

	if (!metadata.format || !(metadata.format in FORMAT_TO_MIME)) {
		throw new Error('El archivo no es una imagen JPEG, PNG o WebP valida.');
	}

	if ((metadata.pages ?? 1) > 1) {
		throw new Error('No se permiten imagenes animadas.');
	}

	const actualMime = FORMAT_TO_MIME[/** @type {keyof typeof FORMAT_TO_MIME} */ (metadata.format)];

	if (actualMime !== expectedMime) {
		throw new Error('El contenido real no coincide con el tipo declarado.');
	}

	const normalized = await sharp(buffer, {
		limitInputPixels: MAX_PHOTO_PIXELS,
		failOn: 'warning'
	})
		.rotate()
		.toColourspace('srgb')
		.toBuffer({ resolveWithObject: true });

	const { width, height } = normalized.info;

	if (!width || !height || width * height > MAX_PHOTO_PIXELS) {
		throw new Error('La imagen supera el limite de pixeles permitido.');
	}

	return {
		sha256: createHash('sha256').update(buffer).digest('hex'),
		width,
		height,
		mimeType: actualMime
	};
}
