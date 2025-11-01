<script>
  import { supabase } from '$lib/supabaseClient';

  export let userId; // ID del usuario para nombrar la foto
  export let onUpload; // Callback después de subir

  let files; // FileList vinculado al input
  let uploading = false;
  let error = '';

  async function uploadPhoto() {
    const file = files?.[0];
    if (!file) {
      error = 'Selecciona un archivo';
      return;
    }

    uploading = true;
    error = '';

    try {
      const fileExt = file.name.split('.').pop();
      const filePath = `${userId}/profile.${fileExt}`;

      // Subir al bucket 'profiles'
      const { data: uploadData, error: uploadError } = await supabase.storage
        .from('profiles')
        .upload(filePath, file, { upsert: true });
      if (uploadError) throw uploadError;

      // Obtener URL pública (manejar posibles nombres de campo según la versión del SDK)
      const publicResponse = supabase.storage.from('profiles').getPublicUrl(filePath);
      // getPublicUrl puede devolver { data: { publicUrl } } o { publicURL } según versión
      const publicURL =
        (publicResponse?.data && (publicResponse.data.publicUrl ?? publicResponse.data.publicURL)) ??
        publicResponse?.publicURL ??
        publicResponse?.publicUrl;

      if (!publicURL) throw new Error('No se pudo obtener la URL pública del archivo');

      // Actualizar la tabla users con la URL
      const { error: updateError } = await supabase
        .from('users')
        .update({ profile_pic: publicURL })
        .eq('id', userId);

      if (updateError) throw updateError;

      if (onUpload) onUpload(publicURL);
    } catch (e) {
      error = e?.message ?? String(e);
      console.error('UploadPhoto error:', e);
    } finally {
      uploading = false;
    }
  }
</script>

<div class="mt-4">
  <input
    type="file"
    accept="image/*"
    bind:files={files}
    class="border rounded-lg p-2 w-full mb-2"
  />
  <button
    on:click={uploadPhoto}
    disabled={uploading}
    class="bg-green-500 text-white px-4 py-2 rounded-lg w-full"
  >
    {uploading ? 'Subiendo...' : 'Subir Foto'}
  </button>
  {#if error}
    <p class="text-red-500 mt-2">{error}</p>
  {/if}
</div>