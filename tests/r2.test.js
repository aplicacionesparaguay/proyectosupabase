import { afterEach, describe, expect, it, vi } from 'vitest';
import { createPresignedDownload, createPresignedUpload, getObjectBytes, getR2Client, ObjectTooLargeError } from '../src/lib/server/r2.js';

afterEach(() => vi.restoreAllMocks());
describe('R2: firma real del SDK con credenciales sinteticas, sin red', () => {
	it('la firma obliga a Content-Type e If-None-Match y caduca en 15 minutos', async () => {
		const url = new URL(await createPresignedUpload('staging/user/test.png', 'private', 'image/png', 900, true, 100));
		expect(url.searchParams.get('X-Amz-SignedHeaders')?.split(';')).toEqual(expect.arrayContaining(['content-type', 'content-length', 'if-none-match']));
		expect(url.searchParams.get('X-Amz-Expires')).toBe('900');
	});
	it('las descargas llevan no-store y expiracion breve', async () => {
		const url = new URL(await createPresignedDownload('protected/user/test.webp'));
		expect(url.searchParams.get('response-cache-control')).toBe('private, no-store');
		expect(url.searchParams.get('X-Amz-Expires')).toBe('300');
	});
	it('rechaza buckets desconocidos en vez de caer al publico', async () => {
		await expect(createPresignedUpload('test', /** @type {any} */ ('unknown'))).rejects.toThrow('Bucket');
	});
	it('un HEAD sobredimensionado impide el GET', async () => {
		/** @type {any} */ const send = vi.spyOn(getR2Client(), 'send');
		send.mockResolvedValue({ ContentLength: 100 });
		await expect(getObjectBytes('staging/test', 10)).rejects.toBeInstanceOf(ObjectTooLargeError);
		expect(send).toHaveBeenCalledTimes(1);
	});
	it('el limite durante streaming cierra el iterador y el GET fija ETag', async () => {
		let closed = false;
		const body = (async function* () { try { yield Buffer.alloc(11); } finally { closed = true; } })();
		/** @type {any} */ const send = vi.spyOn(getR2Client(), 'send');
		send.mockResolvedValueOnce({ ContentLength: 1, ETag: 'expected-etag' }).mockResolvedValueOnce({ Body: body });
		await expect(getObjectBytes('staging/test', 10)).rejects.toBeInstanceOf(ObjectTooLargeError);
		expect(closed).toBe(true);
		expect(send.mock.calls[1][0].input.IfMatch).toBe('expected-etag');
	});
});
