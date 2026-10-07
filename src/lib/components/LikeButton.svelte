<script>
	import { supabase } from '$lib/supabaseClient';
	import { user } from '$lib/stores/auth';
	import { onMount } from 'svelte';

	/** @type {string} */
	export let mediaId;

	/** @type {number} */
	export let initialCount = 0;

	let liked = false;
	let count = initialCount;
	let loading = false;

	onMount(async () => {
		if (!$user) return;
		const { data } = await supabase
			.from('media_likes')
			.select('id')
			.eq('media_id', mediaId)
			.eq('user_id', $user.id)
			.maybeSingle();
		liked = !!data;
	});

	async function toggle() {
		if (!$user || loading) return;
		loading = true;

		if (liked) {
			await supabase.from('media_likes').delete().eq('media_id', mediaId).eq('user_id', $user.id);
			liked = false;
			count = Math.max(0, count - 1);
		} else {
			await supabase.from('media_likes').insert({ media_id: mediaId, user_id: $user.id });
			liked = true;
			count += 1;
		}

		loading = false;
	}
</script>

<button
	on:click={toggle}
	disabled={loading || !$user}
	class="flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-medium transition
		{liked
		? 'bg-pink-600/20 text-pink-400 hover:bg-pink-600/30'
		: 'bg-white/5 text-pink-300/70 hover:bg-white/10 hover:text-pink-300'}
		disabled:opacity-40"
	aria-label={liked ? 'Quitar like' : 'Dar like'}
>
	<svg
		class="h-4 w-4 transition-transform {loading ? 'scale-90' : 'scale-100'}"
		fill={liked ? 'currentColor' : 'none'}
		stroke="currentColor"
		stroke-width="2"
		viewBox="0 0 24 24"
	>
		<path
			stroke-linecap="round"
			stroke-linejoin="round"
			d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
		/>
	</svg>
	<span>{count}</span>
</button>
