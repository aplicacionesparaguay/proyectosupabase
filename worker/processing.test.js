import { readFile } from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';
import { beforeAll, describe, expect, it } from 'vitest';
import {
	createThumbnail,
	decodeImage,
	detectFaces,
	loadModels,
	protectAndVerify
} from './processing.js';

const modelDir = path.resolve('node_modules/@vladmandic/face-api/model');
const samplePath = path.resolve('node_modules/@vladmandic/face-api/demo/sample1.jpg');

/** @type {Awaited<ReturnType<typeof decodeImage>>} */
let image;
/** @type {Awaited<ReturnType<typeof detectFaces>>} */
let faces;

beforeAll(async () => {
	await loadModels(modelDir);
	image = await decodeImage(await readFile(samplePath));
	faces = await detectFaces(image.pixels, image.width, image.height);
}, 120000);

describe('procesamiento de fotografias', () => {
	it('decodifica a RGB y detecta rostros', { timeout: 120000 }, () => {
		expect(image.width).toBeGreaterThan(0);
		expect(image.height).toBeGreaterThan(0);
		expect(image.pixels.length).toBe(image.width * image.height * 3);
		expect(faces.length).toBeGreaterThan(0);
	});

	it(
		'protege los rostros con desenfoque y verifica la copia final',
		{ timeout: 120000 },
		async () => {
			const result = await protectAndVerify(image, faces, 'blur', 100);
			const metadata = await sharp(result.protectedBuffer).metadata();

			expect(result.verified).toBe(true);
			expect(result.facesDetected).toBeGreaterThan(0);
			expect(metadata.format).toBe('webp');
			expect(result.protectedBuffer.length).toBeGreaterThan(1000);
		}
	);

	it('genera un thumbnail WebP', { timeout: 120000 }, async () => {
		const result = await protectAndVerify(image, faces, 'blur', 100);
		const thumbnail = await createThumbnail(result.protectedBuffer);
		const metadata = await sharp(thumbnail).metadata();

		expect(metadata.format).toBe('webp');
		expect(metadata.width).toBeLessThanOrEqual(640);
		expect(metadata.height).toBeLessThanOrEqual(640);
		expect(thumbnail.length).toBeGreaterThan(1000);
	});

	it('el pixelado reduce detalle real y pasa la verificacion facial', { timeout: 120000 }, async () => {
		const result = await protectAndVerify(image, faces, 'pixelate', 100);
		expect(result.verified).toBe(true);
		expect(result.facesDetected).toBeGreaterThan(0);
		const decoded = await decodeImage(result.protectedBuffer);
		expect(decoded.pixels.equals(image.pixels)).toBe(false);
		expect(await detectFaces(decoded.pixels, decoded.width, decoded.height)).toHaveLength(0);
	});

	it('normaliza orientacion y elimina EXIF/GPS, ICC y XMP de ambas derivadas', async () => {
		const original = await sharp({ create: { width: 80, height: 40, channels: 3, background: '#447799' } })
			.jpeg().withMetadata({ orientation: 6 }).withExifMerge({
				IFD0: { Artist: 'Dato privado' },
				IFD3: { GPSLatitudeRef: 'N', GPSLatitude: '51/1 30/1 0/1', GPSLongitudeRef: 'W', GPSLongitude: '0/1 7/1 0/1' }
			}).toBuffer();
		expect((await sharp(original).metadata()).exif?.length).toBeGreaterThan(0);
		const normalized = await decodeImage(original);
		expect([normalized.width, normalized.height]).toEqual([40, 80]);
		const result = await protectAndVerify(normalized, [], 'pixelate', 100);
		for (const bytes of [result.protectedBuffer, await createThumbnail(result.protectedBuffer)]) {
			const metadata = await sharp(bytes).metadata();
			expect(metadata.exif).toBeUndefined();
			expect(metadata.icc).toBeUndefined();
			expect(metadata.xmp).toBeUndefined();
		}
	});

	it('una foto sin rostros conserva dimensiones y se verifica', async () => {
		const original = await sharp({ create: { width: 256, height: 128, channels: 3, background: '#778899' } }).png().toBuffer();
		const normalized = await decodeImage(original);
		const boxes = await detectFaces(normalized.pixels, normalized.width, normalized.height);
		expect(boxes).toHaveLength(0);
		const result = await protectAndVerify(normalized, boxes, 'pixelate', 100);
		expect(result).toMatchObject({ verified: true, facesDetected: 0 });
		expect(await sharp(result.protectedBuffer).metadata()).toMatchObject({ width: 256, height: 128 });
	});
});
