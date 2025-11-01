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

  // ✅ Subir nueva foto al álbum
  async function uploadPhoto() {
    if (!files || !files.length) {
      return alert('Selecciona una imagen');
    }
    if (!$user?.id) {
      return alert('Usuario no autenticado');
    }

    loading = true;
    const file = files[0];
    const filename = file.name;
    const filePath = `${$user.id}/${Date.now()}_${filename}`;

    try {
      // Subir a storage (bucket: 'photos')
      const { error: uploadError } = await supabase.storage
        .from('photos')
        .upload(filePath, file, { upsert: true });

      if (uploadError) throw uploadError;

      // Obtener URL pública
      const publicResponse = supabase.storage.from('photos').getPublicUrl(filePath);
      const publicUrl =
        (publicResponse?.data && (publicResponse.data.publicUrl ?? publicResponse.data.publicURL)) ??
        publicResponse?.publicURL ??
        publicResponse?.publicUrl;

      if (!publicUrl) throw new Error('No se pudo obtener la URL pública del archivo');

      // ✅ Insertar metadata (incluyendo filename para evitar el error 400)
      const { error: insertError } = await supabase.from('photos').insert({
        user_id: $user.id,
        image_url: publicUrl,
        description,
        filename // 👈 agregado para cumplir el NOT NULL constraint
      });

      if (insertError) throw insertError;

      // Reset campos y recargar
      description = '';
      files = [];
      await loadPhotos();
    } catch (e) {
      console.error('uploadPhoto error:', e);
      alert('Error al subir: ' + (e?.message ?? String(e)));
    } finally {
      loading = false;
    }
  }

  // ✅ Eliminar foto (de storage y DB)
  async function deletePhoto(id, url) {
    if (!confirm('¿Eliminar esta foto?')) return;
    loading = true;
    try {
      const match = url.match(/\/object\/public\/[^\/]+\/(.+)$/);
      const path = match ? decodeURIComponent(match[1]) : null;

      if (path) {
        const { error: removeError } = await supabase.storage.from('photos').remove([path]);
        if (removeError) console.warn('remove from storage error:', removeError);
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

  onMount(loadPhotos);
</script>

<!-- 🎨 Layout y estilos originales (sin tocar) -->
<div class="p-6 max-w-3xl mx-auto">
  <h2 class="text-2xl font-bold mb-4">Mis fotos</h2>

  <!-- Subir nueva foto -->
  <div class="bg-white p-4 rounded-lg shadow mb-6">
    <input type="file" bind:files={files} multiple={false} accept="image/*" />
    <input
      type="text"
      bind:value={description}
      placeholder="Descripción"
      class="border rounded p-2 w-full mt-2"
    />
    <button
      class="bg-green-500 text-white px-4 py-2 mt-2 rounded"
      on:click={uploadPhoto}
      disabled={loading}
    >
      {loading ? 'Subiendo...' : 'Subir'}
    </button>
  </div>

  <!-- Mostrar fotos -->
  <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
    {#each photos as photo}
      <div class="bg-white p-4 rounded-lg shadow">
        <img src={photo.image_url} alt="foto" class="w-full h-60 object-cover rounded" />
        <p class="mt-2 text-gray-700">{photo.description}</p>
        <button
          class="bg-red-500 text-white px-3 py-1 mt-2 rounded"
          on:click={() => deletePhoto(photo.id, photo.image_url)}
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
