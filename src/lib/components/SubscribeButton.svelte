<script>
	import { supabase } from '$lib/supabaseClient';
	import { user } from '$lib/stores/auth';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';

	/** @type {string} */
	export let creatorId;

	/** @type {number | null} */
	export let price = null;

	/** @type {string | null} */
	export let creatorName = null;

	let subscribed = false;
	let loading = false;
	let showConfirm = false;
	/** @type {string | null} */
	/** @type {string | null} */
	let subscriptionId = null;

	onMount(async () => {
		if (!$user) return;
		const { data } = await supabase
			.from('media_subscriptions')
			.select('id, status')
			.eq('creator_id', creatorId)
			.eq('subscriber_id', $user.id)
			.maybeSingle();

		if (data && data.status === 'activa') {
			subscribed = true;
			subscriptionId = data.id;
		}
	});

	async function subscribe() {
		if (!$user) {
			goto('/login');
			return;
		}
		loading = true;

		const { data, error } = await supabase
			.from('media_subscriptions')
			.upsert(
				{
					creator_id: creatorId,
					subscriber_id: $user.id,
					status: 'activa',
					price: price ?? 0
				},
				{ onConflict: 'creator_id,subscriber_id' }
			)
			.select('id')
			.single();

		if (!error && data) {
			subscribed = true;
			subscriptionId = data.id;
		}

		showConfirm = false;
		loading = false;
	}

	async function unsubscribe() {
		if (!subscriptionId || loading) return;
		loading = true;

		await supabase
			.from('media_subscriptions')
			.update({ status: 'cancelada' })
			.eq('id', subscriptionId);

		subscribed = false;
		subscriptionId = null;
		loading = false;
	}

	/** @param {number | null | undefined} p */
	function formatPrice(p) {
		if (!p || p === 0) return 'Gratis';
		return `$${Number(p).toFixed(2)}/mes`;
	}
</script>

{#if subscribed}
	<div class="flex items-center gap-2">
		<span
			class="flex items-center gap-1.5 rounded-full border border-green-500/40 bg-green-900/20 px-4 py-2 text-sm font-semibold text-green-400"
		>
			<svg class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
				<path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
			</svg>
			Suscrita
		</span>
		<button
			on:click={unsubscribe}
			disabled={loading}
			class="rounded-full border border-white/10 px-3 py-1.5 text-xs text-white/50 transition hover:border-red-500/40 hover:text-red-400"
		>
			Cancelar
		</button>
	</div>
{:else}
	<button
		on:click={() => (showConfirm = true)}
		disabled={loading || $user?.id === creatorId}
		class="rounded-full bg-gradient-to-r from-pink-600 to-purple-600 px-5 py-2.5 text-sm font-bold text-white shadow-lg transition hover:shadow-pink-600/40 hover:brightness-110 disabled:opacity-40"
	>
		Suscribirse · {formatPrice(price)}
	</button>
{/if}

{#if showConfirm}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
		role="dialog"
		aria-modal="true"
	>
		<div class="w-full max-w-sm rounded-2xl border border-pink-500/30 bg-black p-6 shadow-2xl">
			<h3 class="mb-2 text-lg font-bold text-pink-100">Confirmar suscripción</h3>
			<p class="mb-1 text-sm text-pink-300">
				{creatorName ? `Vas a suscribirte a ${creatorName}.` : 'Vas a suscribirte a esta creadora.'}
			</p>
			<p class="mb-6 text-xl font-bold text-pink-400">{formatPrice(price)}</p>

			<div class="flex gap-3">
				<button
					on:click={subscribe}
					disabled={loading}
					class="flex-1 rounded-xl bg-gradient-to-r from-pink-600 to-purple-600 py-2.5 font-bold text-white transition hover:brightness-110 disabled:opacity-50"
				>
					{loading ? 'Procesando...' : 'Confirmar'}
				</button>
				<button
					on:click={() => (showConfirm = false)}
					class="flex-1 rounded-xl border border-white/10 py-2.5 text-white/60 transition hover:bg-white/5"
				>
					Cancelar
				</button>
			</div>
		</div>
	</div>
{/if}
