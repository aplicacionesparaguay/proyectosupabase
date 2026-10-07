<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { session, user } from '$lib/stores/auth';
	import { supabase } from '$lib/supabaseClient';

	/**
	 * @typedef {Object} Subscription
	 * @property {string} id
	 * @property {string} creator_id
	 * @property {string} subscriber_id
	 * @property {string} status
	 * @property {number | null} price
	 * @property {string} started_at
	 * @property {string | null} expires_at
	 * @property {{ display_name: string | null, username: string | null, avatar_key: string | null, subscription_price: number | null, is_verified: boolean | null }} creator
	 */

	/** @type {Subscription[]} */
	let subscriptions = [];
	let loading = true;
	let tab = 'activas';

	$: active = subscriptions.filter((s) => s.status === 'activa');
	$: cancelled = subscriptions.filter((s) => s.status !== 'activa');

	onMount(async () => {
		if (!$session?.user) {
			goto('/login');
			return;
		}

		const { data } = await supabase
			.from('media_subscriptions')
			.select(
				`id, creator_id, subscriber_id, status, price, started_at, expires_at,
				 creator:profiles!media_subscriptions_creator_id_fkey(
				   display_name, username, avatar_key, subscription_price, is_verified
				 )`
			)
			.eq('subscriber_id', $user?.id)
			.order('started_at', { ascending: false });

		subscriptions = /** @type {any[]} */ (data ?? []);
		loading = false;
	});

	/** @param {any} sub */
	async function cancel(sub) {
		await supabase.from('media_subscriptions').update({ status: 'cancelada' }).eq('id', sub.id);

		subscriptions = subscriptions.map((s) => (s.id === sub.id ? { ...s, status: 'cancelada' } : s));
	}

	/** @param {any} sub */
	async function reactivate(sub) {
		await supabase.from('media_subscriptions').update({ status: 'activa' }).eq('id', sub.id);

		subscriptions = subscriptions.map((s) => (s.id === sub.id ? { ...s, status: 'activa' } : s));
	}

	/** @param {number | null | undefined} p */
	/** @param {number | null | undefined} p */
	function formatPrice(p) {
		if (!p || p === 0) return 'Gratis';
		return `$${Number(p).toFixed(2)}/mes`;
	}

	/** @param {string} iso */
	/** @param {string} iso */
	function formatDate(iso) {
		return new Date(iso).toLocaleDateString('es-ES', {
			day: 'numeric',
			month: 'long',
			year: 'numeric'
		});
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
				.join('') ?? '?'
		);
	}

	$: shown = tab === 'activas' ? active : cancelled;
</script>

{#if loading}
	<div class="flex min-h-[60vh] items-center justify-center">
		<div
			class="h-10 w-10 animate-spin rounded-full border-2 border-pink-500 border-t-transparent"
		></div>
	</div>
{:else}
	<div class="mx-auto w-full max-w-2xl px-4 py-8">
		<h1 class="mb-6 text-2xl font-bold text-pink-100">Mis suscripciones</h1>

		<!-- Tabs -->
		<div class="mb-6 flex gap-1 rounded-xl border border-pink-900/30 bg-black/40 p-1">
			<button
				on:click={() => (tab = 'activas')}
				class="flex-1 rounded-lg py-2 text-sm font-semibold transition
					{tab === 'activas' ? 'bg-pink-600/20 text-pink-300' : 'text-pink-300/50 hover:text-pink-300'}"
			>
				Activas ({active.length})
			</button>
			<button
				on:click={() => (tab = 'historial')}
				class="flex-1 rounded-lg py-2 text-sm font-semibold transition
					{tab === 'historial' ? 'bg-pink-600/20 text-pink-300' : 'text-pink-300/50 hover:text-pink-300'}"
			>
				Historial ({cancelled.length})
			</button>
		</div>

		{#if shown.length === 0}
			<div
				class="rounded-2xl border border-dashed border-pink-900/40 bg-black/20 px-6 py-16 text-center"
			>
				{#if tab === 'activas'}
					<p class="mb-2 text-pink-300">No tienes suscripciones activas</p>
					<a href="/" class="text-sm text-pink-400 underline">Explorar creadoras</a>
				{:else}
					<p class="text-pink-300/50">Sin historial.</p>
				{/if}
			</div>
		{:else}
			<div class="space-y-3">
				{#each shown as sub (sub.id)}
					<div
						class="flex items-center gap-4 rounded-2xl border border-pink-900/30 bg-black/40 p-4"
					>
						<!-- Avatar -->
						<a href="/perfil/{sub.creator_id}" class="shrink-0">
							{#if sub.creator?.avatar_key}
								<img
									src={sub.creator.avatar_key}
									alt=""
									class="h-12 w-12 rounded-full object-cover"
								/>
							{:else}
								<div
									class="flex h-12 w-12 items-center justify-center rounded-full bg-pink-900/50 font-bold text-pink-300"
								>
									{getInitials(sub.creator?.display_name ?? sub.creator?.username)}
								</div>
							{/if}
						</a>

						<!-- Info -->
						<div class="min-w-0 flex-1">
							<div class="flex items-center gap-1.5">
								<a
									href="/perfil/{sub.creator_id}"
									class="truncate font-semibold text-pink-100 hover:text-pink-300"
								>
									{sub.creator?.display_name ?? sub.creator?.username ?? 'Creadora'}
								</a>
								{#if sub.creator?.is_verified}
									<span class="text-blue-400">✓</span>
								{/if}
							</div>
							<p class="text-sm text-pink-300/60">{formatPrice(sub.price)}</p>
							<p class="text-xs text-pink-400/40">Desde {formatDate(sub.started_at)}</p>
						</div>

						<!-- Estado + acción -->
						<div class="flex shrink-0 flex-col items-end gap-2">
							<span
								class="rounded-full px-2.5 py-0.5 text-xs font-semibold
								{sub.status === 'activa' ? 'bg-green-900/30 text-green-400' : 'bg-white/5 text-white/40'}"
							>
								{sub.status === 'activa' ? 'Activa' : 'Cancelada'}
							</span>
							{#if sub.status === 'activa'}
								<button
									on:click={() => cancel(sub)}
									class="text-xs text-white/40 underline transition hover:text-red-400"
								>
									Cancelar
								</button>
							{:else}
								<button
									on:click={() => reactivate(sub)}
									class="text-xs text-pink-400 underline transition hover:text-pink-300"
								>
									Reactivar
								</button>
							{/if}
						</div>
					</div>
				{/each}
			</div>
		{/if}
	</div>
{/if}
