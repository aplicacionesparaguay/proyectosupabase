<script lang="ts">
	import '..//app.css';
	import { goto } from '$app/navigation';
	import { user } from '$lib/stores/auth';
	import { supabase } from '$lib/supabaseClient';
	import { onMount, onDestroy } from 'svelte';
	import { browser } from '$app/environment';

	let showRegister = false;
	let credential = '';
	let password = '';
	let showPassword = false;
	let errorLogin = '';
	let loadingLogin = false;

	let email = '';
	let passwordReg = '';
	let repeatPassword = '';
	let showPasswordReg = false;
	let showRepeat = false;
	let errorReg = '';
	let message = '';
	let loadingReg = false;

	let showMenu = false;
	let menuRef: HTMLDivElement;

	// Variable para almacenar el listener
	let authListener: { data: { subscription: { unsubscribe: () => void } } } | null = null;

	onMount(async () => {
		// Obtener sesión actual
		const { data } = await supabase.auth.getSession();
		if (data.session) {
			user.set(data.session.user);
		}

		// Listener para cambios en autenticación
		authListener = supabase.auth.onAuthStateChange((event, session) => {
			if (session?.user) {
				user.set(session.user);
			} else {
				user.set(null);
			}
		});

		// Cerrar menú al hacer clic fuera (solo en el navegador)
		if (browser) {
			document.addEventListener('click', handleClickOutside);
		}
	});

	onDestroy(() => {
		// Limpiar listener al destruir componente
		if (authListener) {
			authListener.data.subscription.unsubscribe();
		}
		
		// Remover event listener solo en el navegador
		if (browser) {
			document.removeEventListener('click', handleClickOutside);
		}
	});

	function handleClickOutside(event: MouseEvent) {
		if (showMenu && menuRef && !menuRef.contains(event.target as Node)) {
			showMenu = false;
		}
	}

	async function login() {
		errorLogin = '';
		loadingLogin = true;

		if (!credential.trim() || !password.trim()) {
			errorLogin = 'Completa todos los campos';
			loadingLogin = false;
			return;
		}

		// Validar que sea un email
		if (!credential.includes('@')) {
			errorLogin = 'Ingresa un email válido';
			loadingLogin = false;
			return;
		}

		const { error } = await supabase.auth.signInWithPassword({
			email: credential,
			password
		});

		loadingLogin = false;

		if (error) {
			errorLogin = error.message === 'Invalid login credentials' 
				? 'Email o contraseña incorrectos' 
				: error.message;
			return;
		}

		// Limpiar formulario
		credential = '';
		password = '';
		goto('/');
	}

	async function register() {
		errorReg = '';
		message = '';
		loadingReg = true;

		if (!email.trim() || !passwordReg.trim() || !repeatPassword.trim()) {
			errorReg = 'Completa todos los campos';
			loadingReg = false;
			return;
		}

		if (passwordReg.length < 6) {
			errorReg = 'La contraseña debe tener al menos 6 caracteres';
			loadingReg = false;
			return;
		}

		if (passwordReg !== repeatPassword) {
			errorReg = 'Las contraseñas no coinciden';
			loadingReg = false;
			return;
		}

		const { error } = await supabase.auth.signUp({
			email,
			password: passwordReg,
			options: { 
				emailRedirectTo: `${location.origin}/auth/callback`
			}
		});

		loadingReg = false;

		if (error) {
			errorReg = error.message;
			return;
		}

		// Limpiar formulario
		email = '';
		passwordReg = '';
		repeatPassword = '';
		message = 'Se envió enlace de verificación al correo.';
	}

	async function logout() {
		await supabase.auth.signOut();
		showMenu = false;
		goto('/');
	}

	function toggleMenu(event: MouseEvent) {
		event.stopPropagation();
		showMenu = !showMenu;
	}
</script>

{#if $user}
	<!-- Barra de navegación: inferior en móvil, lateral en desktop -->
	<nav class="fixed bottom-0 left-0 right-0 h-16 md:left-0 md:top-0 md:bottom-0 md:right-auto md:w-20 md:h-auto bg-black/90 backdrop-blur-xl border-t md:border-t-0 md:border-r border-pink-900/40 flex flex-row md:flex-col items-center justify-around md:justify-start md:gap-12 md:py-20 px-4 md:px-0 z-50">
		<a href="/" class="hover:opacity-70 transition">
			<img src="/icons/home.svg" alt="Inicio" class="w-7 h-7 md:w-8 md:h-8" />
		</a>
		<a href="/notificaciones" class="hover:opacity-70 transition">
			<img src="/icons/bell.svg" alt="Notificaciones" class="w-7 h-7 md:w-8 md:h-8" />
		</a>
		<a href="/publicar" class="hover:opacity-70 transition">
			<img src="/icons/plus.svg" alt="Publicar" class="w-7 h-7 md:w-8 md:h-8" />
		</a>
		<a href="/mensajes" class="hover:opacity-70 transition">
			<img src="/icons/message.svg" alt="Mensajes" class="w-7 h-7 md:w-8 md:h-8" />
		</a>

		<button on:click={toggleMenu} class="md:mt-auto hover:opacity-70 transition">
			<div class="w-10 h-10 md:w-12 md:h-12 rounded-full bg-gradient-to-r from-pink-600 to-purple-600 flex items-center justify-center text-white font-bold text-lg md:text-xl">
				{$user.email?.[0]?.toUpperCase() || 'U'}
			</div>
		</button>
	</nav>

	{#if showMenu}
		<div bind:this={menuRef} class="fixed left-1/2 -translate-x-1/2 bottom-20 md:left-20 md:bottom-auto md:top-1/2 md:-translate-y-1/2 md:translate-x-0 bg-black/95 rounded-2xl border border-pink-500/50 shadow-2xl z-50 w-64">
			<button on:click={() => { goto('/perfil'); showMenu = false; }} class="block w-full text-left px-6 py-4 text-pink-200 hover:bg-pink-900/50 rounded-t-2xl">Mi Perfil</button>
			<button on:click={() => { goto('/suscripciones'); showMenu = false; }} class="block w-full text-left px-6 py-4 text-pink-200 hover:bg-pink-900/50">Suscripciones</button>
			<button on:click={() => { goto('/pago'); showMenu = false; }} class="block w-full text-left px-6 py-4 text-pink-200 hover:bg-pink-900/50">Forma de pago</button>
			<button on:click={() => { goto('/configuracion'); showMenu = false; }} class="block w-full text-left px-6 py-4 text-pink-200 hover:bg-pink-900/50">Configuración</button>
			<button on:click={logout} class="block w-full text-left px-6 py-4 text-red-400 hover:bg-red-900/50 rounded-b-2xl">Cerrar Sesión</button>
		</div>
	{/if}
{:else}
	<header class="w-full flex h-screen flex-col overflow-hidden bg-white/80 md:flex-row">
		<!-- Lado izquierdo -->
		<div class="flex h-1/3 md:h-auto flex-col items-center justify-center bg-gradient-to-br from-pink-800 to-purple-900 p-6 md:p-12">
			<a href="/" class="group flex items-center space-x-4">
				<div class="h-14 w-14 overflow-hidden rounded-full border-2 border-white/20 shadow-2xl ring-4 shadow-pink-600/40 ring-pink-500/60">
					<img src="/kunaguapa.jpeg" alt="Kuña Guapa" class="h-full w-full object-cover transition duration-700 group-hover:scale-125" />
				</div>
				<span class="bg-gradient-to-r from-pink-400 via-purple-400 to-pink-300 bg-clip-text text-4xl font-black text-transparent">
					Kuña Guapa
				</span>
			</a>
			<h2 class="mt-6 max-w-md text-center text-lg text-white/90">
				Para interactuar con los creadores debes Acceder.
			</h2>
		</div>

		<!-- Lado derecho -->
		<div class="flex flex-1 justify-center p-6 overflow-y-auto">
			<div class="w-full max-w-md">
				{#if !showRegister}
					<h1 class="p-6 text-center text-black text-3xl font-bold">Iniciar Sesión</h1>
					<form on:submit|preventDefault={login} class="space-y-6">
						<input 
							type="email" 
							bind:value={credential} 
							placeholder="Email" 
							disabled={loadingLogin}
							class="w-full rounded-full border border-pink-900/60 bg-white/80 px-6 py-4 text-pink-800 placeholder-pink-500 transition focus:border-pink-500 focus:outline-none disabled:opacity-50" 
						/>
						<div class="relative">
							<input 
								type={showPassword ? 'text' : 'password'} 
								bind:value={password} 
								placeholder="Contraseña" 
								disabled={loadingLogin}
								class="w-full rounded-full border border-pink-900/60 bg-white/80 px-6 py-4 text-pink-800 placeholder-pink-500 transition focus:border-pink-500 focus:outline-none disabled:opacity-50" 
							/>
							<button 
								type="button" 
								on:click={() => showPassword = !showPassword} 
								class="absolute right-3 top-1/2 -translate-y-1/2 text-pink-600 hover:text-fuchsia-700 font-medium text-sm"
							>
								{showPassword ? 'Ocultar' : 'Mostrar'}
							</button>
						</div>
						<p class="text-center text-xs leading-relaxed text-black/70">
							Al iniciar sesión aceptas nuestros
							<a href="/terminos" class="text-black underline hover:text-fuchsia-900">Términos de servicio</a>
							y
							<a href="/privacidad" class="underline hover:text-fuchsia-700">Política de privacidad</a>,
							y confirmas que tienes al menos <strong>18 años</strong>.
						</p>
						<button 
							type="submit" 
							disabled={loadingLogin}
							class="w-full rounded-full bg-gradient-to-r from-pink-600 to-purple-600 py-4 text-lg font-bold text-white shadow-lg transition hover:shadow-pink-600/50 disabled:opacity-50 disabled:cursor-not-allowed"
						>
							{loadingLogin ? 'Iniciando...' : 'Iniciar Sesión'}
						</button>
					</form>
					<p class="mt-6 flex flex-col gap-2 text-center text-pink-900">
						<a href="/recuperar" class="hover:underline">¿Has olvidado la contraseña?</a>
						<button on:click={() => showRegister = true} class="font-bold text-pink-600 hover:underline">
							Regístrate en Kuña Guapa
						</button>
					</p>
				{:else}
					<h1 class="p-6 text-center text-black text-3xl font-bold">Registrarse</h1>
					<form on:submit|preventDefault={register} class="space-y-6">
						<input 
							type="email" 
							bind:value={email} 
							placeholder="Tu email" 
							required 
							disabled={loadingReg}
							class="w-full rounded-full border border-pink-900/60 bg-white/80 px-6 py-4 text-pink-800 placeholder-pink-500 transition focus:border-pink-500 focus:outline-none disabled:opacity-50" 
						/>
						<div class="relative">
							<input 
								type={showPasswordReg ? 'text' : 'password'} 
								bind:value={passwordReg} 
								placeholder="Contraseña (mínimo 6 caracteres)" 
								required 
								disabled={loadingReg}
								class="w-full rounded-full border border-pink-900/60 bg-white/80 px-6 py-4 text-pink-800 placeholder-pink-500 transition focus:border-pink-500 focus:outline-none disabled:opacity-50" 
							/>
							<button 
								type="button" 
								on:click={() => showPasswordReg = !showPasswordReg} 
								class="absolute right-3 top-1/2 -translate-y-1/2 text-pink-600 hover:text-fuchsia-700 font-medium text-sm"
							>
								{showPasswordReg ? 'Ocultar' : 'Mostrar'}
							</button>
						</div>
						<div class="relative">
							<input 
								type={showRepeat ? 'text' : 'password'} 
								bind:value={repeatPassword} 
								placeholder="Repetir contraseña" 
								required 
								disabled={loadingReg}
								class="w-full rounded-full border border-pink-900/60 bg-white/80 px-6 py-4 text-pink-800 placeholder-pink-500 transition focus:border-pink-500 focus:outline-none disabled:opacity-50" 
							/>
							<button 
								type="button" 
								on:click={() => showRepeat = !showRepeat} 
								class="absolute right-3 top-1/2 -translate-y-1/2 text-pink-600 hover:text-fuchsia-700 font-medium text-sm"
							>
								{showRepeat ? 'Ocultar' : 'Mostrar'}
							</button>
						</div>
						<p class="text-center text-xs leading-relaxed text-black/70">
							Al registrarte aceptas nuestros
							<a href="/terminos" class="text-black underline hover:text-fuchsia-900">Términos de servicio</a>
							y
							<a href="/privacidad" class="underline hover:text-fuchsia-700">Política de privacidad</a>,
							y confirmas que tienes al menos <strong>18 años</strong>.
						</p>
						<button 
							type="submit" 
							disabled={loadingReg}
							class="w-full rounded-full bg-gradient-to-r from-pink-600 to-purple-600 py-4 text-lg font-bold text-white shadow-lg transition hover:shadow-pink-600/50 disabled:opacity-50 disabled:cursor-not-allowed"
						>
							{loadingReg ? 'Registrando...' : 'Registrarse 💕'}
						</button>
					</form>
					<p class="mt-6 text-center text-pink-900">
						<button on:click={() => showRegister = false} class="font-bold text-pink-600 hover:underline">
							Volver a Iniciar Sesión
						</button>
					</p>
				{/if}
			</div>
		</div>
	</header>
{/if}

<!-- MODALES DE ALERTAS -->
{#if errorLogin}
	<div class="fixed inset-0 bg-black/70 z-[9999] flex items-center justify-center p-4">
		<div class="bg-red-100 rounded-2xl p-8 max-w-md w-full shadow-2xl relative">
			<button on:click={() => errorLogin = ''} class="absolute top-4 right-4 text-red-700 text-2xl hover:text-red-900">
				×
			</button>
			<p class="text-center text-red-700 font-bold text-xl">
				{errorLogin}
			</p>
		</div>
	</div>
{/if}

{#if errorReg}
	<div class="fixed inset-0 bg-black/70 z-[9999] flex items-center justify-center p-4">
		<div class="bg-red-100 rounded-2xl p-8 max-w-md w-full shadow-2xl relative">
			<button on:click={() => errorReg = ''} class="absolute top-4 right-4 text-red-700 text-2xl hover:text-red-900">
				×
			</button>
			<p class="text-center text-red-700 font-bold text-xl">
				{errorReg}
			</p>
		</div>
	</div>
{/if}

{#if message}
	<div class="fixed inset-0 bg-black/70 z-[9999] flex items-center justify-center p-4">
		<div class="bg-gradient-to-r from-pink-100 to-rose-100 rounded-2xl p-8 max-w-md w-full shadow-2xl relative">
			<button on:click={() => message = ''} class="absolute top-4 right-4 text-pink-700 text-2xl hover:text-pink-900">
				×
			</button>
			<p class="text-center text-pink-800 font-bold text-xl">¡Bienvenido!</p>
			<p class="text-center text-pink-800 mt-2">{message}</p>
		</div>
	</div>
{/if}

<main class="min-h-screen pb-20 md:pb-0 {$user ? 'md:ml-20' : ''}">
	<slot />
</main>

<footer class="border-t border-pink-900/30 py-12 bg-gradient-to-b from-black to-pink-950/20 {$user ? 'md:ml-20' : ''}">
	<div class="mx-auto max-w-7xl px-8">
		<div class="grid gap-16 text-center md:grid-cols-3 md:text-left">
			<div>
				<h3 class="mb-3 bg-gradient-to-r from-pink-400 to-purple-400 bg-clip-text text-2xl font-bold text-transparent">
					Sobre Nosotras
				</h3>
				<p class="text-sm leading-relaxed text-pink-300">
					Somos una plataforma de entretenimiento para adultos que prioriza la privacidad, la seguridad y el contenido exclusivo para mayores de edad.
				</p>
			</div>

			<div>
				<h3 class="mb-3 text-xl font-bold text-pink-400">Enlaces Útiles</h3>
				<ul class="space-y-3 text-pink-200">
					<li><a href="/terminos" class="transition hover:text-pink-400">Términos y Condiciones</a></li>
					<li><a href="/privacidad" class="transition hover:text-pink-400">Política de Privacidad</a></li>
					<li><a href="/contacto" class="transition hover:text-pink-400">Contacto</a></li>
					<li><a href="/soporte" class="transition hover:text-pink-400">Soporte</a></li>
				</ul>
			</div>

			<div>
				<h3 class="mb-3 text-xl font-bold text-pink-400">Información Legal</h3>
				<p class="text-sm leading-relaxed text-pink-300">
					Solo para mayores de 18 años. Todo el contenido cumple con las leyes internacionales de consentimiento y protección.
				</p>
				<p class="mt-6 text-xs text-pink-500">
					© {new Date().getFullYear()} Kuña Guapa. Todos los derechos reservados.
				</p>
			</div>
		</div>

		<div class="mt-12 border-t border-pink-800/50 pt-8 text-center">
			<p class="text-sm text-pink-400 italic">Diseñado con privacidad y seguridad en mente.</p>
		</div>
	</div>
</footer>