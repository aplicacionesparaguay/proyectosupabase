import sharp from 'sharp';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
	rpc: vi.fn(), from: vi.fn(), getObjectBytes: vi.fn(), sign: vi.fn(), upload: vi.fn()
}));
vi.mock('../src/lib/server/mediaDb.js', () => ({
	mediaServerQuery: (/** @type {(db: any) => any} */ query) => query({ rpc: mocks.rpc, from: mocks.from })
}));
vi.mock('../src/lib/server/r2.js', () => ({
	getObjectBytes: mocks.getObjectBytes,
	createPresignedDownload: mocks.sign,
	createPresignedUpload: mocks.upload,
	ObjectTooLargeError: class ObjectTooLargeError extends Error {}
}));

import { POST as intentPost } from '../src/routes/api/media/upload-intent/+server.js';
import { POST as commitPost } from '../src/routes/api/media/upload-commit/+server.js';
import { POST as abortPost } from '../src/routes/api/media/upload-abort/+server.js';
import { POST as deletePost } from '../src/routes/api/media/delete/+server.js';
import { GET as ownerGet } from '../src/routes/api/media/owner/+server.js';
import { GET as publicGet } from '../src/routes/api/media/public/+server.js';
import { requireMediaStaff } from '../src/lib/server/admin.js';

const USER = '11111111-1111-4111-8111-111111111111';
const INTENT = '22222222-2222-4222-8222-222222222222';
/** @type {Record<string, any>} */
let table;
/** @type {ReturnType<typeof vi.fn>} */
let sessionRpc;
/** @type {any} Fixture parcial de RequestEvent.locals. */
let locals;
let png;

/** @returns {any} Fixture parcial: el handler solo usa request/locals/url. */
function event(body = {}, auth = locals) {
	return {
		locals: auth,
		url: new URL(`http://localhost/api?user_id=${USER}`),
		request: new Request('http://localhost/api', { method: 'POST', body: JSON.stringify(body) })
	};
}
/** @param {any} data */
function queryResult(data) {
	/** @type {Record<string, any>} */
	const chain = {};
	for (const method of ['select', 'eq', 'is', 'order', 'limit', 'range', 'or']) chain[method] = vi.fn(() => chain);
	chain.maybeSingle = vi.fn(async () => ({ data, error: null }));
	chain.then = (/** @type {any} */ resolve, /** @type {any} */ reject) => Promise.resolve({ data, error: null }).then(resolve, reject);
	return chain;
}

beforeEach(async () => {
	vi.clearAllMocks();
	png = await sharp({ create: { width: 12, height: 8, channels: 3, background: '#c76' } }).png().toBuffer();
	table = queryResult({
		id: INTENT, object_key: `staging/${USER}/${INTENT}.png`, mime_type: 'image/png',
		status: 'created', declared_size: png.length, expires_at: new Date(Date.now() + 60000).toISOString()
	});
	mocks.from.mockReturnValue(table);
	mocks.rpc.mockResolvedValue({ data: { id: INTENT }, error: null });
	mocks.getObjectBytes.mockResolvedValue(png);
	mocks.sign.mockResolvedValue('https://objects.invalid/signed-read');
	mocks.upload.mockResolvedValue('https://objects.invalid/signed-put');
	sessionRpc = vi.fn().mockResolvedValue({ data: true, error: null });
	locals = {
		auth: { status: 'verified', userId: USER }, user: { id: USER },
		supabase: { rpc: sessionRpc }, getSession: async () => ({ user: { id: USER } })
	};
});

describe('fronteras HTTP del pipeline (dobles, sin servicios)', () => {
	for (const [name, handler] of Object.entries({ intent: intentPost, commit: commitPost, abort: abortPost, delete: deletePost, owner: ownerGet })) {
		it(`${name}: sin identidad verificada no consulta ni firma`, async () => {
			const result = await handler(event({}, { auth: { status: 'invalid' }, user: null }));
			expect(result.status).toBe(401);
			expect(mocks.from).not.toHaveBeenCalled();
			expect(mocks.rpc).not.toHaveBeenCalled();
			expect(mocks.sign).not.toHaveBeenCalled();
		});
		it(`${name}: fallo temporal de Auth es 503`, async () => {
			expect((await handler(event({}, { auth: { status: 'error' }, user: null }))).status).toBe(503);
		});
	}
	it('intent usa el actor del servidor y no expone objectKey', async () => {
		mocks.rpc.mockResolvedValue({ data: {
			intent_id: INTENT, object_key: `staging/${USER}/${INTENT}.png`, mime_type: 'image/png',
			max_bytes: 10485760, expires_at: new Date(Date.now() + 60000).toISOString()
		}, error: null });
		const response = await intentPost(event({ fileName: 'a.png', contentType: 'image/png', declaredSize: png.length, userId: INTENT }));
		expect(response.status).toBe(201);
		expect(mocks.rpc.mock.calls[0][1].p_actor_id).toBe(USER);
		expect(mocks.upload.mock.calls[0].slice(1)).toEqual(['private', 'image/png', 900, true, png.length]);
		expect(await response.json()).not.toHaveProperty('objectKey');
		expect(response.headers.get('cache-control')).toContain('no-store');
	});
	it('rechaza tamanos fraccionarios antes de reservar', async () => {
		expect((await intentPost(event({ contentType: 'image/png', declaredSize: 1.5 }))).status).toBe(400);
		expect(mocks.rpc).not.toHaveBeenCalled();
	});
	it('commit calcula hash/dimensiones reales e ignora metadatos falsificados', async () => {
		const response = await commitPost(event({ intentId: INTENT, p_actor_id: INTENT, sha256: 'f'.repeat(64), width: 9000 }));
		expect(response.status).toBe(201);
		const args = mocks.rpc.mock.calls[0][1];
		expect(args).toMatchObject({ p_actor_id: USER, p_width: 12, p_height: 8, p_byte_size: png.length });
		expect(args.p_sha256).not.toBe('f'.repeat(64));
		expect(table.eq).toHaveBeenCalledWith('user_id', USER);
	});
	it('un intent ajeno no llega a almacenamiento', async () => {
		table.maybeSingle.mockResolvedValue({ data: null, error: null });
		expect((await commitPost(event({ intentId: INTENT }))).status).toBe(404);
		expect(mocks.getObjectBytes).not.toHaveBeenCalled();
	});
	it('un intent expirado no descarga y pide limpieza durable', async () => {
		table = queryResult({ status: 'created', expires_at: '2020-01-01T00:00:00Z' });
		mocks.from.mockReturnValue(table);
		expect((await commitPost(event({ intentId: INTENT }))).status).toBe(409);
		expect(mocks.getObjectBytes).not.toHaveBeenCalled();
		expect(sessionRpc).toHaveBeenCalledWith('media_abort_upload_intent', { p_intent_id: INTENT });
	});
	it('un error transitorio de lectura conserva el intent', async () => {
		mocks.getObjectBytes.mockRejectedValue(new Error('fallo de almacenamiento'));
		expect((await commitPost(event({ intentId: INTENT }))).status).toBe(503);
		expect(sessionRpc).not.toHaveBeenCalled();
	});
	it('contenido distinto al declarado no se registra', async () => {
		mocks.getObjectBytes.mockResolvedValue(Buffer.alloc(png.length));
		const response = await commitPost(event({ intentId: INTENT }));
		expect(response.status).toBe(422);
		expect(mocks.rpc).not.toHaveBeenCalled();
		expect(sessionRpc).toHaveBeenCalledWith('media_abort_upload_intent', { p_intent_id: INTENT });
	});
	it('un commit duplicado no vuelve a leer R2', async () => {
		mocks.from.mockImplementation((name) => queryResult(name === 'media_upload_intents'
			? { status: 'committed', media_id: INTENT } : { id: INTENT, moderation_status: 'pending' }));
		const response = await commitPost(event({ intentId: INTENT }));
		expect(await response.json()).toMatchObject({ duplicate: true });
		expect(mocks.getObjectBytes).not.toHaveBeenCalled();
	});
	it('la galeria publica proyecta campos, sin devolver claves originales ni derivadas', async () => {
		mocks.rpc.mockResolvedValue({ data: [{ id: INTENT, owner_id: USER, protected_key: 'protected/internal', thumb_key: 'thumbs/internal', original_key: 'originals/secret' }], error: null });
		const response = await publicGet(event());
		const text = await response.text();
		expect(response.status).toBe(200);
		expect(text).not.toMatch(/internal|secret|_key/);
		expect(mocks.sign).not.toHaveBeenCalledWith('originals/secret', expect.anything(), expect.anything());
	});
	it('un rechazo conserva el original solo tras auditar autorizacion de propietaria', async () => {
		mocks.from.mockReturnValue(queryResult([{ id: INTENT, moderation_status: 'rejected', original_key: 'originals/private' }]));
		sessionRpc.mockResolvedValue({ data: false, error: null });
		const response = await ownerGet(event());
		expect((await response.json()).items[0].originalAvailable).toBe(false);
		expect(mocks.sign).not.toHaveBeenCalledWith('originals/private', expect.anything(), expect.anything());
	});
	it('staff sin rol se deniega aunque haya sesion', async () => {
		sessionRpc.mockResolvedValue({ data: null, error: null });
		await expect(requireMediaStaff(locals)).rejects.toMatchObject({ status: 403 });
	});
});
