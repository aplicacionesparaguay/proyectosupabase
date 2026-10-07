<script>
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { supabase } from '$lib/supabaseClient';

	/**
	 * Perfil público, tal como lo devuelve el select de este archivo.
	 * @typedef {Object} Perfil
	 * @property {string} id
	 * @property {string | null} [role]
	 * @property {string | null} [username]
	 * @property {string | null} [display_name]
	 * @property {string | null} [bio]
	 * @property {string | null} [avatar_key]
	 * @property {string | null} [banner_key]
	 * @property {boolean | null} [is_verified]
	 * @property {string | null} [created_at]
	 * @property {string | null} [updated_at]
	 */

	/**
	 * @typedef {Object} Banner
	 * @property {string | null} public_url
	 * @property {number | null} [orden]
	 */

	/**
	 * Foto del álbum con el discriminante `tipo` que añade el `.map()`.
	 * @typedef {Object} Foto
	 * @property {string} id
	 * @property {string} public_url
	 * @property {string | null} [titulo]
	 * @property {string | null} [descripcion]
	 * @property {'video' | 'image'} tipo
	 */

	/** @type {Perfil | null} */
	let user = null;
	/** @type {Banner[]} */
	let banners = [];
	let currentBannerIndex = 0;
	/** @type {Foto[]} */
	let photos = [];
	/** @type {Foto | null} */
	let selectedPhoto = null;
	let loading = true;
	/** @type {string | null} */
	let error = null;

	onMount(async () => {
		try {
			const id = $page.params.id;

			const { data: profile, error: pErr } = await supabase
				.from('profiles')
				.select(
					`
                id,
                role,
                username,
                display_name,
                bio,
                avatar_key,
                banner_key,
                subscription_price,
                is_verified,
                is_banned,
                created_at,
                updated_at
        `
				)
				.eq('id', id)
				.single();

			if (pErr || !profile) throw pErr || new Error('Perfil no encontrado');
			user = profile;

			const { data: bData } = await supabase
				.from('user_banners')
				.select('public_url, orden')
				.eq('user_id', id)
				.order('orden', { ascending: true });
			banners = bData || [];

			const { data: phData, error: phErr } = await supabase
				.from('user_photos')
				.select('id, public_url, titulo, descripcion')
				.eq('user_id', id)
				.order('orden', { ascending: true });

			if (phErr) console.error('Error photos:', phErr);
			photos = (phData || []).map((p) => ({
				...p,
				tipo: /\.(mp4|webm|ogg)$/i.test(p.public_url) ? 'video' : 'image'
			}));
		} catch (err) {
			console.error('Load error:', err);
			error = err instanceof Error ? err.message : String(err);
		} finally {
			loading = false;
		}
	});

	const prevBanner = () => {
		if (banners.length > 1) {
			currentBannerIndex = (currentBannerIndex - 1 + banners.length) % banners.length;
		}
	};
	const nextBanner = () => {
		if (banners.length > 1) {
			currentBannerIndex = (currentBannerIndex + 1) % banners.length;
		}
	};

	const showPaywall = () => {
		alert('Este contenido está bloqueado. ¡Paga para desbloquear el álbum completo!');
	};
</script>

{#if loading}
	<p class="mt-20 text-center text-gray-600">Cargando...</p>
{:else if error}
	<p class="mt-20 text-center text-red-600">Error: {error}</p>
{:else if !user}
	<p class="mt-20 text-center text-red-600">Perfil no encontrado.</p>
{:else}
	<div class="mx-auto max-w-6xl px-4 py-8">
		<div class="rounded-xl border border-gray-200 bg-white p-6 shadow-lg md:p-8">
			<!-- BANNER -->
			<div class="relative mb-6 h-64 w-full overflow-hidden rounded-xl bg-gray-900">
				{#if banners.length}
					<img
						src={banners[currentBannerIndex].public_url}
						alt="Banner"
						class="absolute inset-0 h-full w-full object-cover transition-all duration-300"
					/>

					{#if banners.length > 1}
						<button
							on:click={prevBanner}
							class="absolute top-1/2 left-3 z-10 -translate-y-1/2 rounded-full bg-white/80 p-3 shadow-lg transition hover:bg-white"
							aria-label="Anterior">Previous</button
						>
						<button
							on:click={nextBanner}
							class="absolute top-1/2 right-3 z-10 -translate-y-1/2 rounded-full bg-white/80 p-3 shadow-lg transition hover:bg-white"
							aria-label="Siguiente">Next</button
						>

						<div class="absolute bottom-3 left-1/2 flex -translate-x-1/2 gap-1.5">
							{#each banners as _, i}
								<div
									class={`h-2 w-2 rounded-full transition ${i === currentBannerIndex ? 'bg-white' : 'bg-white/50'}`}
								></div>
							{/each}
						</div>
					{/if}
				{:else}
					<div class="flex h-full items-center justify-center bg-gray-700 text-lg text-white">
						Sin banner
					</div>
				{/if}
			</div>

			<h1 class="mb-6 text-center text-3xl font-bold text-gray-900 md:text-4xl">
				{user.display_name || user.username || 'Usuario'}

				{#if user.is_verified}
					<span class="ml-2 text-blue-500" title="Perfil verificado"> ✓ </span>
				{/if}
			</h1>

			<div class="mb-8 grid grid-cols-1 gap-3 text-gray-700 md:grid-cols-2">
				{#if user.username}
					<p>
						<span class="font-medium">Usuario:</span>
						@{user.username}
					</p>
				{/if}

				{#if user.role}
					<p>
						<span class="font-medium">Tipo:</span>
						{user.role === 'creator' ? 'Creador' : 'Fan'}
					</p>
				{/if}
			</div>

			<div class="mb-8 rounded-lg bg-gray-50 p-6">
				<h3 class="mb-3 text-lg font-semibold text-gray-900">Sobre mí</h3>
				{#if user.bio}
					<p class="whitespace-pre-wrap text-gray-700">{user.bio}</p>
				{:else}
					<p class="text-gray-500 italic">Sin descripción.</p>
				{/if}
			</div>

			{#if photos.length > 0}
				<div class="mb-8">
					<h2 class="mb-4 text-2xl font-bold">Álbum Exclusivo</h2>
					<div class="grid grid-cols-2 gap-4 md:grid-cols-4">
						{#each photos.slice(0, 4) as photo}
							<div
								class="group relative cursor-pointer overflow-hidden rounded-lg"
								on:click={showPaywall}
							>
								{#if photo.tipo === 'video'}
									<video
										src={photo.public_url}
										muted
										loop
										autoplay
										class="h-48 w-full rounded-lg object-cover brightness-75"
									></video>
								{:else}
									<img
										src={photo.public_url}
										alt={photo.titulo}
										class="h-48 w-full rounded-lg object-cover brightness-75"
									/>
								{/if}
								<div
									class="absolute inset-0 flex items-center justify-center bg-black/50 opacity-0 transition group-hover:opacity-100"
								>
									<span class="text-3xl text-white">Locked</span>
								</div>
							</div>
						{/each}
					</div>
					{#if photos.length > 4}
						<p class="mt-4 text-center text-sm text-gray-600">
							+{photos.length - 4} más...
							<strong class="text-green-600">Paga para desbloquear</strong>
						</p>
					{/if}
				</div>
			{:else}
				<div class="mb-8">
					<h2 class="mb-4 text-2xl font-bold">Álbum Exclusivo</h2>
					<p class="text-gray-500 italic">Sin fotos aún.</p>
				</div>
			{/if}
		</div>
	</div>
{/if}

<!-- MODAL -->
{#if selectedPhoto}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/90 p-4"
		on:click={() => (selectedPhoto = null)}
	>
		<div class="relative w-full max-w-4xl" on:click|stopPropagation>
			<button
				on:click={() => (selectedPhoto = null)}
				class="absolute -top-12 right-0 text-3xl text-white hover:text-gray-300">×</button
			>

			{#if selectedPhoto.tipo === 'video'}
				<video src={selectedPhoto.public_url} controls class="max-h-[80vh] w-full rounded-lg"
				></video>
			{:else}
				<div class="group relative overflow-hidden rounded-lg">
					<img
						src={selectedPhoto.public_url}
						alt={selectedPhoto.titulo}
						class="max-h-[80vh] w-full object-contain transition-transform duration-300 group-hover:scale-110"
					/>
					<div
						class="absolute inset-0 flex items-center justify-center opacity-0 transition group-hover:opacity-100"
					>
						<span class="text-6xl text-white">Magnifying Glass</span>
					</div>
				</div>
			{/if}

			{#if selectedPhoto.titulo || selectedPhoto.descripcion}
				<div class="mt-4 text-center text-white">
					{#if selectedPhoto.titulo}<h3 class="text-xl font-semibold">
							{selectedPhoto.titulo}
						</h3>{/if}
					{#if selectedPhoto.descripcion}<p class="mt-2">{selectedPhoto.descripcion}</p>{/if}
				</div>
			{/if}
		</div>
	</div>
{/if}
