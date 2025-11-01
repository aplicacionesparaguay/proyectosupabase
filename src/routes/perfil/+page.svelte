<script>
	import { onMount, onDestroy } from 'svelte';
	import { supabase } from '$lib/supabaseClient';
	import { session, user, logout } from '$lib/stores/auth';

	let bannerPhotos = [], currentBannerIndex = 0;
	let foto = '', nombre = '', email = '', bio = '', fecha_nacimiento = '', ciudad = '', pais = '';
	let whatsapp = '', twitter_url = '', instagram_url = '', website_url = '', direccion = '';
	let editing = false, saving = false;
	let photos = [], selectedPhoto = null, photoComment = '', photoComments = [];

	let showMenu = false;
	let menuRef;
	let buttonRef;
	let bannerUrl = ''; // asegurate de tener tu URL real aquí

	// 🔹 Cerrar menú si se hace clic fuera
	function handleClickOutside(event) {
		if (
			showMenu &&
			menuRef &&
			!menuRef.contains(event.target) &&
			!buttonRef.contains(event.target)
		) {
			showMenu = false;
		}
	}

	onMount(() => {
		document.addEventListener('click', handleClickOutside);
	});

	onDestroy(() => {
		document.removeEventListener('click', handleClickOutside);
	});

	// Sincronizar datos con sesión
	$: if ($session?.user) {
		nombre = $session.user.user_metadata?.nombre || $session.user.email || 'Usuario';
		email = $session.user.email || '';
	}

	onMount(async () => {
		await loadProfile();
		await loadPhotos();
		await loadBannerPhotos();
	});

	// ------------------ FUNCIONES ------------------

	// General: subir archivo
	async function uploadFile(bucket, folder = '', callback) {
		const fileInput = document.createElement('input');
		fileInput.type = 'file';
		fileInput.accept = 'image/*';
		fileInput.onchange = async (e) => {
			const file = e.target.files[0];
			if (!file || !$session?.user) return;
			const filename = `${Date.now()}-${file.name}`;
			const { data, error } = await supabase.storage
				.from(bucket)
				.upload(`${$session.user.id}/${folder}${filename}`, file, { upsert: true });
			if (error) return console.error('Error uploading file:', error);
			const url = supabase.storage.from(bucket).getPublicUrl(data.path).data.publicUrl;
			callback(data.path, url);
		};
		fileInput.click();
	}

	// 🧩 PERFIL (corregido)
	async function loadProfile() {
		if (!$session?.user) return;

		const { data, error } = await supabase
			.from('profiles')
			.select('*')
			.eq('id', $session.user.id)
			.single();

		if (error && error.code !== 'PGRST116') {
			console.error('Error loading profile:', error);
			return;
		}

		if (data) {
			// ✅ Asignamos los valores a las variables reactivas
			nombre = data.nombre || '';
			email = data.email || $session.user.email || '';
			bio = data.bio || '';
			foto = data.avatar_url || '';
			fecha_nacimiento = data.fecha_nacimiento || '';
			ciudad = data.ciudad || '';
			pais = data.pais || '';
			whatsapp = data.whatsapp || '';
			twitter_url = data.twitter_url || '';
			instagram_url = data.instagram_url || '';
			website_url = data.website_url || '';
			direccion = data.direccion || '';
		}
	}

	async function saveProfile() {
		if (!$session?.user) return;
		saving = true;
		try {
			const { error } = await supabase.from('profiles').upsert({
				id: $session.user.id,
				nombre: nombre || null,
				email: email || null,
				bio: bio || null,
				avatar_url: foto || null,
				fecha_nacimiento: fecha_nacimiento || null,
				ciudad: ciudad || null,
				pais: pais || null,
				whatsapp: whatsapp || null,
				twitter_url: twitter_url || null,
				instagram_url: instagram_url || null,
				website_url: website_url || null,
				direccion: direccion || null
			});
			if (error) console.error('Error saving profile:', error);
			else {
				await supabase.auth.updateUser({ data: { nombre, bio } });
				await loadProfile(); // ✅ Recarga después de guardar
			}
		} catch (e) {
			console.error(e);
		} finally {
			saving = false;
			editing = false;
		}
	}

	// Avatar
	async function uploadAvatar() {
		await uploadFile('avatars', 'avatar.', async (path, url) => {
			foto = url;
			await saveProfile();
		});
	}

	// Banner
	async function loadBannerPhotos() {
		if (!$session?.user) return;
		const { data, error } = await supabase
			.from('user_banners')
			.select('*')
			.eq('user_id', $session.user.id)
			.order('orden', { ascending: true });
		if (error) return console.error('Error loading banners:', error);
		bannerPhotos = (data || []).map((b) => b.public_url).filter(Boolean);
	}

	async function uploadBanner() {
		await uploadFile('banners', '', async (path, url) => {
			const { error } = await supabase
				.from('user_banners')
				.insert({
					user_id: $session.user.id,
					storage_path: path,
					public_url: url,
					orden: bannerPhotos.length
				});
			if (error) console.error('Error inserting banner:', error);
			await loadBannerPhotos();
			currentBannerIndex = bannerPhotos.length - 1;
		});
	}

	async function deleteCurrentBanner() {
		if (!$session?.user || bannerPhotos.length === 0) return;
		const currentUrl = bannerPhotos[currentBannerIndex];
		const { data, error } = await supabase
			.from('user_banners')
			.select('storage_path,id')
			.eq('public_url', currentUrl)
			.single();
		if (error) return console.error(error);
		await supabase.storage.from('banners').remove([data.storage_path]);
		await supabase.from('user_banners').delete().eq('id', data.id);
		await loadBannerPhotos();
		currentBannerIndex = Math.min(currentBannerIndex, bannerPhotos.length - 1);
	}

	function verBanner() {
		if (bannerUrl) {
			window.open(bannerUrl, '_blank');
		} else {
			alert('No hay imagen disponible.');
		}
	}

	const prevBanner = () => {
		if (bannerPhotos.length)
			currentBannerIndex = (currentBannerIndex - 1 + bannerPhotos.length) % bannerPhotos.length;
	};
	const nextBanner = () => {
		if (bannerPhotos.length) currentBannerIndex = (currentBannerIndex + 1) % bannerPhotos.length;
	};

	// Álbum
	async function loadPhotos() {
		if (!$session?.user) return;
		const { data, error } = await supabase
			.from('user_photos')
			.select('*')
			.eq('user_id', $session.user.id)
			.order('orden', { ascending: true });
		if (error) console.error('Error loading photos:', error);
		photos = data || [];
	}

	async function uploadPhoto() {
		await uploadFile('user-photos', '', async (path, url) => {
			const filename = path.split('/').pop();
			const { error } = await supabase.from('user_photos').insert({
				user_id: $session.user.id,
				storage_path: path,
				public_url: url,
				filename,
				orden: photos.length,
				titulo: '',
				descripcion: ''
			});
			if (error) console.error('Error inserting photo:', error);
			else await loadPhotos();
		});
	}

	async function deletePhoto(photoId) {
		const photo = photos.find((p) => p.id === photoId);
		if (!photo || !$session?.user) return;
		await supabase.storage.from('user-photos').remove([photo.storage_path]);
		await supabase.from('user_photos').delete().eq('id', photoId);
		if (selectedPhoto?.id === photoId) selectedPhoto = null;
		await loadPhotos();
	}

	function openPhotoModal(photo) {
		selectedPhoto = photo;
		photoComment = '';
		photoComments = photo.photo_comments || [];
	}

	async function addPhotoComment() {
		if (!selectedPhoto || !photoComment.trim() || !$session?.user) return;
		const { error } = await supabase
			.from('photo_comments')
			.insert({ photo_id: selectedPhoto.id, user_id: $session.user.id, comentario: photoComment });
		if (!error) {
			photoComment = '';
			await loadPhotos();
			const { data } = await supabase
				.from('user_photos')
				.select('*')
				.eq('id', selectedPhoto.id)
				.single();
			photoComments = data?.photo_comments || [];
		}
	}

	async function updatePhotoDetails(photoId, updates) {
		if (!$session?.user) return;
		await supabase
			.from('user_photos')
			.update(updates)
			.eq('id', photoId)
			.eq('user_id', $session.user.id);
		await loadPhotos();
	}
</script>


<!-- Banner -->
<div class="relative h-64 w-full overflow-hidden bg-gray-900">
	{#if bannerPhotos.length > 0}
		<div
			class="absolute inset-0 bg-cover bg-center transition-all"
			style="background-image: url({bannerPhotos[currentBannerIndex]})"
		></div>
	{:else}
		<div class="absolute inset-0 flex items-center justify-center bg-gray-700 text-white">
			Cargar Banner
		</div>
	{/if}

	<!-- Flechas -->
	<button
		on:click={prevBanner}
		class="absolute left-2 top-1/2 -translate-y-1/2 rounded-full bg-white/70 p-2 hover:bg-white"
		>◀</button
	>
	<button
		on:click={nextBanner}
		class="absolute right-2 top-1/2 -translate-y-1/2 rounded-full bg-white/70 p-2 hover:bg-white"
		>▶</button
	>

	<!-- 🔹 Menú del banner -->
	<div class="absolute right-4 top-4">
		<div class="relative">
			<button
				bind:this={buttonRef}
				class="rounded-full bg-white p-2 shadow-lg hover:bg-gray-100"
				on:click={() => (showMenu = !showMenu)}
			>
				⋮
			</button>

			{#if showMenu}
				<div
					bind:this={menuRef}
					class="absolute right-0 z-50 mt-2 w-44 overflow-hidden rounded-xl border bg-white shadow-xl"
				>
					<button
						on:click={() => {
							showMenu = false;
							verBanner();
						}}
						class="block w-full px-4 py-2 text-left hover:bg-gray-100"
					>
						👁️ Ver
					</button>
					<button
						on:click={() => {
							showMenu = false;
							tomarFotoBanner();
						}}
						class="block w-full px-4 py-2 text-left hover:bg-gray-100"
					>
						📷 Tomar foto
					</button>
					<button
						on:click={() => {
							showMenu = false;
							uploadBanner();
						}}
						class="block w-full px-4 py-2 text-left hover:bg-gray-100"
					>
						⬆️ Subir
					</button>
					<button
						on:click={() => {
							showMenu = false;
							deleteCurrentBanner();
						}}
						class="block w-full px-4 py-2 text-left text-red-600 hover:bg-red-100"
					>
						🗑️ Borrar
					</button>
				</div>
			{/if}
		</div>
	</div>
</div>

<!-- Resto del perfil y álbum: conservar tal como lo tenés, sin cambios -->

<!-- Contenido -->
<div class="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
	<!-- Main Card -->
	<div class="relative rounded-xl border border-gray-200 bg-white p-6 shadow-lg md:p-8">
		<!-- Edit Button -->
		<button
			on:click={() => {
				editing = !editing;
				if (!editing) saveProfile();
			}}
			class="absolute right-4 top-4 rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-blue-700"
			disabled={saving}
		>
			{#if editing}
				Guardar
			{:else}
				Editar
			{/if}
		</button>

		<!-- Profile Header -->
		<div class="mb-8 text-center">
			<h1 class="mb-2 text-3xl font-bold text-gray-900 md:text-4xl">
				{#if editing}
					<input
						bind:value={nombre}
						class="w-full max-w-md border-b-2 border-blue-500 bg-transparent text-center text-3xl font-bold focus:outline-none"
						placeholder="Tu nombre"
					/>
				{:else}
					{nombre}
				{/if}
			</h1>
			<p class="mb-1 text-lg text-gray-600">
				{#if editing}
					<input
						bind:value={email}
						type="email"
						class="w-full max-w-sm border-b border-gray-300 bg-transparent text-center focus:border-blue-500 focus:outline-none"
						placeholder="Tu email"
					/>
				{:else}
					{email}
				{/if}
			</p>
			<p class="text-lg text-gray-600"></p>
		</div>

		<!-- Additional Profile Fields -->
		{#if editing}
			<div class="mb-8 grid grid-cols-1 gap-4 md:grid-cols-2">
				<div>
					<label class="mb-1 block text-sm font-medium text-gray-700">Fecha de Nacimiento</label>
					<input
						bind:value={fecha_nacimiento}
						type="date"
						class="w-full rounded-lg border border-gray-300 px-3 py-2 focus:ring-2 focus:ring-blue-500"
					/>
				</div>
				<div>
					<label class="mb-1 block text-sm font-medium text-gray-700">Ciudad</label>
					<input
						bind:value={ciudad}
						class="w-full rounded-lg border border-gray-300 px-3 py-2 focus:ring-2 focus:ring-blue-500"
						placeholder="Ej: Buenos Aires"
					/>
				</div>
				<div>
					<label class="mb-1 block text-sm font-medium text-gray-700">País</label>
					<input
						bind:value={pais}
						class="w-full rounded-lg border border-gray-300 px-3 py-2 focus:ring-2 focus:ring-blue-500"
						placeholder="Ej: Argentina"
					/>
				</div>
				<div>
					<label class="mb-1 block text-sm font-medium text-gray-700">WhatsApp</label>
					<input
						bind:value={whatsapp}
						class="w-full rounded-lg border border-gray-300 px-3 py-2 focus:ring-2 focus:ring-blue-500"
						placeholder="Ej: +54 9 11 1234 5678"
					/>
				</div>
				<div>
					<label class="mb-1 block text-sm font-medium text-gray-700">Twitter</label>
					<input
						bind:value={twitter_url}
						class="w-full rounded-lg border border-gray-300 px-3 py-2 focus:ring-2 focus:ring-blue-500"
						placeholder="Ej: https://twitter.com/tu-perfil"
					/>
				</div>
				<div>
					<label class="mb-1 block text-sm font-medium text-gray-700">Instagram</label>
					<input
						bind:value={instagram_url}
						class="w-full rounded-lg border border-gray-300 px-3 py-2 focus:ring-2 focus:ring-blue-500"
						placeholder="Ej: https://instagram.com/tu-perfil"
					/>
				</div>
				<div>
					<label class="mb-1 block text-sm font-medium text-gray-700">Sitio Web</label>
					<input
						bind:value={website_url}
						class="w-full rounded-lg border border-gray-300 px-3 py-2 focus:ring-2 focus:ring-blue-500"
						placeholder="Ej: https://tupagina.com"
					/>
				</div>
				<div class="md:col-span-2">
					<label class="mb-1 block text-sm font-medium text-gray-700">Dirección</label>
					<input
						bind:value={direccion}
						class="w-full rounded-lg border border-gray-300 px-3 py-2 focus:ring-2 focus:ring-blue-500"
						placeholder="Ej: Av. Corrientes 1234"
					/>
				</div>
			</div>
		{:else}
			<div class="mb-8 grid grid-cols-1 gap-4 md:grid-cols-2">
				{#if fecha_nacimiento}
					<p><span class="font-medium">Nacimiento:</span> {fecha_nacimiento}</p>
				{/if}
				{#if ciudad}
					<p><span class="font-medium">Ciudad:</span> {ciudad}</p>
				{/if}
				{#if pais}
					<p><span class="font-medium">País:</span> {pais}</p>
				{/if}
				{#if whatsapp}
					<p>
						<span class="font-medium">WhatsApp:</span>
						<a href="tel:{whatsapp}" class="text-blue-600">{whatsapp}</a>
					</p>
				{/if}
				{#if twitter_url}
					<p>
						<span class="font-medium">Twitter:</span>
						<a href={twitter_url} class="text-blue-600" target="_blank">Perfil</a>
					</p>
				{/if}
				{#if instagram_url}
					<p>
						<span class="font-medium">Instagram:</span>
						<a href={instagram_url} class="text-blue-600" target="_blank">Perfil</a>
					</p>
				{/if}
				{#if website_url}
					<p>
						<span class="font-medium">Sitio Web:</span>
						<a href={website_url} class="text-blue-600" target="_blank">Visitar</a>
					</p>
				{/if}
				{#if direccion}
					<p><span class="font-medium">Dirección:</span> {direccion}</p>
				{/if}
			</div>
		{/if}

		<!-- Bio Section -->
		<div class="mb-8 rounded-lg bg-gray-50 p-6">
			<h3 class="mb-3 text-lg font-semibold text-gray-900">Descripción Profesional</h3>
			<div class="relative">
				{#if editing}
					<textarea
						bind:value={bio}
						rows="5"
						placeholder="Describe tu experiencia profesional, especialidades y logros..."
						class="w-full resize-none rounded-lg border border-gray-300 px-4 py-3 focus:border-blue-500 focus:ring-2 focus:ring-blue-500"
					></textarea>
					<div class="absolute bottom-3 right-3 text-sm text-gray-500">
						{bio.length}/500
					</div>
				{:else if bio}
					<p class="whitespace-pre-wrap leading-relaxed text-gray-700">{bio}</p>
				{:else}
					<p class="italic text-gray-500">
						Añade una descripción profesional para que otros conozcan tu experiencia...
					</p>
				{/if}
			</div>
		</div>

		<!-- Álbum de Fotos -->
		<div class="mb-8">
			<h2 class="mb-4 text-2xl font-bold">Mi Álbum</h2>
			<button
				on:click={uploadPhoto}
				class="mb-4 rounded-lg bg-blue-600 px-6 py-2 text-white hover:bg-blue-700"
			>
				Agregar Foto
			</button>

			<div class="grid grid-cols-1 gap-4 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
				{#each photos as photo}
					<div class="group relative">
						<img
							src={photo.public_url}
							alt={photo.titulo || 'Foto'}
							class="h-48 w-full cursor-pointer rounded-lg object-cover"
							on:click={() => openPhotoModal(photo)}
						/>
						<div
							class="absolute inset-0 flex items-center justify-center bg-black bg-opacity-0 opacity-0 transition-all group-hover:bg-opacity-50 group-hover:opacity-100"
						>
							<button
								on:click={() => deletePhoto(photo.id)}
								class="mr-2 rounded-lg bg-red-500 p-2 text-white"
							>
								🗑️ Borrar
							</button>
							<button
								on:click={() => openPhotoModal(photo)}
								class="rounded-lg bg-blue-500 p-2 text-white"
							>
								👁️ Ver
							</button>
						</div>
						{#if photo.titulo}
							<div class="absolute bottom-0 w-full bg-black bg-opacity-60 p-2 text-sm text-white">
								{photo.titulo}
							</div>
						{/if}
					</div>
				{/each}
			</div>
		</div>

		<!-- Modal de Foto Grande -->
		{#if selectedPhoto}
			<div class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-75">
				<div class="relative w-full max-w-4xl rounded-lg bg-white p-4">
					<button
						on:click={() => (selectedPhoto = null)}
						class="absolute right-2 top-2 text-2xl text-gray-600 hover:text-gray-800"
					>
						×
					</button>
					<img
						src={selectedPhoto.public_url}
						alt={selectedPhoto.titulo || 'Foto'}
						class="mb-4 max-h-[70vh] w-full rounded-lg object-contain"
					/>
					<div class="space-y-4">
						{#if editing}
							<input
								bind:value={selectedPhoto.titulo}
								placeholder="Título de la foto"
								class="w-full rounded-lg border border-gray-300 px-3 py-2"
								on:input={() =>
									updatePhotoDetails(selectedPhoto.id, { titulo: selectedPhoto.titulo })}
							/>
							<textarea
								bind:value={selectedPhoto.descripcion}
								placeholder="Descripción de la foto"
								rows="3"
								class="w-full resize-none rounded-lg border border-gray-300 px-3 py-2"
								on:input={() =>
									updatePhotoDetails(selectedPhoto.id, { descripcion: selectedPhoto.descripcion })}
							/>
						{:else}
							{#if selectedPhoto.titulo}
								<h3 class="text-lg font-semibold">{selectedPhoto.titulo}</h3>
							{/if}
							{#if selectedPhoto.descripcion}
								<p class="text-gray-600">{selectedPhoto.descripcion}</p>
							{/if}
						{/if}

						<!-- Comentarios -->
						<div class="border-t pt-4">
							<h4 class="mb-2 text-sm font-medium">Comentarios</h4>
							{#each photoComments as comment}
								<div class="mb-2 flex gap-2">
									<span class="font-medium">{comment.profiles?.nombre || 'Anónimo'}:</span>
									<span>{comment.comentario}</span>
								</div>
							{/each}
							{#if $session?.user}
								<div class="mt-4 flex gap-2">
									<input
										bind:value={photoComment}
										placeholder="Añadir un comentario..."
										class="flex-1 rounded-lg border border-gray-300 px-3 py-2"
									/>
									<button
										on:click={addPhotoComment}
										class="rounded-lg bg-blue-600 px-4 py-2 text-white"
										disabled={!photoComment.trim()}
									>
										Comentar
									</button>
								</div>
							{/if}
						</div>
					</div>
				</div>
			</div>
		{/if}

		<!-- Logout Section -->
		<div class="mt-8 border-t border-gray-200 pt-6">
			<div class="flex justify-center">
				<button
					on:click={logout}
					disabled={saving}
					class="flex items-center gap-2 rounded-lg bg-gray-800 px-8 py-3 font-medium text-white transition-colors hover:bg-gray-900 disabled:opacity-50"
				>
					{#if saving}
						<svg class="h-4 w-4 animate-spin" fill="none" viewBox="0 0 24 24">
							<circle
								class="opacity-25"
								cx="12"
								cy="12"
								r="10"
								stroke="currentColor"
								stroke-width="4"
							></circle>
							<path
								class="opacity-75"
								fill="currentColor"
								d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
							></path>
						</svg>
						Cerrando...
					{:else}
						<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path
								stroke-linecap="round"
								stroke-linejoin="round"
								stroke-width="2"
								d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
							></path>
						</svg>
						Cerrar Sesión
					{/if}
				</button>
			</div>
		</div>
	</div>
</div>

<style>
	/* Estilos empresariales */
	.min-h-screen {
		min-height: 100vh;
	}
	input:focus,
	textarea:focus {
		outline: none;
	}
	.group:hover .group-hover\:bg-opacity-50 {
		transition: background-color 0.3s ease;
	}
</style>
