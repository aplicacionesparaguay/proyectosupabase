<script lang="ts">
	import { user } from '$lib/stores/auth';
	import { supabase } from '$lib/supabaseClient';
	import { onMount } from 'svelte';

	let creators = [];
	let loading = true;

	onMount(async () => {
		// Cargar creadoras con contenido
		const { data } = await supabase
			.from('profiles')
			.select('id, username, full_name, avatar_url, cover_url, bio, posts_count, subscription_price')
			.gt('posts_count', 0)
			.order('posts_count', { ascending: false })
			.limit(12);

		creators = data || [];
		loading = false;
	});
</script>

<div class="min-h-screen bg-gradient-to-b from-black via-pink-950/20 to-black p-8">
	<div class="max-w-7xl mx-auto">
		{#if $user}
			<div class="mb-12">
				<h1 class="text-5xl font-bold bg-gradient-to-r from-pink-400 to-purple-400 bg-clip-text text-transparent mb-4">
					¡Bienvenida, {$user.email?.split('@')[0]}!
				</h1>
				<p class="text-gray-400 mb-8">Explora contenido exclusivo de nuestras creadoras</p>
				
				<div class="flex gap-4">
					
						href="/dashboard"
						class="px-8 py-4 bg-gradient-to-r from-pink-600 to-purple-600 text-white font-bold rounded-full hover:from-pink-500 hover:to-purple-500 transition"
					>
						📊 Ir a mi Dashboard
					</a>
					
						href="/perfil"
						class="px-8 py-4 bg-white/10 border border-pink-500/30 text-pink-400 font-semibold rounded-full hover:bg-white/20 transition"
					>
						👤 Mi Perfil
					</a>
				</div>
			</div>

			<h2 class="text-3xl font-bold text-white mb-6">🔥 Creadoras Destacadas</h2>

			{#if loading}
				<p class="text-gray-400">Cargando...</p>
			{:else if creators.length === 0}
				<p class="text-gray-400">Aún no hay creadoras con contenido</p>
			{:else}
				<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
					{#each creators as creator}
						
							href="/{creator.username}"
							class="group bg-black/40 backdrop-blur-xl border border-pink-500/20 rounded-2xl overflow-hidden hover:border-pink-500/50 transition"
						>
							{#if creator.cover_url}
								<img src={creator.cover_url} alt="" class="w-full h-40 object-cover" />
							{:else}
								<div class="w-full h-40 bg-gradient-to-r from-pink-600 to-purple-600" />
							{/if}

							<div class="p-6">
								<div class="flex items-center gap-3 mb-3">
									{#if creator.avatar_url}
										<img src={creator.avatar_url} alt="" class="w-12 h-12 rounded-full object-cover" />
									{:else}
										<div class="w-12 h-12 rounded-full bg-gradient-to-r from-pink-600 to-purple-600 flex items-center justify-center text-white font-bold">
											{creator.username?.[0]?.toUpperCase() || 'U'}
										</div>
									{/if}
									<div>
										<h3 class="font-bold text-white">@{creator.username || 'usuario'}</h3>
										<p class="text-sm text-pink-400">{creator.posts_count} publicaciones</p>
									</div>
								</div>

								{#if creator.bio}
									<p class="text-gray-400 text-sm mb-4 line-clamp-2">{creator.bio}</p>
								{/if}

								<div class="flex items-center justify-between">
									<span class="text-2xl font-bold text-white">${creator.subscription_price}/mes</span>
									<span class="px-4 py-2 bg-gradient-to-r from-pink-600 to-purple-600 text-white font-semibold rounded-full group-hover:from-pink-500 group-hover:to-purple-500 transition">
										Ver Perfil
									</span>
								</div>
							</div>
						</a>
					{/each}
				</div>
			{/if}
		{:else}
			<div class="text-center py-20">
				<h1 class="text-6xl font-bold bg-gradient-to-r from-pink-400 to-purple-400 bg-clip-text text-transparent mb-4">
					Kuña Guapa
				</h1>
				<p class="text-2xl text-gray-400 mb-8">Plataforma de contenido exclusivo para adultos</p>
				<p class="text-gray-500">Inicia sesión para explorar contenido</p>
			</div>
		{/if}
	</div>
</div>