<script>
	import { onMount, onDestroy } from 'svelte';
	import { supabase } from '$lib/supabaseClient';
	import { session, user, logout } from '$lib/stores/auth';
	import * as faceapi from 'face-api.js';

	onMount(async () => {
		console.log('🧠 Cargando modelos de face-api.js...');

		try {
			// Cargar todos los modelos necesarios desde /models
			await faceapi.nets.tinyFaceDetector.loadFromUri('/models');
			await faceapi.nets.faceLandmark68Net.loadFromUri('/models');
			await faceapi.nets.faceRecognitionNet.loadFromUri('/models');
			await faceapi.nets.ssdMobilenetv1.loadFromUri('/models'); // opcional, si usas detección más precisa

			console.log('✅ Modelos cargados correctamente.');
		} catch (err) {
			console.warn('⚠️ No se pudieron cargar modelos face-api.js:', err);
		}
	});

	// --- Estado del perfil (mantuve tus variables) ---
	let bannerPhotos = [],
		currentBannerIndex = 0;
	let foto = '',
		nombre = '',
		email = '',
		bio = '',
		fecha_nacimiento = '',
		ciudad = '',
		pais = '';
	let whatsapp = '',
		twitter_url = '',
		instagram_url = '',
		website_url = '',
		direccion = '';
	let editing = false,
		saving = false;
	let photos = [],
		selectedPhoto = null,
		photoComment = '',
		photoComments = [];

	let showMenu = false;
	let menuRef;
	let buttonRef;
	let bannerUrl = '';

	// --- Nuevas variables para vista previa y censura ---
	let preview = null; // { type: 'image'|'video', file, url, detections:[], censoredDataUrl?:string, filename }
	let isUploadingPreview = false;
	let censorFaces = true; // default when user chooses to censor in preview

	// cerrar menú si click fuera
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

	onMount(async () => {
		document.addEventListener('click', handleClickOutside);

		// Cargar modelos face-api (espera que los pongas en /static/models)
		try {
			await faceapi.nets.tinyFaceDetector.loadFromUri('/models');
			await faceapi.nets.faceLandmark68Net.loadFromUri('/models');
			await faceapi.nets.faceRecognitionNet.loadFromUri('/models');
			// tinyFaceDetector es suficiente para bounding boxes rápidos
		} catch (e) {
			console.warn(
				'No se pudieron cargar modelos face-api.js, detección deshabilitada si falla.',
				e
			);
		}

		// cargar perfil + contenido si hay sesión
		if ($session?.user) {
			await loadProfile();
			await loadPhotos();
			await loadBannerPhotos();
		}
	});

	onDestroy(() => {
		document.removeEventListener('click', handleClickOutside);
	});

	// sincronizar sesión a variables
	$: if ($session?.user) {
		nombre = $session.user.user_metadata?.nombre || $session.user.email || 'Usuario';
		email = $session.user.email || '';
	}

	// ------------------ FUNCIONES DE PERFIL / BANNERS / ALBUM (mantener lógicas) ------------------

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
				// actualizar metadata en auth
				await supabase.auth.updateUser({ data: { nombre, bio } });
				await loadProfile();
			}
		} catch (e) {
			console.error(e);
		} finally {
			saving = false;
			editing = false;
		}
	}

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

	async function uploadBannerFile(path, url) {
		// Inserta metadato en user_banners
		const { error } = await supabase.from('user_banners').insert({
			user_id: $session.user.id,
			storage_path: path,
			public_url: url,
			orden: bannerPhotos.length
		});
		if (error) console.error('Error inserting banner:', error);
		await loadBannerPhotos();
		currentBannerIndex = bannerPhotos.length - 1;
	}

	async function uploadBanner() {
		// usa la misma lógica de subir archivo abajo pero para banners
		openFileDialog(async (file) => {
			const { path, url } = await uploadToStorage(file, 'banners');
			await uploadBannerFile(path, url);
		}, 'image/*,video/*');
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
		if (bannerPhotos[currentBannerIndex]) window.open(bannerPhotos[currentBannerIndex], '_blank');
		else alert('No hay imagen disponible.');
	}

	const prevBanner = () => {
		if (bannerPhotos.length)
			currentBannerIndex = (currentBannerIndex - 1 + bannerPhotos.length) % bannerPhotos.length;
	};
	const nextBanner = () => {
		if (bannerPhotos.length) currentBannerIndex = (currentBannerIndex + 1) % bannerPhotos.length;
	};

	// ------------------ ALBUM: fotos y videos ------------------

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

	// ------------------ Helpers de archivo, preview y upload ------------------

	// abrir diálogo de archivo y devolución del File
	function openFileDialog(callback, accept = 'image/*,video/*') {
		const fileInput = document.createElement('input');
		fileInput.type = 'file';
		fileInput.accept = accept;
		fileInput.onchange = async (e) => {
			const file = e.target.files[0];
			if (!file) return;
			await callback(file);
		};
		fileInput.click();
	}

	// sube un File a storage en bucket dado; retorna { path, url }
	async function uploadToStorage(file, bucket) {
		const filename = `${Date.now()}-${file.name.replace(/\s+/g, '-')}`;
		const path = `${$session.user.id}/${filename}`;
		const { data, error } = await supabase.storage
			.from(bucket)
			.upload(path, file, { upsert: true });
		if (error) throw error;
		const url = supabase.storage.from(bucket).getPublicUrl(data.path).data.publicUrl;
		return { path: data.path, url };
	}

	// --- CREAR PREVIEW antes de subir (imagen o video) ---
	async function preparePreviewFromFile(file) {
		preview = null;
		const type = file.type.startsWith('video/') ? 'video' : 'image';
		const url = URL.createObjectURL(file);
		const filename = file.name;

		// detect faces and, if image, produce censoredDataUrl if requested
		if (type === 'image') {
			const img = await loadImage(url);
			const detections = await detectFacesImageElement(img);
			let censoredDataUrl = null;
			if (detections && detections.length && censorFaces) {
				censoredDataUrl = pixelateImageElement(img, detections, 12); // pixel size 12
			}
			preview = { type, file, url, detections, censoredDataUrl, filename };
		} else {
			// video: capture first frame and detect faces there
			const frameCanvas = await captureVideoFirstFrame(url);
			const detections = await detectFacesCanvas(frameCanvas);
			let censoredDataUrl = null;
			if (detections && detections.length && censorFaces) {
				// pixelar el canvas (modifica el canvas y exporta dataURL)
				censoredDataUrl = pixelateCanvas(frameCanvas, detections, 12);
			}
			preview = {
				type,
				file,
				url,
				detections,
				censoredDataUrl,
				filename,
				thumbnailCanvas: frameCanvas
			};
		}
	}

	// función para abrir diálogo y crear preview (usada por botón "Agregar Foto/Video")
	async function handleAddMedia() {
		openFileDialog(async (file) => {
			// permitir imagen o video
			if (!file.type.startsWith('image/') && !file.type.startsWith('video/')) {
				alert('Solo se permiten imágenes o videos.');
				return;
			}
			await preparePreviewFromFile(file);
			// ahora preview contiene url / censoredDataUrl / detections
			// usuario puede decidir "Subir" o "Cancelar" y si quiere subir censurado o no
		}, 'image/*,video/*');
	}

	// subir la preview (si es image: sube la version censurada si existe y se solicitó; si video: sube video original y opcionalmente thumbnail censurado)
	async function uploadPreview(confirmCensor = false) {
		if (!preview || !$session?.user) return;
		isUploadingPreview = true;
		try {
			if (preview.type === 'image') {
				if (confirmCensor && preview.censoredDataUrl) {
					// convertir dataURL a Blob
					const blob = dataURLtoBlob(preview.censoredDataUrl);
					const { path, url } = await uploadToStorage(
						new File([blob], preview.filename, { type: 'image/png' }),
						'user-photos'
					);
					// insertar en tabla
					await supabase.from('user_photos').insert({
						user_id: $session.user.id,
						storage_path: path,
						public_url: url,
						filename: preview.filename,
						orden: photos.length,
						titulo: '',
						descripcion: ''
					});
				} else {
					// subir original
					const { path, url } = await uploadToStorage(preview.file, 'user-photos');
					await supabase.from('user_photos').insert({
						user_id: $session.user.id,
						storage_path: path,
						public_url: url,
						filename: preview.filename,
						orden: photos.length,
						titulo: '',
						descripcion: ''
					});
				}
			} else {
				// video: subir video original
				const { path, url } = await uploadToStorage(preview.file, 'user-photos');
				// si tenemos thumbnail censurado y queremos subirlo como imagen de portada, subirlo también
				if (confirmCensor && preview.censoredDataUrl) {
					const blob = dataURLtoBlob(preview.censoredDataUrl);
					const thumbName = `thumb-${preview.filename}.png`;
					const { path: tpath, url: turl } = await uploadToStorage(
						new File([blob], thumbName, { type: 'image/png' }),
						'user-photos'
					);
					// Insert metadata with both video public_url and thumbnail (guardar thumbnail en descripcion o campo extra)
					await supabase.from('user_photos').insert({
						user_id: $session.user.id,
						storage_path: path,
						public_url: url,
						filename: preview.filename,
						orden: photos.length,
						titulo: '',
						descripcion: '',
						thumbnail_url: turl
					});
				} else {
					await supabase.from('user_photos').insert({
						user_id: $session.user.id,
						storage_path: path,
						public_url: url,
						filename: preview.filename,
						orden: photos.length,
						titulo: '',
						descripcion: ''
					});
				}
			}

			// limpiar preview y recargar
			preview = null;
			await loadPhotos();
		} catch (e) {
			console.error('Error uploading preview:', e);
			alert('Error al subir el archivo.');
		} finally {
			isUploadingPreview = false;
		}
	}

	// cancelar preview
	function cancelPreview() {
		if (preview?.url) URL.revokeObjectURL(preview.url);
		preview = null;
	}

	// ------------------ UTIL: cargar imagen / video / detectar caras / pixelar ------------------

	function loadImage(url) {
		return new Promise((resolve, reject) => {
			const img = new Image();
			img.crossOrigin = 'anonymous';
			img.onload = () => resolve(img);
			img.onerror = reject;
			img.src = url;
		});
	}

	async function captureVideoFirstFrame(videoUrl, seekTime = 0.1) {
		return new Promise((resolve, reject) => {
			const video = document.createElement('video');
			video.crossOrigin = 'anonymous';
			video.src = videoUrl;
			video.muted = true;
			video.playsInline = true;
			video.currentTime = 0;
			// wait metadata to set size
			video.addEventListener(
				'loadedmetadata',
				() => {
					// Seek to a small time (some videos need it)
					const onSeeked = () => {
						const canvas = document.createElement('canvas');
						canvas.width = video.videoWidth;
						canvas.height = video.videoHeight;
						const ctx = canvas.getContext('2d');
						ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
						// cleanup
						video.pause();
						resolve(canvas);
					};
					const trySeek = () => {
						video.currentTime = Math.min(seekTime, Math.max(0.01, video.duration * 0.01));
					};
					video.addEventListener('seeked', onSeeked, { once: true });
					trySeek();
				},
				{ once: true }
			);
			video.addEventListener('error', () =>
				reject(new Error('Error al cargar video para captura de frame'))
			);
		});
	}

	// detect faces en un elemento image (HTMLImageElement)
	async function detectFacesImageElement(imgEl) {
		try {
			const detections = await faceapi.detectAllFaces(imgEl, new faceapi.TinyFaceDetectorOptions());
			// detections: array de boxes con .box { x, y, width, height }
			return detections.map((d) => d.box);
		} catch (e) {
			console.warn('face-api detect error (image):', e);
			return [];
		}
	}

	// detect faces en canvas
	async function detectFacesCanvas(canvasEl) {
		try {
			const detections = await faceapi.detectAllFaces(
				canvasEl,
				new faceapi.TinyFaceDetectorOptions()
			);
			return detections.map((d) => d.box);
		} catch (e) {
			console.warn('face-api detect error (canvas):', e);
			return [];
		}
	}

	// DETECCIÓN: crea canvas pixelado y devuelve dataURL (imagen PNG)
	function pixelateImageElement(imgEl, boxes, pixelSize = 10) {
		const canvas = document.createElement('canvas');
		canvas.width = imgEl.naturalWidth || imgEl.width;
		canvas.height = imgEl.naturalHeight || imgEl.height;
		const ctx = canvas.getContext('2d');
		ctx.drawImage(imgEl, 0, 0);
		// pixelate each box
		boxes.forEach((box) => {
			pixelateRect(ctx, box.x, box.y, box.width, box.height, pixelSize);
		});
		return canvas.toDataURL('image/png');
	}

	function pixelateCanvas(canvasEl, boxes, pixelSize = 10) {
		const canvas = document.createElement('canvas');
		canvas.width = canvasEl.width;
		canvas.height = canvasEl.height;
		const ctx = canvas.getContext('2d');
		ctx.drawImage(canvasEl, 0, 0);
		boxes.forEach((box) => {
			pixelateRect(ctx, box.x, box.y, box.width, box.height, pixelSize);
		});
		return canvas.toDataURL('image/png');
	}

	// pixelateRect helper: reduce resolution of rect and scale back
	function pixelateRect(ctx, x, y, w, h, pixelSize) {
		// clamp
		x = Math.max(0, Math.floor(x));
		y = Math.max(0, Math.floor(y));
		w = Math.max(1, Math.floor(w));
		h = Math.max(1, Math.floor(h));
		// get image data for rect
		const tmp = document.createElement('canvas');
		tmp.width = w;
		tmp.height = h;
		const tctx = tmp.getContext('2d');
		tctx.drawImage(ctx.canvas, x, y, w, h, 0, 0, w, h);
		// scale down
		const sw = Math.max(1, Math.floor(w / pixelSize));
		const sh = Math.max(1, Math.floor(h / pixelSize));
		const small = document.createElement('canvas');
		small.width = sw;
		small.height = sh;
		const sctx = small.getContext('2d');
		sctx.imageSmoothingEnabled = false;
		sctx.drawImage(tmp, 0, 0, w, h, 0, 0, sw, sh);
		// scale back up
		tctx.imageSmoothingEnabled = false;
		tctx.clearRect(0, 0, w, h);
		tctx.drawImage(small, 0, 0, sw, sh, 0, 0, w, h);
		// put back into main ctx
		ctx.drawImage(tmp, 0, 0, w, h, x, y, w, h);
	}

	// convierte dataURL a Blob
	function dataURLtoBlob(dataurl) {
		const arr = dataurl.split(',');
		const mime = arr[0].match(/:(.*?);/)[1];
		const bstr = atob(arr[1]);
		let n = bstr.length;
		const u8arr = new Uint8Array(n);
		while (n--) u8arr[n] = bstr.charCodeAt(n);
		return new Blob([u8arr], { type: mime });
	}

	// Upload directo (sin preview) - lo dejo por compatibilidad si lo necesitas
	async function uploadFileDirect(bucket) {
		openFileDialog(async (file) => {
			if (!file) return;
			const { path, url } = await uploadToStorage(file, bucket);
			await supabase.from('user_photos').insert({
				user_id: $session.user.id,
				storage_path: path,
				public_url: url,
				filename: file.name,
				orden: photos.length,
				titulo: '',
				descripcion: ''
			});
			await loadPhotos();
		}, 'image/*,video/*');
	}

	// ------------------ FIN helpers ------------------
</script>

<!-- ============================
     HTML: Banner + Preview UI + Álbum con vista previa y opciones
     Mantengo tu markup y agrego la sección de preview antes del botón subir
============================ -->

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

	<!-- Menú del banner -->
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
						class="block w-full px-4 py-2 text-left hover:bg-gray-100">👁️ Ver</button
					>
					<button
						on:click={() => {
							showMenu = false;
							uploadBanner();
						}}
						class="block w-full px-4 py-2 text-left hover:bg-gray-100">⬆️ Subir Banner</button
					>
					<button
						on:click={() => {
							showMenu = false;
							deleteCurrentBanner();
						}}
						class="block w-full px-4 py-2 text-left text-red-600 hover:bg-red-100">🗑️ Borrar</button
					>
				</div>
			{/if}
		</div>
	</div>
</div>

<!-- Contenido principal -->
<div class="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
	<div class="relative rounded-xl border border-gray-200 bg-white p-6 shadow-lg md:p-8">
		<!-- Edit Button (mantengo) -->
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
					<div class="absolute bottom-3 right-3 text-sm text-gray-500">{bio.length}/500</div>
				{:else if bio}
					<p class="whitespace-pre-wrap leading-relaxed text-gray-700">{bio}</p>
				{:else}
					<p class="italic text-gray-500">Añade una descripción profesional...</p>
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
					on:click={() => uploadFileDirect('user-photos')}
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
			<div class="grid grid-cols-1 gap-4 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
				{#each photos as photo}
					<div class="group relative">
						{#if photo.public_url && photo.filename && photo.filename.match(/\.(mp4|webm|ogg|mov)$/i)}
							<!-- video thumbnail if video (use thumbnail_url si existe) -->
							<div class="h-48 w-full overflow-hidden rounded-lg bg-black">
								<video
									src={photo.public_url}
									class="h-full w-full object-cover"
									muted
									playsinline
									preload="metadata"
								></video>
							</div>
						{:else}
							<img
								src={photo.thumbnail_url ?? photo.public_url}
								alt={photo.titulo || 'Foto'}
								class="h-48 w-full cursor-pointer rounded-lg object-cover"
								on:click={() => openPhotoModal(photo)}
							/>
						{/if}

						<div
							class="absolute inset-0 flex items-center justify-center bg-black bg-opacity-0 opacity-0 transition-all group-hover:bg-opacity-50 group-hover:opacity-100"
						>
							<button
								on:click={() => deletePhoto(photo.id)}
								class="mr-2 rounded-lg bg-red-500 p-2 text-white">🗑️ Borrar</button
							>
							<button
								on:click={() => openPhotoModal(photo)}
								class="rounded-lg bg-blue-500 p-2 text-white">👁️ Ver</button
							>
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

		<!-- Modal de Foto/Video Grande -->
		{#if selectedPhoto}
			<div class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-75">
				<div class="relative w-full max-w-4xl rounded-lg bg-white p-4">
					<button
						on:click={() => (selectedPhoto = null)}
						class="absolute right-2 top-2 text-2xl text-gray-600 hover:text-gray-800">×</button
					>

					{#if selectedPhoto.filename && selectedPhoto.filename.match(/\.(mp4|webm|ogg|mov)$/i)}
						<video
							src={selectedPhoto.public_url}
							controls
							class="mb-4 max-h-[70vh] w-full rounded-lg object-contain"
						></video>
					{:else}
						<img
							src={selectedPhoto.public_url}
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
