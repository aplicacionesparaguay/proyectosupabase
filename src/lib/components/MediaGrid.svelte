<script>
	import { supabase } from '$lib/supabaseClient';
	import { user } from '$lib/stores/auth';
	import LikeButton from './LikeButton.svelte';

	/**
	 * @typedef {Object} MediaItem
	 * @property {string} id
	 * @property {string} user_id
	 * @property {string} tipo
	 * @property {string | null} public_url
	 * @property {string | null} storage_key
	 * @property {string | null} titulo
	 * @property {string | null} descripcion
	 * @property {boolean} es_privado
	 * @property {string} bucket
	 * @property {number} orden
	 * @property {string} created_at
	 * @property {number} [like_count]
	 * @property {number} [comment_count]
	 */

	/** @type {MediaItem[]} */
	export let items = [];

	/** @type {boolean} */
	export let showActions = true;

	/** @type {boolean} */
	export let isOwner = false;

	/** @type {boolean} */
	export let canViewPrivate = false;

	/** @type {boolean} */
	export let showDelete = false;

	/** @type {((id: string) => void) | null} */
	export let onDelete = null;

	/** @type {MediaItem | null} */
	let selected = null;
	/** @type {any[]} */
	/** @type {any[]} */
	let comments = [];
	let newComment = '';
	let loadingComments = false;
	let sendingComment = false;

	/** @param {any} item */
	async function openItem(item) {
		selected = item;
		await loadComments(item.id);
	}

	/** @param {string} mediaId */
	/** @param {string} mediaId */
	async function loadComments(mediaId) {
		loadingComments = true;
		const { data } = await supabase
			.from('media_comments')
			.select('id, contenido, created_at, user_id, profiles(display_name, username, avatar_key)')
			.eq('media_id', mediaId)
			.order('created_at', { ascending: true });
		comments = data ?? [];
		loadingComments = false;
	}

	async function addComment() {
		if (!$user || !selected || !newComment.trim() || sendingComment) return;
		sendingComment = true;

		const { error } = await supabase.from('media_comments').insert({
			media_id: selected.id,
			user_id: $user.id,
			contenido: newComment.trim()
		});

		if (!error) {
			newComment = '';
			await loadComments(selected.id);
		}

		sendingComment = false;
	}

	function closeModal() {
		selected = null;
		comments = [];
		newComment = '';
	}

	/** @param {string | null | undefined} url */
	/** @param {string | null | undefined} url */
	function isVideo(url) {
		return /\.(mp4|webm|mov|ogg)$/i.test(url ?? '');
	}

	/** @param {string | null | undefined} name */
	/** @param {string | null | undefined} name */
	function getInitials(name) {
		return (
			name
				?.split(/\s+/)
				.filter(Boolean)
				.slice(0, 2)
				.map((p) => p[0].toUpperCase())
				.join('') ?? 'U'
		);
	}
</script>

{#if items.length === 0}
	<p class="py-8 text-center text-sm text-pink-300/50 italic">Sin contenido todavía.</p>
{:else}
	<div class="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4">
		{#each items as item (item.id)}
			{@const locked = item.es_privado && !canViewPrivate && !isOwner}
			<button
				on:click={() => !locked && openItem(item)}
				class="group relative aspect-square overflow-hidden rounded-xl bg-black/40 {locked
					? 'cursor-default'
					: 'cursor-pointer'}"
				aria-label={locked ? 'Contenido privado' : (item.titulo ?? 'Ver')}
			>
				{#if locked}
					<div
						class="flex h-full w-full flex-col items-center justify-center gap-2 bg-gradient-to-br from-pink-950/60 to-purple-950/60"
					>
						<svg
							class="h-8 w-8 text-pink-400/60"
							fill="none"
							stroke="currentColor"
							stroke-width="1.5"
							viewBox="0 0 24 24"
						>
							<path
								stroke-linecap="round"
								stroke-linejoin="round"
								d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
							/>
						</svg>
						<span class="text-xs text-pink-300/50">Privado</span>
					</div>
				{:else if isVideo(item.public_url)}
					<video
						src={item.public_url}
						muted
						loop
						class="h-full w-full object-cover transition duration-300 group-hover:scale-105"
					></video>
					<div
						class="absolute inset-0 flex items-center justify-center bg-black/20 opacity-0 transition group-hover:opacity-100"
					>
						<svg class="h-10 w-10 text-white" fill="currentColor" viewBox="0 0 24 24">
							<path d="M8 5v14l11-7z" />
						</svg>
					</div>
				{:else}
					<img
						src={item.public_url}
						alt={item.titulo ?? ''}
						loading="lazy"
						decoding="async"
						class="h-full w-full object-cover transition duration-300 group-hover:scale-105"
					/>
				{/if}

				{#if item.es_privado}
					<span
						class="absolute top-2 left-2 rounded-full bg-black/60 px-2 py-0.5 text-[10px] font-semibold text-purple-300"
					>
						PPV
					</span>
				{/if}

				{#if showActions && !locked}
					<div
						class="absolute right-0 bottom-0 left-0 flex items-center justify-between bg-gradient-to-t from-black/80 to-transparent p-2 opacity-0 transition group-hover:opacity-100"
					>
						{#if showDelete && isOwner}
							<button
								on:click|stopPropagation={() => onDelete?.(item.id)}
								class="rounded-full bg-red-600/80 p-1.5 text-white hover:bg-red-600"
								aria-label="Eliminar"
							>
								<svg
									class="h-3.5 w-3.5"
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									viewBox="0 0 24 24"
								>
									<path
										stroke-linecap="round"
										stroke-linejoin="round"
										d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
									/>
								</svg>
							</button>
						{/if}
						{#if item.like_count !== undefined}
							<span class="ml-auto text-xs text-white/70">♥ {item.like_count}</span>
						{/if}
					</div>
				{/if}
			</button>
		{/each}
	</div>
{/if}

<!-- Modal -->
{#if selected}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/90 p-4"
		role="dialog"
		aria-modal="true"
		on:click={closeModal}
		on:keydown={(e) => e.key === 'Escape' && closeModal()}
	>
		<div
			class="flex max-h-full w-full max-w-4xl flex-col overflow-hidden rounded-2xl bg-black"
			on:click|stopPropagation
			role="presentation"
		>
			<!-- Media -->
			<div class="relative flex-1 overflow-hidden bg-black">
				{#if isVideo(selected.public_url)}
					<video src={selected.public_url} controls autoplay class="max-h-[70vh] w-full"></video>
				{:else}
					<img
						src={selected.public_url}
						alt={selected.titulo ?? ''}
						class="max-h-[70vh] w-full object-contain"
					/>
				{/if}

				<button
					on:click={closeModal}
					class="absolute top-3 right-3 flex h-8 w-8 items-center justify-center rounded-full bg-black/60 text-white hover:bg-black/80"
					aria-label="Cerrar"
				>
					×
				</button>
			</div>

			<!-- Info + acciones -->
			<div class="border-t border-white/10 p-4">
				{#if selected.titulo}
					<h3 class="mb-1 font-semibold text-pink-100">{selected.titulo}</h3>
				{/if}
				{#if selected.descripcion}
					<p class="mb-3 text-sm text-pink-300/70">{selected.descripcion}</p>
				{/if}

				<div class="mb-4 flex items-center gap-3">
					<LikeButton mediaId={selected.id} />
					<span class="text-xs text-white/40">{comments.length} comentarios</span>
				</div>

				<!-- Comentarios -->
				<div class="max-h-48 space-y-2 overflow-y-auto">
					{#if loadingComments}
						<p class="text-sm text-white/40">Cargando...</p>
					{:else}
						{#each comments as c (c.id)}
							<div class="flex gap-2">
								<div
									class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-pink-900/50 text-xs font-bold text-pink-300"
								>
									{getInitials(c.profiles?.display_name ?? c.profiles?.username)}
								</div>
								<div>
									<span class="text-xs font-semibold text-pink-300"
										>{c.profiles?.display_name ?? c.profiles?.username ?? 'Usuario'}</span
									>
									<p class="text-sm text-white/80">{c.contenido}</p>
								</div>
							</div>
						{/each}
						{#if comments.length === 0}
							<p class="text-sm text-white/30 italic">Sé la primera en comentar.</p>
						{/if}
					{/if}
				</div>

				{#if $user}
					<div class="mt-3 flex gap-2">
						<input
							bind:value={newComment}
							on:keydown={(e) => e.key === 'Enter' && addComment()}
							placeholder="Escribe un comentario..."
							maxlength="500"
							class="flex-1 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
						/>
						<button
							on:click={addComment}
							disabled={sendingComment || !newComment.trim()}
							class="rounded-xl bg-pink-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-pink-700 disabled:opacity-40"
						>
							{sendingComment ? '...' : 'Enviar'}
						</button>
					</div>
				{/if}
			</div>
		</div>
	</div>
{/if}
