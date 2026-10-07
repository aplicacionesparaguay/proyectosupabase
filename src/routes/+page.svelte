<script>
	import { onMount } from 'svelte';
	import { session } from '$lib/stores/auth';
	import CreatorCard from '$lib/components/CreatorCard.svelte';
	import MediaGrid from '$lib/components/MediaGrid.svelte';
	import { supabase } from '$lib/supabaseClient';

	/**
	 * @typedef {Object} Creadora
	 * @property {string} id
	 * @property {string | null} displayName
	 * @property {string | null} username
	 * @property {string | null} city
	 * @property {string | null} countryName
	 * @property {string | null} photoUrl
	 * @property {boolean} isVerified
	 * @property {number} [followerCount]
	 */

	/** @type {{ creadoras: Creadora[] }} */
	export let data;

	$: creadoras = data?.creadoras ?? [];

	/** @type {any[]} */
	/** @type {any[]} */
	let feedItems = [];
	let feedLoading = false;
	let tab = 'creadoras';

	$: logueado = $session !== null;

	onMount(async () => {
		if (!logueado) return;
		tab = 'feed';
		await loadFeed();
	});

	async function loadFeed() {
		if (!$session?.user) return;
		feedLoading = true;

		const { data: follows } = await supabase
			.from('follows')
			.select('following_id')
			.eq('follower_id', $session.user.id);

		const followingIds = (follows ?? []).map((f) => f.following_id);
		const ids = [...followingIds, $session.user.id];

		const { data: media } = await supabase
			.from('media')
			.select(
				`id, user_id, tipo, public_url, storage_key, titulo, descripcion,
				 es_privado, bucket, orden, created_at,
				 profiles(display_name, username, avatar_key),
				 media_likes(count),
				 media_comments(count)`
			)
			.in('user_id', ids)
			.eq('tipo', 'photo')
			.order('created_at', { ascending: false })
			.limit(40);

		feedItems = (media ?? []).map((m) => ({
			...m,
			like_count: m.media_likes?.[0]?.count ?? 0,
			comment_count: m.media_comments?.[0]?.count ?? 0
		}));

		feedLoading = false;
	}
</script>

{#if logueado}
	<!-- FEED PARA LOGUEADOS -->
	<section class="mx-auto w-full max-w-5xl px-4 py-8">
		<!-- Tabs -->
		<div class="mb-6 flex gap-1 rounded-2xl border border-pink-900/30 bg-black/40 p-1">
			<button
				on:click={() => (tab = 'feed')}
				class="flex-1 rounded-xl py-2.5 text-sm font-semibold transition
					{tab === 'feed'
					? 'bg-gradient-to-r from-pink-600 to-purple-600 text-white'
					: 'text-pink-300/60 hover:text-pink-300'}"
			>
				Para ti
			</button>
			<button
				on:click={() => (tab = 'creadoras')}
				class="flex-1 rounded-xl py-2.5 text-sm font-semibold transition
					{tab === 'creadoras'
					? 'bg-gradient-to-r from-pink-600 to-purple-600 text-white'
					: 'text-pink-300/60 hover:text-pink-300'}"
			>
				Creadoras
			</button>
		</div>

		{#if tab === 'feed'}
			{#if feedLoading}
				<div class="py-16 text-center text-pink-300/50">Cargando...</div>
			{:else if feedItems.length === 0}
				<div
					class="rounded-2xl border border-dashed border-pink-900/40 bg-black/20 px-6 py-16 text-center"
				>
					<p class="mb-2 text-lg text-pink-300">Tu feed está vacío</p>
					<p class="text-sm text-pink-300/50">
						Sigue a algunas creadoras para ver su contenido aquí.
					</p>
					<button
						on:click={() => (tab = 'creadoras')}
						class="mt-4 rounded-xl bg-gradient-to-r from-pink-600 to-purple-600 px-6 py-2.5 font-semibold text-white transition hover:brightness-110"
					>
						Explorar creadoras
					</button>
				</div>
			{:else}
				<MediaGrid items={feedItems} showActions={true} />
			{/if}
		{:else}
			<div class="mb-4 flex items-center justify-between">
				<h2 class="text-xl font-bold text-pink-100">Creadoras</h2>
				<a href="/publicar" class="text-sm text-pink-400 transition hover:text-pink-300"
					>+ Publicar</a
				>
			</div>
			{#if creadoras.length > 0}
				<ul class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
					{#each creadoras as creadora (creadora.id)}
						<li>
							<CreatorCard
								id={creadora.id}
								displayName={creadora.displayName}
								username={creadora.username}
								city={creadora.city}
								countryName={creadora.countryName}
								photoUrl={creadora.photoUrl}
								isVerified={creadora.isVerified}
							/>
						</li>
					{/each}
				</ul>
			{:else}
				<p
					class="rounded-xl border border-dashed border-pink-900/40 bg-black/20 px-6 py-12 text-center text-pink-300"
				>
					No hay creadoras disponibles todavía.
				</p>
			{/if}
		{/if}
	</section>
{:else}
	<!-- LANDING PARA NO LOGUEADOS -->
	<section class="mx-auto w-full max-w-6xl px-4 py-16 text-center">
		<h1
			class="mb-4 bg-gradient-to-r from-pink-400 via-purple-400 to-pink-300 bg-clip-text text-5xl font-black text-transparent md:text-7xl"
		>
			Agua en la Boca
		</h1>
		<p class="mb-8 text-xl text-pink-300/70 md:text-2xl">
			La plataforma de contenido exclusivo para adultos.
		</p>
		<div class="flex justify-center gap-4">
			<a
				href="/register"
				class="rounded-2xl bg-gradient-to-r from-pink-600 to-purple-600 px-8 py-4 text-lg font-bold text-white shadow-2xl shadow-pink-600/40 transition hover:brightness-110"
			>
				Crear cuenta gratis
			</a>
			<a
				href="/login"
				class="rounded-2xl border border-pink-500/40 px-8 py-4 text-lg font-semibold text-pink-300 transition hover:bg-pink-900/20"
			>
				Iniciar sesión
			</a>
		</div>
	</section>

	<section class="mx-auto w-full max-w-6xl px-4 pb-16">
		<h2 class="mb-6 text-2xl font-bold text-pink-100">Creadoras</h2>
		{#if creadoras.length > 0}
			<ul class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
				{#each creadoras as creadora (creadora.id)}
					<li>
						<CreatorCard
							id={creadora.id}
							displayName={creadora.displayName}
							username={creadora.username}
							city={creadora.city}
							countryName={creadora.countryName}
							photoUrl={creadora.photoUrl}
							isVerified={creadora.isVerified}
						/>
					</li>
				{/each}
			</ul>
		{:else}
			<p
				class="rounded-xl border border-dashed border-pink-900/40 bg-black/20 px-6 py-12 text-center text-pink-300"
			>
				No hay creadoras disponibles todavía.
			</p>
		{/if}
	</section>
{/if}
