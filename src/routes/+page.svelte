<script>
	import { onMount } from 'svelte';
	import { supabase } from '$lib/supabaseClient';
	import { session } from '$lib/stores/auth';
	import { goto } from '$app/navigation';

	/** @type {Array<{id: string, nombre: string, fecha_nacimiento: string | null, pais: string, ciudad: string, is_online: boolean, banners: string[], currentIndex: number}>} */
	let publicaciones = [];
	$: logeado = $session !== null;

	async function loadProfilesWithBanners() {
		const { data: profiles, error: pErr } = await supabase
			.from('profiles')
			.select('id, nombre, fecha_nacimiento, pais, ciudad, is_online')
			.order('nombre', { ascending: true });

		if (pErr || !profiles?.length) {
			publicaciones = [];
			return;
		}

		const ids = profiles.map(p => p.id);

		const { data: banners } = await supabase
			.from('user_banners')
			.select('user_id, public_url, orden')
			.in('user_id', ids)
			.order('orden');

		const bannersByUser = {};
		for (const b of banners || []) {
			if (!bannersByUser[b.user_id]) bannersByUser[b.user_id] = [];
			bannersByUser[b.user_id].push(b.public_url);
		}

		let lista = profiles
			.map(p => {
				const userBanners = bannersByUser[p.id] || [];
				if (userBanners.length === 0) return null;

				return {
					id: p.id,
					nombre: p.nombre || 'Usuario',
					fecha_nacimiento: p.fecha_nacimiento || null,
					pais: p.pais || '',
					ciudad: p.ciudad || '',
					is_online: p.is_online || false,
					banners: userBanners,
					currentIndex: 0
				};
			})
			.filter(Boolean);

		// Aleatorizar
		for (let i = lista.length - 1; i > 0; i--) {
			const j = Math.floor(Math.random() * (i + 1));
			[lista[i], lista[j]] = [lista[j], lista[i]];
		}

		publicaciones = lista;
	}

	function prevBanner(pub) {
		if (!pub.banners?.length) return;
		pub.currentIndex = (pub.currentIndex - 1 + pub.banners.length) % pub.banners.length;
		publicaciones = publicaciones;
	}

	function nextBanner(pub) {
		if (!pub.banners?.length) return;
		pub.currentIndex = (pub.currentIndex + 1) % pub.banners.length;
		publicaciones = publicaciones;
	}

	function verPerfil(id) {
		goto(`/perfil/${id}`);
	}

	function calcularEdad(fechaStr) {
		if (!fechaStr) return '';
		const nacimiento = new Date(fechaStr);
		const hoy = new Date();
		let edad = hoy.getFullYear() - nacimiento.getFullYear();
		const m = hoy.getMonth() - nacimiento.getMonth();
		if (m < 0 || (m === 0 && hoy.getDate() < nacimiento.getDate())) edad--;
		return `${edad} años`;
	}

	onMount(() => {
		loadProfilesWithBanners();
	});
</script>

<!-- GRID DE USUARIOS - EDICIÓN SEXY -->
<div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6 p-6 bg-black/90 min-h-screen z-0">

	{#each publicaciones as pub}
		<div class="relative overflow-hidden rounded-2xl bg-gradient-to-b from-pink-900/20 to-black/60 backdrop-blur-md border border-pink-800/40 shadow-2xl hover:shadow-pink-600/40 transition-all duration-500 group z-0">

			<!-- IMAGEN CON NAVEGACIÓN -->
			<div 
				class="relative w-full aspect-[3/4] cursor-pointer" 
				on:click={() => verPerfil(pub.id)} 
				role="button" 
				tabindex="0" 
				on:keydown={(e) => e.key === 'Enter' && verPerfil(pub.id)}
			>
				<img
					src={pub.banners[pub.currentIndex]}
					alt={`Banner de ${pub.nombre}`}
					class="w-full h-full object-cover rounded-2xl transition-transform duration-700 group-hover:scale-110"
				/>

				<!-- Superposición sensual -->
				<div class="absolute inset-0 bg-gradient-to-t from-black/90 via-transparent to-transparent"></div>

				<!-- FLECHAS SEXY -->
				{#if pub.banners.length > 1}
					<button
						class="absolute left-3 top-1/2 -translate-y-1/2 bg-white/10 backdrop-blur-md text-pink-300 rounded-full p-3 hover:bg-white/30 hover:text-white transition z-10"
						on:click|stopPropagation={() => prevBanner(pub)}
					>◀</button>
					<button
						class="absolute right-3 top-1/2 -translate-y-1/2 bg-white/10 backdrop-blur-md text-pink-300 rounded-full p-3 hover:bg-white/30 hover:text-white transition z-10"
						on:click|stopPropagation={() => nextBanner(pub)}
					>▶</button>
				{/if}

				<!-- PUNTOS INDICADORES -->
				{#if pub.banners.length > 1}
					<div class="absolute bottom-4 left-1/2 -translate-x-1/2 flex gap-2 z-10">
						{#each pub.banners as _, i}
							<div class={`w-2 h-2 rounded-full transition-all ${i === pub.currentIndex ? 'bg-pink-400 shadow-lg shadow-pink-400/60' : 'bg-white/40'}`}></div>
						{/each}
					</div>
				{/if}
			</div>

			<!-- INFO + PUNTO ONLINE -->
			<div class="absolute bottom-0 left-0 right-0 p-5 text-center">
				<div class="flex items-center justify-center gap-3">
					<p class="text-2xl font-bold text-white drop-shadow-2xl">{pub.nombre}</p>
					
					<!-- PUNTO VERDE/ROJO -->
					<div class="relative">
						{#if pub.is_online}
							<div class="w-4 h-4 bg-emerald-400 rounded-full shadow-lg shadow-emerald-400/60 animate-pulse"></div>
							<div class="absolute inset-0 w-4 h-4 bg-emerald-400 rounded-full animate-ping opacity-75"></div>
						{:else}
							<div class="w-4 h-4 bg-red-600/80 rounded-full shadow-lg"></div>
						{/if}
					</div>
				</div>

				<p class="text-pink-300 text-sm mt-1">
					{#if pub.fecha_nacimiento}{calcularEdad(pub.fecha_nacimiento)}{/if}
					{#if pub.pais} - {pub.pais}{/if}
					{#if pub.ciudad} ({pub.ciudad}){/if}
				</p>
			</div>
		</div>
	{/each}
</div>

<!-- MENSAJE NO LOGUEADO -->
{#if !logeado}
	<p class="mt-6 text-center text-gray-100">
		Para interactuar con los creadores debes
		<a href="/login" class="font-semibold text-green-600">iniciar sesión</a>.
	</p>
{:else}
	<div class="mt-6 text-center">
		<p class="text-green-600">
			¡Bienvenido, {$session?.user?.email || 'Usuario'}! Puedes interactuar con los perfiles.
		</p>
	</div>
{/if}