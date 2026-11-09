import { afterEach, describe, expect, it, vi } from 'vitest';
import { LeaseLostError, runWithHeartbeat } from './lease.js';
import { databaseConfig } from './config.js';

afterEach(() => vi.useRealTimers());

describe('heartbeat y TLS', () => {
	it('perder la lease aborta el trabajo y evita un exito falso', async () => {
		vi.useFakeTimers();
		let signal;
		const run = runWithHeartbeat({ intervalMs: 10, heartbeat: async () => false,
			run: (s) => { signal = s; return new Promise((resolve) => s.addEventListener('abort', resolve)); } });
		const assertion = expect(run).rejects.toBeInstanceOf(LeaseLostError);
		await vi.advanceTimersByTimeAsync(10);
		await assertion;
		expect(signal.aborted).toBe(true);
	});
	it('no solapa heartbeats ni deja timers despues de finalizar', async () => {
		vi.useFakeTimers();
		let releaseHeartbeat, finish;
		const heartbeat = vi.fn(() => new Promise((resolve) => { releaseHeartbeat = resolve; }));
		const running = runWithHeartbeat({ intervalMs: 10, heartbeat, run: () => new Promise((resolve) => { finish = resolve; }) });
		await vi.advanceTimersByTimeAsync(50);
		expect(heartbeat).toHaveBeenCalledTimes(1);
		releaseHeartbeat(true); finish('ok');
		await expect(running).resolves.toBe('ok');
		await vi.advanceTimersByTimeAsync(100);
		expect(heartbeat).toHaveBeenCalledTimes(1);
	});
	it('TLS valida cadena y hostname con CA opcional', () => {
		expect(databaseConfig({ DATABASE_URL: 'postgres://offline.invalid/test' }).ssl).toEqual({ rejectUnauthorized: true });
		expect(databaseConfig({ DATABASE_URL: 'postgres://offline.invalid/test', DATABASE_CA_PEM: 'fixture-ca' }).ssl).toEqual({ rejectUnauthorized: true, ca: 'fixture-ca' });
	});
	it.each(['disable', 'no-verify', 'require', 'verify-full'])('rechaza sslmode=%s que podria sobreescribir TLS', (mode) => {
		expect(() => databaseConfig({ DATABASE_URL: `postgres://offline.invalid/test?sslmode=${mode}` })).toThrow('TLS');
	});
	it('no permite desactivar SSL ni leer un sslkey de la URL', () => {
		expect(() => databaseConfig({ DATABASE_URL: 'postgres://offline.invalid/test', DATABASE_SSL: 'false' })).toThrow('TLS');
		expect(() => databaseConfig({ DATABASE_URL: 'postgres://offline.invalid/test?sslkey=private.key' })).toThrow('TLS');
	});
});
