<script lang="ts">
	import '../app.css';
	import { goto } from '$app/navigation';
	import { user } from '$lib/stores/auth';
	import { supabase } from '$lib/supabaseClient';
	import { onMount } from 'svelte';

	let isLogin = true;
	let showMenu = false;
	let inactivityTimeout: ReturnType<typeof setTimeout>;

	function resetInactivity() {
		if (inactivityTimeout) clearTimeout(inactivityTimeout);
		inactivityTimeout = setTimeout(logout, 10 * 60 * 1000);
	}

	async function logout() {
		await supabase.auth.signOut();
		user.set(null);
		localStorage.clear();
		sessionStorage.clear();
		goto('/login');
	}

	onMount(() => {
		const events = ['mousemove', 'keydown', 'scroll', 'touchstart'];
		events.forEach((e) => window.addEventListener(e, resetInactivity));
		resetInactivity();

		supabase.auth.getUser().then(({ data }) => {
			if (data?.user) user.set(data.user);
		});
	});

	async function handleClick() {
		if ($user) {
			await logout();
		} else {
			goto(isLogin ? '/login' : '/register');
			isLogin = !isLogin;
		}
	}

	function toggleMenu() {
		showMenu = !showMenu;
	}

	function goToProfile() {
		goto('/perfil');
		showMenu = false;
	}
	function goToSettings() {
		goto('/configuracion');
		showMenu = false;
	}
	function goToSuscripciones() {
		goto('/suscripciones');
		showMenu = false;
	}
	function goToAyuda() {
		goto('/ayuda');
		showMenu = false;
	}
</script>

<header class="top-0 right-0 left-0 z-50 border-b border-pink-900/40 bg-black/70 backdrop-blur-xl">
	<div class="mx-auto flex max-w-7xl items-center justify-between px-1 py-1">
		<!-- Logo + Nombre -->
		<a href="/" class="group flex items-center space-x-4">
			<div
				class="h-14 w-14 overflow-hidden rounded-full border-2 border-white/20 shadow-2xl ring-4 shadow-pink-600/40 ring-pink-500/60"
			>
				<img
					src="/agua-en-la-boca.jpeg"
					alt="Agua en la Boca"
					class="h-full w-full object-cover transition duration-700 group-hover:scale-125"
				/>
			</div>
			<span
				class="bg-gradient-to-r from-pink-400 via-purple-400 to-pink-300 bg-clip-text text-4xl font-black text-transparent drop-shadow-2xl"
			>
				Agua en la Boca
			</span>
		</a>

		<!-- Usuario logueado -->
		{#if $user}
			<div class="relative">
				<button
					aria-label="Abrir menú"
					class="rounded-full bg-white/10 p-3 transition hover:bg-white/20 md:hidden"
					on:click={toggleMenu}
				>
					<svg class="h-7 w-7 text-pink-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2.5"
							d="M4 6h16M4 12h16M4 18h16"
						/>
					</svg>
				</button>

				<button
					class="hidden items-center gap-3 rounded-full border border-pink-500/40 bg-gradient-to-r from-pink-900/50 to-purple-900/50 px-6 py-3 shadow-xl backdrop-blur-md transition-all hover:shadow-pink-500/60 md:flex"
					on:click={toggleMenu}
				>
					<span class="font-bold text-pink-100">
						{$user.user_metadata?.nombre ?? $user.email?.split('@')[0] ?? 'Usuario'}
					</span>
					<svg
						class="h-5 w-5 text-pink-400 transition-transform"
						class:rotate-180={showMenu}
						fill="none"
						stroke="currentColor"
						viewBox="0 0 24 24"
					>
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="3"
							d="M19 9l-7 7-7-7"
						/>
					</svg>
				</button>

				{#if showMenu}
					<div
						class="absolute top-16 right-0 w-64 overflow-hidden rounded-2xl border border-pink-500/40 bg-black/90 shadow-2xl shadow-pink-600/50 backdrop-blur-2xl"
					>
						<button
							on:click={goToProfile}
							class="flex w-full items-center gap-3 px-6 py-4 text-left text-pink-200 transition hover:bg-pink-900/40"
						>
							<span class="text-2xl">Mi Perfil</span>
						</button>
						<button
							on:click={goToSuscripciones}
							class="flex w-full items-center gap-3 px-6 py-4 text-left text-pink-200 transition hover:bg-pink-900/40"
						>
							<span class="text-2xl">Suscripciones</span>
						</button>
						<button
							on:click={goToSettings}
							class="flex w-full items-center gap-3 px-6 py-4 text-left text-pink-200 transition hover:bg-pink-900/40"
						>
							<span class="text-2xl">Configuración</span>
						</button>
						<button
							on:click={goToAyuda}
							class="flex w-full items-center gap-3 px-6 py-4 text-left text-pink-200 transition hover:bg-pink-900/40"
						>
							<span class="text-2xl">Ayuda</span>
						</button>
						<hr class="border-pink-800/50" />
						<button
							on:click={() => {
								logout();
								showMenu = false;
							}}
							class="flex w-full items-center gap-3 px-6 py-4 text-left font-bold text-red-400 transition hover:bg-red-900/40"
						>
							<span class="text-2xl">Cerrar Sesión</span>
						</button>
					</div>
				{/if}
			</div>
		{:else}
			<button
				on:click={handleClick}
				class="rounded-full border-2 border-pink-400/50 bg-gradient-to-r from-pink-600 via-purple-600 to-pink-700 px-1 py-1 text-lg font-black text-white shadow-2xl shadow-purple-600/50 transition-all duration-300 hover:scale-110 hover:shadow-pink-600/70"
			>
				{isLogin ? 'Iniciar Sesión' : 'Registrarse'}
			</button>
		{/if}
	</div>
</header>

<main class="min-h-screen bg-black/30 pt-24">
	<slot />
</main>

<!-- FOOTER SEXY OSCURO -->
<footer
	class="border-t border-pink-900/30 bg-gradient-to-t from-black via-pink-950 to-purple-950 py-20 text-pink-100"
>
	<div class="mx-auto max-w-7xl px-8">
		<div class="grid gap-16 text-center md:grid-cols-3 md:text-left">
			<div>
				<h3
					class="mb-3 bg-gradient-to-r from-pink-400 to-purple-400 bg-clip-text text-2xl font-bold text-transparent"
				>
					Sobre Nosotros
				</h3>
				<p class="text-sm leading-relaxed text-pink-300">
					Somos una plataforma de entretenimiento para adultos que prioriza la privacidad, la
					seguridad y el contenido exclusivo para mayores de edad.
				</p>
			</div>

			<div>
				<h3 class="mb-3 text-xl font-bold text-pink-400">Enlaces Útiles</h3>
				<ul class="space-y-3 text-pink-200">
					<li>
						<a href="/terminos" class="transition hover:text-pink-400">Términos y Condiciones</a>
					</li>
					<li>
						<a href="/privacidad" class="transition hover:text-pink-400">Política de Privacidad</a>
					</li>
					<li><a href="/contacto" class="transition hover:text-pink-400">Contacto</a></li>
					<li><a href="/soporte" class="transition hover:text-pink-400">Soporte</a></li>
				</ul>
			</div>

			<div>
				<h3 class="mb-3 text-xl font-bold text-pink-400">Información Legal</h3>
				<p class="text-sm leading-relaxed text-pink-300">
					Solo para mayores de 18 años. Todo el contenido cumple con las leyes internacionales de
					consentimiento y protección.
				</p>
				<p class="mt-6 text-xs text-pink-500">
					© {new Date().getFullYear()} Agua en la Boca. Todos los derechos reservados.
				</p>
			</div>
		</div>

		<div class="mt-12 border-t border-pink-800/50 pt-8 text-center">
			<p class="text-sm text-pink-400 italic">Diseñado con privacidad y seguridad en mente.</p>
		</div>
	</div>
</footer>
