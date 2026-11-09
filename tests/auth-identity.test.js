import { beforeEach, describe, expect, it, vi } from 'vitest';
const mocks = vi.hoisted(() => ({ getSession: vi.fn(), getClaims: vi.fn() }));
vi.mock('@supabase/ssr', () => ({ createServerClient: () => ({ auth: mocks }) }));

const VERIFIED = '11111111-1111-4111-8111-111111111111';
const FORGED = '22222222-2222-4222-8222-222222222222';
beforeEach(() => {
	vi.resetModules(); vi.clearAllMocks();
	mocks.getSession.mockResolvedValue({ data: { session: { access_token: 'fixture-token', user: { id: FORGED, user_metadata: { role: 'admin' } } } }, error: null });
	mocks.getClaims.mockResolvedValue({ data: { claims: { sub: VERIFIED, exp: Math.floor(Date.now() / 1000) + 300 } }, error: null });
});
async function resolveIdentity() {
	const { handle } = await import('../src/hooks.server.js');
	/** @type {any} */ const event = { locals: {}, url: new URL('http://localhost/'), cookies: { getAll: () => [], set: vi.fn() } };
	await handle({ event, resolve: async () => new Response('ok') });
	return event.locals;
}
describe('identidad SSR verificada, sin Auth real', () => {
	it('la identidad confirmada sustituye el id forjado de la cookie', async () => {
		const locals = await resolveIdentity();
		expect(locals.auth).toEqual({ status: 'verified', userId: VERIFIED });
		expect(locals.user.id).toBe(VERIFIED);
		expect((await locals.getSession()).user.id).toBe(VERIFIED);
	});
	it('un JWT rechazado no crea sesion aunque la cookie afirme admin', async () => {
		mocks.getClaims.mockResolvedValue({ data: null, error: { status: 401 } });
		const locals = await resolveIdentity();
		expect(locals.auth.status).toBe('invalid'); expect(locals.user).toBeNull(); expect(locals.session).toBeNull();
	});
	it('un fallo transitorio de verificacion conserva el estado error sin autorizar', async () => {
		mocks.getClaims.mockRejectedValue(new TypeError('fallo de red simulado'));
		const locals = await resolveIdentity();
		expect(locals.auth.status).toBe('error'); expect(locals.user).toBeNull();
	});
	it('el acceso anonimo sigue disponible sin verificar un token inexistente', async () => {
		mocks.getSession.mockResolvedValue({ data: { session: null }, error: null });
		expect((await resolveIdentity()).auth.status).toBe('none');
		expect(mocks.getClaims).not.toHaveBeenCalled();
	});
});
