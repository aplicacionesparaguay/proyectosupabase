<script>
  import { supabase } from '$lib/supabaseClient';
  import { user } from '$lib/stores/auth';
  import { onMount } from 'svelte';

  /** @type {FileList | null} */
  let files = null;
  let description = '';
  /** @type {any[]} */
  let photos = [];
  /** @type {Record<string, any[]>} */
  let comments = {};
  /** @type {Record<string, string>} */
  let newComment = {};
  let loading = false;

  async function loadPhotos() {
    const me = $user;
    if (!me?.id) return;
    const { data, error } = await supabase
      .from('media')
      .select('id, tipo, storage_key, public_url, thumbnail_url, titulo, descripcion, es_privado, bucket, orden')
      .eq('user_id', me.id)
      .neq('tipo', 'banner')
      .order('orden', { ascending: false });

    if (error) {
      console.error('loadPhotos error:', error);
    } else {
      photos = (data ?? []).map(p => ({
        ...p,
        filename: p.storage_key.split('/').pop()
      }));
    }
  }

  async function uploadPhoto() {
    if (!files || !files.length) {
      return alert('Selecciona una imagen');
    }
    const me = $user;
    if (!me?.id) {
      return alert('Usuario no autenticado');
    }

    loading = true;
    const file = files[0];

    try {
      // 1) Pedir URL firmada de subida al servidor
      const res = await fetch('/api/media/upload', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tipo: file.type.startsWith('video/') ? 'video' : 'photo',
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

      // 3) Guardar metadata en `media`
      const { error: insertError } = await supabase.from('media').insert({
        user_id: me.id,
        tipo: file.type.startsWith('video/') ? 'video' : 'photo',
        bucket: req.bucket,
        storage_key: req.storage_key,
        public_url: req.public_url,
        titulo: description,
        descripcion: description,
        es_privado: false,
        orden: photos.length
      });

      if (insertError) throw insertError;

      description = '';
      files = null;
      await loadPhotos();
    } catch (e) {
      console.error('uploadPhoto error:', e);
      alert('Error al subir: ' + (e instanceof Error ? e.message : String(e)));
    } finally {
      loading = false;
    }
  }

  /** @param {string} id */
  async function deletePhoto(id) {
    if (!confirm('¿Eliminar esta foto?')) return;
    loading = true;
    try {
      const res = await fetch('/api/media/delete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ media_id: id })
      });
      const data = await res.json();
      if (!data.ok) throw new Error(data.error || 'Error al eliminar');
      await loadPhotos();
    } catch (e) {
      console.error('deletePhoto error:', e);
      alert('Error al eliminar: ' + (e instanceof Error ? e.message : String(e)));
    } finally {
      loading = false;
    }
  }

  /** @param {string} mediaId */
  async function loadComments(mediaId) {
    const { data, error } = await supabase
      .from('comments')
      .select('id, media_id, user_id, content, created_at, profiles (nombre)')
      .eq('media_id', mediaId)
      .order('created_at', { ascending: true });

    if (error) {
      console.error('loadComments error:', error);
      comments = { ...comments, [mediaId]: [] };
    } else {
      comments = { ...comments, [mediaId]: data ?? [] };
    }
  }

  /** @param {string} mediaId */
  async function addComment(mediaId) {
    const me = $user;
    if (!me?.id) return;
    const text = (newComment[mediaId] || '').trim();
    if (!text) return;

    try {
      const { error } = await supabase.from('comments').insert({
        media_id: mediaId,
        user_id: me.id,
        content: text
      });
      if (error) throw error;

      newComment = { ...newComment, [mediaId]: '' };
      await loadComments(mediaId);
    } catch (e) {
      console.error('addComment error:', e);
      alert('Error al comentar: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  onMount(loadPhotos);
</script>

<div class="p-6 max-w-3xl mx-auto">
  <h2 class="text-2xl font-bold mb-4">Mis fotos</h2>

  <div class="bg-white p-4 rounded-lg shadow mb-6">
    <input type="file" bind:files={files} multiple={false} accept="image/*,video/*" />
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

  <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
    {#each photos as photo}
      <div class="bg-white p-4 rounded-lg shadow">
        {#if photo.filename && photo.filename.match(/\.(mp4|webm|ogg|mov)$/i)}
          <video src={photo.public_url || '/aguaenlaboca.jpeg'} controls class="w-full h-60 object-cover rounded"></video>
        {:else}
          <img src={photo.public_url || '/aguaenlaboca.jpeg'} alt="foto" class="w-full h-60 object-cover rounded" />
        {/if}
        <p class="mt-2 text-gray-700">{photo.descripcion}</p>
        <button
          class="bg-red-500 text-white px-3 py-1 mt-2 rounded"
          on:click={() => deletePhoto(photo.id)}
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
              <p class="text-gray-600 text-sm border-b py-1">{c.profiles?.nombre || 'Anónimo'}: {c.content}</p>
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
