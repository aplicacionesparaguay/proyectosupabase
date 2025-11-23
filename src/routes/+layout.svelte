<script lang="ts">
	import '../app.css';
	import { goto } from '$app/navigation';
	import { user } from '$lib/stores/auth';
	import { supabase } from '$lib/supabaseClient';
	import { onMount } from 'svelte';

	let isLogin = true;
	let showMenu = false;
	let inactivityTimeout: NodeJS.Timeout;

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
		events.forEach(e => window.addEventListener(e, resetInactivity));
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

	function goToProfile() { goto('/perfil'); showMenu = false; }
	function goToSettings() { goto('/configuracion'); showMenu = false; }
	function goToSuscripciones() { goto('/suscripciones'); showMenu = false; }
	function goToAyuda() { goto('/ayuda'); showMenu = false; }
</script>

<header class="top-0 left-0 right-0 z-50 bg-black/70 backdrop-blur-xl border-b border-pink-900/40">
	<div class="mx-auto flex max-w-7xl items-center justify-between px-1 py-1">

		<!-- Logo + Nombre -->
		<a href="/" class="group flex items-center space-x-4">
			<div class="h-14 w-14 rounded-full ring-4 ring-pink-500/60 shadow-2xl shadow-pink-600/40 overflow-hidden border-2 border-white/20">
				<img src="/kunaguapa.jpeg" alt="Kuña Guapa" class="h-full w-full object-cover group-hover:scale-125 transition duration-700" />
			</div>
			<span class="text-4xl font-black bg-gradient-to-r from-pink-400 via-purple-400 to-pink-300 bg-clip-text text-transparent drop-shadow-2xl">
				Kuña Guapa
			</span>
		</a>

		<!-- Usuario logueado -->
		{#if $user}
			<div class="relative">
				<button class="md:hidden p-3 rounded-full bg-white/10 hover:bg-white/20 transition" on:click={toggleMenu}>
					<svg class="h-7 w-7 text-pink-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M4 6h16M4 12h16M4 18h16" />
					</svg>
				</button>

				<button
					class="hidden md:flex items-center gap-3 rounded-full bg-gradient-to-r from-pink-900/50 to-purple-900/50 backdrop-blur-md px-6 py-3 border border-pink-500/40 shadow-xl hover:shadow-pink-500/60 transition-all"
					on:click={toggleMenu}
				>
					<span class="font-bold text-pink-100">
						{$user.user_metadata?.nombre ?? $user.email.split('@')[0]}
					</span>
					<svg class="h-5 w-5 text-pink-400 transition-transform" class:rotate-180={showMenu} fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M19 9l-7 7-7-7"/>
					</svg>
				</button>

				{#if showMenu}
					<div class="absolute right-0 top-16 w-64 rounded-2xl bg-black/90 backdrop-blur-2xl border border-pink-500/40 shadow-2xl shadow-pink-600/50 overflow-hidden">
						<button on:click={goToProfile} class="w-full px-6 py-4 text-left text-pink-200 hover:bg-pink-900/40 transition flex items-center gap-3">
							<span class="text-2xl">Mi Perfil</span>
						</button>
						<button on:click={goToSuscripciones} class="w-full px-6 py-4 text-left text-pink-200 hover:bg-pink-900/40 transition flex items-center gap-3">
							<span class="text-2xl">Suscripciones</span>
						</button>
						<button on:click={goToSettings} class="w-full px-6 py-4 text-left text-pink-200 hover:bg-pink-900/40 transition flex items-center gap-3">
							<span class="text-2xl">Configuración</span>
						</button>
						<button on:click={goToAyuda} class="w-full px-6 py-4 text-left text-pink-200 hover:bg-pink-900/40 transition flex items-center gap-3">
							<span class="text-2xl">Ayuda</span>
						</button>
						<hr class="border-pink-800/50" />
						<button on:click={() => { logout(); showMenu = false; }} class="w-full px-6 py-4 text-left text-red-400 hover:bg-red-900/40 transition font-bold flex items-center gap-3">
							<span class="text-2xl">Cerrar Sesión</span>
						</button>
					</div>
				{/if}
			</div>
		{:else}
			<button 
				on:click={handleClick}
				class="rounded-full bg-gradient-to-r from-pink-600 via-purple-600 to-pink-700 px-1 py-1 font-black text-white text-lg shadow-2xl shadow-purple-600/50 hover:shadow-pink-600/70 hover:scale-110 transition-all duration-300 border-2 border-pink-400/50">
				{isLogin ? 'Iniciar Sesión' : 'Registrarse'}
			</button>
		{/if}
	</div>
</header>

<main class="min-h-screen pt-24 bg-black/30">
	<slot />
</main>

<!-- FOOTER SEXY OSCURO -->
<footer class="bg-gradient-to-t from-black via-pink-950 to-purple-950 py-20 text-pink-100 border-t border-pink-900/30">
	<div class="mx-auto max-w-7xl px-8">
		<div class="grid gap-16 md:grid-cols-3 text-center md:text-left">

			<div>
				<h3 class="mb-3 text-2xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-pink-400 to-purple-400">Sobre Nosotros</h3>
				<p class="text-pink-300 text-sm leading-relaxed">
					Somos una plataforma de entretenimiento para adultos que prioriza la privacidad, la
					seguridad y el contenido exclusivo para mayores de edad.
				</p>
			</div>

			<div>
				<h3 class="mb-3 text-xl font-bold text-pink-400">Enlaces Útiles</h3>
				<ul class="space-y-3 text-pink-200">
					<li><a href="/terminos" class="hover:text-pink-400 transition">Términos y Condiciones</a></li>
					<li><a href="/privacidad" class="hover:text-pink-400 transition">Política de Privacidad</a></li>
					<li><a href="/contacto" class="hover:text-pink-400 transition">Contacto</a></li>
					<li><a href="/soporte" class="hover:text-pink-400 transition">Soporte</a></li>
				</ul>
			</div>

			<div>
				<h3 class="mb-3 text-xl font-bold text-pink-400">Información Legal</h3>
				<p class="text-pink-300 text-sm leading-relaxed">
					Solo para mayores de 18 años. Todo el contenido cumple con las leyes internacionales de
					consentimiento y protección.
				</p>
				<p class="mt-6 text-xs text-pink-500">
					© {new Date().getFullYear()} Kuña Guapa. Todos los derechos reservados.
				</p>
			</div>
		</div>

		<div class="mt-12 pt-8 border-t border-pink-800/50 text-center">
			<p class="text-pink-400 text-sm italic">
				Diseñado con privacidad y seguridad en mente.
			</p>
		</div>
	</div>
</footer>