<script>
	import { onMount } from 'svelte';
	import { browser } from '$app/environment';
	import { supabase } from '$lib/supabaseClient';
	import { session, user, logout } from '$lib/stores/auth';
	import { goto } from '$app/navigation';
	import MediaGrid from '$lib/components/MediaGrid.svelte';
	import {
		uploadToR2,
		deleteR2Object,
		validateImageFile,
		MAX_UPLOAD_BYTES,
		R2_FOLDERS
	} from '$lib/upload/r2Upload';

	let loading = true;
	let nombre = '';
	let email = '';
	let bio = '';
	let foto = '';
	let editing = false;
	let saving = false;
	let avatarUploading = false;
	let avatarError = '';
	let uploadProgress = 0;

	/** @type {any[]} */
	/** @type {any[]} */
	let mediaItems = [];
	let activeTab = 'publico';

	/** @type {any[]} */
	/** @type {any[]} */
	let bannerItems = [];
	let currentBannerIndex = 0;
	let bannerUploading = false;
	let bannerProgress = 0;

	// Preview upload
	/** @type {File | null} */
	/** @type {File | null} */
	let previewFile = null;
	/** @type {string | null} */
	/** @type {string | null} */
	let previewUrl = null;
	let previewTitulo = '';
	let previewDescripcion = '';
	let previewEsPrivado = false;
	let previewUploading = false;
	let previewProgress = 0;
	let showPreviewModal = false;

	onMount(async () => {
		if (!$session?.user) {
			goto('/login');
			return;
		}
		await Promise.all([loadProfile(), loadMedia(), loadBanners()]);
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
			.select(
				'id, role, username, display_name, bio, avatar_key, is_verified, followers_count, media_count'
			)
			.eq('id', $session?.user?.id)
			.maybeSingle();

		if (data) {
			nombre = data.display_name || data.username || nombre;
			bio = data.bio || '';
			foto = data.avatar_key || '';
		}
	}

	async function saveProfile() {
		if (saving) return;
		saving = true;
		await supabase.from('profiles').upsert({
			id: $session?.user?.id,
			display_name: nombre || null,
			bio: bio || '',
			avatar_key: foto || null
		});
		await supabase.auth.updateUser({ data: { nombre: nombre || null, bio: bio || '' } });
		await loadProfile();
		saving = false;
		editing = false;
	}

	async function loadMedia() {
		const { data } = await supabase
			.from('media')
			.select(
				`id, user_id, tipo, public_url, storage_key, titulo, descripcion,
				 es_privado, bucket, orden, created_at,
				 media_likes(count), media_comments(count)`
			)
			.eq('user_id', $session?.user?.id)
			.eq('tipo', 'photo')
			.order('created_at', { ascending: false });

		mediaItems = (data ?? []).map((m) => ({
			...m,
			like_count: m.media_likes?.[0]?.count ?? 0,
			comment_count: m.media_comments?.[0]?.count ?? 0
		}));
	}

	async function loadBanners() {
		const { data } = await supabase
			.from('media')
			.select('id, public_url, storage_key, orden')
			.eq('user_id', $session?.user?.id)
			.eq('tipo', 'banner')
			.order('orden', { ascending: true });
		bannerItems = data ?? [];
	}

	// ---------- AVATAR ----------

	function uploadAvatar() {
		if (!browser || !$session?.user) return;
		const input = document.createElement('input');
		input.type = 'file';
		input.accept = 'image/jpeg,image/png,image/webp,image/gif';
		input.onchange = async (e) => {
			const file = /** @type {HTMLInputElement} */ (e.target)?.files?.[0];
			if (!file) return;
			avatarError = '';
			avatarUploading = true;
			uploadProgress = 0;
			try {
				const err = validateImageFile(file);
				if (err) throw new Error(err);
				const { publicUrl, key } = await uploadToR2(file, R2_FOLDERS.avatar, {
					onProgress: (p) => (uploadProgress = p)
				});
				const { error } = await supabase
					.from('profiles')
					.update({ avatar_key: publicUrl })
					.eq('id', $session?.user?.id);
				if (error) throw error;
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
		input.accept = 'image/jpeg,image/png,image/webp,image/gif';
		input.onchange = async (e) => {
			const file = /** @type {HTMLInputElement} */ (e.target)?.files?.[0];
			if (!file) return;
			bannerUploading = true;
			bannerProgress = 0;
			try {
				const err = validateImageFile(file);
				if (err) throw new Error(err);
				const { publicUrl, key } = await uploadToR2(file, R2_FOLDERS.cover, {
					onProgress: (p) => (bannerProgress = p)
				});
				const { error } = await supabase.from('media').insert({
					user_id: $session?.user?.id,
					tipo: 'banner',
					storage_key: key,
					public_url: publicUrl,
					bucket: 'public',
					es_privado: false,
					orden: bannerItems.length
				});
				if (error) throw error;
				await loadBanners();
				currentBannerIndex = bannerItems.length - 1;
			} catch (e) {
				console.error('Banner error:', e);
			} finally {
				bannerUploading = false;
			}
		};
		input.click();
	}

	async function deleteCurrentBanner() {
		if (!bannerItems.length || !$session?.user) return;
		const item = bannerItems[currentBannerIndex];
		if (item.storage_key) await deleteR2Object(item.storage_key, R2_FOLDERS.cover);
		await supabase.from('media').delete().eq('id', item.id);
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

	function openPublishModal() {
		if (!browser) return;
		const input = document.createElement('input');
		input.type = 'file';
		input.accept = 'image/jpeg,image/png,image/webp,image/gif';
		input.onchange = async (e) => {
			const file = /** @type {HTMLInputElement} */ (e.target)?.files?.[0];
			if (!file) return;
			const err = validateImageFile(file);
			if (err) {
				alert(err);
				return;
			}
			previewFile = file;
			previewUrl = URL.createObjectURL(file);
			previewTitulo = '';
			previewDescripcion = '';
			previewEsPrivado = false;
			showPreviewModal = true;
		};
		input.click();
	}

	async function confirmPublish() {
		if (!previewFile || !$session?.user || previewUploading) return;
		previewUploading = true;
		previewProgress = 0;
		try {
			const { publicUrl, key } = await uploadToR2(previewFile, R2_FOLDERS.post, {
				onProgress: (p) => (previewProgress = p)
			});
			const { error } = await supabase.from('media').insert({
				user_id: $session?.user?.id,
				tipo: 'photo',
				storage_key: key,
				public_url: publicUrl,
				bucket: previewEsPrivado ? 'private' : 'public',
				es_privado: previewEsPrivado,
				titulo: previewTitulo.trim() || null,
				descripcion: previewDescripcion.trim() || null,
				orden: mediaItems.length
			});
			if (error) throw error;
			cancelPreview();
			await loadMedia();
		} catch (e) {
			console.error('Publish error:', e);
		} finally {
			previewUploading = false;
		}
	}

	function cancelPreview() {
		if (previewUrl) URL.revokeObjectURL(previewUrl);
		previewFile = null;
		previewUrl = null;
		showPreviewModal = false;
	}

	/** @param {string} id */
	async function deleteMedia(id) {
		const item = mediaItems.find((m) => m.id === id);
		if (!item) return;
		if (item.storage_key) await deleteR2Object(item.storage_key, R2_FOLDERS.post);
		await supabase.from('media').delete().eq('id', id);
		mediaItems = mediaItems.filter((m) => m.id !== id);
	}

	$: publicItems = mediaItems.filter((m) => !m.es_privado);
	$: privateItems = mediaItems.filter((m) => m.es_privado);

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
		{#if bannerItems.length > 0}
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

		<!-- Contenido -->
		<div class="mt-6 pb-8">
			<div class="mb-4 flex items-center justify-between">
				<h2 class="text-xl font-bold text-pink-100">Mi contenido</h2>
				<button
					on:click={openPublishModal}
					class="rounded-xl bg-gradient-to-r from-pink-600 to-purple-600 px-5 py-2.5 text-sm font-bold text-white shadow-lg transition hover:brightness-110"
				>
					+ Publicar
				</button>
			</div>

			<!-- Tabs -->
			<div class="mb-4 flex gap-1 rounded-xl border border-pink-900/30 bg-black/40 p-1">
				<button
					on:click={() => (activeTab = 'publico')}
					class="flex-1 rounded-lg py-2 text-sm font-semibold transition
						{activeTab === 'publico' ? 'bg-pink-600/20 text-pink-300' : 'text-pink-300/50 hover:text-pink-300'}"
				>
					Público ({publicItems.length})
				</button>
				<button
					on:click={() => (activeTab = 'privado')}
					class="flex-1 rounded-lg py-2 text-sm font-semibold transition
						{activeTab === 'privado' ? 'bg-pink-600/20 text-pink-300' : 'text-pink-300/50 hover:text-pink-300'}"
				>
					Exclusivo ({privateItems.length})
				</button>
			</div>

			{#if activeTab === 'publico'}
				<MediaGrid
					items={publicItems}
					showActions={true}
					isOwner={true}
					showDelete={true}
					onDelete={deleteMedia}
				/>
			{:else}
				<MediaGrid
					items={privateItems}
					showActions={true}
					isOwner={true}
					showDelete={true}
					canViewPrivate={true}
					onDelete={deleteMedia}
				/>
			{/if}
		</div>
	</div>
{/if}

<!-- Modal de publicación -->
{#if showPreviewModal && previewUrl}
	<div
		class="fixed inset-0 z-50 flex items-center justify-center bg-black/90 p-4"
		role="dialog"
		aria-modal="true"
	>
		<div class="w-full max-w-md overflow-hidden rounded-2xl border border-pink-900/30 bg-black">
			<div class="relative">
				<img src={previewUrl} alt="Preview" class="max-h-64 w-full object-cover" />
				<button
					on:click={cancelPreview}
					class="absolute top-2 right-2 flex h-8 w-8 items-center justify-center rounded-full bg-black/60 text-white hover:bg-black/80"
					aria-label="Cerrar"
				>
					×
				</button>
			</div>

			<div class="p-5">
				<h3 class="mb-4 font-bold text-pink-100">Nueva publicación</h3>

				<div class="mb-3">
					<input
						bind:value={previewTitulo}
						maxlength="100"
						placeholder="Título (opcional)..."
						class="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 text-sm text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
					/>
				</div>

				<div class="mb-4">
					<textarea
						bind:value={previewDescripcion}
						maxlength="500"
						rows="2"
						placeholder="Descripción (opcional)..."
						class="w-full resize-none rounded-xl border border-white/10 bg-white/5 px-4 py-2.5 text-sm text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
					></textarea>
				</div>

				<!-- Toggle privado -->
				<div class="mb-5 flex items-center justify-between">
					<div>
						<p class="text-sm font-medium text-pink-100">Contenido exclusivo</p>
						<p class="text-xs text-pink-300/50">Solo suscriptoras</p>
					</div>
					<button
						role="switch"
						aria-checked={previewEsPrivado}
						on:click={() => (previewEsPrivado = !previewEsPrivado)}
						class="relative h-7 w-12 rounded-full transition {previewEsPrivado
							? 'bg-pink-600'
							: 'bg-white/10'}"
					>
						<span
							class="absolute top-0.5 h-6 w-6 rounded-full bg-white shadow transition-transform {previewEsPrivado
								? 'translate-x-5'
								: 'translate-x-0.5'}"
						></span>
					</button>
				</div>

				{#if previewUploading && previewProgress > 0}
					<div class="mb-4">
						<div class="mb-1 flex justify-between text-xs text-pink-300/70">
							<span>Subiendo...</span><span>{previewProgress}%</span>
						</div>
						<div class="h-2 w-full rounded-full bg-white/10">
							<div
								class="h-2 rounded-full bg-gradient-to-r from-pink-500 to-purple-500 transition-all"
								style="width: {previewProgress}%"
							></div>
						</div>
					</div>
				{/if}

				<div class="flex gap-3">
					<button
						on:click={cancelPreview}
						class="flex-1 rounded-xl border border-white/10 py-2.5 text-sm text-white/60 hover:bg-white/5"
					>
						Cancelar
					</button>
					<button
						on:click={confirmPublish}
						disabled={previewUploading}
						class="flex-1 rounded-xl bg-gradient-to-r from-pink-600 to-purple-600 py-2.5 text-sm font-bold text-white transition hover:brightness-110 disabled:opacity-40"
					>
						{previewUploading ? 'Subiendo...' : 'Publicar'}
					</button>
				</div>
			</div>
		</div>
	</div>
{/if}
