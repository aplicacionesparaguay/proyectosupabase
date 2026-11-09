<script>
	import { onDestroy } from 'svelte';
	import { uploadPhoto, validatePhotoFile } from '$lib/media/client';
	import { MAX_FILES_PER_BATCH, maxPhotoBytesLabel } from '$lib/media/constants';

	/**
	 * @typedef {Object} QueueItem
	 * @property {string} id
	 * @property {File} file
	 * @property {string} previewUrl
	 * @property {'pendiente' | 'subiendo' | 'completado' | 'error' | 'cancelado'} estado
	 * @property {number} progress
	 * @property {string} error
	 * @property {AbortController} controller
	 * @property {string | null} assetId
	 */

	/** @type {QueueItem[]} */
	let queue = [];
	let dragging = false;
	let uploading = false;

	/**
	 * @type {(payload: { asset: import('$lib/media/client').MediaAsset, file: File }) => void | Promise<void>}
	 */
	export let onUploaded = () => {};

	/**
	 * @param {File} file
	 * @returns {QueueItem}
	 */
	function createItem(file) {
		return {
			id: crypto.randomUUID(),
			file,
			previewUrl: URL.createObjectURL(file),
			estado: 'pendiente',
			progress: 0,
			error: '',
			controller: new AbortController(),
			assetId: null
		};
	}

	/** @param {FileList | File[]} files */
	function addFiles(files) {
		const incoming = Array.from(files ?? []);
		const room = MAX_FILES_PER_BATCH - queue.length;
		const accepted = [];
		const rejected = [];

		for (const file of incoming.slice(0, Math.max(0, room))) {
			const problem = validatePhotoFile(file);
			if (problem) rejected.push(`${file.name}: ${problem}`);
			else accepted.push(createItem(file));
		}

		if (incoming.length > Math.max(0, room)) {
			rejected.push(`Maximo ${MAX_FILES_PER_BATCH} fotos por tanda.`);
		}

		if (accepted.length) queue = [...queue, ...accepted];
		if (rejected.length) alert(rejected.join('\n'));
	}

	/** @param {Event} event */
	function onInputChange(event) {
		const input = /** @type {HTMLInputElement} */ (event.target);
		if (input.files) addFiles(input.files);
		input.value = '';
	}

	/** @param {DragEvent} event */
	function onDrop(event) {
		event.preventDefault();
		dragging = false;
		if (event.dataTransfer?.files) addFiles(event.dataTransfer.files);
	}

	/** @param {DragEvent} event */
	function onDragOver(event) {
		event.preventDefault();
		dragging = true;
	}

	/** @param {DragEvent} event */
	function onDragLeave(event) {
		if (event.currentTarget === event.target) dragging = false;
	}

	/** @param {QueueItem} item */
	function removeItem(item) {
		if (item.estado === 'subiendo') item.controller.abort();
		if (item.previewUrl) URL.revokeObjectURL(item.previewUrl);
		queue = queue.filter((candidate) => candidate.id !== item.id);
	}

	function clearQueue() {
		for (const item of queue) {
			if (item.estado === 'subiendo') item.controller.abort();
			if (item.previewUrl) URL.revokeObjectURL(item.previewUrl);
		}
		queue = [];
	}

	/** @param {QueueItem} item */
	async function uploadOne(item) {
		item.estado = 'subiendo';
		item.progress = 0;
		item.error = '';

		try {
			const asset = await uploadPhoto(item.file, {
				onProgress: (percent) => (item.progress = percent),
				signal: item.controller.signal
			});

			item.estado = 'completado';
			item.progress = 100;
			item.assetId = asset.id;

			try {
				await onUploaded({ asset, file: item.file });
			} catch (callbackError) {
				console.error('La foto se registro pero fallo la recarga de la galeria:', callbackError);
			}
		} catch (error) {
			const message = error instanceof Error ? error.message : 'Error desconocido';
			item.estado = message === 'Subida cancelada' ? 'cancelado' : 'error';
			item.error = message;
		}
	}

	async function uploadPending() {
		const pending = queue.filter((item) => item.estado === 'pendiente');
		if (!pending.length || uploading) return;

		uploading = true;
		for (const item of pending) await uploadOne(item);
		uploading = false;
	}

	async function retryFailed() {
		const failed = queue.filter((item) => item.estado === 'error');
		for (const item of failed) {
			item.estado = 'pendiente';
			item.progress = 0;
			item.error = '';
			item.controller = new AbortController();
		}
		await uploadPending();
	}

	function cancelAll() {
		for (const item of queue) {
			if (item.estado === 'subiendo') item.controller.abort();
		}
	}

	/** @param {QueueItem} item */
	function statusLabel(item) {
		if (item.estado === 'pendiente') return 'Pendiente';
		if (item.estado === 'subiendo') return `Subiendo ${item.progress}%`;
		if (item.estado === 'completado') return 'Registrada, pendiente de revision';
		if (item.estado === 'cancelado') return 'Cancelada';
		return 'Fallida';
	}

	/** @param {QueueItem} item */
	function statusColor(item) {
		if (item.estado === 'completado') return 'text-emerald-400';
		if (item.estado === 'error') return 'text-red-400';
		if (item.estado === 'subiendo') return 'text-pink-300';
		if (item.estado === 'cancelado') return 'text-gray-500';
		return 'text-gray-400';
	}

	$: pendingCount = queue.filter((item) => item.estado === 'pendiente').length;
	$: failedCount = queue.filter((item) => item.estado === 'error').length;
	$: doneCount = queue.filter((item) => item.estado === 'completado').length;

	onDestroy(() => {
		for (const item of queue) if (item.previewUrl) URL.revokeObjectURL(item.previewUrl);
	});
</script>

<div class="space-y-4">
	<button
		type="button"
		on:drop={onDrop}
		on:dragover={onDragOver}
		on:dragleave={onDragLeave}
		class="flex w-full flex-col items-center justify-center gap-3 rounded-2xl border-2 border-dashed px-6 py-10 transition
			{dragging
			? 'border-pink-400 bg-pink-950/30'
			: 'border-pink-800/60 bg-pink-950/10 hover:border-pink-600/70'}"
		on:click={() => document.getElementById('gallery-file-input')?.click()}
	>
		<svg
			class="h-10 w-10 text-pink-400/60"
			fill="none"
			stroke="currentColor"
			stroke-width="1.5"
			viewBox="0 0 24 24"
			aria-hidden="true"
		>
			<path
				stroke-linecap="round"
				stroke-linejoin="round"
				d="M12 16V4m0 12l-4-4m4 4l4-4M4 17v2a1 1 0 001 1h14a1 1 0 001-1v-2"
			/>
		</svg>
		<div class="text-center">
			<p class="font-semibold text-pink-200">Arrastra fotos aqui o pulsa para elegir</p>
			<p class="mt-1 text-xs text-pink-400/60">
				JPG, PNG o WebP · maximo {maxPhotoBytesLabel()} · hasta {MAX_FILES_PER_BATCH} por tanda
			</p>
		</div>
	</button>

	<input
		id="gallery-file-input"
		type="file"
		multiple
		accept="image/jpeg,image/png,image/webp"
		class="sr-only"
		on:change={onInputChange}
	/>

	{#if queue.length === 0}
		<p class="py-6 text-center text-sm text-pink-300/40 italic">Todavia no has anadido fotos.</p>
	{:else}
		<div class="flex flex-wrap items-center justify-between gap-3">
			<p class="text-sm text-pink-300/70">
				{queue.length} foto{queue.length !== 1 ? 's' : ''}
				{#if doneCount > 0}
					· {doneCount} registrada{doneCount !== 1 ? 's' : ''}
				{/if}
			</p>
			<div class="flex gap-2">
				{#if failedCount > 0}
					<button
						on:click={retryFailed}
						class="rounded-lg border border-amber-500/40 px-3 py-1.5 text-xs text-amber-300 transition hover:bg-amber-500/10"
					>
						Reintentar ({failedCount})
					</button>
				{/if}
				<button
					on:click={clearQueue}
					disabled={uploading}
					class="rounded-lg border border-white/10 px-3 py-1.5 text-xs text-white/60 transition hover:bg-white/5 disabled:opacity-40"
				>
					Limpiar
				</button>
				{#if uploading}
					<button
						on:click={cancelAll}
						class="rounded-lg border border-red-500/40 px-3 py-1.5 text-xs text-red-300 transition hover:bg-red-500/10"
					>
						Cancelar
					</button>
				{:else}
					<button
						on:click={uploadPending}
						disabled={pendingCount === 0}
						class="rounded-lg bg-gradient-to-r from-pink-600 to-purple-600 px-4 py-1.5 text-xs font-bold text-white transition hover:brightness-110 disabled:opacity-40"
					>
						Subir ({pendingCount})
					</button>
				{/if}
			</div>
		</div>

		<ul class="space-y-2">
			{#each queue as item (item.id)}
				<li class="flex items-center gap-3 rounded-xl border border-white/5 bg-black/30 p-3">
					<div
						class="flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-white/5"
					>
						<img src={item.previewUrl} alt="" class="h-full w-full object-cover" />
					</div>

					<div class="min-w-0 flex-1">
						<p class="truncate text-sm text-pink-100">{item.file.name}</p>
						<p class="text-xs {statusColor(item)}">
							{statusLabel(item)}
							{#if item.error && item.estado === 'error'}
								· {item.error}
							{/if}
						</p>

						{#if item.estado === 'subiendo'}
							<div class="mt-1.5 h-1.5 w-full rounded-full bg-white/10">
								<div
									class="h-1.5 rounded-full bg-gradient-to-r from-pink-500 to-purple-500 transition-all"
									style="width: {item.progress}%"
								></div>
							</div>
						{/if}
					</div>

					<button
						on:click={() => removeItem(item)}
						class="shrink-0 rounded-full p-2 text-white/40 transition hover:bg-white/10 hover:text-white"
						aria-label="Quitar {item.file.name} de la cola"
					>
						<svg
							class="h-4 w-4"
							fill="none"
							stroke="currentColor"
							stroke-width="2"
							viewBox="0 0 24 24"
							aria-hidden="true"
						>
							<path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
						</svg>
					</button>
				</li>
			{/each}
		</ul>
	{/if}
</div>
