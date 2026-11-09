<script>
	import { supabase } from '$lib/supabaseClient';
	import { user } from '$lib/stores/auth';
	import { onMount } from 'svelte';
	import {
		uploadToR2,
		validateImageFile,
		MAX_UPLOAD_BYTES,
		R2_FOLDERS
	} from '$lib/upload/r2Upload';

	/** @type {FileList | null} */
	let files = null;

	let description = '';

	/** @type {Array<Record<string, any>>} */
	let photos = [];

	/** @type {Record<string, Array<Record<string, any>>>} */
	let comments = {};

	/** @type {Record<string, string>} */
	let newComment = {};

	let loading = false;
	let uploadProgress = 0;

	// Cargar fotos del usuario actual
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

	// Subir archivo a R2 usando URL prefirmada.
	// publicUrl la calcula y devuelve el servidor; el cliente no la arma.
	/**
	 * @param {File} file
	 * @param {string} [folder]
	 * @returns {Promise<{ publicUrl: string, key: string }>}
	 */
	async function putToR2(file, folder = R2_FOLDERS.post) {
		const clientError = validateImageFile(file);
		if (clientError) throw new Error(clientError);

		return uploadToR2(file, folder, {
			onProgress: (/** @type {number} */ percent) => (uploadProgress = percent)
		});
	}

	// Subir nueva foto/video al álbum
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
			const { publicUrl, key } = await putToR2(file, R2_FOLDERS.post);

			const { error: insertError } = await supabase.from('photos').insert({
				user_id: $user.id,
				image_url: publicUrl,
				description,
				filename: file.name,
				file_key: key,
				mime_type: file.type
			});

			if (insertError) throw insertError;

			description = '';
			files = null;
			uploadProgress = 0;

			await loadPhotos();
		} catch (e) {
			console.error('uploadPhoto error:', e);

			const message = e instanceof Error ? e.message : String(e);

			alert('Error al subir: ' + message);
		} finally {
			loading = false;
			uploadProgress = 0;
		}
	}

	// Eliminar foto/video
	/**
	 * @param {string} id
	 * @param {string} url
	 * @param {string | null | undefined} fileKey
	 */
	async function deletePhoto(id, url, fileKey) {
		if (!confirm('¿Eliminar este archivo?')) return;

		loading = true;

		try {
			if (fileKey) {
				// El endpoint valida que la clave sea del usuario y de la carpeta.
				const deleted = false;
				if (!deleted) {
					console.warn('Error eliminando de R2, continuando con DB');
				}
			}

			const { error: deleteError } = await supabase.from('photos').delete().eq('id', id);

			if (deleteError) throw deleteError;

			await loadPhotos();
		} catch (e) {
			console.error('deletePhoto error:', e);

			const message = e instanceof Error ? e.message : String(e);

			alert('Error al eliminar: ' + message);
		} finally {
			loading = false;
		}
	}

	// Cargar comentarios de una foto
	/**
	 * @param {string} photoId
	 */
	async function loadComments(photoId) {
		const { data, error } = await supabase
			.from('comments')
			.select('id,photo_id,user_id,content,created_at')
			.eq('photo_id', photoId)
			.order('created_at', { ascending: true });

		if (error) {
			console.error('loadComments error:', error);

			comments = {
				...comments,
				[photoId]: []
			};
		} else {
			comments = {
				...comments,
				[photoId]: data ?? []
			};
		}
	}

	// Agregar comentario
	/**
	 * @param {string} photoId
	 */
	async function addComment(photoId) {
		if (!$user?.id) {
			return alert('Usuario no autenticado');
		}

		const text = (newComment[photoId] || '').trim();

		if (!text) return;

		try {
			const { error } = await supabase.from('comments').insert({
				photo_id: photoId,
				user_id: $user.id,
				content: text
			});

			if (error) throw error;

			newComment = {
				...newComment,
				[photoId]: ''
			};

			await loadComments(photoId);
		} catch (e) {
			console.error('addComment error:', e);

			const message = e instanceof Error ? e.message : String(e);

			alert('Error al comentar: ' + message);
		}
	}

	/**
	 * @param {string | null | undefined} mimeType
	 * @returns {boolean}
	 */
	function isVideo(mimeType) {
		return mimeType?.startsWith('video/') ?? false;
	}

	onMount(loadPhotos);
</script>

<!-- Layout y estilos originales -->
<div class="mx-auto max-w-3xl p-6">
	<h2 class="mb-4 text-2xl font-bold">Mi Galería</h2>

	<!-- Subir nuevo archivo -->
	<div class="mb-6 rounded-lg bg-white p-4 shadow">
		<input
			type="file"
			bind:files
			multiple={false}
			accept="image/jpeg,image/png,image/webp,image/gif"
		/>

		<p class="mt-1 text-xs text-gray-500">
			JPG, PNG, WEBP o GIF. Máximo {MAX_UPLOAD_BYTES / (1024 * 1024)} MB.
		</p>

		<input
			type="text"
			bind:value={description}
			placeholder="Descripción"
			class="mt-2 w-full rounded border p-2"
		/>

		{#if loading && uploadProgress > 0}
			<div class="mb-2">
				<div class="mb-1 flex justify-between text-sm">
					<span>Subiendo...</span>
					<span>{uploadProgress}%</span>
				</div>

				<div class="h-2 w-full rounded-full bg-gray-200">
					<div
						class="h-2 rounded-full bg-green-500 transition-all"
						style="width: {uploadProgress}%"
					></div>
				</div>
			</div>
		{/if}

		<button
			class="mt-2 rounded bg-green-500 px-4 py-2 text-white"
			on:click={uploadPhoto}
			disabled={loading}
		>
			{loading ? 'Subiendo...' : 'Subir'}
		</button>
	</div>

	<!-- Mostrar fotos/videos -->
	<div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
		{#each photos as photo}
			<div class="rounded-lg bg-white p-4 shadow">
				{#if photo.image_url}
					{#if isVideo(photo.mime_type)}
						<video src={photo.image_url} controls class="h-60 w-full rounded object-cover">
							<track kind="captions" />
						</video>
					{:else}
						<img
							src={photo.image_url}
							alt={photo.description || 'Foto'}
							class="h-60 w-full rounded object-cover"
						/>
					{/if}
				{/if}

				<p class="mt-2 text-gray-700">
					{photo.description}
				</p>

				<button
					class="mt-2 rounded bg-red-500 px-3 py-1 text-white"
					on:click={() => deletePhoto(photo.id, photo.image_url, photo.file_key)}
					disabled={loading}
				>
					Eliminar
				</button>

				<div class="mt-4">
					<h4 class="font-semibold">Comentarios</h4>

					<button class="text-sm text-blue-500" on:click={() => loadComments(photo.id)}>
						Ver comentarios
					</button>

					{#if comments[photo.id]}
						{#each comments[photo.id] as c}
							<p class="border-b py-1 text-sm text-gray-600">
								{c.content}
							</p>
						{/each}
					{/if}

					<input
						type="text"
						placeholder="Escribe un comentario..."
						bind:value={newComment[photo.id]}
						class="mt-2 w-full rounded border p-1"
					/>

					<button
						class="mt-1 rounded bg-green-500 px-3 py-1 text-white"
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
	video {
		max-width: 100%;
		height: auto;
	}
</style>
