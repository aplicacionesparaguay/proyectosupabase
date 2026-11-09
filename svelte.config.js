import adapter from '@sveltejs/adapter-auto';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	kit: {
		// Solo para checks locales aislados: nunca buscar .env del proyecto.
		...(process.env.AGUA_OFFLINE_CHECK === '1'
			? { env: { dir: './scripts/offline-env-disabled' } }
			: {}),
		// adapter-auto only supports some environments, see https://svelte.dev/docs/kit/adapter-auto for a list.
		// If your environment is not supported, or you settled on a specific environment, switch out the adapter.
		// See https://svelte.dev/docs/kit/adapters for more information about adapters.
		adapter: adapter()
	}
};

export default config;
