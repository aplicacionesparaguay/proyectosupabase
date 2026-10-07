<script>
  import { goto } from '$app/navigation';
  import SignUp from '$lib/components/Register.svelte';
  import UploadPhoto from '$lib/components/UploadPhoto.svelte';

  /**
   * ID de auth con el que se cargarán las fotos.
   *
   * SignUp (Register.svelte) no declara ninguna prop `onSuccess`, por lo que
   * nunca invoca este callback y `userId` permanece vacío: el bloque de
   * UploadPhoto queda inaccesible, igual que antes de tipar.
   * @type {string}
   */
  let userId = '';
</script>

<div class="flex items-center justify-center p-4">
  {#if !userId}
    <SignUp />
  {:else}
    <div class="bg-white p-6 rounded-lg shadow-md max-w-md mx-auto">
      <h2 class="text-2xl font-bold mb-4">Subí tu Foto</h2>
      <UploadPhoto {userId} onUpload={() => goto('/')} /> <!-- Redirige al grid después de subir -->
    </div>
  {/if}
</div>