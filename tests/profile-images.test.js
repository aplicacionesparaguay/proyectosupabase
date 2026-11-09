import sharp from 'sharp';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ rpc: vi.fn(), from: vi.fn(), get: vi.fn(), put: vi.fn(), upload: vi.fn(), download: vi.fn() }));
vi.mock('../src/lib/server/mediaDb.js', () => ({ mediaServerQuery: (/** @type {(db: any) => any} */ query) => query({ rpc: mocks.rpc, from: mocks.from }) }));
vi.mock('../src/lib/server/r2.js', () => ({
	getObjectBytes: mocks.get, putObjectBytes: mocks.put, createPresignedUpload: mocks.upload,
	createPresignedDownload: mocks.download, publicUrl: (/** @type {string} */ key) => `https://images.invalid/${key}`
}));
import { POST } from '../src/routes/api/upload/r2/+server.js';
import { GET as coversGet } from '../src/routes/api/media/covers/+server.js';
import { POST as coverDelete } from '../src/routes/api/media/delete-cover/+server.js';
import { POST as retiredPresign } from '../src/routes/api/media/presign/+server.js';

const USER = '11111111-1111-4111-8111-111111111111';
const ID = '22222222-2222-4222-8222-222222222222';
/** @type {any} */ let locals;
/** @type {Record<string, any>} */ let table;
/** @type {Buffer} */ let source;
/** @type {string[]} */ let sequence;

/** @param {any} data */
function tableResult(data) {
	/** @type {Record<string, any>} */ const chain = {};
	for (const method of ['select', 'eq', 'order', 'limit']) chain[method] = vi.fn(() => chain);
	chain.maybeSingle = vi.fn(async () => ({ data, error: null }));
	chain.then = (/** @type {any} */ resolve, /** @type {any} */ reject) => Promise.resolve({ data, error: null }).then(resolve, reject);
	return chain;
}
/** @returns {any} */
function event(body = {}, auth = locals) {
	return { locals: auth, url: new URL(`http://localhost/api?user_id=${USER}`), request: new Request('http://localhost/api', { method: 'POST', body: JSON.stringify(body) }) };
}
beforeEach(async () => {
	vi.clearAllMocks(); sequence = [];
	source = await sharp({ create: { width: 64, height: 32, channels: 3, background: '#a65' } }).jpeg().withMetadata({ orientation: 6 }).toBuffer();
	locals = { auth: { status: 'verified', userId: USER }, user: { id: USER }, supabase: { rpc: vi.fn(async () => ({ data: true, error: null })) } };
	table = tableResult({ id: ID, object_key: `staging/${USER}/${ID}.jpg`, purpose: 'cover', status: 'created', mime_type: 'image/jpeg', declared_size: source.length, expires_at: new Date(Date.now() + 60000).toISOString() });
	mocks.from.mockReturnValue(table);
	mocks.get.mockResolvedValue(source);
	mocks.upload.mockResolvedValue('https://objects.invalid/signed-upload');
	mocks.download.mockResolvedValue('https://objects.invalid/signed-cover');
	mocks.put.mockImplementation(async () => { sequence.push('put'); });
	mocks.rpc.mockImplementation(async (name) => {
		sequence.push(name);
		return { error: null, data: name === 'media_prepare_profile_image'
			? { object_key: `covers/${USER}/${ID}.webp`, bucket: 'private' }
			: name === 'media_create_upload_intent' ? { intent_id: ID, object_key: `staging/${USER}/${ID}.jpg`, mime_type: 'image/jpeg' }
			: { key: ID, contentType: 'image/webp', publicUrl: null } };
	});
});

describe('portadas y compatibilidad de subida, sin servicios', () => {
	it('posts no puede esquivar el pipeline moderado', async () => {
		expect((await POST(event({ folder: 'posts', action: 'upload' }))).status).toBe(410);
		expect(mocks.rpc).not.toHaveBeenCalled();
	});
	it.each(['image/gif', 'image/svg+xml', 'video/mp4'])('rechaza %s antes de firmar', async (contentType) => {
		expect((await POST(event({ folder: 'covers', contentType, fileSize: 100 }))).status).toBe(400);
		expect(mocks.upload).not.toHaveBeenCalled();
	});
	it('avatar/portada suben solo al staging privado con PUT write-once', async () => {
		const response = await POST(event({ folder: 'covers', contentType: 'image/jpeg', fileSize: source.length }));
		expect(response.status).toBe(201);
		expect(mocks.upload).toHaveBeenCalledWith(`staging/${USER}/${ID}.jpg`, 'private', 'image/jpeg', 900, true, source.length);
		expect((await response.json()).key).toBe(ID);
	});
	it('portada es privada por defecto y solo publica bytes sin EXIF tras una reserva durable', async () => {
		const response = await POST(event({ folder: 'covers', action: 'commit', key: ID, bucket: 'public', original_key: 'ajeno' }));
		expect(response.status).toBe(200);
		const [key, bytes, type, bucket] = mocks.put.mock.calls[0];
		expect([key, type, bucket]).toEqual([`covers/${USER}/${ID}.webp`, 'image/webp', 'private']);
		const metadata = await sharp(bytes).metadata();
		expect(metadata).toMatchObject({ format: 'webp', width: 32, height: 64 });
		expect(metadata.exif).toBeUndefined(); expect(metadata.icc).toBeUndefined();
		expect(sequence).toEqual(['media_prepare_profile_image', 'put', 'media_commit_profile_image']);
		expect(mocks.rpc.mock.calls.at(-1)?.[1]).toMatchObject({ p_actor_id: USER, p_visibility: 'privado', p_public_url: null });
		expect(await response.text()).not.toContain('covers/');
	});
	it('una portada visible publicamente sigue almacenada en privado', async () => {
		await POST(event({ folder: 'covers', action: 'commit', key: ID, visibility: 'publico' }));
		expect(mocks.put.mock.calls[0][3]).toBe('private');
		expect(mocks.rpc.mock.calls.at(-1)?.[1].p_visibility).toBe('publico');
	});
	it('un fallo de commit tras PUT conserva el objeto reservado para recuperacion', async () => {
		const normal = mocks.rpc.getMockImplementation();
		mocks.rpc.mockImplementation((name, args) => name === 'media_commit_profile_image'
			? Promise.resolve({ data: null, error: { code: 'XX000', message: 'secreto' } }) : normal?.(name, args));
		const response = await POST(event({ folder: 'covers', action: 'commit', key: ID }));
		expect(response.status).toBe(503);
		expect(await response.text()).not.toContain('secreto');
		expect(mocks.put).toHaveBeenCalledTimes(1);
	});
	it('ni URL ni clave arbitraria del cliente se usa como identificador de commit', async () => {
		expect((await POST(event({ folder: 'covers', action: 'commit', key: 'covers/ajena/x.jpg' }))).status).toBe(400);
		expect(mocks.get).not.toHaveBeenCalled();
	});
	it('un visitante no recibe portadas privadas aunque el backend devolviera filas extra', async () => {
		mocks.from.mockReturnValue(tableResult([
			{ id: ID, user_id: USER, visibilidad: 'privado', storage_bucket: 'public', storage_path: `covers/${USER}/private.jpg` },
			{ id: 'visible', user_id: USER, visibilidad: 'publico', storage_bucket: 'private', storage_path: `covers/${USER}/visible.webp` }
		]));
		const response = await coversGet(event({}, { auth: { status: 'none' }, user: null }));
		expect((await response.json()).items.map((/** @type {any} */ row) => row.id)).toEqual(['visible']);
		expect(mocks.download).toHaveBeenCalledTimes(1);
	});
	it('la propietaria recibe URLs firmadas de sus portadas, sin claves separadas', async () => {
		mocks.from.mockReturnValue(tableResult([{ id: ID, user_id: USER, visibilidad: 'privado', storage_bucket: 'private', storage_path: `covers/${USER}/private.webp` }]));
		const response = await coversGet(event());
		expect(await response.text()).not.toMatch(/storage_path|storage_bucket|covers\//);
		expect(mocks.download).toHaveBeenCalledWith(`covers/${USER}/private.webp`, 'private', 300);
	});
	it('una portada heredada marcada privada se oculta hasta migrar su objeto publico', async () => {
		mocks.from.mockReturnValue(tableResult([{ id: ID, user_id: USER, visibilidad: 'privado', storage_bucket: 'public', storage_path: `covers/${USER}/legacy.jpg` }]));
		const response = await coversGet(event());
		expect((await response.json()).items[0].public_url).toBeNull();
		expect(mocks.download).not.toHaveBeenCalled();
	});
	it('borrado de portada oculta via RPC y devuelve 202 sin borrar R2 sincronicamente', async () => {
		expect((await coverDelete(event({ banner_id: ID }))).status).toBe(202);
		expect(locals.supabase.rpc).toHaveBeenCalledWith('media_request_delete_cover', { p_banner_id: ID });
		expect(mocks.put).not.toHaveBeenCalled();
	});
	it('el presign legacy esta retirado', async () => {
		expect(retiredPresign().status).toBe(410);
	});
});
