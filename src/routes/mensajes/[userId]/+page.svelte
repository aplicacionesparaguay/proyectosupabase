<script>
	import { onMount, onDestroy, tick } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';
	import { session, user } from '$lib/stores/auth';
	import { supabase } from '$lib/supabaseClient';

	/**
	 * @typedef {Object} Message
	 * @property {string} id
	 * @property {string} sender_id
	 * @property {string} receiver_id
	 * @property {string} contenido
	 * @property {boolean} leido
	 * @property {string} created_at
	 */

	/** @type {Message[]} */
	let messages = [];
	let newMessage = '';
	let loading = true;
	let sending = false;
	/** @type {{ display_name: string | null, username: string | null, avatar_key: string | null } | null} */
	let otherProfile = null;
	/** @type {ReturnType<typeof supabase.channel> | null} */
	let channel = null;
	/** @type {HTMLElement | null} */
	let bottomRef = null;

	$: otherId = $page.params.userId;

	onMount(async () => {
		if (!$session?.user) {
			goto('/login');
			return;
		}
		if (otherId === $user?.id) {
			goto('/mensajes');
			return;
		}

		await Promise.all([loadProfile(), loadMessages()]);
		await markAsRead();
		subscribeToMessages();
		await scrollToBottom();
		loading = false;
	});

	onDestroy(() => {
		if (channel) supabase.removeChannel(channel);
	});

	async function loadProfile() {
		const { data } = await supabase
			.from('profiles')
			.select('display_name, username, avatar_key')
			.eq('id', otherId)
			.single();
		otherProfile = data;
	}

	async function loadMessages() {
		const { data } = await supabase
			.from('messages')
			.select('id, sender_id, receiver_id, contenido, leido, created_at')
			.or(
				`and(sender_id.eq.${$user?.id},receiver_id.eq.${otherId}),and(sender_id.eq.${otherId},receiver_id.eq.${$user?.id})`
			)
			.order('created_at', { ascending: true });

		messages = data ?? [];
	}

	async function markAsRead() {
		await supabase
			.from('messages')
			.update({ leido: true })
			.eq('sender_id', otherId)
			.eq('receiver_id', $user?.id)
			.eq('leido', false);
	}

	function subscribeToMessages() {
		channel = supabase
			.channel(`chat-${$user?.id}-${otherId}`)
			.on(
				'postgres_changes',
				{
					event: 'INSERT',
					schema: 'public',
					table: 'messages',
					filter: `receiver_id=eq.${$user?.id}`
				},
				async (payload) => {
					const msg = /** @type {any} */ (payload.new);
					if (msg.sender_id === otherId) {
						messages = [...messages, msg];
						await markAsRead();
						await scrollToBottom();
					}
				}
			)
			.subscribe();
	}

	async function send() {
		if (!newMessage.trim() || sending || !$user) return;
		sending = true;

		const content = newMessage.trim();
		newMessage = '';

		const { data, error } = await supabase
			.from('messages')
			.insert({
				sender_id: $user?.id,
				receiver_id: otherId,
				contenido: content
			})
			.select()
			.single();

		if (!error && data) {
			messages = [...messages, data];
			await scrollToBottom();
		} else {
			newMessage = content;
		}

		sending = false;
	}

	async function scrollToBottom() {
		await tick();
		bottomRef?.scrollIntoView({ behavior: 'smooth' });
	}

	/** @param {string} iso */
	function formatTime(iso) {
		return new Date(iso).toLocaleTimeString('es-ES', { hour: '2-digit', minute: '2-digit' });
	}

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
</script>

<div class="mx-auto flex h-[calc(100vh-4rem)] w-full max-w-2xl flex-col px-4 py-4">
	<!-- Header -->
	<div
		class="mb-3 flex items-center gap-3 rounded-2xl border border-pink-900/30 bg-black/40 px-4 py-3"
	>
		<a href="/mensajes" class="text-pink-400 hover:text-pink-300" aria-label="Volver">
			<svg class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
				<path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
			</svg>
		</a>

		{#if otherProfile?.avatar_key}
			<img src={otherProfile.avatar_key} alt="" class="h-9 w-9 rounded-full object-cover" />
		{:else}
			<div
				class="flex h-9 w-9 items-center justify-center rounded-full bg-pink-900/50 text-sm font-bold text-pink-300"
			>
				{getInitials(otherProfile?.display_name ?? otherProfile?.username)}
			</div>
		{/if}

		<div>
			<a href="/perfil/{otherId}" class="font-semibold text-pink-100 hover:text-pink-300">
				{otherProfile?.display_name ?? otherProfile?.username ?? 'Usuario'}
			</a>
		</div>
	</div>

	<!-- Mensajes -->
	<div
		class="flex-1 space-y-2 overflow-y-auto rounded-2xl border border-pink-900/20 bg-black/20 p-4"
	>
		{#if loading}
			<div class="flex h-full items-center justify-center">
				<div
					class="h-8 w-8 animate-spin rounded-full border-2 border-pink-500 border-t-transparent"
				></div>
			</div>
		{:else if messages.length === 0}
			<div class="flex h-full flex-col items-center justify-center gap-2 text-center">
				<p class="text-pink-300/50">Sin mensajes todavía.</p>
				<p class="text-sm text-pink-300/30">Envía el primero.</p>
			</div>
		{:else}
			{#each messages as msg (msg.id)}
				{@const isMine = msg.sender_id === $user?.id}
				<div class="flex {isMine ? 'justify-end' : 'justify-start'}">
					<div
						class="max-w-[75%] rounded-2xl px-4 py-2.5 text-sm
							{isMine
							? 'rounded-br-sm bg-gradient-to-r from-pink-600 to-purple-600 text-white'
							: 'rounded-bl-sm border border-white/10 bg-white/5 text-pink-100'}"
					>
						<p>{msg.contenido}</p>
						<p class="mt-1 text-right text-[10px] opacity-50">
							{formatTime(msg.created_at)}
							{#if isMine}{msg.leido ? ' ✓✓' : ' ✓'}{/if}
						</p>
					</div>
				</div>
			{/each}
		{/if}
		<div bind:this={bottomRef}></div>
	</div>

	<!-- Input -->
	<div class="mt-3 flex gap-2">
		<input
			bind:value={newMessage}
			on:keydown={(e) => e.key === 'Enter' && !e.shiftKey && send()}
			placeholder="Escribe un mensaje..."
			maxlength="2000"
			class="flex-1 rounded-2xl border border-white/10 bg-white/5 px-4 py-3 text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
		/>
		<button
			on:click={send}
			disabled={sending || !newMessage.trim()}
			class="flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-r from-pink-600 to-purple-600 text-white shadow-lg transition hover:brightness-110 disabled:opacity-40"
			aria-label="Enviar"
		>
			<svg class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
				<path stroke-linecap="round" stroke-linejoin="round" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
			</svg>
		</button>
	</div>
</div>
