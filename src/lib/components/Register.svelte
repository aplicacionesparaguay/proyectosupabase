<script>
  import { goto } from '$app/navigation';
  import { supabase } from '$lib/supabaseClient'; // ✅ Usa la instancia global
  import { session } from '$lib/stores/auth';	

  // Redirigir si ya está logeado
  $: if ($session) {
    goto('/');
  }

  let email = '';
  let password = '';
  let repeatPassword = '';
  let showPassword = false;
  let showRepeat = false;
  let error = '';
  let message = '';

  async function register() {
    error = '';
    message = '';

    if (!email.trim() || !password.trim() || !repeatPassword.trim()) {
      error = 'Completa todos los campos';
      return;
    }

    if (password !== repeatPassword) {
      error = 'Las contraseñas no coinciden';
      return;
    }

    try {
      const { data, error: authError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          emailRedirectTo: `${window.location.origin}/`
        }
      });

      if (authError) {
        error = authError.message;
        return;
      }

      message = 'Se ha enviado un enlace de verificación a tu correo. Por favor, revísalo.';

      // Limpiar campos
      email = '';
      password = '';
      repeatPassword = '';
    } catch (e) {
      error = e.message || 'Error al registrarse';
    }
  }
</script>

<div class="mx-auto mt-32 w-full max-w-md rounded-2xl bg-gradient-to-br from-pink-50 via-rose-50 to-fuchsia-50 p-8 shadow-2xl border border-pink-200">
  <h2 class="mb-8 text-center text-3xl font-bold text-pink-900 drop-shadow-sm">
    Únete a Kuña Guapa 💋
  </h2>

  {#if error}
    <div class="mb-5 rounded-lg bg-red-100 p-4 text-center text-red-700 border border-red-300">
      {error}
    </div>
  {/if}

  {#if message}
    <div class="mb-5 rounded-lg bg-gradient-to-r from-pink-100 to-rose-100 p-5 text-center text-pink-800 border border-pink-300 shadow-inner">
      <p class="font-bold text-lg">¡Bienvenida, preciosa!</p>
      <p class="mt-1">{message}</p>
    </div>
  {/if}

  <form on:submit|preventDefault={register} class="space-y-6">
    <!-- Email -->
    <div>
      <label class="block text-pink-800 font-medium mb-2">Tu email</label>
      <input
        type="email"
        bind:value={email}
        placeholder="tunombre@ejemplo.com"
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
        on:click={() => (showPassword = !showPassword)}
        class="absolute right-3 top-11 text-pink-600 hover:text-fuchsia-700 font-medium text-sm"
      >
        {showPassword ? 'Ocultar' : 'Mostrar'}
      </button>
    </div>

    <!-- Repetir contraseña -->
    <div class="relative">
      <label class="block text-pink-800 font-medium mb-2">Repetir contraseña</label>
      <input
        type={showRepeat ? 'text' : 'password'}
        bind:value={repeatPassword}
        placeholder="••••••••"
        required
        class="w-full rounded-xl border-2 border-pink-200 bg-white/80 px-5 py-3.5 pr-14 text-pink-900 focus:border-fuchsia-500 focus:outline-none focus:ring-4 focus:ring-fuchsia-100 transition"
      />
      <button
        type="button"
        on:click={() => (showRepeat = !showRepeat)}
        class="absolute right-3 top-11 text-pink-600 hover:text-fuchsia-700 font-medium text-sm"
      >
        {showRepeat ? 'Ocultar' : 'Mostrar'}
      </button>
    </div>

    <!-- Botón -->
    <button
      type="submit"
      class="w-full rounded-xl bg-gradient-to-r from-pink-600 to-fuchsia-600 py-4 font-bold text-white text-lg shadow-lg hover:from-pink-700 hover:to-fuchsia-700 transform hover:scale-105 transition-all duration-200"
    >
      Entrar al paraíso 💕
    </button>
  </form>
</div>