<script>
  import { supabase } from '$lib/supabaseClient';

  export let userId; // ID del usuario para nombrar la foto
  export let onUpload; // Callback después de subir
  export let folder = 'profiles'; // Carpeta en R2

  let files; // FileList vinculado al input
  let uploading = false;
  let error = '';
  let progress = 0;

  async function uploadPhoto() {
    const file = files?.[0];
    if (!file) {
      error = 'Selecciona un archivo';
      return;
    }

    uploading = true;
    error = '';
    progress = 0;

    try {
      // 1. Obtener URL prefirmada del servidor
      const response = await fetch('/api/upload/r2', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fileName: file.name,
          contentType: file.type,
          folder,
        }),
      });

      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Error obteniendo URL de subida');

      const { signedUrl, key } = result;

      // 2. Subir archivo directamente a R2 usando la URL prefirmada
      await uploadToR2(signedUrl, file, key);

      // 3. Construir URL pública
      const publicUrl = `${import.meta.env.VITE_R2_PUBLIC_URL}/${key}`;

      // 4. Actualizar la tabla users con la URL
      const { error: updateError } = await supabase
        .from('users')
        .update({ profile_pic: publicUrl })
        .eq('id', userId);

      if (updateError) throw updateError;

      if (onUpload) onUpload(publicUrl);
    } catch (e) {
      error = e?.message ?? String(e);
      console.error('UploadPhoto error:', e);
    } finally {
      uploading = false;
      progress = 0;
    }
  }

  async function uploadToR2(signedUrl, file, key) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();

      xhr.upload.addEventListener('progress', (e) => {
        if (e.lengthComputable) {
          progress = Math.round((e.loaded / e.total) * 100);
        }
      });

      xhr.addEventListener('load', () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve();
        } else {
          reject(new Error(`Error subiendo a R2: ${xhr.status} ${xhr.statusText}`));
        }
      });

      xhr.addEventListener('error', () => reject(new Error('Error de red subiendo a R2')));
      xhr.addEventListener('abort', () => reject(new Error('Subida cancelada')));

      xhr.open('PUT', signedUrl);
      xhr.setRequestHeader('Content-Type', file.type);
      xhr.send(file);
    });
  }
</script>

<div class="mt-4">
  <input
    type="file"
    accept="image/*,video/*"
    bind:files={files}
    class="border rounded-lg p-2 w-full mb-2"
  />
  {#if uploading && progress > 0}
    <div class="mb-2">
      <div class="flex justify-between text-sm mb-1">
        <span>Subiendo...</span>
        <span>{progress}%</span>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-2">
        <div class="bg-green-500 h-2 rounded-full transition-all" style="width: {progress}%"></div>
      </div>
    </div>
  {/if}
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