<script>
  import { goto } from '$app/navigation';
  import { user, session } from '$lib/stores/auth';
  import { supabase } from '$lib/supabaseClient'; // ✅ Importa el cliente único

  import { get } from 'svelte/store';

  let credential = ''; // email o teléfono
  let password = '';
  let showPassword = false;
  let error = '';

  // Redirigir si ya está logeado
  $: if (get(session)?.user) {
    goto('/');
  }

  async function login() {
    if (!credential.trim() || !password.trim()) {
      error = 'Completa todos los campos';
      return;
    }

    try {
      const { data, error: authError } = await supabase.auth.signInWithPassword({
        email: credential.includes('@') ? credential : undefined,
        phone: credential.startsWith('+') ? credential : undefined,
        password
      });

      if (authError) {
        // Usuario no existe -> redirigir a Register
        if (authError.message.includes('User not found')) {
          goto('/register', { state: { credential, password } });
        } else {
          error = authError.message;
        }
        return;
      }

      // Login exitoso
      user.set(data.user);
      goto('/');
    } catch (e) {
      error = e.message || 'Error al iniciar sesión';
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
      class="w-full rounded-xl bg-gradient-to-r from-pink-600 to-fuchsia-600 py-4 font-bold text-white text-lg shadow-lg hover:from-pink-700 hover:to-fuchsia-700 transform hover:scale-105 transition-all duration-200"
    >
      Entrar al paraíso 🔥
    </button>
  </form>
</div>