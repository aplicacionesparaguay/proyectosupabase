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

<div class="max-w-md mx-auto p-6 bg-white rounded-lg shadow-md">
  <h2 class="text-2xl font-bold mb-4">Iniciar Sesión</h2>
  {#if error}
    <p class="text-red-500 mb-3">{error}</p>
  {/if}

  <form on:submit|preventDefault={login}>
    <div class="mb-4">
      <label class="block text-gray-700 mb-1">Email o Teléfono</label>
      <input
        type="text"
        bind:value={credential}
        placeholder="+59512345678 o ejemplo@email.com"
        class="border p-2 rounded w-full"
        required
      />
    </div>

    <div class="mb-4 relative">
      <label class="block text-gray-700 mb-1">Contraseña</label>
      <input
        type={showPassword ? 'text' : 'password'}
        bind:value={password}
        placeholder="Contraseña"
        class="border p-2 rounded w-full"
        required
      />
      <button
        type="button"
        on:click={() => showPassword = !showPassword}
        class="absolute right-2 top-1/2 -translate-y-1/2 text-gray-500"
      >
        {showPassword ? 'Ocultar' : 'Mostrar'}
      </button>
    </div>

    <p class="text-xs text-gray-500 mb-4">
      Al iniciar sesión y usar SeninPrivate.com, aceptas nuestros
      <a href="/terminos" class="underline">Términos de servicio</a> y
      <a href="/privacidad" class="underline">Política de privacidad</a>, y confirmas que tienes al menos 18 años.
    </p>

    <button type="submit" class="bg-green-500 text-white px-4 py-2 rounded w-full hover:bg-green-600">
      Continuar
    </button>
  </form>
</div>
