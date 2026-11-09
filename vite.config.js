import tailwindcss from '@tailwindcss/vite';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	...(process.env.AGUA_OFFLINE_CHECK === '1' ? { envDir: false } : {}),
	plugins: [tailwindcss(), sveltekit()],
});
