<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { session, user } from '$lib/stores/auth';
	import { supabase } from '$lib/supabaseClient';
	import { SOCIAL } from '$lib/featureFlags';

	/**
	 * @typedef {Object} Notification
	 * @property {string} id
	 * @property {string} tipo
	 * @property {string | null} contenido
	 * @property {boolean} leido
	 * @property {string} created_at
	 * @property {string | null} media_id
	 * @property {{ display_name: string | null, username: string | null, avatar_key: string | null } | null} actor
	 */

	/** @type {Notification[]} */
	let notifications = [];
	let loading = true;
	let markingAll = false;

	onMount(async () => {
		if (!$session?.user) {
			goto('/login');
			return;
		}

		if (!SOCIAL.notifications) {
			loading = false;
			return;
		}

		const { data } = await supabase
			.from('notifications')
			.select(
				`id, tipo, contenido, leido, created_at, media_id,
				 actor:profiles!notifications_actor_id_fkey(display_name, username, avatar_key)`
			)
			.eq('user_id', $user?.id)
			.order('created_at', { ascending: false })
			.limit(50);

		notifications = /** @type {any[]} */ (data ?? []);
		loading = false;
	});

	async function markAllRead() {
		if (markingAll || !$user) return;
		markingAll = true;

		await supabase
			.from('notifications')
			.update({ leido: true })
			.eq('user_id', $user?.id)
			.eq('leido', false);

		notifications = notifications.map((n) => ({ ...n, leido: true }));
		markingAll = false;
	}

	/** @param {any} n */
	async function openNotification(n) {
		if (!n.leido) {
			await supabase.from('notifications').update({ leido: true }).eq('id', n.id);
			notifications = notifications.map((x) => (x.id === n.id ? { ...x, leido: true } : x));
		}

		if (n.media_id) {
			// Ir al perfil del dueño del media
			const { data: media } = await supabase
				.from('media')
				.select('user_id')
				.eq('id', n.media_id)
				.single();
			if (media) goto(`/perfil/${media.user_id}`);
		} else if (n.tipo === 'follow' || n.tipo === 'subscribe') {
			const actorId = /** @type {any} */ (notifications.find((x) => x.id === n.id))?.actor?.id;
			if (actorId) goto(`/perfil/${actorId}`);
		}
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

	/** @param {string} tipo */
	/** @param {string} tipo */
	function iconFor(tipo) {
		if (tipo === 'like') return '♥';
		if (tipo === 'comment') return '💬';
		if (tipo === 'follow') return '👤';
		if (tipo === 'subscribe') return '⭐';
		if (tipo === 'message') return '✉️';
		return '🔔';
	}

	$: unreadCount = notifications.filter((n) => !n.leido).length;
</script>

{#if loading}
	<div class="flex min-h-[60vh] items-center justify-center">
		<div
			class="h-10 w-10 animate-spin rounded-full border-2 border-pink-500 border-t-transparent"
		></div>
	</div>
{:else}
	<div class="mx-auto w-full max-w-2xl px-4 py-8">
		<div class="mb-6 flex items-center justify-between">
			<h1 class="text-2xl font-bold text-pink-100">Notificaciones</h1>
			{#if unreadCount > 0}
				<button
					on:click={markAllRead}
					disabled={markingAll}
					class="text-sm text-pink-400 underline transition hover:text-pink-300"
				>
					Marcar todas como leídas
				</button>
			{/if}
		</div>

		{#if notifications.length === 0}
			<div
				class="rounded-2xl border border-dashed border-pink-900/40 bg-black/20 px-6 py-16 text-center"
			>
				<p class="text-pink-300/50">Sin notificaciones todavía.</p>
			</div>
		{:else}
			<div class="space-y-1">
				{#each notifications as n (n.id)}
					<button
						on:click={() => openNotification(n)}
						class="flex w-full items-center gap-3 rounded-2xl border px-4 py-3 text-left transition
							{n.leido
							? 'border-white/5 bg-transparent hover:bg-white/5'
							: 'border-pink-500/20 bg-pink-900/10 hover:bg-pink-900/20'}"
					>
						<!-- Avatar del actor -->
						<div class="relative shrink-0">
							{#if n.actor?.avatar_key}
								<img src={n.actor.avatar_key} alt="" class="h-10 w-10 rounded-full object-cover" />
							{:else}
								<div
									class="flex h-10 w-10 items-center justify-center rounded-full bg-pink-900/50 font-bold text-pink-300"
								>
									{getInitials(n.actor?.display_name ?? n.actor?.username)}
								</div>
							{/if}
							<span class="absolute -right-0.5 -bottom-0.5 text-sm">{iconFor(n.tipo)}</span>
						</div>

						<!-- Contenido -->
						<div class="min-w-0 flex-1">
							<p class="text-sm text-pink-100">
								<strong>{n.actor?.display_name ?? n.actor?.username ?? 'Alguien'}</strong>
								{' '}{n.contenido ?? ''}
							</p>
							<p class="text-xs text-pink-400/50">{timeAgo(n.created_at)}</p>
						</div>

						{#if !n.leido}
							<span class="h-2 w-2 shrink-0 rounded-full bg-pink-500" aria-label="Sin leer"></span>
						{/if}
					</button>
				{/each}
			</div>
		{/if}
	</div>
{/if}
