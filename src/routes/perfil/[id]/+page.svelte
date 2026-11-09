<script>
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { supabase } from '$lib/supabaseClient';
	import { user } from '$lib/stores/auth';
	import MediaGrid from '$lib/components/MediaGrid.svelte';
	import FollowButton from '$lib/components/FollowButton.svelte';
	import SubscribeButton from '$lib/components/SubscribeButton.svelte';
	import { loadCovers, loadPublicMediaPage } from '$lib/media/client';
	import { SOCIAL } from '$lib/featureFlags';

	/**
	 * @typedef {Object} Perfil
	 * @property {string} id
	 * @property {string | null} role
	 * @property {string | null} username
	 * @property {string | null} display_name
	 * @property {string | null} bio
	 * @property {string | null} avatar_key
	 * @property {string | null} banner_key
	 * @property {number | null} subscription_price
	 * @property {boolean | null} is_verified
	 * @property {string | null} city
	 * @property {string | null} country_code
	 * @property {number} followers_count
	 * @property {number} media_count
	 */

	/** @type {Perfil | null} */
	/** @type {any} */
	let profile = null;
	/** @type {any[]} */
	let banners = [];
	let currentBannerIndex = 0;
	/** @type {any[]} */
	let mediaItems = [];
	/** @type {string | null} */
	let mediaCursor = null;
	let mediaLoading = false;
	let mediaError = '';
	/** @type {number} */
	let mediaCount = 0;
	let loading = true;
	/** @type {string | null} */
	let error = null;
	let isOwnProfile = false;

	/** @type {string} */
	let profileId;
	$: profileId = $page.params.id ?? '';

	onMount(async () => {
		try {
			const { data: p, error: pErr } = await supabase
				.from('profiles')
				.select(
					'id, role, username, display_name, bio, avatar_key, banner_key, subscription_price, is_verified, city, country_code, followers_count, following_count, media_count'
				)
				.eq('id', profileId)
				.single();

			if (pErr || !p) throw new Error('Perfil no encontrado');
			profile = /** @type {any} */ (p);

			isOwnProfile = $user?.id === profileId;

			// Solo se cuentan y muestran fotos aprobadas. La RPC vuelve a
			// comprobar el estado en la base; el cliente no decide visibilidad.
			const { data: count } = await supabase.rpc('public_approved_media_count', {
				target_user_id: profileId
			});
			mediaCount = Number(count ?? 0);

			banners = await loadCovers(profileId);

			// Cargar contenido
			await loadMedia();
		} catch (err) {
			error = err instanceof Error ? err.message : String(err);
		} finally {
			loading = false;
		}
	});

	async function loadMedia(append = false) {
		if (mediaLoading) return;
		mediaLoading = true;
		mediaError = '';
		try {
		const { items: rows, nextCursor } = await loadPublicMediaPage(profileId, { cursor: append ? mediaCursor : null });

		const incoming = rows.map((row) => ({
			id: row.id,
			user_id: profileId,
			tipo: 'photo',
			public_url: row.previewUrl ?? row.fullUrl,
			storage_key: null,
			titulo: row.title,
			descripcion: row.description,
			es_privado: false,
			bucket: 'private',
			orden: 0,
			created_at: row.created_at
		}));
		mediaItems = append ? [...mediaItems, ...incoming.filter((row) => !mediaItems.some((current) => current.id === row.id))] : incoming;
		mediaCursor = nextCursor;
		} catch (err) {
			mediaError = err instanceof Error ? err.message : 'No se pudo cargar la galeria.';
		} finally { mediaLoading = false; }
	}

	const prevBanner = () => {
		if (banners.length > 1)
			currentBannerIndex = (currentBannerIndex - 1 + banners.length) % banners.length;
	};
	const nextBanner = () => {
		if (banners.length > 1) currentBannerIndex = (currentBannerIndex + 1) % banners.length;
	};

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

{#if loading}
	<div class="flex min-h-[60vh] items-center justify-center">
		<div
			class="h-10 w-10 animate-spin rounded-full border-2 border-pink-500 border-t-transparent"
		></div>
	</div>
{:else if error || !profile}
	<div class="flex min-h-[60vh] flex-col items-center justify-center gap-4 text-center">
		<p class="text-xl text-pink-300">{error ?? 'Perfil no encontrado'}</p>
		<a href="/" class="text-sm text-pink-400 underline">Volver al inicio</a>
	</div>
{:else}
	<div class="mx-auto w-full max-w-5xl px-4 py-6">
		<!-- Banner -->
		<div class="relative mb-0 h-56 w-full overflow-hidden rounded-t-2xl bg-black/60 md:h-72">
			{#if banners.length > 0}
				<img
					src={banners[currentBannerIndex].public_url}
					alt="Banner"
					class="h-full w-full object-cover"
				/>
				{#if banners.length > 1}
					<button
						on:click={prevBanner}
						class="absolute top-1/2 left-3 -translate-y-1/2 rounded-full bg-black/60 p-2 text-white hover:bg-black/80"
						aria-label="Anterior">‹</button
					>
					<button
						on:click={nextBanner}
						class="absolute top-1/2 right-3 -translate-y-1/2 rounded-full bg-black/60 p-2 text-white hover:bg-black/80"
						aria-label="Siguiente">›</button
					>
					<div class="absolute bottom-2 left-1/2 flex -translate-x-1/2 gap-1">
						{#each banners as _, i}
							<div
								class="h-1.5 w-1.5 rounded-full transition {i === currentBannerIndex
									? 'bg-white'
									: 'bg-white/40'}"
							></div>
						{/each}
					</div>
				{/if}
			{:else}
				<div
					class="flex h-full items-center justify-center bg-gradient-to-br from-pink-950/40 to-purple-950/40"
				>
					<span class="text-4xl text-pink-400/30">Agua en la Boca</span>
				</div>
			{/if}
		</div>

		<!-- Perfil header -->
		<div class="rounded-b-2xl border border-t-0 border-pink-900/30 bg-black/50 px-6 pb-6">
			<div class="flex flex-col gap-4 pt-4 sm:flex-row sm:items-end sm:gap-6">
				<!-- Avatar -->
				<div class="-mt-10 shrink-0 sm:-mt-8">
					{#if profile.avatar_key}
						<img
							src={profile.avatar_key}
							alt={profile.display_name}
							class="h-24 w-24 rounded-full border-4 border-black object-cover shadow-xl sm:h-28 sm:w-28"
						/>
					{:else}
						<div
							class="flex h-24 w-24 items-center justify-center rounded-full border-4 border-black bg-gradient-to-br from-pink-900 to-purple-900 text-3xl font-bold text-pink-300 shadow-xl sm:h-28 sm:w-28"
						>
							{getInitials(profile.display_name ?? profile.username)}
						</div>
					{/if}
				</div>

				<!-- Info -->
				<div class="min-w-0 flex-1">
					<div class="flex flex-wrap items-center gap-2">
						<h1 class="text-2xl font-bold text-pink-100">
							{profile.display_name ?? profile.username ?? 'Usuario'}
						</h1>
						{#if profile.is_verified}
							<span class="text-blue-400" title="Verificada" aria-label="Verificada">✓</span>
						{/if}
						{#if profile.role === 'creator'}
							<span
								class="rounded-full bg-pink-600/20 px-2 py-0.5 text-xs font-semibold text-pink-400"
								>Creadora</span
							>
						{/if}
					</div>

					{#if profile.username}
						<p class="text-sm text-pink-400/60">@{profile.username}</p>
					{/if}

					<div class="mt-2 flex gap-4 text-sm text-pink-300/70">
						<span><strong class="text-pink-100">{mediaCount}</strong> publicaciones</span>
						<span
							><strong class="text-pink-100">{profile.followers_count ?? 0}</strong> seguidoras</span
						>
					</div>

					{#if profile.bio}
						<p class="mt-2 text-sm text-pink-300/80">{profile.bio}</p>
					{/if}
				</div>

				<!-- Acciones -->
				{#if !isOwnProfile}
					<div class="flex shrink-0 flex-col gap-2 sm:items-end">
						{#if SOCIAL.follows}
							<FollowButton targetUserId={profileId} />
						{/if}
						{#if SOCIAL.subscriptions && profile.role === 'creator'}
							<SubscribeButton
								creatorId={profileId}
								price={profile.subscription_price}
								creatorName={profile.display_name}
							/>
						{/if}
						{#if SOCIAL.messages}
							<a
								href="/mensajes/{profileId}"
								class="rounded-full border border-white/10 px-4 py-2 text-center text-sm text-pink-300 transition hover:bg-white/5"
							>
								Mensaje
							</a>
						{/if}
					</div>
				{/if}
			</div>
		</div>

		<!-- Contenido aprobado -->
		<div class="mt-6">
			<MediaGrid items={mediaItems} showActions={true} isOwner={isOwnProfile} />
			{#if mediaError}<p class="mt-4 text-sm text-red-300">{mediaError}</p>{/if}
			{#if mediaCursor}
				<button on:click={() => loadMedia(true)} disabled={mediaLoading} class="mt-4 rounded-xl border border-pink-500/40 px-5 py-2 text-sm text-pink-200 disabled:opacity-50">
					{mediaLoading ? 'Cargando...' : 'Cargar mas fotos'}
				</button>
			{/if}

			{#if mediaItems.length === 0 && !mediaError}
				<p class="py-8 text-center text-sm text-pink-300/50 italic">
					Todavia no hay fotos aprobadas.
				</p>
			{/if}
		</div>
	</div>
{/if}
