<script>
	import { goto } from '$app/navigation';
	import { supabase } from '$lib/supabaseClient'; // ✅ Usa la instancia global
	import { session } from '$lib/stores/auth';
	import { ensureProfile, authErrorMessage } from '$lib/authProfile';

	// Redirigir si ya está logeado
	$: if ($session) {
		goto('/');
	}

	const CALLBACK_PATH = '/auth/callback';
	const PHONE_PATTERN = /^\+[1-9]\d{6,14}$/;

	let method = 'email'; // 'email' | 'phone'

	let email = '';
	let password = '';
	let repeatPassword = '';
	let showPassword = false;
	let showRepeat = false;
	let error = '';
	let message = '';
	let loading = false;

	// Teléfono + OTP
	let phone = '';
	let otp = '';
	let otpSent = false;

	async function register() {
		error = '';
		message = '';
		loading = true;

		try {
			if (method === 'email') {
				await registerWithEmail();
			} else {
				await registerWithPhone();
			}
		} catch (e) {
			error = authErrorMessage(e);
		} finally {
			loading = false;
		}
	}

	async function registerWithEmail() {
		const mail = email.trim();

		if (!mail || !password || !repeatPassword) {
			error = 'Completa todos los campos';
			return;
		}
		if (!/^\S+@\S+\.\S+$/.test(mail)) {
			error = 'El formato del correo no es válido';
			return;
		}
		if (password.length < 6) {
			error = 'La contraseña debe tener al menos 6 caracteres';
			return;
		}
		if (password !== repeatPassword) {
			error = 'Las contraseñas no coinciden';
			return;
		}

		const { data, error: authError } = await supabase.auth.signUp({
			email: mail,
			password,
			options: { emailRedirectTo: `${window.location.origin}${CALLBACK_PATH}` }
		});

		if (authError) {
			error = authErrorMessage(authError);
			return;
		}

		// Sin sesión = Supabase exige confirmar el correo. No se simula sesión.
		if (!data.session) {
			email = '';
			password = '';
			repeatPassword = '';
			message =
				'Te enviamos un enlace de confirmación a tu correo. Revisá tu bandeja (y spam) para activarlo.';
			return;
		}

		// Confirmación automática activada en Supabase: hay sesión real.
		await ensureProfile(data.user);
		email = '';
		password = '';
		repeatPassword = '';
		goto('/');
	}

	async function registerWithPhone() {
		const number = phone.trim();

		if (!otpSent) {
			if (!PHONE_PATTERN.test(number)) {
				error = 'Ingresá el teléfono en formato internacional. Ej: +595981234567';
				return;
			}

			const { error: otpError } = await supabase.auth.signInWithOtp({
				phone: number,
				options: { shouldCreateUser: true }
			});

			if (otpError) {
				error = authErrorMessage(otpError);
				return;
			}

			otpSent = true;
			message = `Te enviamos un código por SMS al ${number}.`;
			return;
		}

		if (!otp.trim()) {
			error = 'Ingresá el código que recibiste por SMS';
			return;
		}

		const { data, error: verifyError } = await supabase.auth.verifyOtp({
			phone: number,
			token: otp.trim(),
			type: 'sms'
		});

		if (verifyError) {
			error = authErrorMessage(verifyError, 'El código es incorrecto o expiró.');
			return;
		}

		await ensureProfile(data.user);
		phone = '';
		otp = '';
		goto('/');
	}

	function resendOtp() {
		otp = '';
		otpSent = false;
		message = '';
		error = '';
	}

	async function registerWithGoogle() {
		error = '';
		message = '';
		loading = true;

		const { error: oauthError } = await supabase.auth.signInWithOAuth({
			provider: 'google',
			options: { redirectTo: `${window.location.origin}${CALLBACK_PATH}` }
		});

		// Si no hay error, el navegador ya está redirigiendo a Google.
		if (oauthError) {
			loading = false;
			error = authErrorMessage(oauthError);
		}
	}
</script>

<div
	class="mx-auto mt-32 w-full max-w-md rounded-2xl border border-pink-200 bg-gradient-to-br from-pink-50 via-rose-50 to-fuchsia-50 p-8 shadow-2xl"
>
	<h2 class="mb-8 text-center text-3xl font-bold text-pink-900 drop-shadow-sm">
		Únete a Agua en la Boca 💋
	</h2>

	{#if error}
		<div class="mb-5 rounded-lg border border-red-300 bg-red-100 p-4 text-center text-red-700">
			{error}
		</div>
	{/if}

	{#if message}
		<div
			class="mb-5 rounded-lg border border-pink-300 bg-gradient-to-r from-pink-100 to-rose-100 p-5 text-center text-pink-800 shadow-inner"
		>
			<p class="text-lg font-bold">¡Bienvenida, preciosa!</p>
			<p class="mt-1">{message}</p>
		</div>
	{/if}

	<!-- Selector de método -->
	<div class="mb-6 grid grid-cols-2 gap-2 rounded-xl border border-pink-200 bg-white/60 p-1">
		<button
			type="button"
			on:click={() => {
				method = 'email';
				error = '';
				message = '';
				otpSent = false;
			}}
			class="rounded-lg px-4 py-2 font-medium transition {method === 'email'
				? 'bg-gradient-to-r from-pink-600 to-fuchsia-600 text-white shadow'
				: 'text-pink-700 hover:text-fuchsia-700'}"
		>
			Email
		</button>
		<button
			type="button"
			on:click={() => {
				method = 'phone';
				error = '';
				message = '';
				otpSent = false;
			}}
			class="rounded-lg px-4 py-2 font-medium transition {method === 'phone'
				? 'bg-gradient-to-r from-pink-600 to-fuchsia-600 text-white shadow'
				: 'text-pink-700 hover:text-fuchsia-700'}"
		>
			Teléfono
		</button>
	</div>

	{#if method === 'email'}
		<form on:submit|preventDefault={register} class="space-y-6">
			<!-- Email -->
			<div>
				<label for="reg-email" class="mb-2 block font-medium text-pink-800">Tu email</label>
				<input
					id="reg-email"
					type="email"
					bind:value={email}
					placeholder="tunombre@ejemplo.com"
					autocomplete="email"
					required
					class="w-full rounded-xl border-2 border-pink-200 bg-white/80 px-5 py-3.5 text-pink-900 placeholder-pink-400 transition focus:border-fuchsia-500 focus:ring-4 focus:ring-fuchsia-100 focus:outline-none"
				/>
			</div>

			<!-- Contraseña -->
			<div class="relative">
				<label for="reg-password" class="mb-2 block font-medium text-pink-800">Contraseña</label>
				<input
					id="reg-password"
					type={showPassword ? 'text' : 'password'}
					bind:value={password}
					placeholder="••••••••"
					autocomplete="new-password"
					required
					class="w-full rounded-xl border-2 border-pink-200 bg-white/80 px-5 py-3.5 pr-14 text-pink-900 transition focus:border-fuchsia-500 focus:ring-4 focus:ring-fuchsia-100 focus:outline-none"
				/>
				<button
					type="button"
					on:click={() => (showPassword = !showPassword)}
					class="absolute top-11 right-3 text-sm font-medium text-pink-600 hover:text-fuchsia-700"
				>
					{showPassword ? 'Ocultar' : 'Mostrar'}
				</button>
			</div>

			<!-- Repetir contraseña -->
			<div class="relative">
				<label for="reg-password-2" class="mb-2 block font-medium text-pink-800"
					>Repetir contraseña</label
				>
				<input
					id="reg-password-2"
					type={showRepeat ? 'text' : 'password'}
					bind:value={repeatPassword}
					placeholder="••••••••"
					autocomplete="new-password"
					required
					class="w-full rounded-xl border-2 border-pink-200 bg-white/80 px-5 py-3.5 pr-14 text-pink-900 transition focus:border-fuchsia-500 focus:ring-4 focus:ring-fuchsia-100 focus:outline-none"
				/>
				<button
					type="button"
					on:click={() => (showRepeat = !showRepeat)}
					class="absolute top-11 right-3 text-sm font-medium text-pink-600 hover:text-fuchsia-700"
				>
					{showRepeat ? 'Ocultar' : 'Mostrar'}
				</button>
			</div>

			<button
				type="submit"
				disabled={loading}
				class="w-full transform rounded-xl bg-gradient-to-r from-pink-600 to-fuchsia-600 py-4 text-lg font-bold text-white shadow-lg transition-all duration-200 hover:scale-105 hover:from-pink-700 hover:to-fuchsia-700 disabled:opacity-60"
			>
				{loading ? 'Creando cuenta...' : 'Entrar al paraíso 💕'}
			</button>
		</form>
	{:else}
		<form on:submit|preventDefault={register} class="space-y-6">
			<div>
				<label for="reg-phone" class="mb-2 block font-medium text-pink-800">Tu teléfono</label>
				<input
					id="reg-phone"
					type="tel"
					bind:value={phone}
					placeholder="+595981234567"
					autocomplete="tel"
					required
					disabled={otpSent}
					class="w-full rounded-xl border-2 border-pink-200 bg-white/80 px-5 py-3.5 text-pink-900 placeholder-pink-400 transition focus:border-fuchsia-500 focus:ring-4 focus:ring-fuchsia-100 focus:outline-none disabled:opacity-60"
				/>
				<p class="mt-1 text-xs text-pink-600">Formato internacional, ej: +595981234567</p>
			</div>

			{#if otpSent}
				<div>
					<label for="reg-otp" class="mb-2 block font-medium text-pink-800">Código SMS</label>
					<input
						id="reg-otp"
						type="text"
						inputmode="numeric"
						bind:value={otp}
						placeholder="123456"
						autocomplete="one-time-code"
						required
						class="w-full rounded-xl border-2 border-pink-200 bg-white/80 px-5 py-3.5 tracking-widest text-pink-900 placeholder-pink-400 transition focus:border-fuchsia-500 focus:ring-4 focus:ring-fuchsia-100 focus:outline-none"
					/>
					<button
						type="button"
						on:click={resendOtp}
						class="mt-1 text-xs text-fuchsia-700 underline"
					>
						Usar otro número
					</button>
				</div>
			{/if}

			<button
				type="submit"
				disabled={loading}
				class="w-full transform rounded-xl bg-gradient-to-r from-pink-600 to-fuchsia-600 py-4 text-lg font-bold text-white shadow-lg transition-all duration-200 hover:scale-105 hover:from-pink-700 hover:to-fuchsia-700 disabled:opacity-60"
			>
				{#if loading}
					Enviando...
				{:else if otpSent}
					Verificar código ✅
				{:else}
					Enviar código SMS 📱
				{/if}
			</button>
		</form>
	{/if}

	<!-- Separador -->
	<div class="my-6 flex items-center gap-3">
		<span class="h-px flex-1 bg-pink-300"></span>
		<span class="text-xs font-semibold tracking-widest text-pink-500 uppercase">o</span>
		<span class="h-px flex-1 bg-pink-300"></span>
	</div>

	<!-- Google OAuth -->
	<button
		type="button"
		on:click={registerWithGoogle}
		disabled={loading}
		class="flex w-full items-center justify-center gap-3 rounded-xl border-2 border-pink-200 bg-white/90 px-5 py-3.5 font-bold text-pink-900 shadow-md transition hover:border-fuchsia-400 hover:shadow-lg disabled:opacity-60"
	>
		<svg class="h-6 w-6" viewBox="0 0 24 24" aria-hidden="true">
			<path
				fill="#4285F4"
				d="M23.52 12.27c0-.85-.08-1.67-.22-2.45H12v4.64h6.46a5.52 5.52 0 0 1-2.4 3.62v3h3.88c2.27-2.09 3.58-5.17 3.58-8.81z"
			/>
			<path
				fill="#34A853"
				d="M12 24c3.24 0 5.95-1.08 7.93-2.91l-3.88-3a7.2 7.2 0 0 1-10.72-3.78H1.34v3.09A12 12 0 0 0 12 24z"
			/>
			<path
				fill="#FBBC05"
				d="M5.33 14.31a7.2 7.2 0 0 1 0-4.6V6.62H1.34a12 12 0 0 0 0 10.78l3.99-3.09z"
			/>
			<path
				fill="#EA4335"
				d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0A12 12 0 0 0 1.34 6.62l3.99 3.09A7.15 7.15 0 0 1 12 4.75z"
			/>
		</svg>
		Registrate con Google
	</button>

	<p class="mt-6 text-center text-xs leading-relaxed text-pink-700">
		Al registrarte aceptas nuestros
		<a href="/terminos" class="underline hover:text-fuchsia-700">Términos de servicio</a> y
		<a href="/privacidad" class="underline hover:text-fuchsia-700">Política de privacidad</a>, y
		confirmas que tienes al menos <strong>18 años</strong>.
	</p>

	<p class="mt-4 text-center text-sm text-pink-800">
		¿Ya tenés cuenta?
		<a href="/login" class="font-semibold underline hover:text-fuchsia-700">Iniciá sesión</a>
	</p>
</div>
