<script>
  import { supabase } from '$lib/supabaseClient';

  /** @type {string} */
  export let userId; // ID del usuario para nombrar la foto
  /** @type {((url: string) => void) | undefined} */
  export let onUpload; // Callback después de subir

  /** @type {FileList | null} */
  let files = null; // FileList vinculado al input
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
      // 1) Pedir URL firmada de subida (bucket public)
      const res = await fetch('/api/media/upload', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tipo: 'avatar',
          filename: file.name,
          contentType: file.type,
          es_privado: false
        })
      });
      const req = await res.json();
      if (!res.ok) throw new Error(req.error || 'Error generando subida');

      // 2) Subir directo a R2
      const put = await fetch(req.upload_url, {
        method: 'PUT',
        headers: { 'Content-Type': file.type },
        body: file
      });
      if (!put.ok) throw new Error('Error subiendo archivo a R2');

      // 3) Actualizar el avatar en profiles
      const { error: updateError } = await supabase
        .from('profiles')
        .update({ avatar_key: req.storage_key, avatar_url: req.public_url })
        .eq('id', userId);

      if (updateError) throw updateError;

      if (onUpload) onUpload(req.public_url);
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
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
