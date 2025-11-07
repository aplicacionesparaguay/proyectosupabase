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
  let nombre = '';
  let error = '';
  let message = '';

  async function register() {
    error = '';
    message = '';

    if (!email.trim() || !password.trim() || !repeatPassword.trim() || !nombre.trim()) {
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
          data: { nombre }, // ✅ guarda el nombre en el perfil
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
      nombre = '';
    } catch (e) {
      error = e.message || 'Error al registrarse';
    }
  }
</script>

<div class="max-w-md mx-auto p-6 bg-white rounded-lg shadow-md">
  <h2 class="text-2xl font-bold mb-4">Registro</h2>

  {#if error}
    <p class="text-red-500 mb-3">{error}</p>
  {/if}

  {#if message}
    <div class="bg-green-100 border-l-4 border-green-500 text-green-700 p-4 mb-3 rounded shadow-md">
      <p class="font-semibold">¡Registro exitoso!</p>
      <p>{message}</p>
    </div>
  {/if}

  <form on:submit|preventDefault={register}>
    <div class="mb-4">
      <label class="block text-gray-700 mb-1">Email</label>
      <input
        type="email"
        bind:value={email}
        placeholder="ejemplo@email.com"
        class="border p-2 rounded w-full"
        required
      />
    </div>

    <div class="mb-4">
      <label class="block text-gray-700 mb-1">Nombre o Alias</label>
      <input
        type="text"
        bind:value={nombre}
        placeholder="Tu nombre visible"
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
        on:click={() => (showPassword = !showPassword)}
        class="absolute right-2 top-1/2 -translate-y-1/2 text-gray-500"
      >
        {showPassword ? 'Ocultar' : 'Mostrar'}
      </button>
    </div>

    <div class="mb-4 relative">
      <label class="block text-gray-700 mb-1">Repetir Contraseña</label>
      <input
        type={showRepeat ? 'text' : 'password'}
        bind:value={repeatPassword}
        placeholder="Repite tu contraseña"
        class="border p-2 rounded w-full"
        required
      />
      <button
        type="button"
        on:click={() => (showRepeat = !showRepeat)}
        class="absolute right-2 top-1/2 -translate-y-1/2 text-gray-500"
      >
        {showRepeat ? 'Ocultar' : 'Mostrar'}
      </button>
    </div>

    <button
      type="submit"
      class="bg-green-500 text-white px-4 py-2 rounded w-full hover:bg-green-600"
    >
      Continuar
    </button>
  </form>
</div>
