<!-- Panel de control para subir fotos las chicas -->
<script>
	// @ts-nocheck
	import { onMount, onDestroy } from 'svelte';
	import { supabase } from '$lib/supabaseClient';
	import { session, logout } from '$lib/stores/auth';
	import * as faceapi from 'face-api.js';

	// === Estado del banner ===
	let bannerPhotos = [];
	let currentBannerIndex = 0;
	let selectedBanner = null; // para fullscreen

	// === Estado del perfil ===
	let foto = '', nombre = '', email = '', bio = '', fecha_nacimiento = '',
		ciudad = '', pais = '', whatsapp = '', twitter_url = '',
		instagram_url = '', website_url = '', direccion = '';

	let editing = false;
	let saving = false;

	// === Álbum ===
	let photos = [];
	let selectedPhoto = null;
	let photoComment = '';
	let photoComments = [];

	// === Menú banner ===
	let showMenu = false;
	let menuRef;
	let buttonRef;

	// === Preview + censura ===
	let preview = null;
	let isUploadingPreview = false;
	let censorFaces = true;

	// Click fuera del menú
	function handleClickOutside(event) {
		if (showMenu && menuRef && !menuRef.contains(event.target) && buttonRef && !buttonRef.contains(event.target)) {
			showMenu = false;
		}
	}

	// Sincronizar desde sesión
	$: if ($session?.user) {
		nombre = $session.user.user_metadata?.nombre || $session.user.email?.split('@')[0] || 'Usuario';
		email = $session.user.email || '';
	}

	// === onMount ÚNICO ===
	onMount(async () => {
		document.addEventListener('click', handleClickOutside);

		// Cargar face-api
		try {
			await Promise.all([
				faceapi.nets.tinyFaceDetector.loadFromUri('/models'),
				faceapi.nets.faceLandmark68Net.loadFromUri('/models'),
				faceapi.nets.faceRecognitionNet.loadFromUri('/models'),
				faceapi.nets.ssdMobilenetv1.loadFromUri('/models')
			]);
			console.log('Modelos face-api cargados (4/4)');
		} catch (e) {
			console.warn('Error face-api:', e);
		}

		if ($session?.user) {
			await Promise.all([loadProfile(), loadPhotos(), loadBannerPhotos()]);
		}
	});

	onDestroy(() => {
		document.removeEventListener('click', handleClickOutside);
	});

	// === CARGAR PERFIL ===
	async function loadProfile() {
		if (!$session?.user) return;
		const { data } = await supabase
			.from('profiles')
			.select('*')
			.eq('id', $session.user.id)
			.maybeSingle();

		if (data) {
			nombre = data.nombre || nombre;
			email = data.email || email;
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

	// === GUARDAR PERFIL ===
	async function saveProfile() {
		if (!$session?.user) return;
		saving = true;
		try {
			await supabase.from('profiles').upsert({
				id: $session.user.id,
				nombre, email, bio, avatar_url: foto,
				fecha_nacimiento, ciudad, pais, whatsapp,
				twitter_url, instagram_url, website_url, direccion
			});
			await supabase.auth.updateUser({ data: { nombre } });
			editing = false;
		} catch (e) {
			alert('Error al guardar');
		} finally {
			saving = false;
		}
	}

	// === HELPERS R2 (subida firmada) ===
	async function requestUpload({ tipo, filename, contentType, es_privado }) {
		const res = await fetch('/api/media/upload', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ tipo, filename, contentType, es_privado })
		});
		const data = await res.json();
		if (!res.ok) throw new Error(data.error || 'Error generando subida');
		return data;
	}

	async function uploadBlobToR2(uploadUrl, blob, contentType) {
		const res = await fetch(uploadUrl, {
			method: 'PUT',
			headers: { 'Content-Type': contentType },
			body: blob
		});
		if (!res.ok) throw new Error('Error subiendo archivo a R2');
	}

	async function insertMedia(row) {
		const { error } = await supabase.from('media').insert(row);
		if (error) throw error;
	}

	// === BANNERS ===
	async function loadBannerPhotos() {
		if (!$session?.user) return;
		const { data } = await supabase
			.from('media')
			.select('id, storage_key, public_url, tipo, es_privado, orden')
			.eq('user_id', $session.user.id)
			.eq('tipo', 'banner')
			.order('orden');
		bannerPhotos = data || [];
	}

	async function uploadBanner() {
		openFileDialog(async (file) => {
			try {
				const req = await requestUpload({ tipo: 'banner', filename: file.name, contentType: file.type, es_privado: false });
				await uploadBlobToR2(req.upload_url, file, file.type);
				await insertMedia({
					user_id: $session.user.id,
					tipo: 'banner',
					bucket: req.bucket,
					storage_key: req.storage_key,
					public_url: req.public_url,
					es_privado: false,
					orden: bannerPhotos.length
				});
				await loadBannerPhotos();
			} catch (e) {
				alert('Error al subir banner: ' + (e?.message ?? e));
			}
		}, 'image/*,video/*');
	}

	async function deleteCurrentBanner() {
		const banner = bannerPhotos[currentBannerIndex];
		if (!banner) return;
		if (!confirm('¿Borrar este banner?')) return;
		const res = await fetch('/api/media/delete', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ media_id: banner.id })
		});
		const data = await res.json();
		if (!data.ok) alert(data.error || 'Error al borrar');
		await loadBannerPhotos();
		currentBannerIndex = Math.min(currentBannerIndex, Math.max(0, bannerPhotos.length - 1));
	}

	const prevBanner = () => currentBannerIndex = (currentBannerIndex - 1 + bannerPhotos.length) % bannerPhotos.length;
	const nextBanner = () => currentBannerIndex = (currentBannerIndex + 1) % bannerPhotos.length;

	// === ÁLBUM ===
	async function loadPhotos() {
		if (!$session?.user) return;
		const { data } = await supabase
			.from('media')
			.select('id, tipo, storage_key, public_url, thumbnail_url, titulo, descripcion, orden, es_privado, bucket')
			.eq('user_id', $session.user.id)
			.neq('tipo', 'banner')
			.order('orden');
		photos = (data || []).map(p => ({ ...p, filename: p.storage_key.split('/').pop() }));
	}

	// === UPLOAD HELPERS ===
	function openFileDialog(callback, accept = 'image/*,video/*') {
		const i = document.createElement('input');
		i.type = 'file';
		i.accept = accept;
		i.onchange = e => e.target.files[0] && callback(e.target.files[0]);
		i.click();
	}

	// === CENSURA Y PREVIEW ===
	async function detectFaces(file) {
		const url = URL.createObjectURL(file);
		const img = new Image();
		await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = url; });
		let detections = [];
		try {
			detections = await faceapi.detectAllFaces(img, new faceapi.TinyFaceDetectorOptions()).withFaceLandmarks();
		} finally {
			URL.revokeObjectURL(url);
		}
		return detections;
	}

	async function pixelateFacesInImage(file, detections) {
		const url = URL.createObjectURL(file);
		const img = new Image();
		await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = url; });
		const canvas = document.createElement('canvas');
		canvas.width = img.width;
		canvas.height = img.height;
		const ctx = canvas.getContext('2d');
		ctx.drawImage(img, 0, 0);
		URL.revokeObjectURL(url);
		for (const det of detections) {
			const box = det.detection.box;
			const sx = Math.max(0, Math.floor(box.x));
			const sy = Math.max(0, Math.floor(box.y));
			const sw = Math.min(canvas.width - sx, Math.floor(box.width));
			const sh = Math.min(canvas.height - sy, Math.floor(box.height));
			if (sw <= 0 || sh <= 0) continue;
			const blockW = Math.max(4, Math.floor(sw / 8));
			const blockH = Math.max(4, Math.floor(sh / 8));
			ctx.drawImage(canvas, sx, sy, sw, sh, sx, sy, blockW, blockH);
			ctx.drawImage(canvas, sx, sy, blockW, blockH, sx, sy, sw, sh);
		}
		return canvas.toDataURL('image/jpeg', 0.85);
	}

	async function captureVideoThumbnail(file) {
		const url = URL.createObjectURL(file);
		const video = document.createElement('video');
		video.src = url;
		video.muted = true;
		video.playsinline = true;
		await new Promise((res, rej) => { video.onloadeddata = res; video.onerror = rej; });
		try {
			video.currentTime = Math.min(0.5, video.duration || 1);
			await new Promise(res => { video.onseeked = res; });
		} catch { /* sin frame */ }
		const canvas = document.createElement('canvas');
		canvas.width = video.videoWidth || 320;
		canvas.height = video.videoHeight || 240;
		canvas.getContext('2d').drawImage(video, 0, 0);
		URL.revokeObjectURL(url);
		return canvas.toDataURL('image/jpeg', 0.85);
	}

	function cancelPreview() {
		if (preview?.url) URL.revokeObjectURL(preview.url);
		preview = null;
	}

	function handleAddMedia() {
		openFileDialog(preparePreviewFromFile, 'image/*,video/*');
	}

	async function preparePreviewFromFile(file) {
		const isImage = file.type.startsWith('image/');
		const isVideo = file.type.startsWith('video/');
		if (!isImage && !isVideo) return alert('Formato no soportado');

		preview = {
			file,
			type: isImage ? 'image' : 'video',
			filename: file.name,
			url: URL.createObjectURL(file),
			censoredDataUrl: null,
			detections: [],
			thumbnail: null
		};
		censorFaces = true;

		try {
			if (isImage) {
				const detections = await detectFaces(file);
				preview.detections = detections;
				if (detections.length > 0) {
					preview.censoredDataUrl = await pixelateFacesInImage(file, detections);
				}
			} else if (isVideo) {
				const thumb = await captureVideoThumbnail(file);
				if (thumb) {
					const detections = await detectFacesFromDataUrl(thumb);
					preview.detections = detections;
					preview.thumbnail = thumb;
					if (detections.length > 0) {
						preview.censoredDataUrl = await pixelateFacesFromDataUrl(thumb, detections);
					}
				}
			}
		} catch (e) {
			console.warn('Detección de rostros:', e);
		}
	}

	async function detectFacesFromDataUrl(dataUrl) {
		const img = new Image();
		await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = dataUrl; });
		try {
			return await faceapi.detectAllFaces(img, new faceapi.TinyFaceDetectorOptions()).withFaceLandmarks();
		} catch {
			return [];
		}
	}

	async function pixelateFacesFromDataUrl(dataUrl, detections) {
		const img = new Image();
		await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = dataUrl; });
		const canvas = document.createElement('canvas');
		canvas.width = img.width;
		canvas.height = img.height;
		const ctx = canvas.getContext('2d');
		ctx.drawImage(img, 0, 0);
		for (const det of detections) {
			const box = det.detection.box;
			const sx = Math.max(0, Math.floor(box.x));
			const sy = Math.max(0, Math.floor(box.y));
			const sw = Math.min(canvas.width - sx, Math.floor(box.width));
			const sh = Math.min(canvas.height - sy, Math.floor(box.height));
			if (sw <= 0 || sh <= 0) continue;
			const blockW = Math.max(4, Math.floor(sw / 8));
			const blockH = Math.max(4, Math.floor(sh / 8));
			ctx.drawImage(canvas, sx, sy, sw, sh, sx, sy, blockW, blockH);
			ctx.drawImage(canvas, sx, sy, blockW, blockH, sx, sy, sw, sh);
		}
		return canvas.toDataURL('image/jpeg', 0.85);
	}

	async function uploadPreview(applyCensor) {
		if (!preview) return;
		isUploadingPreview = true;
		try {
			const isVideo = preview.type === 'video';
			const tipo = isVideo ? 'video' : 'photo';
			const esPrivado = false;

			const req = await requestUpload({ tipo, filename: preview.file.name, contentType: preview.file.type, es_privado: esPrivado });
			await uploadBlobToR2(req.upload_url, preview.file, preview.file.type);

			let thumbnailKey = null, thumbnailUrl = null;
			if (isVideo && preview.censoredDataUrl) {
				const thumbReq = await requestUpload({ tipo: 'photo', filename: `thumb-${preview.file.name}.jpg`, contentType: 'image/jpeg', es_privado: false });
				const blob = await (await fetch(preview.censoredDataUrl)).blob();
				await uploadBlobToR2(thumbReq.upload_url, blob, 'image/jpeg');
				thumbnailKey = thumbReq.storage_key;
				thumbnailUrl = thumbReq.public_url;
			}

			await insertMedia({
				user_id: $session.user.id,
				tipo,
				bucket: req.bucket,
				storage_key: req.storage_key,
				public_url: req.public_url,
				thumbnail_key: thumbnailKey,
				thumbnail_url: thumbnailUrl,
				es_privado: esPrivado,
				orden: photos.length
			});
			cancelPreview();
			await loadPhotos();
		} catch (e) {
			alert('Error al subir: ' + (e?.message ?? e));
		} finally {
			isUploadingPreview = false;
		}
	}

	async function uploadFileDirect() {
		openFileDialog(async (file) => {
			try {
				const isVideo = file.type.startsWith('video/');
				const tipo = isVideo ? 'video' : 'photo';
				const req = await requestUpload({ tipo, filename: file.name, contentType: file.type, es_privado: false });
				await uploadBlobToR2(req.upload_url, file, file.type);
				await insertMedia({
					user_id: $session.user.id,
					tipo,
					bucket: req.bucket,
					storage_key: req.storage_key,
					public_url: req.public_url,
					es_privado: false,
					orden: photos.length
				});
				await loadPhotos();
			} catch (e) {
				alert('Error: ' + (e?.message ?? e));
			}
		}, 'image/*,video/*');
	}

	// === CRUD ÁLBUM ===
	async function deletePhoto(id) {
		if (!confirm('¿Eliminar este elemento?')) return;
		const res = await fetch('/api/media/delete', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ media_id: id })
		});
		const data = await res.json();
		if (!data.ok) return alert(data.error || 'Error al eliminar');
		if (selectedPhoto?.id === id) selectedPhoto = null;
		await loadPhotos();
	}

	async function openPhotoModal(photo) {
		selectedPhoto = { ...photo };
		photoComment = '';
		await loadPhotoComments(photo.id);
		if (!photo.public_url) {
			try {
				const res = await fetch('/api/media/presign', {
					method: 'POST',
					headers: { 'Content-Type': 'application/json' },
					body: JSON.stringify({ media_id: photo.id })
				});
				const data = await res.json();
				if (data.url) selectedPhoto = { ...selectedPhoto, public_url: data.url };
			} catch { /* sin URL */ }
		}
	}

	async function updatePhotoDetails(id, patch) {
		const { error } = await supabase.from('media').update(patch).eq('id', id);
		if (error) console.error('updatePhotoDetails:', error);
	}

	async function loadPhotoComments(mediaId) {
		const { data } = await supabase
			.from('comments')
			.select('id, content, created_at, profiles (nombre)')
			.eq('media_id', mediaId)
			.order('created_at');
		photoComments = data || [];
	}

	async function addPhotoComment() {
		if (!photoComment.trim() || !selectedPhoto) return;
		const { error } = await supabase.from('comments').insert({
			media_id: selectedPhoto.id,
			user_id: $session.user.id,
			content: photoComment.trim()
		});
		if (error) return alert(error.message);
		photoComment = '';
		await loadPhotoComments(selectedPhoto.id);
	}
</script>

<!-- BANNER MEJORADO -->
<div class="relative h-96 bg-black rounded-2xl overflow-hidden mb-8">
	{#if bannerPhotos.length === 0}
		<div class="h-full flex items-center justify-center bg-gradient-to-br from-gray-800 to-black text-white text-3xl font-bold">
			Fotos o video
		</div>
	{:else}
		<!-- Contenido clicable -->
		<div
			class="relative h-full cursor-pointer"
			on:click={() => selectedBanner = bannerPhotos[currentBannerIndex].public_url}
		>
			{#if bannerPhotos[currentBannerIndex].public_url?.match(/\.(mp4|webm|ogg|mov)$/i)}
				<!-- VIDEO -->
				<video
					src={bannerPhotos[currentBannerIndex].public_url}
					class="w-full h-full object-cover"
					muted
					loop
					playsinline
				/>
				<!-- Play grande -->
				<div class="absolute inset-0 flex items-center justify-center pointer-events-none">
					<div class="bg-black/60 rounded-full p-8">
						<svg class="w-20 h-20 text-white" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>
					</div>
				</div>
			{:else}
				<!-- FOTO -->
				<img
					src={bannerPhotos[currentBannerIndex].public_url}
					alt="Banner"
					class="w-full h-full object-cover"
				/>
			{/if}
		</div>
	{/if}

	<!-- Flechas -->
	{#if bannerPhotos.length > 1}
		<button
			on:click|stopPropagation={prevBanner}
			class="absolute left-4 top-1/2 -translate-y-1/2 bg-black/60 hover:bg-black text-white w-14 h-14 rounded-full flex items-center justify-center text-4xl z-10"
		>‹</button>
		<button
			on:click|stopPropagation={nextBanner}
			class="absolute right-4 top-1/2 -translate-y-1/2 bg-black/60 hover:bg-black text-white w-14 h-14 rounded-full flex items-center justify-center text-4xl z-10"
		>›</button>
	{/if}

	<!-- Menú tres puntos -->
	<div class="absolute top-4 right-4 z-20">
		<button
			bind:this={buttonRef}
			on:click|stopPropagation={() => showMenu = !showMenu}
			class="bg-white/90 hover:bg-white p-3 rounded-full shadow-xl"
		>⋮</button>

		{#if showMenu}
			<div
				bind:this={menuRef}
				class="absolute right-0 mt-2 w-56 bg-white rounded-2xl shadow-2xl border overflow-hidden"
			>
				<button
					on:click|stopPropagation={() => { uploadBanner(); showMenu = false }}
					class="w-full text-left px-6 py-4 hover:bg-gray-100 font-medium"
				>Subir foto o video</button>
				{#if bannerPhotos.length > 0}
					<button
						on:click|stopPropagation={() => { deleteCurrentBanner(); showMenu = false }}
						class="w-full text-left px-6 py-4 text-red-600 hover:bg-red-50 font-medium"
					>Borrar actual</button>
				{/if}
			</div>
		{/if}
	</div>
</div>

<!-- MODAL FULLSCREEN (grande con X) -->
{#if selectedBanner}
	<div
		class="fixed inset-0 bg-black/95 z-[9999] flex items-center justify-center p-4"
		on:click={() => selectedBanner = null}
	>
		<div class="relative max-w-7xl w-full max-h-full">
			<button
				on:click|stopPropagation={() => selectedBanner = null}
				class="absolute -top-12 right-0 text-white text-5xl hover:text-gray-300"
			>×</button>

			{#if selectedBanner.match(/\.(mp4|webm|ogg|mov)$/i)}
				<video
					src={selectedBanner}
					controls
					class="w-full max-h-screen rounded-2xl shadow-2xl"
				/>
			{:else}
				<img
					src={selectedBanner}
					alt="Banner grande"
					class="w-full max-h-screen rounded-2xl object-contain shadow-2xl"
				/>
			{/if}
		</div>
	</div>
{/if}

<!-- Contenido principal -->
<div class="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
	<div class="relative rounded-xl border border-gray-200 bg-white p-6 shadow-lg md:p-8">
		<!-- Edit Button -->
		<button
			type="button"
			on:click={() => {
				editing = !editing;
				if (!editing) saveProfile();
			}}
			class="absolute top-4 right-4 rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-blue-700"
			disabled={saving}
		>
			{#if editing}
				Guardar
			{:else}
				Editar
			{/if}
		</button>

		<!-- Header -->
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
		</div>

		<!-- Bio -->
		<div class="mb-8 rounded-lg bg-gray-50 p-6">
			<h3 class="mb-3 text-lg font-semibold text-gray-900">Descripción Profesional</h3>
			<div class="relative">
				{#if editing}
					<textarea
						bind:value={bio}
						rows="5"
						placeholder="Describe tu experiencia..."
						class="w-full resize-none rounded-lg border border-gray-300 px-4 py-3 focus:border-blue-500 focus:ring-2 focus:ring-blue-500"
					></textarea>
					<div class="absolute right-3 bottom-3 text-sm text-gray-500">{bio.length}/500</div>
				{:else if bio}
					<p class="leading-relaxed whitespace-pre-wrap text-gray-700">{bio}</p>
				{:else}
					<p class="text-gray-500 italic">Añade una descripción profesional...</p>
				{/if}
			</div>
		</div>

		<!-- Álbum -->
		<div class="mb-8">
			<h2 class="mb-4 text-2xl font-bold">Mi Álbum (Fotos y Videos)</h2>

			<!-- BOTONES: agregar con preview -->
			<div class="mb-4 flex gap-3">
				<button
					on:click={handleAddMedia}
					class="rounded-lg bg-blue-600 px-6 py-2 text-white hover:bg-blue-700"
					>Agregar Foto/Video</button
				>
				<button
					on:click={uploadFileDirect}
					class="rounded-lg bg-gray-200 px-4 py-2 hover:bg-gray-300"
					>Subir directo (sin preview)</button
				>
			</div>

			<!-- PREVIEW antes de subir -->
			{#if preview}
				<div class="mb-6 rounded-lg border bg-gray-50 p-4">
					<h3 class="mb-2 font-semibold">Vista previa — {preview.filename}</h3>

					{#if preview.type === 'image'}
						<div class="flex items-start gap-4">
							<div>
								<img
									src={preview.censoredDataUrl ? preview.censoredDataUrl : preview.url}
									alt="preview"
									class="max-h-56 rounded-md border"
								/>
								<div class="mt-2 text-sm text-gray-600">
									Detecciones: {preview.detections?.length ?? 0}
								</div>
							</div>
							<div class="flex flex-col gap-2">
								<label class="flex items-center gap-2"
									><input type="checkbox" bind:checked={censorFaces} /> Censurar rostros automáticamente</label
								>
								<button
									on:click={() => uploadPreview(censorFaces)}
									class="rounded bg-green-600 px-4 py-2 text-white"
									disabled={isUploadingPreview}>Subir {isUploadingPreview ? '...' : ''}</button
								>
								<button on:click={cancelPreview} class="rounded bg-red-500 px-4 py-2 text-white"
									>Cancelar</button
								>
							</div>
						</div>
					{:else}
						<!-- video preview -->
						<div class="flex items-start gap-4">
							<div>
								<video src={preview.url} controls class="max-h-56 rounded-md border"></video>
								<div class="mt-2 text-sm text-gray-600">
									Detecciones en primer fotograma: {preview.detections?.length ?? 0}
								</div>
								{#if preview.censoredDataUrl}
									<div class="mt-2">
										<div class="text-sm font-medium">Thumbnail censurado</div>
										<img
											src={preview.censoredDataUrl}
											alt="thumb censurado"
											class="max-h-40 rounded-md border"
										/>
									</div>
								{/if}
							</div>
							<div class="flex flex-col gap-2">
								<label class="flex items-center gap-2"
									><input type="checkbox" bind:checked={censorFaces} /> Generar thumbnail censurado</label
								>
								<button
									on:click={() => uploadPreview(censorFaces)}
									class="rounded bg-green-600 px-4 py-2 text-white"
									disabled={isUploadingPreview}>Subir video</button
								>
								<button on:click={cancelPreview} class="rounded bg-red-500 px-4 py-2 text-white"
									>Cancelar</button
								>
							</div>
						</div>
					{/if}
				</div>
			{/if}

			<!-- GRID de fotos/videos -->
			<div class="relative grid grid-cols-1 gap-4 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
				{#each photos as photo}
					<div class="group relative">
						{#if photo.filename && photo.filename.match(/\.(mp4|webm|ogg|mov)$/i)}
							<!-- video -->
							<div class="h-48 w-full overflow-hidden rounded-lg bg-black">
								<video
									src={photo.public_url || photo.thumbnail_url || '/aguaenlaboca.jpeg'}
									class="h-full w-full object-cover"
									muted
									playsinline
									preload="metadata"
								></video>
							</div>
						{:else}
							<img
								src={photo.thumbnail_url || photo.public_url || '/aguaenlaboca.jpeg'}
								alt={photo.titulo || 'Foto'}
								class="h-full w-full rounded-lg object-cover object-fill"
								on:click={() => openPhotoModal(photo)}
							/>
						{/if}

						<div
							class="bg-opacity-0 group-hover:bg-opacity-50 absolute inset-0 flex items-center justify-center bg-black opacity-0 transition-all group-hover:opacity-100"
						>
							<button
								type="button"
								on:click={() => deletePhoto(photo.id)}
								class="mr-2 rounded-lg bg-red-500 p-2 text-white">🗑️ Borrar</button
							>
							<button
								type="button"
								on:click={() => openPhotoModal(photo)}
								class="rounded-lg bg-blue-500 p-2 text-white">👁️ Ver</button
							>
						</div>
						{#if photo.titulo}
							<div class="bg-opacity-60 absolute bottom-0 w-full bg-black p-2 text-sm text-white">
								{photo.titulo}
							</div>
						{/if}
					</div>
				{/each}
			</div>
		</div>

		<!-- Modal de Foto/Video Grande -->
		{#if selectedPhoto}
			<div class="bg-opacity-75 fixed relative inset-0 z-50 flex items-center justify-center bg-black">
				<div class="relative w-full max-w-4xl rounded-lg bg-white p-4">
					<button
						on:click={() => (selectedPhoto = null)}
						class="absolute top-2 right-2 text-2xl text-gray-600 hover:text-gray-800">×</button
					>

					{#if selectedPhoto.filename && selectedPhoto.filename.match(/\.(mp4|webm|ogg|mov)$/i)}
						<video
							src={selectedPhoto.public_url}
							controls
							class="mb-4 max-h-[70vh] w-full rounded-lg object-contain"
						></video>
					{:else}
						<img
							src={selectedPhoto.public_url || '/aguaenlaboca.jpeg'}
							alt={selectedPhoto.titulo || 'Foto'}
							class="mb-4 max-h-[70vh] w-full rounded-lg object-contain"
						/>
					{/if}

					<div class="space-y-4">
						{#if editing}
							<input
								bind:value={selectedPhoto.titulo}
								placeholder="Título"
								class="w-full rounded-lg border border-gray-300 px-3 py-2"
								on:input={() =>
									updatePhotoDetails(selectedPhoto.id, { titulo: selectedPhoto.titulo })}
							/>
							<textarea
								bind:value={selectedPhoto.descripcion}
								placeholder="Descripción"
								rows="3"
								class="w-full rounded-lg border border-gray-300 px-3 py-2"
								on:input={() =>
									updatePhotoDetails(selectedPhoto.id, { descripcion: selectedPhoto.descripcion })}
							></textarea>
						{:else}
							{#if selectedPhoto.titulo}<h3 class="text-lg font-semibold">
									{selectedPhoto.titulo}
								</h3>{/if}
							{#if selectedPhoto.descripcion}<p class="text-gray-600">
									{selectedPhoto.descripcion}
								</p>{/if}
						{/if}

						<!-- Comentarios -->
						<div class="border-t pt-4">
							<h4 class="mb-2 text-sm font-medium">Comentarios</h4>
							{#each photoComments as comment}
								<div class="mb-2 flex gap-2">
									<span class="font-medium">{comment.profiles?.nombre || 'Anónimo'}:</span>
									<span>{comment.content}</span>
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
										disabled={!photoComment.trim()}>Comentar</button
									>
								</div>
							{/if}
						</div>
					</div>
				</div>
			</div>
		{/if}

		<!-- Logout -->
		<div class="mt-8 border-t border-gray-200 pt-6">
			<div class="flex justify-center">
				<button
					on:click={logout}
					disabled={saving}
					class="flex items-center gap-2 rounded-lg bg-gray-800 px-8 py-3 font-medium text-white transition-colors hover:bg-gray-900 disabled:opacity-50"
				>
					{#if saving}
						<svg class="h-4 w-4 animate-spin" fill="none" viewBox="0 0 24 24"
							><circle
								class="opacity-25"
								cx="12"
								cy="12"
								r="10"
								stroke="currentColor"
								stroke-width="4"
							></circle></svg
						> Cerrando...
					{:else}
						<svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"
							><path
								stroke-linecap="round"
								stroke-linejoin="round"
								stroke-width="2"
								d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
							></path></svg
						> Cerrar Sesión
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
