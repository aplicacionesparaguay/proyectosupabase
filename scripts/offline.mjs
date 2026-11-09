import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const commands = {
	test: ['node_modules/vitest/vitest.mjs', 'run', '--config', 'vitest.config.js'],
	sync: ['node_modules/@sveltejs/kit/svelte-kit.js', 'sync'],
	check: ['node_modules/svelte-check/bin/svelte-check', '--tsconfig', './jsconfig.json'],
	build: ['node_modules/vite/bin/vite.js', 'build', '--mode', 'offline']
};
const command = process.argv[2];
if (!(command in commands)) throw new Error('Usa offline.mjs test|sync|check|build.');

// Entorno nuevo: no se heredan claves, sesiones, DATABASE_URL ni NODE_OPTIONS.
const env = {};
for (const key of ['PATH', 'Path', 'SystemRoot', 'SYSTEMROOT', 'WINDIR', 'TEMP', 'TMP']) {
	if (process.env[key]) env[key] = process.env[key];
}
Object.assign(env, {
	AGUA_OFFLINE_CHECK: '1',
	CI: 'true',
	PUBLIC_SUPABASE_URL: 'https://offline.invalid',
	PUBLIC_SUPABASE_ANON_KEY: 'offline-placeholder',
	R2_ACCOUNT_ID: 'offline-placeholder',
	R2_ACCESS_KEY_ID: 'offline-placeholder',
	R2_SECRET_ACCESS_KEY: 'offline-placeholder',
	R2_PUBLIC_BUCKET: 'offline-public',
	R2_PRIVATE_BUCKET: 'offline-private',
	R2_PUBLIC_URL: 'https://offline.invalid',
	NODE_OPTIONS: `--require="${fileURLToPath(new URL('./offline-guard.cjs', import.meta.url)).replaceAll('\\', '/')}"`
});

function run(name, args = []) {
	const result = spawnSync(process.execPath, [...commands[name], ...args], {
		cwd: fileURLToPath(new URL('../', import.meta.url)),
		env,
		stdio: 'inherit'
	});
	if (result.error) throw result.error;
	if (result.status !== 0) process.exit(result.status ?? 1);
}

if (command === 'check') run('sync');
run(command, process.argv.slice(3));
