<script>
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { supabase } from '$lib/supabaseClient';

	let user = null;
	let banners = [];
	let currentBannerIndex = 0;
	let photos = [];
	let selectedPhoto = null;
	let loading = true;
	let error = null;

	onMount(async () => {
		try {
			const id = $page.params.id;

			const { data: profile, error: pErr } = await supabase
				.from('profiles')
				.select('*, whatsapp, twitter_url, instagram_url, website_url, direccion')
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
			photos = (phData || []).map(p => ({
				...p,
				tipo: /\.(mp4|webm|ogg)$/i.test(p.public_url) ? 'video' : 'image'
			}));
		} catch (err) {
			console.error('Load error:', err);
			error = err.message;
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

	function calcularEdad(fechaStr) {
		if (!fechaStr) return '';
		const nacimiento = new Date(fechaStr);
		const hoy = new Date();
		let edad = hoy.getFullYear() - nacimiento.getFullYear();
		const m = hoy.getMonth() - nacimiento.getMonth();
		if (m < 0 || (m === 0 && hoy.getDate() < nacimiento.getDate())) edad--;
		return `${edad} años`;
	}
</script>

{#if loading}
	<p class="text-center mt-20 text-gray-600">Cargando...</p>
{:else if error}
	<p class="text-center mt-20 text-red-600">Error: {error}</p>
{:else if !user}
	<p class="text-center mt-20 text-red-600">Perfil no encontrado.</p>
{:else}
	<div class="mx-auto max-w-6xl px-4 py-8">
		<div class="rounded-xl border border-gray-200 bg-white p-6 shadow-lg md:p-8">

			<!-- BANNER -->
			<div class="relative h-64 w-full overflow-hidden bg-gray-900 mb-6 rounded-xl">
				{#if banners.length}
					<img src={banners[currentBannerIndex].public_url} alt="Banner"
					     class="absolute inset-0 h-full w-full object-cover transition-all duration-300" />

					{#if banners.length > 1}
						<button on:click={prevBanner}
						        class="absolute left-3 top-1/2 -translate-y-1/2 rounded-full bg-white/80 p-3 shadow-lg hover:bg-white transition z-10"
						        aria-label="Anterior">Previous</button>
						<button on:click={nextBanner}
						        class="absolute right-3 top-1/2 -translate-y-1/2 rounded-full bg-white/80 p-3 shadow-lg hover:bg-white transition z-10"
						        aria-label="Siguiente">Next</button>

						<div class="absolute bottom-3 left-1/2 -translate-x-1/2 flex gap-1.5">
							{#each banners as _, i}
								<div class={`h-2 w-2 rounded-full transition ${i === currentBannerIndex ? 'bg-white' : 'bg-white/50'}`}></div>
							{/each}
						</div>
					{/if}
				{:else}
					<div class="flex h-full items-center justify-center bg-gray-700 text-white text-lg">Sin banner</div>
				{/if}
			</div>

			<h1 class="text-center mb-6 text-3xl font-bold text-gray-900 md:text-4xl">{user.nombre}</h1>

			<div class="grid grid-cols-1 gap-3 md:grid-cols-2 mb-8 text-gray-700">
				{#if user.fecha_nacimiento}<p><span class="font-medium">Edad:</span> {calcularEdad(user.fecha_nacimiento)}</p>{/if}
				{#if user.ciudad}<p><span class="font-medium">Ciudad:</span> {user.ciudad}</p>{/if}
				{#if user.pais}<p><span class="font-medium">País:</span> {user.pais}</p>{/if}
				{#if user.whatsapp}<p><span class="font-medium">WhatsApp:</span> <a href="tel:{user.whatsapp}" class="text-blue-600">{user.whatsapp}</a></p>{/if}
				{#if user.twitter_url}<p><span class="font-medium">Twitter:</span> <a href={user.twitter_url} target="_blank" class="text-blue-600">Ver perfil</a></p>{/if}
				{#if user.instagram_url}<p><span class="font-medium">Instagram:</span> <a href={user.instagram_url} target="_blank" class="text-blue-600">Ver perfil</a></p>{/if}
				{#if user.website_url}<p><span class="font-medium">Web:</span> <a href={user.website_url} target="_blank" class="text-blue-600">Visitar</a></p>{/if}
				{#if user.direccion}<p><span class="font-medium">Dirección:</span> {user.direccion}</p>{/if}
			</div>

			<div class="rounded-lg bg-gray-50 p-6 mb-8">
				<h3 class="mb-3 text-lg font-semibold text-gray-900">Sobre mí</h3>
				{#if user.bio}
					<p class="whitespace-pre-wrap text-gray-700">{user.bio}</p>
				{:else}
					<p class="italic text-gray-500">Sin descripción.</p>
				{/if}
			</div>

			{#if photos.length > 0}
				<div class="mb-8">
					<h2 class="mb-4 text-2xl font-bold">Álbum Exclusivo</h2>
					<div class="grid grid-cols-2 gap-4 md:grid-cols-4">
						{#each photos.slice(0, 4) as photo}
							<div class="group relative cursor-pointer overflow-hidden rounded-lg" on:click={showPaywall}>
								{#if photo.tipo === 'video'}
									<video src={photo.public_url} muted loop autoplay class="h-48 w-full rounded-lg object-cover brightness-75"></video>
								{:else}
									<img src={photo.public_url} alt={photo.titulo} class="h-48 w-full rounded-lg object-cover brightness-75" />
								{/if}
								<div class="absolute inset-0 flex items-center justify-center bg-black/50 opacity-0 transition group-hover:opacity-100">
									<span class="text-3xl text-white">Locked</span>
								</div>
							</div>
						{/each}
					</div>
					{#if photos.length > 4}
						<p class="mt-4 text-center text-sm text-gray-600">
							+{photos.length - 4} más... <strong class="text-green-600">Paga para desbloquear</strong>
						</p>
					{/if}
				</div>
			{:else}
				<div class="mb-8">
					<h2 class="mb-4 text-2xl font-bold">Álbum Exclusivo</h2>
					<p class="italic text-gray-500">Sin fotos aún.</p>
				</div>
			{/if}

		</div>
	</div>
{/if}

<!-- MODAL -->
{#if selectedPhoto}
	<div class="fixed inset-0 z-50 flex items-center justify-center bg-black/90 p-4" on:click={() => selectedPhoto = null}>
		<div class="relative w-full max-w-4xl" on:click|stopPropagation>
			<button on:click={() => selectedPhoto = null} class="absolute -top-12 right-0 text-3xl text-white hover:text-gray-300">×</button>

			{#if selectedPhoto.tipo === 'video'}
				<video src={selectedPhoto.public_url} controls class="w-full rounded-lg max-h-[80vh]"></video>
			{:else}
				<div class="group relative overflow-hidden rounded-lg">
					<img src={selectedPhoto.public_url} alt={selectedPhoto.titulo}
					     class="max-h-[80vh] w-full object-contain transition-transform duration-300 group-hover:scale-110" />
					<div class="absolute inset-0 flex items-center justify-center opacity-0 transition group-hover:opacity-100">
						<span class="text-6xl text-white">Magnifying Glass</span>
					</div>
				</div>
			{/if}

			{#if selectedPhoto.titulo || selectedPhoto.descripcion}
				<div class="mt-4 text-center text-white">
					{#if selectedPhoto.titulo}<h3 class="text-xl font-semibold">{selectedPhoto.titulo}</h3>{/if}
					{#if selectedPhoto.descripcion}<p class="mt-2">{selectedPhoto.descripcion}</p>{/if}
				</div>
			{/if}
		</div>
	</div>
{/if}