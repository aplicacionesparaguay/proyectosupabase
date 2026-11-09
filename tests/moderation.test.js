import { beforeEach, describe, expect, it, vi } from 'vitest';
const mocks = vi.hoisted(() => ({ rpc: vi.fn(), sign: vi.fn() }));
vi.mock('../src/lib/server/mediaDb.js', () => ({ mediaServerQuery: (/** @type {(db: any) => any} */ query) => query({ rpc: mocks.rpc }) }));
vi.mock('../src/lib/server/r2.js', () => ({ createPresignedDownload: mocks.sign }));
import { actions, load } from '../src/routes/moderacion/+page.server.js';

const USER = '11111111-1111-4111-8111-111111111111';
const ID = '22222222-2222-4222-8222-222222222222';
/** @type {any} */ let locals;
beforeEach(() => {
	vi.clearAllMocks();
	locals = { auth: { status: 'verified', userId: USER }, getSession: async () => ({ user: { id: USER } }),
		supabase: { rpc: vi.fn(async (name) => ({ data: name === 'media_admin_role' ? 'moderator' : [], error: null })) } };
	mocks.rpc.mockResolvedValue({ data: [], error: null });
	mocks.sign.mockResolvedValue('https://objects.invalid/protected');
});
/** @returns {any} */
function event(query = '', fields = {}) {
	const form = new FormData(); for (const [name, value] of Object.entries(fields)) form.set(name, value);
	return { locals, url: new URL(`http://localhost/moderacion?${query}`), setHeaders: vi.fn(), request: new Request('http://localhost/moderacion', { method: 'POST', body: form }) };
}
describe('moderacion y recuperacion de dead-letter', () => {
	it('limita y pagina antes de firmar sin exponer payload ni claves', async () => {
		mocks.rpc.mockResolvedValue({ data: [
			{ id: ID, created_at: '2026-11-08T12:00:00.123456Z', protected_key: 'protected/first', original_key: 'originals/private' },
			{ id: USER, created_at: '2026-11-08T12:00:00.123457Z', protected_key: 'protected/second' }
		], error: null });
		const result = await load(event('limit=1'));
		expect(result?.items).toHaveLength(1);
		expect(result?.nextCursor).toBe(`2026-11-08T12:00:00.123456Z|${ID}`);
		expect(mocks.sign).toHaveBeenCalledTimes(1);
		expect(JSON.stringify(result)).not.toMatch(/_key|payload|originals/);
		expect(mocks.rpc.mock.calls[0][1]).toMatchObject({ p_actor_id: USER, p_limit: 2 });
	});
	it('una cuenta sin staff no consulta ni firma', async () => {
		locals.supabase.rpc.mockResolvedValue({ data: null, error: null });
		await expect(load(event())).rejects.toMatchObject({ status: 403 });
		expect(mocks.rpc).not.toHaveBeenCalled();
		expect(mocks.sign).not.toHaveBeenCalled();
	});
	it('errores de consulta no se presentan como una cola vacia valida', async () => {
		mocks.rpc.mockResolvedValue({ data: null, error: { code: 'XX000', message: 'secreto' } });
		const result = await load(event());
		expect(result?.queueError).toBeTruthy();
		expect(JSON.stringify(result)).not.toContain('secreto');
	});
	it('valida el motivo antes de reencolar y nunca acepta un payload del formulario', async () => {
		const invalid = await actions.retryJob(event('', { job_id: ID, reason: 'x' }));
		expect(invalid).toMatchObject({ status: 400 });
		expect(locals.supabase.rpc.mock.calls.some((/** @type {any[]} */ call) => call[0] === 'media_retry_dead_job')).toBe(false);
		await actions.retryJob(event('', { job_id: ID, reason: 'Recuperacion comprobada', payload: 'ajeno', user_id: ID }));
		expect(locals.supabase.rpc).toHaveBeenCalledWith('media_retry_dead_job', { p_job_id: ID, p_reason: 'Recuperacion comprobada' });
	});
});
