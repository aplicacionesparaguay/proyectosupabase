import sharp from 'sharp';
import { describe, expect, it } from 'vitest';
import { cleanText, inspectPhoto, isUuid, readJson, safeRpcMessage } from './media.js';

const USER_ID = '8f3eb06b-510a-439c-bba5-c7ba84e04254';

describe('utilidades de media', () => {
	it('valida UUIDs', () => {
		expect(isUuid(USER_ID)).toBe(true);
		expect(isUuid('no-es-uuid')).toBe(false);
		expect(isUuid(null)).toBe(false);
	});

	it('limpia y recorta texto', () => {
		expect(cleanText('  hola  ', 3)).toBe('hol');
		expect(cleanText('  hola  ', 10)).toBe('hola');
		expect(cleanText(null, 10)).toBe('');
	});

	it('solo expone mensajes RPC conocidos', () => {
		expect(safeRpcMessage({ code: '42501', message: 'originals/clave-interna' })).toBe('No tienes permisos para esta operacion.');
		expect(safeRpcMessage({ code: 'XX000', message: 'detalle interno' })).toBeNull();
		expect(safeRpcMessage({ code: 'constructor' })).toBeNull();
	});

	it('lee JSON valido y limita el tamano del cuerpo', async () => {
		const valid = new Request('http://localhost/api', {
			method: 'POST',
			body: JSON.stringify({ mediaId: USER_ID })
		});
		expect(await readJson(valid)).toEqual({ mediaId: USER_ID });

		const large = new Request('http://localhost/api', {
			method: 'POST',
			body: JSON.stringify({ data: 'x'.repeat(40 * 1024) })
		});
		expect(await readJson(large)).toBeNull();
	});

	it('inspecciona una imagen PNG real', async () => {
		const png = await sharp({
			create: { width: 20, height: 10, channels: 3, background: '#ff0000' }
		})
			.png()
			.toBuffer();

		const result = await inspectPhoto(png, 'image/png');

		expect(result.mimeType).toBe('image/png');
		expect(result.width).toBe(20);
		expect(result.height).toBe(10);
		expect(result.sha256).toMatch(/^[0-9a-f]{64}$/);
	});

	it('rechaza un tipo declarado que no coincide con el contenido', async () => {
		const png = await sharp({
			create: { width: 20, height: 10, channels: 3, background: '#ff0000' }
		})
			.png()
			.toBuffer();

		await expect(inspectPhoto(png, 'image/jpeg')).rejects.toThrow(
			'El contenido real no coincide con el tipo declarado.'
		);
	});

	it('rechaza contenido que no es una imagen', async () => {
		await expect(inspectPhoto(Buffer.from('no soy una imagen'), 'image/png')).rejects.toThrow();
	});
});
