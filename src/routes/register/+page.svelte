<script>
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';
  import SignUp from '$lib/components/Register.svelte';
  import UploadPhoto from '$lib/components/UploadPhoto.svelte';
  import { supabase } from '$lib/supabaseClient';

  let userId = null;

  async function refreshUserId() {
    const { data } = await supabase.auth.getSession();
    userId = data.session?.user?.id ?? null;
  }

  onMount(refreshUserId);

  async function handleSignupSuccess() {
    await refreshUserId();
    if (!userId) goto('/login'); // requiere confirmación de email
  }
</script>

<div class="flex items-center justify-center p-4">
  {#if !userId}
    <SignUp onSuccess={handleSignupSuccess} />
  {:else}
    <div class="bg-white p-6 rounded-lg shadow-md max-w-md mx-auto">
      <h2 class="text-2xl font-bold mb-4">Subí tu Foto</h2>
      <UploadPhoto {userId} onUpload={() => goto('/')} />
    </div>
  {/if}
</div>
