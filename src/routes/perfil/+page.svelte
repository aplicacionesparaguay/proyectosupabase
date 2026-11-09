<script>
	import { onMount } from 'svelte';
	import { browser } from '$app/environment';
	import { supabase } from '$lib/supabaseClient';
	import { session, user, logout } from '$lib/stores/auth';
	import { goto } from '$app/navigation';
	import UploadQueue from '$lib/components/UploadQueue.svelte';
	import {
		uploadMedia,
		deleteCoverPhoto,
		validateMediaFile,
		R2_FOLDERS
	} from '$lib/upload/r2Upload';
	import { deleteMedia, loadCovers, loadOwnerMediaPage, moderationClass, moderationLabel } from '$lib/media/client';

	let loading = true;
	let nombre = '';
	let email = '';
	let bio = '';
	let pais = '';
	let ciudad = '';
	let username = '';
	let foto = '';
	let editing = false;
	let saving = false;
	let avatarUploading = false;
	let avatarError = '';
	let uploadProgress = 0;

	/**
	 * Elemento de la galeria propia. La URL firmada y los estados vienen del
	 * servidor; las claves privadas nunca llegan al navegador.
	 *
	 * @typedef {Object} GalleryItem
	 * @property {string} id
	 * @property {string | null} original_filename
	 * @property {string | null} mime_type
	 * @property {number | null} byte_size
	 * @property {string} created_at
	 * @property {string} moderation_status
	 * @property {string} processing_status
	 * @property {string} upload_status
	 * @property {string | null} rejection_reason
	 * @property {string | null} previewUrl
	 * @property {string | null} fullUrl
	 * @property {boolean} originalAvailable
	 */

	/** @type {GalleryItem[]} */
	let galleryItems = [];
	/** @type {string | null} */
	let galleryCursor = null;
	let galleryLoading = false;

	/** @type {any[]} */
	let bannerItems = [];
	let currentBannerIndex = 0;
	let bannerUploading = false;
	let bannerProgress = 0;
	let coverVisibility = 'privado';
	let bannerError = '';

	/** @type {string | null} */
	let galleryError = null;

	/** @type {string | null} */
	let deletingId = null;

	onMount(async () => {
		if (!$session?.user) {
			goto('/login');
			return;
		}
		await Promise.all([loadProfile(), loadGallery(), loadBanners()]);
		loading = false;
	});

	$: if ($session?.user) {
		nombre =
			nombre ||
			$session.user.user_metadata?.nombre ||
			$session.user.email?.split('@')[0] ||
			'Usuario';
		email = $session.user.email || '';
	}

	async function loadProfile() {
		const { data } = await supabase
			.from('profiles')
			.select('id, role, username, display_name, bio, pais, ciudad, avatar_key, is_verified')
			.eq('id', $session?.user?.id)
			.maybeSingle();

		if (data) {
			nombre = data.display_name || data.username || nombre;
			bio = data.bio || '';
			pais = data.pais || '';
			ciudad = data.ciudad || '';
		}

		// El avatar es publico y se guarda como URL permanente: asi el Home
		// puede mostrarlo sin sesion y sin una llamada extra.
		if (data?.avatar_key) {
			foto = data.avatar_key;
		} else {
			foto = '';
		}
	}

	async function saveProfile() {
		if (saving) return;
		saving = true;

		// El avatar se confirma en el servidor al subir. Editar nombre/bio no
		// debe reemplazarlo por una URL temporal de otra imagen del perfil.
		await supabase.from('profiles').upsert({
			id: $session?.user?.id,
			display_name: nombre || null,
			bio: bio || '',
			username: username || null,
			pais: pais || null,
			ciudad: ciudad || null
		});
		await supabase.auth.updateUser({ data: { nombre: nombre || null, bio: bio || '' } });
		await loadProfile();
		saving = false;
		editing = false;
	}

	async function loadGallery(append = false) {
		if (galleryLoading) return;
		galleryError = null;

		if (!$session?.user?.id) return;
		galleryLoading = true;

		try {
			const page = await loadOwnerMediaPage({ cursor: append ? galleryCursor : null });
			const incoming = /** @type {GalleryItem[]} */ (page.items);
			galleryItems = append ? [...galleryItems, ...incoming.filter((row) => !galleryItems.some((current) => current.id === row.id))] : incoming;
			galleryCursor = page.nextCursor;
		} catch (e) {
			galleryError = e instanceof Error ? e.message : 'No se pudo cargar la galeria.';
			if (!append) galleryItems = [];
		} finally {
			galleryLoading = false;
		}
	}

	async function loadBanners() {
		try {
			bannerItems = await loadCovers($session?.user?.id ?? '');
		} catch (error) {
			bannerError = error instanceof Error ? error.message : 'No se pudieron cargar las portadas.';
		}
	}

	// ---------- AVATAR ----------

	function uploadAvatar() {
		if (!browser || !$session?.user) return;
		const input = document.createElement('input');
		input.type = 'file';
		input.accept = 'image/jpeg,image/png,image/webp';
		input.onchange = async (e) => {
			const file = /** @type {HTMLInputElement} */ (e.target)?.files?.[0];
			if (!file) return;
			avatarError = '';
			avatarUploading = true;
			uploadProgress = 0;
			try {
				const err = validateMediaFile(file);
				if (err) throw new Error(err);

				// El avatar vive en el bucket publico: se guarda la URL
				// permanente, que es lo que el Home necesita para mostrarlo a
				// un visitante sin sesion.
				const { publicUrl } = await uploadMedia(file, R2_FOLDERS.avatar, {
					onProgress: (p) => (uploadProgress = p)
				});

				if (!publicUrl) throw new Error('No se pudo confirmar el avatar.');
				foto = publicUrl;
			} catch (e) {
				avatarError = e instanceof Error ? e.message : String(e);
			} finally {
				avatarUploading = false;
			}
		};
		input.click();
	}

	async function removeAvatar() {
		if (!$session?.user || !foto) return;
		foto = '';
		await supabase.from('profiles').update({ avatar_key: null }).eq('id', $session?.user?.id);
	}

	// ---------- BANNER ----------

	function uploadBanner() {
		if (!browser || !$session?.user) return;
		const input = document.createElement('input');
		input.type = 'file';
		input.accept = 'image/jpeg,image/png,image/webp';
		input.onchange = async (e) => {
			const file = /** @type {HTMLInputElement} */ (e.target)?.files?.[0];
			if (!file) return;
			bannerUploading = true;
			bannerError = '';
			bannerProgress = 0;
			try {
				const err = validateMediaFile(file);
				if (err) throw new Error(err);
				// El objeto permanece privado. La visibilidad se elige explicitamente.
				await uploadMedia(file, R2_FOLDERS.cover, {
					visibility: coverVisibility,
					onProgress: (p) => (bannerProgress = p)
				});
				await loadBanners();
				currentBannerIndex = bannerItems.length - 1;
			} catch (e) {
				bannerError = e instanceof Error ? e.message : 'No se pudo subir la portada.';
			} finally {
				bannerUploading = false;
			}
		};
		input.click();
	}

	const deleteCover = deleteCoverPhoto;

	async function deleteCurrentBanner() {
		if (!bannerItems.length || !$session?.user) return;
		const item = bannerItems[currentBannerIndex];
		const result = await deleteCover(item.id);
		if (!result.ok) { bannerError = result.message ?? 'No se pudo retirar la portada.'; return; }
		await loadBanners();
		currentBannerIndex = Math.min(currentBannerIndex, bannerItems.length - 1);
	}

	const prevBanner = () => {
		if (bannerItems.length > 1)
			currentBannerIndex = (currentBannerIndex - 1 + bannerItems.length) % bannerItems.length;
	};
	const nextBanner = () => {
		if (bannerItems.length > 1) currentBannerIndex = (currentBannerIndex + 1) % bannerItems.length;
	};

	// ---------- PUBLICACIÓN ----------

	/**
	 * El archivo ya quedo registrado y encolado por el servidor. La galeria
	 * muestra el estado real de procesamiento y moderacion.
	 *
	 * @param {{ asset: import('$lib/media/client').MediaAsset, file: File }} _payload
	 */
	async function handleUploaded(_payload) {
		galleryError = null;
		await loadGallery();
	}

	/**
	 * Solicita el borrado. La fila se oculta de inmediato y los objetos se
	 * eliminan mediante un trabajo durable.
	 *
	 * @param {GalleryItem} item
	 */
	async function deleteGalleryItem(item) {
		if (
			!confirm(
				`¿Eliminar "${item.original_filename ?? 'esta foto'}"? Esta accion no se puede deshacer.`
			)
		) {
			return;
		}

		deletingId = item.id;
		const result = await deleteMedia(item.id);
		deletingId = null;

		if (!result.ok) {
			galleryError = result.message ?? 'No se pudo eliminar la foto.';
			return;
		}

		galleryError = null;
		galleryItems = galleryItems.filter((candidate) => candidate.id !== item.id);
	}

	/**
	 * @param {string} iso
	 * @returns {string}
	 */
	function formatDate(iso) {
		return new Date(iso).toLocaleDateString('es-ES', {
			day: 'numeric',
			month: 'short',
			year: 'numeric'
		});
	}

	/**
	 * @param {number | null} bytes
	 * @returns {string}
	 */
	function formatBytes(bytes) {
		if (!bytes && bytes !== 0) return '';
		if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
		return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
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
</script>

{#if loading}
	<div class="flex min-h-[60vh] items-center justify-center">
		<div
			class="h-10 w-10 animate-spin rounded-full border-2 border-pink-500 border-t-transparent"
		></div>
	</div>
{:else}
	<!-- Banner -->
	<div class="relative h-52 w-full overflow-hidden bg-black/60 md:h-72">
		{#if bannerItems.length > 0 && bannerItems[currentBannerIndex]?.public_url}
			<img
				src={bannerItems[currentBannerIndex].public_url}
				alt="Portada"
				class="h-full w-full object-cover"
			/>
			{#if bannerItems.length > 1}
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
			{/if}
		{:else}
			<div
				class="flex h-full items-center justify-center bg-gradient-to-br from-pink-950/40 to-purple-950/40"
			>
				<span class="text-4xl text-pink-400/20">Agua en la Boca</span>
			</div>
		{/if}

		<!-- Controles del banner -->
		<div class="absolute top-3 right-3 flex gap-2">
			<select bind:value={coverVisibility} aria-label="Visibilidad de la nueva portada" class="rounded-full bg-black/80 px-2 text-xs text-white">
				<option value="privado">Nueva portada privada</option>
				<option value="publico">Nueva portada publica</option>
			</select>
			<button
				on:click={uploadBanner}
				disabled={bannerUploading}
				class="rounded-full bg-black/60 px-3 py-1.5 text-xs text-white hover:bg-black/80"
			>
				{bannerUploading ? `${bannerProgress}%` : bannerItems.length ? 'Cambiar' : 'Añadir portada'}
			</button>
			{#if bannerItems.length > 0}
				<button
					on:click={deleteCurrentBanner}
					class="rounded-full bg-black/60 px-3 py-1.5 text-xs text-red-400 hover:bg-black/80"
				>
					Eliminar
				</button>
			{/if}
		</div>
	</div>

	<!-- Perfil -->
	<div class="mx-auto w-full max-w-5xl px-4">
		{#if bannerError}<p class="p-3 text-sm text-red-300">{bannerError}</p>{/if}
		<div class="rounded-b-2xl border border-t-0 border-pink-900/30 bg-black/50 px-6 pb-6">
			<div class="flex flex-col gap-4 pt-4 sm:flex-row sm:items-end sm:gap-6">
				<!-- Avatar -->
				<div class="relative -mt-10 shrink-0 sm:-mt-8">
					{#if foto}
						<img
							src={foto}
							alt="Tu foto"
							class="h-24 w-24 rounded-full border-4 border-black object-cover shadow-xl sm:h-28 sm:w-28"
						/>
					{:else}
						<div
							class="flex h-24 w-24 items-center justify-center rounded-full border-4 border-black bg-gradient-to-br from-pink-900 to-purple-900 text-3xl font-bold text-pink-300 shadow-xl sm:h-28 sm:w-28"
						>
							{getInitials(nombre)}
						</div>
					{/if}
					{#if avatarUploading}
						<div
							class="absolute inset-0 flex items-center justify-center rounded-full bg-black/70 text-xs font-medium text-white"
						>
							{uploadProgress}%
						</div>
					{/if}
				</div>

				<!-- Info -->
				<div class="min-w-0 flex-1">
					<div class="flex items-center gap-2">
						<h1 class="text-2xl font-bold text-pink-100">
							{#if editing}
								<input
									bind:value={nombre}
									class="border-b border-pink-500 bg-transparent text-2xl font-bold focus:outline-none"
								/>
							{:else}
								{nombre}
							{/if}
						</h1>
					</div>
					<p class="text-sm text-pink-400/60">{email}</p>
				</div>

				<!-- Acciones -->
				<div class="flex shrink-0 gap-2">
					<button
						on:click={uploadAvatar}
						disabled={avatarUploading}
						class="rounded-full bg-black/60 px-4 py-2 text-sm text-white hover:bg-black/80"
					>
						{foto ? 'Cambiar foto' : 'Subir foto'}
					</button>
					{#if foto}
						<button
							on:click={removeAvatar}
							class="rounded-full border border-white/10 px-4 py-2 text-sm text-white/60 hover:bg-white/5"
						>
							Quitar
						</button>
					{/if}
					<button
						on:click={() => {
							editing = !editing;
							if (!editing) saveProfile();
						}}
						disabled={saving}
						class="rounded-full bg-gradient-to-r from-pink-600 to-purple-600 px-4 py-2 text-sm font-bold text-white hover:brightness-110"
					>
						{editing ? (saving ? 'Guardando...' : 'Guardar') : 'Editar'}
					</button>
				</div>
			</div>

			{#if avatarError}
				<p class="mt-2 text-sm text-red-400">{avatarError}</p>
			{/if}

			<!-- Bio -->
			<div class="mt-4">
				{#if editing}
					<textarea
						bind:value={bio}
						rows="3"
						maxlength="500"
						placeholder="Cuéntales sobre ti..."
						class="w-full resize-none rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
					></textarea>
				{:else if bio}
					<p class="text-sm text-pink-300/80">{bio}</p>
				{:else}
					<button
						on:click={() => (editing = true)}
						class="text-sm text-pink-400/50 italic hover:text-pink-400"
					>
						+ Añadir biografía
					</button>
				{/if}
			</div>
		</div>

		<!-- Galeria propia -->
		<div class="mt-6 pb-8">
			<div class="mb-4">
				<h2 class="text-xl font-bold text-pink-100">Mi galeria</h2>
				<p class="mt-1 text-sm text-pink-300/50">
					Tus fotos pasan por proteccion de rostros y revision antes de publicarse. Solo tu puedes
					verlas mientras estan pendientes.
				</p>
			</div>

			{#if galleryError}
				<p
					class="mb-4 rounded-xl border border-red-500/30 bg-red-900/20 px-4 py-3 text-sm text-red-400"
				>
					{galleryError}
				</p>
			{/if}

			<div class="rounded-2xl border border-pink-900/30 bg-black/40 p-5">
				<UploadQueue onUploaded={handleUploaded} />
			</div>

			{#if galleryItems.length === 0 && !galleryError}
				<p
					class="mt-6 rounded-xl border border-dashed border-pink-900/40 bg-black/20 px-6 py-12 text-center text-sm text-pink-300/50"
				>
					Tu galeria esta vacia. Sube tu primera foto para empezar.
				</p>
			{:else}
				<ul class="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
					{#each galleryItems as item (item.id)}
						<li class="overflow-hidden rounded-xl border border-white/5 bg-black/30">
							<div class="relative flex aspect-square items-center justify-center bg-white/5">
								{#if item.previewUrl}
									<a
										href={item.fullUrl ?? item.previewUrl}
										target="_blank"
										rel="noreferrer"
										class="h-full w-full"
									>
										<img
											src={item.previewUrl}
											alt={item.original_filename ?? 'Foto'}
											loading="lazy"
											class="h-full w-full object-cover"
										/>
									</a>
								{:else if item.processing_status === 'failed' || item.moderation_status === 'blocked'}
									<p class="px-3 text-center text-xs text-red-400">
										No se pudo proteger esta foto. Eliminala y vuelve a intentarlo.
									</p>
								{:else}
									<div class="flex flex-col items-center gap-2 px-3 text-center">
										<div
											class="h-6 w-6 animate-spin rounded-full border-2 border-pink-500 border-t-transparent"
											role="status"
											aria-label="Procesando foto"
										></div>
										<p class="text-[11px] text-pink-300/60">Procesando...</p>
									</div>
								{/if}
							</div>

							<div class="p-3">
								<p class="truncate text-xs text-pink-100">
									{item.original_filename ?? 'Foto'}
								</p>
								<p class="mt-0.5 text-[11px] text-pink-400/50">
									{formatDate(item.created_at)}
									{#if item.byte_size}· {formatBytes(item.byte_size)}{/if}
								</p>
								<p class="mt-1 text-[11px] {moderationClass(item.moderation_status)}">
									{moderationLabel(item.moderation_status)}
								</p>
								{#if item.rejection_reason}
									<p class="mt-1 text-[11px] text-red-300/80">{item.rejection_reason}</p>
								{/if}
								{#if item.originalAvailable}
									<p class="mt-1 text-[10px] text-pink-400/40">
										Original privado disponible 30 dias.
									</p>
								{/if}
								<button
									on:click={() => deleteGalleryItem(item)}
									disabled={deletingId !== null}
									class="mt-2 w-full rounded-lg border border-white/10 px-2 py-1.5 text-xs text-white/50 transition hover:border-red-500/40 hover:text-red-400 disabled:opacity-40"
								>
									{deletingId === item.id ? 'Eliminando...' : 'Eliminar'}
								</button>
							</div>
						</li>
					{/each}
				</ul>
			{/if}
			{#if galleryCursor}
				<button on:click={() => loadGallery(true)} disabled={galleryLoading} class="mt-4 rounded-xl border border-pink-500/40 px-5 py-2 text-sm text-pink-200 disabled:opacity-50">
					{galleryLoading ? 'Cargando...' : 'Cargar mas fotos'}
				</button>
			{/if}
		</div>
	</div>
{/if}
