import sharp from 'sharp';
import { createRequire } from 'node:module';
import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-backend-wasm';
import * as faceapi from '@vladmandic/face-api/dist/face-api.node-wasm.js';
import { MAX_PHOTO_BYTES, MAX_PHOTO_PIXELS } from '../src/lib/media/constants.js';

const DETECTOR_NAME = 'ssd_mobilenetv1+tiny_face_detector';
const DETECTOR_VERSION = createRequire(import.meta.url)('@vladmandic/face-api/package.json').version;
const DETECTION_MAX_SIDE = 1600;
const MIN_CONFIDENCE = 0.5;
const TINY_INPUT_SIZE = 416;

let modelsLoaded = false;

/**
 * @param {string} modelDir
 */
export async function loadModels(modelDir) {
	if (modelsLoaded) return;

	await tf.setBackend('wasm');
	await tf.ready();
	await Promise.all([
		faceapi.nets.ssdMobilenetv1.loadFromDisk(modelDir),
		faceapi.nets.tinyFaceDetector.loadFromDisk(modelDir)
	]);
	modelsLoaded = true;
}

/**
 * Decodifica, aplica orientacion EXIF y elimina alfa/metadatos. Devuelve los
 * pixeles RGB normalizados que usa tanto la deteccion como la proteccion.
 *
 * @param {Buffer} buffer
 * @param {string} [expectedMime]
 * @returns {Promise<{ pixels: Buffer, width: number, height: number }>}
 */
export async function decodeImage(buffer, expectedMime) {
	if (!Buffer.isBuffer(buffer) || !buffer.length || buffer.length > MAX_PHOTO_BYTES) {
		throw new Error('Tamano de foto invalido.');
	}
	const metadata = await sharp(buffer, { limitInputPixels: MAX_PHOTO_PIXELS, failOn: 'warning', animated: true }).metadata();
	const mime = { jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' }[metadata.format];
	if (!mime || (metadata.pages ?? 1) > 1 || (expectedMime && mime !== expectedMime)) {
		throw new Error('La foto no es estatica o su formato no coincide.');
	}
	const { data, info } = await sharp(buffer, {
		limitInputPixels: MAX_PHOTO_PIXELS,
		failOn: 'warning'
	})
		.rotate()
		.toColourspace('srgb')
		.removeAlpha()
		.raw()
		.toBuffer({ resolveWithObject: true });

	if (info.channels !== 3) {
		throw new Error(`Se esperaban 3 canales y se obtuvieron ${info.channels}.`);
	}

	return { pixels: data, width: info.width, height: info.height };
}

/**
 * @param {Buffer} pixels
 * @param {number} width
 * @param {number} height
 * @returns {Promise<{ pixels: Buffer, width: number, height: number }>}
 */
async function downscaleForDetection(pixels, width, height) {
	const scale = Math.min(1, DETECTION_MAX_SIDE / Math.max(width, height));

	if (scale >= 1) return { pixels, width, height };

	const targetWidth = Math.max(1, Math.round(width * scale));
	const targetHeight = Math.max(1, Math.round(height * scale));

	const { data, info } = await sharp(pixels, {
		raw: { width, height, channels: 3 }
	})
		.resize(targetWidth, targetHeight, { fit: 'fill', kernel: 'lanczos3' })
		.raw()
		.toBuffer({ resolveWithObject: true });

	return { pixels: data, width: info.width, height: info.height };
}

/**
 * @param {Buffer} pixels
 * @param {number} width
 * @param {number} height
 * @returns {Promise<{ x: number, y: number, width: number, height: number, score: number }[]>}
 */
export async function detectFaces(pixels, width, height) {
	const input = await downscaleForDetection(pixels, width, height);
	const scaleX = width / input.width;
	const scaleY = height / input.height;

	const tensor = tf.tensor3d(
		new Uint8Array(input.pixels.buffer, input.pixels.byteOffset, input.pixels.byteLength),
		[input.height, input.width, 3],
		'int32'
	);

	try {
		const ssdDetections = await faceapi.detectAllFaces(
			tensor,
			new faceapi.SsdMobilenetv1Options({
				minConfidence: MIN_CONFIDENCE,
				maxResults: 50
			})
		);

		const tinyDetections = await faceapi.detectAllFaces(
			tensor,
			new faceapi.TinyFaceDetectorOptions({
				inputSize: TINY_INPUT_SIZE,
				scoreThreshold: MIN_CONFIDENCE
			})
		);

		const boxes = [...ssdDetections, ...tinyDetections].map((detection) => ({
			x: detection.box.x * scaleX,
			y: detection.box.y * scaleY,
			width: detection.box.width * scaleX,
			height: detection.box.height * scaleY,
			score: detection.score
		}));

		return mergeBoxes(boxes);
	} finally {
		tensor.dispose();
	}
}

/**
 * Une detecciones del mismo rostro vistas por los dos detectores para no
 * duplicar la proteccion.
 *
 * @param {{ x: number, y: number, width: number, height: number, score: number }[]} boxes
 * @returns {{ x: number, y: number, width: number, height: number, score: number }[]}
 */
function mergeBoxes(boxes) {
	/** @type {{ x: number, y: number, width: number, height: number, score: number }[]} */
	const merged = [];

	for (const box of boxes) {
		const match = merged.find((existing) => {
			const overlapX = Math.max(
				0,
				Math.min(existing.x + existing.width, box.x + box.width) - Math.max(existing.x, box.x)
			);
			const overlapY = Math.max(
				0,
				Math.min(existing.y + existing.height, box.y + box.height) - Math.max(existing.y, box.y)
			);
			const intersection = overlapX * overlapY;
			const union = existing.width * existing.height + box.width * box.height - intersection;
			return union > 0 && intersection / union > 0.3;
		});

		if (!match) {
			merged.push({ ...box });
			continue;
		}

		const left = Math.min(match.x, box.x);
		const top = Math.min(match.y, box.y);
		const right = Math.max(match.x + match.width, box.x + box.width);
		const bottom = Math.max(match.y + match.height, box.y + box.height);

		match.x = left;
		match.y = top;
		match.width = right - left;
		match.height = bottom - top;
		match.score = Math.max(match.score, box.score);
	}

	return merged;
}

/**
 * @param {{ x: number, y: number, width: number, height: number }} box
 * @param {number} imageWidth
 * @param {number} imageHeight
 * @param {number} paddingRatio
 */
function clampBox(box, imageWidth, imageHeight, paddingRatio) {
	const padX = box.width * paddingRatio;
	const padY = box.height * paddingRatio;

	const left = Math.max(0, Math.floor(box.x - padX));
	const top = Math.max(0, Math.floor(box.y - padY));
	const right = Math.min(imageWidth, Math.ceil(box.x + box.width + padX));
	const bottom = Math.min(imageHeight, Math.ceil(box.y + box.height + padY));

	return {
		left,
		top,
		width: Math.max(1, right - left),
		height: Math.max(1, bottom - top)
	};
}

/**
 * @param {Buffer} pixels
 * @param {number} width
 * @param {number} height
 * @param {{ x: number, y: number, width: number, height: number }[]} boxes
 * @param {'pixelate' | 'blur'} mode
 * @param {number} strength
 * @returns {Promise<Buffer>}
 */
async function protectPixels(pixels, width, height, boxes, mode, strength) {
	if (boxes.length === 0) {
		return sharp(pixels, { raw: { width, height, channels: 3 } })
			.webp({ quality: 90, effort: 4 })
			.toBuffer();
	}

	/** @type {import('sharp').OverlayOptions[]} */
	const overlays = [];

	for (const box of boxes) {
		const region = clampBox(box, width, height, 0.32);

		if (mode === 'pixelate') {
			const blockSize = Math.max(
				4,
				Math.round(Math.min(region.width, region.height) * (0.04 + (strength / 100) * 0.12))
			);
			const smallWidth = Math.max(1, Math.floor(region.width / blockSize));
			const smallHeight = Math.max(1, Math.floor(region.height / blockSize));

			// Sharp solo aplica el ultimo resize de una misma cadena. Materializar
			// la reduccion es esencial para que el mosaico destruya detalle real.
			const small = await sharp(pixels, { raw: { width, height, channels: 3 } })
				.extract(region)
				.resize(smallWidth, smallHeight, { fit: 'fill', kernel: 'nearest' })
				.raw()
				.toBuffer();
			const mosaic = await sharp(small, { raw: { width: smallWidth, height: smallHeight, channels: 3 } })
				.resize(region.width, region.height, { fit: 'fill', kernel: 'nearest' })
				.png()
				.toBuffer();

			overlays.push({ input: mosaic, left: region.left, top: region.top });
		} else {
			const sigma = Math.max(
				8,
				Math.round(Math.min(region.width, region.height) * (0.03 + (strength / 100) * 0.1))
			);

			const blurred = await sharp(pixels, { raw: { width, height, channels: 3 } })
				.extract(region)
				.blur(sigma)
				.png()
				.toBuffer();

			overlays.push({ input: blurred, left: region.left, top: region.top });
		}
	}

	return sharp(pixels, { raw: { width, height, channels: 3 } })
		.composite(overlays)
		.webp({ quality: 90, effort: 4 })
		.toBuffer();
}

/**
 * Protege todos los rostros y vuelve a detectar sobre la copia final. Si la
 * verificacion encuentra un rostro, amplia la proteccion y reintenta. La foto
 * nunca se publica si la verificacion no queda limpia.
 *
 * @param {{ pixels: Buffer, width: number, height: number }} normalized
 * @param {{ x: number, y: number, width: number, height: number }[]} initialBoxes
 * @param {'pixelate' | 'blur'} mode
 * @param {number} strength
 * @returns {Promise<{ protectedBuffer: Buffer, facesDetected: number, verified: boolean, mode: 'pixelate' | 'blur', strength: number }>}
 */
export async function protectAndVerify(normalized, initialBoxes, mode, strength) {
	let boxes = [...initialBoxes];
	let currentStrength = Math.min(100, Math.max(1, strength));
	let protectedBuffer = Buffer.alloc(0);

	for (let attempt = 0; attempt < 3; attempt += 1) {
		protectedBuffer = await protectPixels(
			normalized.pixels,
			normalized.width,
			normalized.height,
			boxes,
			mode,
			currentStrength
		);

		const decoded = await sharp(protectedBuffer, {
			limitInputPixels: MAX_PHOTO_PIXELS,
			failOn: 'warning'
		})
			.removeAlpha()
			.raw()
			.toBuffer({ resolveWithObject: true });

		const remaining = await detectFaces(decoded.data, decoded.info.width, decoded.info.height);

		if (remaining.length === 0) {
			return {
				protectedBuffer,
				facesDetected: Math.max(initialBoxes.length, boxes.length),
				verified: true,
				mode,
				strength: currentStrength
			};
		}

		boxes = [...boxes, ...remaining];
		currentStrength = Math.min(100, currentStrength + 20);
	}

	return {
		protectedBuffer,
		facesDetected: Math.max(initialBoxes.length, boxes.length),
		verified: false,
		mode,
		strength: currentStrength
	};
}

/**
 * @param {Buffer} protectedBuffer
 * @returns {Promise<Buffer>}
 */
export async function createThumbnail(protectedBuffer) {
	return sharp(protectedBuffer, {
		limitInputPixels: MAX_PHOTO_PIXELS,
		failOn: 'warning'
	})
		.rotate()
		.resize({ width: 640, height: 640, fit: 'inside', withoutEnlargement: true })
		.webp({ quality: 82, effort: 4 })
		.toBuffer();
}

/** Codifica RGB ya normalizado sin transportar metadatos del archivo fuente. */
export async function encodeProfileImage(normalized) {
	return sharp(normalized.pixels, { raw: { width: normalized.width, height: normalized.height, channels: 3 } })
		.webp({ quality: 90 }).toBuffer();
}

export const detectorInfo = Object.freeze({
	name: DETECTOR_NAME,
	version: DETECTOR_VERSION
});
