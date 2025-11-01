<script>
	import '../app.css';
	import { goto } from '$app/navigation';
	import { user } from '$lib/stores/auth';
	import { supabase } from '$lib/supabaseClient';
	import { onMount } from 'svelte';

	let isLogin = true;
	let showMenu = false;
	let inactivityTimeout;

	// Reiniciar timer de inactividad
	function resetInactivity() {
		if (inactivityTimeout) clearTimeout(inactivityTimeout);
		inactivityTimeout = setTimeout(() => {
			logout();
		}, 10 * 60 * 1000); // 10 minutos
	}

	// Logout completo
	async function logout() {
		await supabase.auth.signOut();
		user.set(null);
		localStorage.clear();
		sessionStorage.clear();
		goto('/login');
	}

	// Montaje inicial
	onMount(async () => {
		// Escuchar actividad del usuario para resetear timer
		const events = ['mousemove', 'keydown', 'scroll', 'touchstart'];
		events.forEach(e => window.addEventListener(e, resetInactivity));

		resetInactivity();

		// Comprobar sesión actual
		const { data } = await supabase.auth.getUser();
		if (data?.user) user.set(data.user);
	});

	async function handleClick() {
		if ($user) {
			logout();
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

<header class="top-0 z-10 flex items-center justify-between p-4">
	<!-- Logo -->
	<a href="/" class="flex items-center space-x-3">
		<div class="logo h-10 w-10 rounded-full bg-gray-200"></div>
		<span class="text-2xl font-bold text-gray-800">Ero Senin</span>
	</a>

	<!-- Botón menú / usuario -->
	{#if $user}
		<div class="relative">
			<!-- Solo en móvil -->
			<button
				class="flex h-6 w-8 flex-col justify-between rounded-lg p-1 block md:hidden"
				on:click={toggleMenu}
				aria-label="Abrir menú de usuario">
				<span class="block h-1 w-full rounded bg-black"></span>
				<span class="block h-1 w-full rounded bg-black"></span>
				<span class="block h-1 w-full rounded bg-black"></span>
			</button>

			<!-- Desktop -->
			<button
				class="hidden items-center space-x-2 rounded-lg px-4 py-2 text-black sm:flex bold hover:bg-gray-100 font-zita"
				on:click={toggleMenu}
			>
				<span>{$user.user_metadata?.nombre ?? $user.email}</span>
				<svg
					class="h-4 w-4 transform transition-transform duration-200"
					class:rotate-180={showMenu}
					fill="none"
					stroke="currentColor"
					viewBox="0 0 24 24"
					xmlns="http://www.w3.org/2000/svg"
				>
					<path
						stroke-linecap="round"
						stroke-linejoin="round"
						stroke-width="2"
						d="M19 9l-7 7-7-7"
					/>
				</svg>
			</button>

			{#if showMenu}
				<div class="absolute right-0 z-50 mt-2 w-48 rounded-lg border bg-white shadow-lg">
					<button on:click={goToProfile} class="block w-full px-4 py-2 text-left hover:bg-gray-100">
						👤 Mi Perfil
					</button>
					<button on:click={goToSuscripciones} class="block w-full px-4 py-2 text-left hover:bg-gray-100">
						💳 Suscripciones
					</button>
					<button on:click={goToSettings} class="block w-full px-4 py-2 text-left hover:bg-gray-100">
						⚙️ Configuración
					</button>
					<button on:click={goToAyuda} class="block w-full px-4 py-2 text-left hover:bg-gray-100">
						❓ Ayuda
					</button>
					<button
						on:click={logout}
						class="block w-full px-4 py-2 text-left text-red-600 hover:bg-red-100"
					>
						🚪 Cerrar Sesión
					</button>
				</div>
			{/if}
		</div>
	{:else}
		<button class="rounded-lg bg-green-500 px-4 py-2 text-white" on:click={handleClick}>
			{isLogin ? 'Acceder' : 'Registrarse'}
		</button>
	{/if}
</header>

<main class="flex-grow">
	<slot />
</main>

<footer class="mt-auto bg-gray- py-8 text-gray-500">
	<div class="mx-auto grid max-w-6xl gap-8 px-4 text-sm md:grid-cols-3">
		<div>
			<h3 class="mb-3 text-lg font-semibold">Sobre Nosotros</h3>
			<p>
				Somos una plataforma de entretenimiento para adultos que prioriza la privacidad, la
				seguridad y el contenido exclusivo para mayores de edad.
			</p>
		</div>

		<div>
			<h3 class="mb-3 text-lg font-semibold">Enlaces Útiles</h3>
			<ul class="space-y-2">
				<li><a href="/terminos" class="hover:text-white">Términos y Condiciones</a></li>
				<li><a href="/privacidad" class="hover:text-white">Política de Privacidad</a></li>
				<li><a href="/contacto" class="hover:text-white">Contacto</a></li>
				<li><a href="/soporte" class="hover:text-white">Soporte</a></li>
			</ul>
		</div>

		<div>
			<h3 class="mb-3 text-lg font-semibold ">Información Legal</h3>
			<p>
				Solo para mayores de 18 años. Todo el contenido cumple con las leyes internacionales de
				consentimiento y protección.
			</p>
			<p class="mt-2 text-xs text-gray-400">
				&copy; {new Date().getFullYear()} SeninPrivate. Todos los derechos reservados.
			</p>
		</div>
	</div>

	<div class="mt-8 pt-4 text-center text-xs text-gray-500">
		Diseñado con privacidad y seguridad en mente.
	</div>
</footer>
