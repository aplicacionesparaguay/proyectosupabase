<script>
  import { supabase } from '$lib/supabaseClient';
  import { user } from '$lib/stores/auth';
  import { onMount } from 'svelte';

  let files = [];
  let description = '';
  let photos = [];
  let comments = {};
  let newComment = {};
  let loading = false;
  let uploadProgress = 0;

  // ✅ Cargar fotos del usuario actual
  async function loadPhotos() {
    if (!$user?.id) return;
    const { data, error } = await supabase
      .from('photos')
      .select('*')
      .eq('user_id', $user.id)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('loadPhotos error:', error);
    } else {
      photos = data ?? [];
    }
  }

  // ✅ Subir archivo a R2 usando URL prefirmada
  async function uploadToR2(file, folder = 'gallery') {
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

    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();

      xhr.upload.addEventListener('progress', (e) => {
        if (e.lengthComputable) {
          uploadProgress = Math.round((e.loaded / e.total) * 100);
        }
      });

      xhr.addEventListener('load', () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          const publicUrl = `${import.meta.env.VITE_R2_PUBLIC_URL}/${key}`;
          resolve({ publicUrl, key });
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

  // ✅ Subir nueva foto/video al álbum
  async function uploadPhoto() {
    if (!files || !files.length) {
      return alert('Selecciona una imagen o video');
    }
    if (!$user?.id) {
      return alert('Usuario no autenticado');
    }

    loading = true;
    uploadProgress = 0;
    const file = files[0];

    try {
      const { publicUrl, key } = await uploadToR2(file, 'gallery');

      // ✅ Insertar metadata en DB
      const { error: insertError } = await supabase.from('photos').insert({
        user_id: $user.id,
        image_url: publicUrl,
        description,
        filename: file.name,
        file_key: key,
        mime_type: file.type,
      });

      if (insertError) throw insertError;

      // Reset campos y recargar
      description = '';
      files = [];
      uploadProgress = 0;
      await loadPhotos();
    } catch (e) {
      console.error('uploadPhoto error:', e);
      alert('Error al subir: ' + (e?.message ?? String(e)));
    } finally {
      loading = false;
      uploadProgress = 0;
    }
  }

  // ✅ Eliminar foto/video (de R2 y DB)
  async function deletePhoto(id, url, fileKey) {
    if (!confirm('¿Eliminar este archivo?')) return;
    loading = true;
    try {
      // Eliminar de R2 si tenemos la key
      if (fileKey) {
        const deleteResponse = await fetch('/api/upload/r2', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            fileName: fileKey,
            contentType: 'application/octet-stream',
            folder: 'gallery',
            action: 'delete',
          }),
        });
        if (!deleteResponse.ok) {
          console.warn('Error eliminando de R2, continuando con DB');
        }
      }

      const { error: deleteError } = await supabase.from('photos').delete().eq('id', id);
      if (deleteError) throw deleteError;

      await loadPhotos();
    } catch (e) {
      console.error('deletePhoto error:', e);
      alert('Error al eliminar: ' + (e?.message ?? String(e)));
    } finally {
      loading = false;
    }
  }

  // ✅ Cargar comentarios de una foto
  async function loadComments(photoId) {
    const { data, error } = await supabase
      .from('comments')
      .select('id,photo_id,user_id,content,created_at')
      .eq('photo_id', photoId)
      .order('created_at', { ascending: true });

    if (error) {
      console.error('loadComments error:', error);
      comments = { ...comments, [photoId]: [] };
    } else {
      comments = { ...comments, [photoId]: data ?? [] };
    }
  }

  // ✅ Agregar comentario
  async function addComment(photoId) {
    const text = (newComment[photoId] || '').trim();
    if (!text) return;

    try {
      const { error } = await supabase.from('comments').insert({
        photo_id: photoId,
        user_id: $user.id,
        content: text
      });
      if (error) throw error;

      newComment = { ...newComment, [photoId]: '' };
      await loadComments(photoId);
    } catch (e) {
      console.error('addComment error:', e);
      alert('Error al comentar: ' + (e?.message ?? String(e)));
    }
  }

  function isVideo(mimeType) {
    return mimeType?.startsWith('video/');
  }

  function getMediaElement(photo) {
    if (isVideo(photo.mime_type)) {
      return (
        <video src={photo.image_url} controls class="w-full h-60 object-cover rounded" />
      );
    }
    return (
      <img src={photo.image_url} alt="media" class="w-full h-60 object-cover rounded" />
    );
  }

  onMount(loadPhotos);
</script>

<!-- 🎨 Layout y estilos originales (sin tocar) -->
<div class="p-6 max-w-3xl mx-auto">
  <h2 class="text-2xl font-bold mb-4">Mi Galería</h2>

  <!-- Subir nuevo archivo -->
  <div class="bg-white p-4 rounded-lg shadow mb-6">
    <input type="file" bind:files={files} multiple={false} accept="image/*,video/*" />
    <input
      type="text"
      bind:value={description}
      placeholder="Descripción"
      class="border rounded p-2 w-full mt-2"
    />
    {#if loading && uploadProgress > 0}
      <div class="mb-2">
        <div class="flex justify-between text-sm mb-1">
          <span>Subiendo...</span>
          <span>{uploadProgress}%</span>
        </div>
        <div class="w-full bg-gray-200 rounded-full h-2">
          <div class="bg-green-500 h-2 rounded-full transition-all" style="width: {uploadProgress}%"></div>
        </div>
      </div>
    {/if}
    <button
      class="bg-green-500 text-white px-4 py-2 mt-2 rounded"
      on:click={uploadPhoto}
      disabled={loading}
    >
      {loading ? 'Subiendo...' : 'Subir'}
    </button>
  </div>

  <!-- Mostrar fotos/videos -->
  <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
    {#each photos as photo}
      <div class="bg-white p-4 rounded-lg shadow">
        {#if photo.image_url}
          {@html getMediaElement(photo)}
        {/if}
        <p class="mt-2 text-gray-700">{photo.description}</p>
        <button
          class="bg-red-500 text-white px-3 py-1 mt-2 rounded"
          on:click={() => deletePhoto(photo.id, photo.image_url, photo.file_key)}
          disabled={loading}
        >
          Eliminar
        </button>

        <div class="mt-4">
          <h4 class="font-semibold">Comentarios</h4>
          <button
            class="text-sm text-blue-500"
            on:click={() => loadComments(photo.id)}
          >
            Ver comentarios
          </button>

          {#if comments[photo.id]}
            {#each comments[photo.id] as c}
              <p class="text-gray-600 text-sm border-b py-1">{c.content}</p>
            {/each}
          {/if}

          <input
            type="text"
            placeholder="Escribe un comentario..."
            bind:value={newComment[photo.id]}
            class="border rounded p-1 w-full mt-2"
          />
          <button
            class="bg-green-500 text-white px-3 py-1 mt-1 rounded"
            on:click={() => addComment(photo.id)}
          >
            Comentar
          </button>
        </div>
      </div>
    {/each}
  </div>
</div>

<style>
  /* Estilos globales para video */
  video {
    max-width: 100%;
    height: auto;
  }
</style>