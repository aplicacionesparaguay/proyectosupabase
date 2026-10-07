<script>
	import { onMount, onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import { session, user } from '$lib/stores/auth';
	import { supabase } from '$lib/supabaseClient';
	import ConversationList from '$lib/components/ConversationList.svelte';

	/** @type {import('$lib/components/ConversationList.svelte').default['$$prop_def']['conversations']} */
	let conversations = [];
	let loading = true;
	/** @type {ReturnType<typeof supabase.channel> | null} */
	let channel = null;

	onMount(async () => {
		if (!$session?.user) {
			goto('/login');
			return;
		}
		await loadConversations();
		subscribeToMessages();
	});

	onDestroy(() => {
		if (channel) supabase.removeChannel(channel);
	});

	async function loadConversations() {
		const { data: messages } = await supabase
			.from('messages')
			.select('id, sender_id, receiver_id, contenido, leido, created_at')
			.or(`sender_id.eq.${$user?.id},receiver_id.eq.${$user?.id}`)
			.order('created_at', { ascending: false });

		if (!messages) {
			loading = false;
			return;
		}

		// Agrupar por otra persona
		/** @type {Map<string, { lastMessage: string; lastAt: string; unread: number }>} */
		const byOther = new Map();

		for (const msg of messages) {
			const otherId = msg.sender_id === $user?.id ? msg.receiver_id : msg.sender_id;
			if (!byOther.has(otherId)) {
				byOther.set(otherId, {
					lastMessage: msg.contenido,
					lastAt: msg.created_at,
					unread: msg.receiver_id === $user?.id && !msg.leido ? 1 : 0
				});
			} else {
				const conv = /** @type {any} */ (byOther.get(otherId));
				if (msg.receiver_id === $user?.id && !msg.leido) conv.unread += 1;
			}
		}

		// Cargar perfiles de los otros
		const otherIds = [...byOther.keys()];
		if (otherIds.length === 0) {
			loading = false;
			return;
		}

		const { data: profiles } = await supabase
			.from('profiles')
			.select('id, display_name, username, avatar_key')
			.in('id', otherIds);

		const profileMap = new Map((profiles ?? []).map((p) => [p.id, p]));

		conversations = otherIds.map((otherId) => {
			const conv = /** @type {any} */ (byOther.get(otherId));
			const profile = profileMap.get(otherId);
			return {
				otherId,
				otherName: profile?.display_name ?? profile?.username ?? 'Usuario',
				otherAvatar: profile?.avatar_key ?? null,
				lastMessage: conv.lastMessage,
				lastAt: conv.lastAt,
				unread: conv.unread
			};
		});

		loading = false;
	}

	function subscribeToMessages() {
		channel = supabase
			.channel(`messages-${$user?.id}`)
			.on(
				'postgres_changes',
				{
					event: 'INSERT',
					schema: 'public',
					table: 'messages',
					filter: `receiver_id=eq.${$user?.id}`
				},
				() => loadConversations()
			)
			.subscribe();
	}
</script>

{#if loading}
	<div class="flex min-h-[60vh] items-center justify-center">
		<div
			class="h-10 w-10 animate-spin rounded-full border-2 border-pink-500 border-t-transparent"
		></div>
	</div>
{:else}
	<div class="mx-auto w-full max-w-md px-4 py-8">
		<div class="h-[70vh]">
			<ConversationList {conversations} />
		</div>
	</div>
{/if}
