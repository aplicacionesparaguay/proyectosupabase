import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

// Sin el plugin de SvelteKit: las pruebas no cargan .env ni inicializan servicios.
export default defineConfig({
	envDir: false,
	resolve: {
		alias: {
			$lib: fileURLToPath(new URL('./src/lib', import.meta.url)),
			'$env/dynamic/private': fileURLToPath(new URL('./tests/fixtures/private-env.js', import.meta.url)),
			'$env/static/public': fileURLToPath(new URL('./tests/fixtures/public-env.js', import.meta.url))
		}
	},
	test: {
		environment: 'node',
		include: ['src/**/*.test.js', 'worker/**/*.test.js', 'tests/**/*.test.js'],
		testTimeout: 120000,
		hookTimeout: 120000
	}
});
