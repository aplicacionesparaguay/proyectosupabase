<script>
  import SignUp from '$lib/components/Register.svelte';
  import UploadPhoto from '$lib/components/UploadPhoto.svelte';

  let userId = null;
</script>

<div class="flex items-center justify-center p-4">
  {#if !userId}
    <SignUp onSuccess={() => userId = 'id-del-usuario-desde-auth'} /> <!-- Reemplazá con el ID real del auth -->
  {:else}
    <div class="bg-white p-6 rounded-lg shadow-md max-w-md mx-auto">
      <h2 class="text-2xl font-bold mb-4">Subí tu Foto</h2>
      <UploadPhoto {userId} onUpload={() => goto('/')} /> <!-- Redirige al grid después de subir -->
    </div>
  {/if}
</div>  
