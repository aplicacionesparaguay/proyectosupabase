<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { session, user } from '$lib/stores/auth';
	import { supabase } from '$lib/supabaseClient';
	import {
		uploadToR2,
		R2_FOLDERS,
		validateImageFile,
		MAX_UPLOAD_BYTES
	} from '$lib/upload/r2Upload';

	let loading = true;
	let uploading = false;
	let uploadProgress = 0;
	let error = '';
	let success = false;

	/** @type {File | null} */
	let file = null;
	/** @type {string | null} */
	let preview = null;
	let titulo = '';
	let descripcion = '';
	let esPrivado = false;
	/** @type {HTMLInputElement | undefined} */
	let fileInput;

	onMount(async () => {
		if (!$session?.user) {
			goto('/login');
			return;
		}
		loading = false;
	});

	/** @param {Event} e */
	function onFileChange(e) {
		const input = /** @type {HTMLInputElement} */ (e.target);
		const f = input?.files?.[0];
		if (!f) return;

		const err = validateImageFile(f);
		if (err) {
			error = err;
			file = null;
			preview = null;
			return;
		}

		error = '';
		file = f;
		preview = URL.createObjectURL(f);
	}

	function removeFile() {
		if (preview) URL.revokeObjectURL(preview);
		file = null;
		preview = null;
		if (fileInput) fileInput.value = '';
	}

	async function publish() {
		if (!file || !$user || uploading) return;

		error = '';
		uploading = true;
		uploadProgress = 0;

		try {
			const { publicUrl, key } = await uploadToR2(file, R2_FOLDERS.post, {
				onProgress: (p) => (uploadProgress = p)
			});

			const { error: insertError } = await supabase.from('media').insert({
				user_id: $user?.id,
				tipo: 'photo',
				storage_key: key,
				public_url: publicUrl,
				bucket: esPrivado ? 'private' : 'public',
				es_privado: esPrivado,
				titulo: titulo.trim() || null,
				descripcion: descripcion.trim() || null,
				orden: 0
			});

			if (insertError) throw insertError;

			success = true;
			setTimeout(() => goto('/perfil'), 1500);
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		} finally {
			uploading = false;
		}
	}
</script>

{#if loading}
	<div class="flex min-h-[60vh] items-center justify-center">
		<div
			class="h-10 w-10 animate-spin rounded-full border-2 border-pink-500 border-t-transparent"
		></div>
	</div>
{:else}
	<div class="mx-auto w-full max-w-lg px-4 py-8">
		<div class="rounded-2xl border border-pink-900/30 bg-black/50 p-6">
			<h1 class="mb-6 text-2xl font-bold text-pink-100">Nueva publicación</h1>

			{#if success}
				<div class="mb-4 rounded-xl border border-green-500/30 bg-green-900/20 p-4 text-center">
					<p class="font-semibold text-green-400">¡Publicado!</p>
					<p class="text-sm text-green-300/70">Redirigiendo a tu perfil...</p>
				</div>
			{:else}
				<!-- Selector de archivo -->
				{#if !preview}
					<button
						on:click={() => fileInput?.click()}
						class="mb-4 flex w-full flex-col items-center justify-center gap-3 rounded-xl border-2 border-dashed border-pink-500/40 bg-pink-950/10 p-10 transition hover:border-pink-500/70 hover:bg-pink-950/20"
					>
						<svg
							class="h-12 w-12 text-pink-400/50"
							fill="none"
							stroke="currentColor"
							stroke-width="1.5"
							viewBox="0 0 24 24"
						>
							<path
								stroke-linecap="round"
								stroke-linejoin="round"
								d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
							/>
						</svg>
						<div class="text-center">
							<p class="font-semibold text-pink-300">Seleccionar foto</p>
							<p class="mt-1 text-xs text-pink-400/50">
								JPG, PNG, WEBP o GIF · máx. {MAX_UPLOAD_BYTES / (1024 * 1024)} MB
							</p>
						</div>
					</button>
				{:else}
					<!-- Preview -->
					<div class="relative mb-4 overflow-hidden rounded-xl">
						<img src={preview} alt="Preview" class="max-h-80 w-full object-cover" />
						<button
							on:click={removeFile}
							class="absolute top-2 right-2 flex h-8 w-8 items-center justify-center rounded-full bg-black/70 text-white hover:bg-black/90"
							aria-label="Quitar foto"
						>
							×
						</button>
					</div>
				{/if}

				<input
					bind:this={fileInput}
					type="file"
					accept="image/jpeg,image/png,image/webp,image/gif"
					class="hidden"
					on:change={onFileChange}
				/>

				<!-- Título -->
				<div class="mb-4">
					<label for="titulo" class="mb-1 block text-sm font-medium text-pink-300"
						>Título <span class="text-pink-400/50">(opcional)</span></label
					>
					<input
						id="titulo"
						bind:value={titulo}
						maxlength="100"
						placeholder="Título de la publicación..."
						class="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
					/>
				</div>

				<!-- Descripción -->
				<div class="mb-4">
					<label for="descripcion" class="mb-1 block text-sm font-medium text-pink-300"
						>Descripción <span class="text-pink-400/50">(opcional)</span></label
					>
					<textarea
						id="descripcion"
						bind:value={descripcion}
						maxlength="500"
						rows="3"
						placeholder="Cuéntales algo sobre esta publicación..."
						class="w-full resize-none rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
					></textarea>
				</div>

				<!-- Privacidad -->
				<div
					class="mb-6 flex items-center justify-between rounded-xl border border-white/10 bg-white/5 px-4 py-3"
				>
					<div>
						<p class="text-sm font-medium text-pink-100">Contenido exclusivo</p>
						<p class="text-xs text-pink-300/50">Solo visible para suscriptoras</p>
					</div>
					<button
						role="switch"
						aria-checked={esPrivado}
						on:click={() => (esPrivado = !esPrivado)}
						class="relative h-7 w-12 rounded-full transition {esPrivado
							? 'bg-pink-600'
							: 'bg-white/10'}"
					>
						<span
							class="absolute top-0.5 h-6 w-6 rounded-full bg-white shadow transition-transform {esPrivado
								? 'translate-x-5'
								: 'translate-x-0.5'}"
						></span>
					</button>
				</div>

				<!-- Progreso -->
				{#if uploading && uploadProgress > 0}
					<div class="mb-4">
						<div class="mb-1 flex justify-between text-xs text-pink-300/70">
							<span>Subiendo...</span>
							<span>{uploadProgress}%</span>
						</div>
						<div class="h-2 w-full rounded-full bg-white/10">
							<div
								class="h-2 rounded-full bg-gradient-to-r from-pink-500 to-purple-500 transition-all"
								style="width: {uploadProgress}%"
							></div>
						</div>
					</div>
				{/if}

				<!-- Error -->
				{#if error}
					<p
						class="mb-4 rounded-xl border border-red-500/30 bg-red-900/20 px-4 py-3 text-sm text-red-400"
					>
						{error}
					</p>
				{/if}

				<!-- Botones -->
				<div class="flex gap-3">
					<a
						href="/perfil"
						class="flex-1 rounded-xl border border-white/10 py-3 text-center text-sm font-medium text-white/60 transition hover:bg-white/5"
					>
						Cancelar
					</a>
					<button
						on:click={publish}
						disabled={!file || uploading}
						class="flex-1 rounded-xl bg-gradient-to-r from-pink-600 to-purple-600 py-3 font-bold text-white shadow-lg transition hover:brightness-110 disabled:opacity-40"
					>
						{uploading ? 'Subiendo...' : 'Publicar'}
					</button>
				</div>
			{/if}
		</div>
	</div>
{/if}
