import { createHash } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createWorkerRuntime } from './jobs.js';
import { LeaseLostError } from './lease.js';

// Dobles de pg/R2: ninguna sentencia de estas pruebas se ejecuta en PostgreSQL.
const USER = '11111111-1111-4111-8111-111111111111';
const ID = '22222222-2222-4222-8222-222222222222';
const TOKEN = '33333333-3333-4333-8333-333333333333';
const SOURCE = Buffer.from('bytes-originales-inmutables');
let job, asset, calls, objects, processing, runtime, query, send, leaseOwned, ledger, events;

beforeEach(() => {
	job = { id: ID, media_id: ID, lease_token: TOKEN, kind: 'process', attempts: 1, max_attempts: 8 };
	asset = { id: ID, owner_id: USER, byte_size: SOURCE.length, width: 12, height: 8, mime_type: 'image/png',
		sha256_original: createHash('sha256').update(SOURCE).digest('hex'), moderation_status: 'pending',
		processing_status: 'queued', original_key: `originals/${USER}/${ID}/source.png` };
	calls = []; objects = new Map([[`staging/${USER}/${ID}.png`, SOURCE]]); events = [];
	leaseOwned = true; ledger = [];
	query = vi.fn(async (sql, params = []) => {
		calls.push({ sql, params });
		if (sql === 'COMMIT') events.push('commit');
		if (/SELECT id FROM media_jobs/.test(sql)) return { rows: leaseOwned && params[2] === TOKEN ? [{ id: ID }] : [], rowCount: 1 };
		if (/SELECT \* FROM media_assets/.test(sql)) return { rows: asset ? [{ ...asset }] : [] };
		if (/SELECT object_key\s+FROM media_upload_intents/.test(sql)) return { rows: [{ object_key: `staging/${USER}/${ID}.png` }] };
		if (/SELECT .*FROM storage_objects WHERE media_id/s.test(sql)) return { rows: ledger };
		if (/SELECT object_key, state, kind/.test(sql)) return { rows: ledger };
		if (/INSERT INTO storage_objects/.test(sql)) events.push(`reserve:${params[2]}`);
		return { rows: [], rowCount: 1 };
	});
	const client = { query, release: vi.fn() };
	const pool = { query, connect: vi.fn(async () => client) };
	send = vi.fn(async (command) => {
		const { Key, Body } = command.input;
		if (command.constructor.name === 'HeadObjectCommand') {
			if (!objects.has(Key)) throw Object.assign(new Error('missing'), { name: 'NotFound' });
			return { ContentLength: objects.get(Key).length, ETag: 'etag' };
		}
		if (command.constructor.name === 'GetObjectCommand') {
			const data = objects.get(Key);
			return { Body: (async function* () { yield data; })() };
		}
		if (command.constructor.name === 'PutObjectCommand') { events.push('put'); objects.set(Key, Buffer.from(Body)); }
		if (command.constructor.name === 'DeleteObjectCommand') objects.delete(Key);
		return {};
	});
	processing = {
		decodeImage: vi.fn(async () => ({ pixels: Buffer.alloc(12 * 8 * 3), width: 12, height: 8 })),
		detectFaces: vi.fn(async () => []),
		protectAndVerify: vi.fn(async () => ({ protectedBuffer: Buffer.from('protected'), facesDetected: 0, mode: 'pixelate', strength: 100, verified: true })),
		createThumbnail: vi.fn(async () => Buffer.from('thumbnail')),
		encodeProfileImage: vi.fn(async () => Buffer.from('canonical-cover')),
		detectorInfo: { name: 'test-detector', version: '1' }
	};
	runtime = createWorkerRuntime({ pool, r2: { send }, workerId: 'same-worker', leaseSeconds: 60, bucket: 'private-bucket', processing, logger: vi.fn() });
});

describe('worker: leases, escrituras y recuperacion con dobles', () => {
	it('claim genera una lease nueva, usa SKIP LOCKED y respeta max_attempts', async () => {
		await runtime.claimJob();
		const sql = calls.map((c) => c.sql).join('\n');
		expect(sql).toContain('FOR UPDATE SKIP LOCKED');
		expect(sql).toContain('lease_token = gen_random_uuid()');
		expect(sql).toContain("run_after <= now() AND attempts < max_attempts");
	});
	it('heartbeat y complete cercan por token ademas de worker y vigencia', async () => {
		await runtime.heartbeatJob(job); await runtime.completeJob(job);
		for (const { sql, params } of calls) {
			expect(sql).toContain('lease_token = $3 AND locked_until > clock_timestamp()');
			expect(params.slice(0, 3)).toEqual([ID, 'same-worker', TOKEN]);
		}
	});
	it('una lease anterior del mismo worker no modifica el asset', async () => {
		job.lease_token = 'old-token';
		await expect(runtime.withFencedAsset(job, async () => { throw new Error('no debe llamarse'); })).rejects.toBeInstanceOf(LeaseLostError);
		expect(calls.some((c) => /UPDATE media_assets/.test(c.sql))).toBe(false);
	});
	it('si la lease se pierde dentro de una escritura, el fence final revierte la transaccion', async () => {
		await expect(runtime.withFencedAsset(job, async () => { leaseOwned = false; return true; })).rejects.toBeInstanceOf(LeaseLostError);
		expect(calls.some((c) => c.sql === 'ROLLBACK')).toBe(true);
		expect(calls.some((c) => c.sql === 'COMMIT')).toBe(false);
	});
	it('un borrado durante la deteccion impide subir y volver a publicar derivadas', async () => {
		processing.detectFaces.mockImplementation(async () => { asset.deleted_at = new Date(); asset.moderation_status = 'deleted'; return []; });
		await runtime.runJob(job);
		expect([...objects.keys()].some((key) => /^(protected|thumbs)\//.test(key))).toBe(false);
		expect(calls.some((c) => /SET processing_status = 'protected'/.test(c.sql))).toBe(false);
	});
	it('el original usa los bytes hasheados aunque staging cambie despues del GET', async () => {
		processing.decodeImage.mockImplementation(async () => {
			objects.set(`staging/${USER}/${ID}.png`, Buffer.from('atacante'));
			return { pixels: Buffer.alloc(288), width: 12, height: 8 };
		});
		await runtime.runJob(job);
		expect(objects.get(asset.original_key)).toEqual(SOURCE);
		expect(send.mock.calls.some(([c]) => c.constructor.name === 'CopyObjectCommand')).toBe(false);
		const firstPut = events.indexOf('put');
		expect(events.slice(0, firstPut)).toContain('reserve:original');
		expect(events.slice(0, firstPut).at(-1)).toBe('commit');
	});
	it('metadatos inconsistentes fallan antes de escribir el original', async () => {
		asset.width = 90;
		await expect(runtime.runJob(job)).rejects.toThrow('metadatos');
		expect(send.mock.calls.some(([c]) => c.constructor.name === 'PutObjectCommand')).toBe(false);
	});
	it('una verificacion facial fallida bloquea sin crear copias para moderacion', async () => {
		processing.protectAndVerify.mockResolvedValue({ verified: false, mode: 'blur', facesDetected: 2 });
		await runtime.runJob(job);
		expect(calls.some((c) => c.sql.includes("moderation_status = 'blocked'"))).toBe(true);
		expect([...objects.keys()].some((key) => key.startsWith('protected/'))).toBe(false);
	});
	it('un rostro detectado en el thumbnail tambien bloquea', async () => {
		processing.detectFaces.mockResolvedValueOnce([]).mockResolvedValueOnce([{ x: 0, y: 0, width: 4, height: 4 }]);
		await runtime.runJob(job);
		expect(calls.some((c) => c.sql.includes("moderation_status = 'blocked'"))).toBe(true);
		expect([...objects.keys()].some((key) => key.startsWith('protected/'))).toBe(false);
	});
	it('derivadas llevan token de generacion y se reservan antes del PUT', async () => {
		await runtime.runJob(job);
		expect([...objects.keys()].filter((key) => /^(protected|thumbs)\//.test(key))).toHaveLength(2);
		expect([...objects.keys()].find((key) => key.startsWith('protected/'))).toContain(TOKEN);
		const reserve = events.indexOf('reserve:protected');
		expect(events.slice(reserve + 1)).toContain('commit');
	});
	it('fallo tras un PUT deja la reserva durable para recuperacion', async () => {
		const normal = send.getMockImplementation();
		send.mockImplementation(async (command, options) => {
			if (command.constructor.name === 'PutObjectCommand' && command.input.Key.startsWith('thumbs/')) throw new Error('fallo inyectado');
			return normal(command, options);
		});
		await expect(runtime.runJob(job)).rejects.toThrow('fallo inyectado');
		expect(events).toContain('reserve:thumb');
		expect([...objects.keys()].some((key) => key.startsWith('protected/'))).toBe(true);
		expect(calls.some((c) => c.sql.includes("SET processing_status = 'protected'"))).toBe(false);
	});
	it('fallo final pasa a dead sin persistir mensajes con rutas/credenciales', async () => {
		job.attempts = 8;
		await runtime.failJob(job, new Error('https://secret:token@host/originals/private'));
		const update = calls.find((c) => /SET status = \$2/.test(c.sql));
		expect(update.params[1]).toBe('dead');
		expect(update.params[3]).not.toMatch(/secret|token|originals/);
	});
	it('borrado incluye generaciones reservadas que no llegaron al asset', async () => {
		const key = `protected/${USER}/${ID}/partial/protected.webp`;
		ledger = [{ bucket: 'private', kind: 'protected', object_key: key }]; objects.set(key, Buffer.from('partial'));
		await runtime.runJob({ ...job, kind: 'delete_all', payload: { objects: [] } });
		expect(objects.has(key)).toBe(false);
		expect(calls.some((c) => c.sql.includes('INSERT INTO object_tombstones'))).toBe(true);
	});
	it('payload de borrado con traversal falla, no queda falsamente done', async () => {
		await expect(runtime.runJob({ ...job, kind: 'delete_all', media_id: null, payload: { objects: [{ object_key: 'staging/a/../private' }] } })).rejects.toThrow('Clave');
		expect(send).not.toHaveBeenCalled();
	});
	it('reconciliacion vuelve a borrar un tombstone reaparecido y rota el ledger', async () => {
		const key = `protected/${USER}/${ID}/old/file.webp`; objects.set(key, Buffer.from('again'));
		ledger = [{ object_key: key, state: 'deleted', kind: 'protected', media_id: ID, created_at: new Date() }];
		await runtime.runJob({ ...job, kind: 'reconcile' });
		expect(objects.has(key)).toBe(false);
		expect(calls.find((c) => c.sql.includes('SET state = $2, updated_at = now()')).params[1]).toBe('deleted');
	});
	it('portadas antiguas se borran duramente del bucket publico correcto', async () => {
		const key = `covers/${USER}/old.jpg`; objects.set(key, Buffer.from('cover'));
		await runtime.runJob({ ...job, kind: 'delete_all', media_id: null, payload: { objects: [{ object_key: key, bucket: 'public', kind: 'cover' }] } });
		expect(objects.has(key)).toBe(false);
		expect(send.mock.calls[0][0].input.Bucket).toBe('aguaenlaboca-public');
	});
	it('una reserva de portada no referenciada se limpia como huerfana', async () => {
		const key = `covers/${USER}/${ID}.webp`; objects.set(key, Buffer.from('orphan'));
		await runtime.runJob({ ...job, kind: 'delete_profile_orphan', payload: { object_key: key, bucket: 'private', kind: 'cover', user_id: USER } });
		expect(objects.has(key)).toBe(false);
		expect(calls.some((c) => c.sql.includes('INSERT INTO object_tombstones'))).toBe(true);
	});
	it('migrar una portada publica reserva, copia saneada y encola retirar la fuente despues del cambio de fila', async () => {
		const row = { id: ID, user_id: USER, storage_path: `covers/${USER}/legacy.jpg`, storage_bucket: 'public', public_url: 'https://public.invalid/legacy', visibilidad: 'privado' };
		objects.set(row.storage_path, SOURCE);
		const normal = query.getMockImplementation();
		query.mockImplementation((sql, args) => /SELECT \* FROM user_banners/.test(sql)
			? Promise.resolve({ rows: [row] }) : normal(sql, args));
		await runtime.runJob({ ...job, kind: 'migrate_cover', payload: { banner_id: ID } });
		expect(objects.get(`covers/${USER}/${ID}/${TOKEN}/migrated.webp`)).toEqual(Buffer.from('canonical-cover'));
		expect(objects.has(row.storage_path)).toBe(true); // la retirada es un trabajo durable separado
		expect(calls.some((c) => c.sql.includes("storage_bucket = 'private'"))).toBe(true);
		expect(calls.some((c) => c.params.includes(`migrated_cover_source:${ID}`))).toBe(true);
	});
});
