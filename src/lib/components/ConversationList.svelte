<script>
	import { supabase } from '$lib/supabaseClient';
	import { user } from '$lib/stores/auth';
	import { goto } from '$app/navigation';

	/**
	 * @typedef {Object} MessagePreview
	 * @property {string} otherId
	 * @property {string | null} otherName
	 * @property {string | null} otherAvatar
	 * @property {string} lastMessage
	 * @property {string} lastAt
	 * @property {number} unread
	 */

	/** @type {MessagePreview[]} */
	export let conversations = [];

	/** @type {string | null} */
	export let activeId = null;

	/** @param {string | null | undefined} name */
	/** @param {string | null | undefined} name */
	function getInitials(name) {
		return (
			name
				?.split(/\s+/)
				.filter(Boolean)
				.slice(0, 2)
				.map((p) => p[0].toUpperCase())
				.join('') ?? '?'
		);
	}

	/** @param {string} iso */
	/** @param {string} iso */
	function timeAgo(iso) {
		const diff = Date.now() - new Date(iso).getTime();
		const mins = Math.floor(diff / 60000);
		if (mins < 1) return 'ahora';
		if (mins < 60) return `${mins}m`;
		const hours = Math.floor(mins / 60);
		if (hours < 24) return `${hours}h`;
		return `${Math.floor(hours / 24)}d`;
	}
</script>

<div class="flex h-full flex-col overflow-hidden rounded-2xl border border-pink-900/30 bg-black/40">
	<div class="border-b border-pink-900/30 px-4 py-3">
		<h2 class="font-bold text-pink-100">Mensajes</h2>
	</div>

	<div class="flex-1 overflow-y-auto">
		{#if conversations.length === 0}
			<p class="p-6 text-center text-sm text-pink-300/40 italic">Sin conversaciones.</p>
		{:else}
			{#each conversations as conv (conv.otherId)}
				<button
					on:click={() => goto(`/mensajes/${conv.otherId}`)}
					class="flex w-full items-center gap-3 border-b border-white/5 px-4 py-3 text-left transition hover:bg-white/5
						{activeId === conv.otherId ? 'bg-pink-900/20' : ''}"
				>
					<div class="relative shrink-0">
						{#if conv.otherAvatar}
							<img src={conv.otherAvatar} alt="" class="h-10 w-10 rounded-full object-cover" />
						{:else}
							<div
								class="flex h-10 w-10 items-center justify-center rounded-full bg-pink-900/50 font-bold text-pink-300"
							>
								{getInitials(conv.otherName)}
							</div>
						{/if}
						{#if conv.unread > 0}
							<span
								class="absolute -top-0.5 -right-0.5 flex h-4 w-4 items-center justify-center rounded-full bg-pink-600 text-[9px] font-bold text-white"
							>
								{conv.unread}
							</span>
						{/if}
					</div>

					<div class="min-w-0 flex-1">
						<div class="flex items-baseline justify-between gap-2">
							<span class="truncate text-sm font-semibold text-pink-100"
								>{conv.otherName ?? 'Usuario'}</span
							>
							<span class="shrink-0 text-xs text-pink-400/50">{timeAgo(conv.lastAt)}</span>
						</div>
						<p class="truncate text-xs text-pink-300/60">{conv.lastMessage}</p>
					</div>
				</button>
			{/each}
		{/if}
	</div>
</div>
