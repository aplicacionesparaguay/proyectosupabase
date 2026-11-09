<script>
	import { onDestroy, onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { session } from '$lib/stores/auth';
	import { uploadPhoto, validatePhotoFile } from '$lib/media/client';
	import {
		MAX_DESCRIPTION_LENGTH,
		MAX_TITLE_LENGTH,
		maxPhotoBytesLabel
	} from '$lib/media/constants';

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
	/** @type {HTMLInputElement | undefined} */
	let fileInput;

	onMount(() => {
		if (!$session?.user) {
			goto('/login');
			return;
		}
		loading = false;
	});

	onDestroy(() => {
		if (preview) URL.revokeObjectURL(preview);
	});

	/** @param {Event} event */
	function onFileChange(event) {
		const input = /** @type {HTMLInputElement} */ (event.target);
		const selected = input?.files?.[0];
		if (!selected) return;

		const problem = validatePhotoFile(selected);
		if (problem) {
			error = problem;
			file = null;
			if (preview) URL.revokeObjectURL(preview);
			preview = null;
			return;
		}

		error = '';
		if (preview) URL.revokeObjectURL(preview);
		file = selected;
		preview = URL.createObjectURL(selected);
	}

	function removeFile() {
		if (preview) URL.revokeObjectURL(preview);
		file = null;
		preview = null;
		if (fileInput) fileInput.value = '';
	}

	async function publish() {
		if (!file || !$session?.user || uploading) return;

		error = '';
		uploading = true;
		uploadProgress = 0;

		try {
			await uploadPhoto(file, {
				title: titulo,
				description: descripcion,
				onProgress: (percent) => (uploadProgress = percent)
			});

			success = true;
			setTimeout(() => goto('/perfil'), 1800);
		} catch (uploadError) {
			error = uploadError instanceof Error ? uploadError.message : String(uploadError);
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
			<h1 class="mb-2 text-2xl font-bold text-pink-100">Nueva foto</h1>
			<p class="mb-6 text-sm text-pink-300/60">
				La foto pasara por revision humana. Los rostros detectados se protegen antes de mostrarla en
				publico.
			</p>

			{#if success}
				<div class="mb-4 rounded-xl border border-green-500/30 bg-green-900/20 p-4 text-center">
					<p class="font-semibold text-green-400">Foto recibida</p>
					<p class="text-sm text-green-300/70">Queda pendiente de revision. Redirigiendo...</p>
				</div>
			{:else}
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
								JPG, PNG o WebP · maximo {maxPhotoBytesLabel()}
							</p>
						</div>
					</button>
				{:else}
					<div class="relative mb-4 overflow-hidden rounded-xl">
						<img src={preview} alt="Vista previa" class="max-h-80 w-full object-cover" />
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
					accept="image/jpeg,image/png,image/webp"
					class="hidden"
					on:change={onFileChange}
				/>

				<div class="mb-4">
					<label for="titulo" class="mb-1 block text-sm font-medium text-pink-300">
						Titulo <span class="text-pink-400/50">(opcional)</span>
					</label>
					<input
						id="titulo"
						bind:value={titulo}
						maxlength={MAX_TITLE_LENGTH}
						placeholder="Titulo de la foto..."
						class="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
					/>
				</div>

				<div class="mb-6">
					<label for="descripcion" class="mb-1 block text-sm font-medium text-pink-300">
						Descripcion <span class="text-pink-400/50">(opcional)</span>
					</label>
					<textarea
						id="descripcion"
						bind:value={descripcion}
						maxlength={MAX_DESCRIPTION_LENGTH}
						rows="3"
						placeholder="Cuentanos algo sobre esta foto..."
						class="w-full resize-none rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
					></textarea>
				</div>

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

				{#if error}
					<p
						class="mb-4 rounded-xl border border-red-500/30 bg-red-900/20 px-4 py-3 text-sm text-red-400"
					>
						{error}
					</p>
				{/if}

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
						{uploading ? 'Subiendo...' : 'Enviar a revision'}
					</button>
				</div>
			{/if}
		</div>
	</div>
{/if}
