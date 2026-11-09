<script>
	import { supabase } from '$lib/supabaseClient';
	import { user } from '$lib/stores/auth';
	import { onMount } from 'svelte';
	import { SOCIAL } from '$lib/featureFlags';

	/** @type {string} */
	export let targetUserId;

	let following = false;
	let loading = false;
	let followerCount = 0;

	onMount(async () => {
		if (!SOCIAL.follows) return;
		if (!$user) return;
		const { data } = await supabase
			.from('follows')
			.select('id')
			.eq('follower_id', $user.id)
			.eq('following_id', targetUserId)
			.maybeSingle();
		following = !!data;

		const { count } = await supabase
			.from('follows')
			.select('id', { count: 'exact', head: true })
			.eq('following_id', targetUserId);
		followerCount = count ?? 0;
	});

	async function toggle() {
		if (!SOCIAL.follows) return;
		if (!$user || loading) return;
		loading = true;

		if (following) {
			await supabase
				.from('follows')
				.delete()
				.eq('follower_id', $user.id)
				.eq('following_id', targetUserId);
			following = false;
			followerCount = Math.max(0, followerCount - 1);
		} else {
			await supabase.from('follows').insert({ follower_id: $user.id, following_id: targetUserId });
			following = true;
			followerCount += 1;
		}

		loading = false;
	}
</script>

<button
	on:click={toggle}
	disabled={loading || !$user || $user?.id === targetUserId}
	class="flex items-center gap-2 rounded-full px-4 py-2 text-sm font-semibold transition
		{following
		? 'border border-pink-500/40 bg-pink-900/30 text-pink-300 hover:bg-pink-900/50'
		: 'bg-gradient-to-r from-pink-600 to-purple-600 text-white shadow-lg hover:shadow-pink-600/40 hover:brightness-110'}
		disabled:opacity-40"
	aria-label={following ? 'Dejar de seguir' : 'Seguir'}
>
	{#if following}
		<svg class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
			<path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
		</svg>
		Siguiendo
	{:else}
		<svg class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
			<path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
		</svg>
		Seguir
	{/if}
	{#if followerCount > 0}
		<span class="text-xs opacity-70">({followerCount})</span>
	{/if}
</button>
