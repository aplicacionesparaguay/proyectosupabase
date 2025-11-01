<script>
	import { onMount } from 'svelte';
	import { supabase } from '$lib/supabaseClient';
	import { session } from '$lib/stores/auth';
	import { goto } from '$app/navigation';

	let publicaciones = [];
	$: logeado = $session !== null;

	async function loadProfilesWithBanners() {
		const { data: profiles, error: pErr } = await supabase
			.from('profiles')
			.select('id, nombre, fecha_nacimiento, pais, ciudad')
			.order('nombre', { ascending: true });

		if (pErr) {
			console.error('Error al cargar perfiles:', pErr);
			publicaciones = [];
			return;
		}

		if (!profiles?.length) {
			publicaciones = [];
			return;
		}

		const ids = profiles.map((r) => r.id);

		const { data: banners, error: bErr } = await supabase
			.from('user_banners')
			.select('user_id, public_url, orden')
			.in('user_id', ids)
			.order('orden', { ascending: true });

		if (bErr) {
			console.error('Error al cargar banners:', bErr);
			return;
		}

		const bannersByUser = {};
		for (const b of banners || []) {
			if (!bannersByUser[b.user_id]) bannersByUser[b.user_id] = [];
			bannersByUser[b.user_id].push(b.public_url);
		}

		let lista = profiles
			.map((p) => {
				const userBanners = bannersByUser[p.id] || [];
				if (userBanners.length === 0) return null;

				return {
					id: p.id,
					nombre: p.nombre || 'Usuario',
					fecha_nacimiento: p.fecha_nacimiento || null,
					pais: p.pais || '',
					ciudad: p.ciudad || '',
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

<!-- GRID DE USUARIOS -->
<div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6 p-4">
	{#each publicaciones as pub}
		<div
			class="relative overflow-hidden rounded-xl bg-white shadow hover:shadow-xl transition"
			tabindex="0"
		>
			<!-- IMAGEN CON NAVEGACIÓN -->
			<div
				class="relative cursor-pointer w-full"
				on:click={() => verPerfil(pub.id)}
				aria-label={`Ver perfil de ${pub.nombre}`}
			>
				<img
					src={pub.banners[pub.currentIndex]}
					alt={`Banner de ${pub.nombre}`}
					class="h-48 w-full object-cover rounded-t-xl transition-all duration-300"
				/>

				<!-- FLECHAS: solo si hay más de 1 foto -->
				{#if pub.banners.length > 1}
					<button
						class="absolute left-2 top-1/2 -translate-y-1/2 bg-black bg-opacity-50 text-white rounded-full p-2 hover:bg-opacity-70 focus:outline-none z-10"
						on:click|stopPropagation={() => prevBanner(pub)}
						aria-label="Anterior banner"
					>
						←
					</button>

					<button
						class="absolute right-2 top-1/2 -translate-y-1/2 bg-black bg-opacity-50 text-white rounded-full p-2 hover:bg-opacity-70 focus:outline-none z-10"
						on:click|stopPropagation={() => nextBanner(pub)}
						aria-label="Siguiente banner"
					>
						→
					</button>
				{/if}
			</div>

			{#if pub.banners.length > 1}
	<div class="absolute bottom-2 left-1/2 -translate-x-1/2 flex gap-1">
		{#each pub.banners as _, i}
			<div
				class={`w-2 h-2 rounded-full transition ${
					i === pub.currentIndex ? 'bg-white' : 'bg-white/50'
				}`}
			></div>
		{/each}
	</div>
{/if}

			<!-- INFO -->
			<div class="p-3 text-center">
				<p class="font-semibold text-gray-800">{pub.nombre}</p>
				<p class="text-sm text-gray-500">
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
	<p class="mt-6 text-center text-gray-600">
		Para interactuar con los creadores debes
		<a href="/login" class="font-semibold text-green-600">iniciar sesión</a>.
	</p>
{:else}
	<div class="mt-6 text-center">
		<p class="text-green-600">
			¡Bienvenido, {$session?.user?.email}! Puedes interactuar con los perfiles.
		</p>
	</div>
{/if}