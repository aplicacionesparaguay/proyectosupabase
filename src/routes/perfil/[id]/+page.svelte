<script>
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { supabase } from '$lib/supabaseClient';

	let user = null;
	let banners = [];
	let loading = true;

	// 🔹 Cargar datos del usuario por ID
	onMount(async () => {
		const id = $page.params.id;

		const { data: profile, error: profileError } = await supabase
			.from('profiles')
			.select('id, nombre, fecha_nacimiento, pais, ciudad, bio')
			.eq('id', id)
			.single();

		if (profileError) {
			console.error('Error al cargar perfil:', profileError);
			loading = false;
			return;
		}
		user = profile;

		// 🔹 Cargar banners del usuario
		const { data: bannerData, error: bannerError } = await supabase
			.from('user_banners')
			.select('public_url, orden')
			.eq('user_id', id)
			.order('orden', { ascending: true });

		if (bannerError) {
			console.error('Error al cargar banners:', bannerError);
			loading = false;
			return;
		}

		banners = bannerData || [];
		loading = false;
	});

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
	<p class="text-center mt-10 text-gray-600">Cargando perfil...</p>
{:else if !user}
	<p class="text-center mt-10 text-red-600">Perfil no encontrado.</p>
{:else}
	<div class="max-w-4xl mx-auto mt-8 bg-white shadow rounded-xl p-6">
		<h1 class="text-2xl font-bold text-gray-800 text-center mb-4">
			{user.nombre || 'Usuario'}
		</h1>

		<!-- 🖼️ Carrusel de banners -->
		{#if banners.length > 0}
			<div class="flex overflow-x-auto space-x-2 mb-4 scrollbar-hide">
				{#each banners as b}
					<img
						src={b.public_url}
						alt="Banner"
						class="h-48 object-cover rounded-lg flex-shrink-0"
					/>
				{/each}
			</div>
		{:else}
			<p class="text-gray-500 text-center mb-4">Este usuario aún no tiene fotos.</p>
		{/if}

		<!-- 🧾 Info -->
		<div class="text-gray-700 text-center">
			{#if user.fecha_nacimiento}<p>{calcularEdad(user.fecha_nacimiento)}</p>{/if}
			{#if user.pais}<p>{user.pais}</p>{/if}
			{#if user.ciudad}<p>{user.ciudad}</p>{/if}
			{#if user.bio}<p class="mt-2 italic text-gray-600">{user.bio}</p>{/if}
		</div>
	</div>
{/if}

<style>
	/* 🔧 Quitar barra de scroll del carrusel */
	.scrollbar-hide::-webkit-scrollbar {
		display: none;
	}
	.scrollbar-hide {
		-ms-overflow-style: none;
		scrollbar-width: none;
	}
</style>
