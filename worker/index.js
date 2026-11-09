import { hostname } from 'node:os';
import path from 'node:path';
import pg from 'pg';
import { S3Client } from '@aws-sdk/client-s3';
import { databaseConfig } from './config.js';
import { createWorkerRuntime } from './jobs.js';
import { LeaseLostError, runWithHeartbeat } from './lease.js';
import { loadModels } from './processing.js';
import { R2_CLIENT_OPTIONS } from '../src/lib/media/r2Config.js';

const env = process.env;
const workerId = env.WORKER_ID || `${hostname()}-${process.pid}`;
const leaseSeconds = Math.min(3600, Math.max(60, Number(env.WORKER_LEASE_SECONDS) || 300));
const pollMs = Math.max(500, Number(env.WORKER_POLL_MS) || 2000);
if (!env.R2_ACCOUNT_ID || !env.R2_ACCESS_KEY_ID || !env.R2_SECRET_ACCESS_KEY) {
	throw new Error('Falta configuracion R2 del worker.');
}
const pool = new pg.Pool(databaseConfig(env));
const r2 = new S3Client({
	...R2_CLIENT_OPTIONS, endpoint: `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
	requestChecksumCalculation: 'WHEN_REQUIRED',
	credentials: { accessKeyId: env.R2_ACCESS_KEY_ID, secretAccessKey: env.R2_SECRET_ACCESS_KEY },
	maxAttempts: 2
});
const runtime = createWorkerRuntime({
	pool, r2, workerId, leaseSeconds, bucket: env.R2_PRIVATE_BUCKET || 'aguaenlaboca-private',
	publicBucket: env.R2_PUBLIC_BUCKET || 'aguaenlaboca-public'
});
let stopping = false;
let nextMaintenance = 0;
pool.on('error', () => console.error('[worker] fallo de conexion inactiva'));
process.on('SIGINT', () => { stopping = true; });
process.on('SIGTERM', () => { stopping = true; });

try {
	await loadModels(env.FACE_MODEL_DIR || path.resolve('node_modules/@vladmandic/face-api/model'));
	while (!stopping) {
		try {
			if (Date.now() >= nextMaintenance) {
				await runtime.maintenance();
				nextMaintenance = Date.now() + 60000;
			}
			const job = await runtime.claimJob();
			if (!job) {
				await new Promise((resolve) => setTimeout(resolve, pollMs));
				continue;
			}
			try {
				await runWithHeartbeat({
					heartbeat: () => runtime.heartbeatJob(job),
					intervalMs: Math.max(1000, Math.floor(leaseSeconds * 1000 / 3)),
					run: (signal) => runtime.runJob({ ...job, signal })
				});
				await runtime.completeJob(job);
			} catch (error) {
				if (!(error instanceof LeaseLostError)) await runtime.failJob(job, error);
			}
		} catch {
			console.error('[worker] fallo de ciclo; se reintentara sin exponer detalles internos');
			await new Promise((resolve) => setTimeout(resolve, pollMs));
		}
	}
} catch {
	console.error('[worker] fallo de inicializacion');
	process.exitCode = 1;
} finally {
	await pool.end();
	r2.destroy();
}
