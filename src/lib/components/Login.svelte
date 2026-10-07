<script>
  import { goto } from '$app/navigation';
  import { session } from '$lib/stores/auth';
  import { supabase } from '$lib/supabaseClient'; // ✅ Importa el cliente único
  import { authErrorMessage } from '$lib/authProfile';

  const CALLBACK_PATH = '/auth/callback';

  let credential = ''; // email o teléfono
  let password = '';
  let showPassword = false;
  let error = '';
  let loading = false;

  // Redirigir si ya está logeado
  $: if ($session?.user) {
    goto('/');
  }

  async function login() {
    error = '';

    if (!credential.trim() || !password.trim()) {
      error = 'Completa todos los campos';
      return;
    }

    loading = true;

    try {
      const value = credential.trim();
      /** @type {{ email: string; password: string } | { phone: string; password: string }} */
      const credentials = value.startsWith('+')
        ? { phone: value, password }
        : { email: value, password };

      const { error: authError } = await supabase.auth.signInWithPassword(credentials);

      if (authError) {
        error = authErrorMessage(authError, 'No pudimos iniciar sesión.');
        return;
      }

      // Login exitoso
      goto('/');
    } catch (e) {
      error = authErrorMessage(e, 'Error al iniciar sesión');
    } finally {
      loading = false;
    }
  }

  async function loginWithGoogle() {
    error = '';
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

<div class="mx-auto mt-32 w-full max-w-md rounded-2xl bg-gradient-to-br from-pink-50 via-rose-50 to-fuchsia-50 p-8 shadow-2xl border border-pink-200">
  <h2 class="mb-8 text-center text-3xl font-bold text-pink-900 drop-shadow-sm">
    ¡Te extrañamos, preciosa! 💕
  </h2>

  {#if error}
    <div class="mb-6 rounded-lg bg-red-100 p-4 text-center text-red-700 border border-red-300 shadow-sm">
      {error}
    </div>
  {/if}

  <form on:submit|preventDefault={login} class="space-y-6">

    <!-- Email o Teléfono -->
    <div>
      <label class="block text-pink-800 font-medium mb-2">Email o Teléfono</label>
      <input
        type="text"
        bind:value={credential}
        placeholder="+595981234567 o hola@ejemplo.com"
        required
        class="w-full rounded-xl border-2 border-pink-200 bg-white/80 px-5 py-3.5 text-pink-900 placeholder-pink-400 focus:border-fuchsia-500 focus:outline-none focus:ring-4 focus:ring-fuchsia-100 transition"
      />
    </div>

    <!-- Contraseña -->
    <div class="relative">
      <label class="block text-pink-800 font-medium mb-2">Contraseña</label>
      <input
        type={showPassword ? 'text' : 'password'}
        bind:value={password}
        placeholder="••••••••"
        required
        class="w-full rounded-xl border-2 border-pink-200 bg-white/80 px-5 py-3.5 pr-14 text-pink-900 focus:border-fuchsia-500 focus:outline-none focus:ring-4 focus:ring-fuchsia-100 transition"
      />
      <button
        type="button"
        on:click={() => showPassword = !showPassword}
        class="absolute right-3 top-11 text-pink-600 hover:text-fuchsia-700 font-medium text-sm"
      >
        {showPassword ? 'Ocultar' : 'Mostrar'}
      </button>
    </div>

    <!-- Términos y edad -->
    <p class="text-xs text-pink-700 leading-relaxed text-center mb-6">
      Al iniciar sesión aceptas nuestros 
      <a href="/terminos" class="underline hover:text-fuchsia-700">Términos de servicio</a> y 
      <a href="/privacidad" class="underline hover:text-fuchsia-700">Política de privacidad</a>, 
      y confirmas que tienes al menos <strong>18 años</strong>.
    </p>

    <!-- Botón sexy -->
    <button
      type="submit"
      disabled={loading}
      class="w-full rounded-xl bg-gradient-to-r from-pink-600 to-fuchsia-600 py-4 font-bold text-white text-lg shadow-lg hover:from-pink-700 hover:to-fuchsia-700 transform hover:scale-105 transition-all duration-200 disabled:opacity-60"
    >
      {loading ? 'Entrando...' : 'Entrar al paraíso 🔥'}
    </button>
  </form>

  <!-- Separador -->
  <div class="my-6 flex items-center gap-3">
    <span class="h-px flex-1 bg-pink-300"></span>
    <span class="text-xs font-semibold uppercase tracking-widest text-pink-500">o</span>
    <span class="h-px flex-1 bg-pink-300"></span>
  </div>

  <!-- Google OAuth -->
  <button
    type="button"
    on:click={loginWithGoogle}
    disabled={loading}
    class="flex w-full items-center justify-center gap-3 rounded-xl border-2 border-pink-200 bg-white/90 px-5 py-3.5 font-bold text-pink-900 shadow-md transition hover:border-fuchsia-400 hover:shadow-lg disabled:opacity-60"
  >
    <svg class="h-6 w-6" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="#4285F4" d="M23.52 12.27c0-.85-.08-1.67-.22-2.45H12v4.64h6.46a5.52 5.52 0 0 1-2.4 3.62v3h3.88c2.27-2.09 3.58-5.17 3.58-8.81z" />
      <path fill="#34A853" d="M12 24c3.24 0 5.95-1.08 7.93-2.91l-3.88-3a7.2 7.2 0 0 1-10.72-3.78H1.34v3.09A12 12 0 0 0 12 24z" />
      <path fill="#FBBC05" d="M5.33 14.31a7.2 7.2 0 0 1 0-4.6V6.62H1.34a12 12 0 0 0 0 10.78l3.99-3.09z" />
      <path fill="#EA4335" d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0A12 12 0 0 0 1.34 6.62l3.99 3.09A7.15 7.15 0 0 1 12 4.75z" />
    </svg>
    Entrar con Google
  </button>

  <p class="mt-6 text-sm text-center text-pink-800">
    ¿Todavía no tenés cuenta?
    <a href="/register" class="font-semibold underline hover:text-fuchsia-700">Registrate</a>
  </p>
</div>