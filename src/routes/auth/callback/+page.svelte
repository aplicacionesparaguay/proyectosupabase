<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabaseClient';
	import { ensureProfile } from '$lib/authProfile';

	let error = '';

	/**
	 * @param {string | null} code
	 * @param {string | null} description
	 */
	function describeProviderError(code, description) {
		if (code === 'access_denied') {
			return 'Cancelaste el inicio de sesión con Google.';
		}
		if (code === 'server_error' || code === 'temporarily_unavailable') {
			return 'Google no respondió en este momento. Volvé a intentarlo en un rato.';
		}
		if (description) {
			return description.replace(/\+/g, ' ');
		}
		return 'No pudimos completar el inicio de sesión con Google.';
	}

	/**
	 * @param {number} timeout
	 * @returns {Promise<import('@supabase/supabase-js').Session | null>}
	 */
	function waitForSession(timeout = 10000) {
		return new Promise((resolve) => {
			let settled = false;
			/** @type {{ data: { subscription: { unsubscribe: () => void } } } | undefined} */
			let listener;
			/** @type {ReturnType<typeof setTimeout>} */
			let timer;

			/** @param {import('@supabase/supabase-js').Session | null} value */
			const finish = (value) => {
				if (settled) return;
				settled = true;
				clearTimeout(timer);
				listener?.data.subscription.unsubscribe();
				resolve(value);
			};

			listener = supabase.auth.onAuthStateChange((_event, current) => {
				if (current) finish(current);
			});

			timer = setTimeout(() => finish(null), timeout);
		});
	}

	onMount(async () => {
		const params = new URLSearchParams(window.location.search);

		if (params.get('error')) {
			error = describeProviderError(params.get('error'), params.get('error_description'));
			return;
		}

		// Flujo PKCE: el código vuelve en ?code=
		const code = params.get('code');
		if (code) {
			const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);
			if (exchangeError) {
				error = 'No pudimos validar la respuesta de Google. Volvé a iniciar sesión.';
				return;
			}
		}

		// Flujo implícito: los tokens ya fueron procesados por detectSessionInUrl.
		const current = (await supabase.auth.getSession()).data.session ?? (await waitForSession());

		if (!current?.user) {
			error = 'No pudimos recuperar tu sesión. Volvé a iniciar sesión.';
			return;
		}

		// Primer login de Google: crea el profile con role = 'fan' si no existe.
		await ensureProfile(current.user);

		goto('/', { replaceState: true });
	});
</script>

<div class="mx-auto mt-32 w-full max-w-md rounded-2xl bg-gradient-to-br from-pink-50 via-rose-50 to-fuchsia-50 p-8 text-center shadow-2xl border border-pink-200">
	{#if error}
		<h2 class="mb-4 text-2xl font-bold text-pink-900">No pudimos entrar</h2>
		<p class="mb-6 rounded-lg bg-red-100 p-4 text-red-700 border border-red-300">{error}</p>
		<div class="flex gap-3">
			<a
				href="/login"
				class="flex-1 rounded-xl bg-gradient-to-r from-pink-600 to-fuchsia-600 py-3 font-bold text-white shadow-lg hover:from-pink-700 hover:to-fuchsia-700 transition"
			>
				Iniciar sesión
			</a>
			<a
				href="/register"
				class="flex-1 rounded-xl border-2 border-pink-300 bg-white py-3 font-bold text-pink-800 transition hover:border-fuchsia-500"
			>
				Registrarme
			</a>
		</div>
	{:else}
		<h2 class="mb-2 text-2xl font-bold text-pink-900">Entrando con Google…</h2>
		<p class="text-pink-700">Un momento, estamos cerrando tu sesión.</p>
		<div
			class="mx-auto mt-6 h-10 w-10 animate-spin rounded-full border-4 border-pink-200 border-t-fuchsia-600"
		></div>
	{/if}
</div>
