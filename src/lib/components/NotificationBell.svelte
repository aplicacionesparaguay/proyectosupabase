<script>
	import { supabase } from '$lib/supabaseClient';
	import { user } from '$lib/stores/auth';
	import { onMount, onDestroy } from 'svelte';

	let unread = 0;
	/** @type {ReturnType<typeof supabase.channel> | null} */
	let channel = null;

	async function loadCount() {
		if (!$user) return;
		const { count } = await supabase
			.from('notifications')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', $user.id)
			.eq('leido', false);
		unread = count ?? 0;
	}

	onMount(async () => {
		await loadCount();

		if (!$user) return;
		channel = supabase
			.channel(`notifications-${$user.id}`)
			.on(
				'postgres_changes',
				{
					event: 'INSERT',
					schema: 'public',
					table: 'notifications',
					filter: `user_id=eq.${$user.id}`
				},
				() => loadCount()
			)
			.on(
				'postgres_changes',
				{
					event: 'UPDATE',
					schema: 'public',
					table: 'notifications',
					filter: `user_id=eq.${$user.id}`
				},
				() => loadCount()
			)
			.subscribe();
	});

	onDestroy(() => {
		if (channel) supabase.removeChannel(channel);
	});
</script>

<a
	href="/notificaciones"
	class="relative flex h-10 w-10 items-center justify-center rounded-full text-pink-300 transition hover:bg-white/10"
	aria-label="Notificaciones{unread > 0 ? ` (${unread} sin leer)` : ''}"
>
	<svg class="h-5 w-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
		<path
			stroke-linecap="round"
			stroke-linejoin="round"
			d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"
		/>
	</svg>
	{#if unread > 0}
		<span
			class="absolute -top-0.5 -right-0.5 flex h-5 w-5 items-center justify-center rounded-full bg-pink-600 text-[10px] font-bold text-white"
			aria-hidden="true"
		>
			{unread > 99 ? '99+' : unread}
		</span>
	{/if}
</a>
