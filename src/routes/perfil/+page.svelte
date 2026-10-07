<script>
	import { onMount, onDestroy } from 'svelte';
	import { browser } from '$app/environment';
	import { supabase } from '$lib/supabaseClient';
	import { session, user, logout } from '$lib/stores/auth';
	import * as faceapi from 'face-api.js';
	import {
		uploadToR2,
		deleteR2Object,
		validateImageFile,
		MAX_UPLOAD_BYTES,
		R2_FOLDERS
	} from '$lib/upload/r2Upload';

	/**
	 * Bounding box de una detección de face-api.js. El código solo usa estas
	 * cuatro propiedades (detectFaces*, pixelateRect).
	 * @typedef {Object} FaceBox
	 * @property {number} x
	 * @property {number} y
	 * @property {number} width
	 * @property {number} height
	 */

	/**
	 * Vista previa previa a la subida, con las propiedades que ya usaba el
	 * código original.
	 * @typedef {Object} Preview
	 * @property {'image' | 'video'} type
	 * @property {File} file
	 * @property {string} url
	 * @property {FaceBox[]} detections
	 * @property {string} filename
	 * @property {'album' | 'banner'} uploadTarget
	 * @property {string | null} [censoredDataUrl]
	 * @property {HTMLCanvasElement} [thumbnailCanvas]
	 */

	/**
	 * Fila de `user_photos` tal como la devuelve el select de loadPhotos().
	 * @typedef {Object} Foto
	 * @property {string} id
	 * @property {string} public_url
	 * @property {string | null} [thumbnail_url]
	 * @property {string | null} [titulo]
	 * @property {string | null} [descripcion]
	 * @property {string | null} [storage_path]
	 * @property {string | null} [filename]
	 * @property {string | null} [mime_type]
	 * @property {Comentario[]} [photo_comments]
	 */

	/**
	 * Comentario de `photo_comments`, con el join anidado `profiles` que usa el
	 * template.
	 * @typedef {Object} Comentario
	 * @property {string} [id]
	 * @property {string} comentario
	 * @property {{ nombre?: string | null } | null} [profiles]
	 */

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
	/** @type {string[]} */
	let bannerPhotos = [];
	let currentBannerIndex = 0;

	let foto = '';
	// Clave R2 del avatar actual, necesaria para poder borrarlo al reemplazarlo.
	let previousAvatarKey = '';
	let nombre = '';
	let email = '';
	let bio = '';

	let editing = false;
	let saving = false;

	// --- Avatar ---
	let avatarUploading = false;
	let avatarError = '';

	/** @type {Foto[]} */
	let photos = [];
	/** @type {Foto | null} */
	let selectedPhoto = null;
	let photoComment = '';
	/** @type {Comentario[]} */
	let photoComments = [];

	let showMenu = false;
	/** @type {HTMLElement | null} */
	let menuRef = null;
	/** @type {HTMLElement | null} */
	let buttonRef = null;
	let bannerUrl = '';

	// --- Nuevas variables para vista previa y censura ---
	/** @type {Preview | null} */
	let preview = null; // { type: 'image'|'video', file, url, detections:[], censoredDataUrl?:string, filename, uploadTarget }
	let isUploadingPreview = false;
	let uploadProgress = 0;
	let censorFaces = true; // default when user chooses to censor in preview

	// cerrar menú si click fuera
	/**
	 * @param {MouseEvent} event
	 */
	function handleClickOutside(event) {
		const target = /** @type {Node | null} */ (event.target);
		if (showMenu && menuRef && !menuRef.contains(target) && !buttonRef?.contains(target)) {
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

	// onDestroy también se ejecuta durante el render en servidor, donde `document`
	// no existe. Sin este guard la ruta /perfil devolvía 500 en SSR.
	onDestroy(() => {
		if (browser) {
			document.removeEventListener('click', handleClickOutside);
		}
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
			.select(
				`
                        id,
                        role,
                        username,
                        display_name,
                        bio,
                        avatar_key,
                        banner_key,
                        subscription_price,
                        is_verified,
                        is_banned,
                        created_at,
                        updated_at
                `
			)
			.eq('id', $session.user.id)
			.maybeSingle();

		if (error && error.code !== 'PGRST116') {
			console.error('Error loading profile:', error);
			return;
		}

		if (data) {
			nombre =
				data.display_name ||
				data.username ||
				$session.user.user_metadata?.nombre ||
				$session.user.email?.split('@')[0] ||
				'Usuario';

			email = $session.user.email || '';
			bio = data.bio || '';
			foto = data.avatar_key || '';
		} else {
			nombre =
				$session.user.user_metadata?.nombre || $session.user.email?.split('@')[0] || 'Usuario';

			email = $session.user.email || '';
			bio = '';
			foto = '';
		}
	}

	async function saveProfile() {
		if (!$session?.user) return;

		saving = true;

		try {
			const { error } = await supabase.from('profiles').upsert({
				id: $session.user.id,
				display_name: nombre || null,
				bio: bio || '',
				avatar_key: foto || null
			});

			if (error) {
				console.error('Error saving profile:', error);
				return;
			}

			// El email pertenece a Supabase Auth, no a profiles.
			// Guardamos únicamente los datos que corresponden a profiles.
			await supabase.auth.updateUser({
				data: {
					nombre: nombre || null,
					bio: bio || ''
				}
			});

			await loadProfile();
		} catch (e) {
			console.error('Error saving profile:', e);
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

	/**
	 * @param {string} path
	 * @param {string} url
	 */
	async function uploadBannerFile(path, url) {
		if (!$session?.user) return;
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
		// usa la misma lógica de preview con censura facial que el álbum
		openFileDialog(async (file) => {
			const problem = validateImageFile(file);
			if (problem) {
				alert(problem);
				return;
			}
			await preparePreviewFromFile(file, 'banner');
		}, 'image/*');
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

		// Eliminar de R2. Antes se enviaba la clave en `fileName` y el endpoint
		// exigia `key`, asi que el borrado siempre fallaba con 400.
		if (data.storage_path) {
			const deleted = await deleteR2Object(data.storage_path, R2_FOLDERS.cover);
			if (!deleted) console.warn('Error eliminando de R2, continuando con DB');
		}

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

	/**
	 * @param {string} photoId
	 */
	async function deletePhoto(photoId) {
		const photo = photos.find((p) => p.id === photoId);
		if (!photo || !$session?.user) return;

		// Eliminar de R2
		if (photo.storage_path) {
			const deleted = await deleteR2Object(photo.storage_path, R2_FOLDERS.post);
			if (!deleted) console.warn('Error eliminando de R2, continuando con DB');
		}

		await supabase.from('user_photos').delete().eq('id', photoId);
		if (selectedPhoto?.id === photoId) selectedPhoto = null;
		await loadPhotos();
	}

	/**
	 * @param {Foto} photo
	 */
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

	/**
	 * @param {string} photoId
	 * @param {Partial<Pick<Foto, 'titulo' | 'descripcion'>>} updates
	 */
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
	/**
	 * @param {(file: File) => void | Promise<void>} callback
	 * @param {string} [accept]
	 */
	function openFileDialog(callback, accept = 'image/*,video/*') {
		const fileInput = document.createElement('input');
		fileInput.type = 'file';
		fileInput.accept = accept;
		fileInput.onchange = async (e) => {
			const input = /** @type {HTMLInputElement | null} */ (e.target);
			const file = input?.files?.[0];
			if (!file) return;
			await callback(file);
		};
		fileInput.click();
	}

	// Sube archivo a R2 usando la URL prefirmada del backend.
	// La publicUrl la calcula y devuelve el servidor: el cliente nunca la arma.
	/**
	 * @param {File} file
	 * @param {string} folder una de R2_FOLDERS
	 * @returns {Promise<{ publicUrl: string, key: string }>}
	 */
	async function putToR2(file, folder) {
		return uploadToR2(file, folder, {
			onProgress: (percent) => (uploadProgress = percent)
		});
	}

	// ------------------ AVATAR ------------------

	/**
	 * Sube el avatar. Sin preview ni censura facial: pixelar el rostro
	 * anularia el proposito de una foto de perfil.
	 */
	function uploadAvatar() {
		if (!$session?.user) return;

		openFileDialog(async (file) => {
			avatarError = '';
			avatarUploading = true;

			try {
				const clientError = validateImageFile(file);
				if (clientError) throw new Error(clientError);

				const { publicUrl, key } = await putToR2(file, R2_FOLDERS.avatar);

				const { error } = await supabase
					.from('profiles')
					.update({ avatar_key: publicUrl })
					.eq('id', $session.user.id);

				if (error) throw error;

				foto = publicUrl;

				// La clave anterior solo se borra si es nuestra y del bucket publico.
				// El endpoint devuelve 403 ante cualquier otra cosa, asi que es seguro.
				const previousKey = previousAvatarKey;
				previousAvatarKey = key;

				if (previousKey && previousKey !== key) {
					await deleteR2Object(previousKey, R2_FOLDERS.avatar);
				}
			} catch (e) {
				avatarError = e instanceof Error ? e.message : String(e);
				console.error('Error subiendo avatar:', e);
			} finally {
				avatarUploading = false;
			}
		});
	}

	/** Quita el avatar: borra de R2 y limpia profiles.avatar_key. */
	async function removeAvatar() {
		if (!$session?.user || !foto) return;

		const key = previousAvatarKey;

		foto = '';
		previousAvatarKey = '';
		avatarError = '';

		const { error } = await supabase
			.from('profiles')
			.update({ avatar_key: null })
			.eq('id', $session.user.id);

		if (error) {
			avatarError = error.message;
			return;
		}

		if (key) {
			await deleteR2Object(key, R2_FOLDERS.avatar);
		}
	}

	// sube un File a storage en bucket dado; retorna { path, url } - MANTENIDO POR COMPATIBILIDAD
	/**
	 * @param {File} file
	 * @param {string} bucket
	 * @returns {Promise<{ path: string, url: string }>}
	 */
	async function uploadToStorage(file, bucket) {
		if (!$session?.user) throw new Error('No hay sesión para subir a storage');
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
	// uploadTarget: 'album' | 'banner'
	/**
	 * @param {File} file
	 * @param {'album' | 'banner'} [uploadTarget]
	 */
	async function preparePreviewFromFile(file, uploadTarget = 'album') {
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
			preview = { type, file, url, detections, censoredDataUrl, filename, uploadTarget };
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
				thumbnailCanvas: frameCanvas,
				uploadTarget
			};
		}
	}

	// función para abrir diálogo y crear preview (usada por botón "Agregar Foto/Video")
	async function handleAddMedia() {
		openFileDialog(async (file) => {
			const problem = validateImageFile(file);
			if (problem) {
				alert(problem);
				return;
			}
			await preparePreviewFromFile(file);
			// ahora preview contiene url / censoredDataUrl / detections
			// usuario puede decidir "Subir" o "Cancelar" y si quiere subir censurado o no
		}, 'image/*');
	}

	// subir la preview a R2 (imagen o video) con censura facial opcional
	// uploadTarget: 'album' | 'banner'
	async function uploadPreview(confirmCensor = false) {
		if (!preview || !$session?.user) return;
		isUploadingPreview = true;
		try {
			const target = preview.uploadTarget || 'album';
			const folder = target === 'banner' ? R2_FOLDERS.cover : R2_FOLDERS.post;

			if (preview.type === 'image') {
				const fileToUpload =
					confirmCensor && preview.censoredDataUrl
						? new File([dataURLtoBlob(preview.censoredDataUrl)], preview.filename, {
								type: 'image/png'
							})
						: preview.file;

				const { publicUrl, key } = await putToR2(fileToUpload, folder);

				if (target === 'banner') {
					// Guardar en user_banners
					await supabase.from('user_banners').insert({
						user_id: $session.user.id,
						storage_path: key,
						public_url: publicUrl,
						orden: bannerPhotos.length
					});
					await loadBannerPhotos();
					currentBannerIndex = bannerPhotos.length - 1;
				} else {
					// Guardar en user_photos (álbum)
					await supabase.from('user_photos').insert({
						user_id: $session.user.id,
						storage_path: key,
						public_url: publicUrl,
						filename: preview.filename,
						orden: photos.length,
						titulo: '',
						descripcion: '',
						mime_type: fileToUpload.type
					});
					await loadPhotos();
				}
			} else {
				// video: subir video original a R2
				const { publicUrl: videoUrl, key: videoKey } = await putToR2(preview.file, folder);

				let thumbnailUrl = null;
				if (confirmCensor && preview.censoredDataUrl) {
					// Subir thumbnail censurado a R2
					const blob = dataURLtoBlob(preview.censoredDataUrl);
					const thumbName = `thumb-${preview.filename}.png`;
					const { publicUrl: thumbUrl } = await putToR2(
						new File([blob], thumbName, { type: 'image/png' }),
						folder
					);
					thumbnailUrl = thumbUrl;
				}

				if (target === 'banner') {
					await supabase.from('user_banners').insert({
						user_id: $session.user.id,
						storage_path: videoKey,
						public_url: videoUrl,
						orden: bannerPhotos.length
					});
					await loadBannerPhotos();
					currentBannerIndex = bannerPhotos.length - 1;
				} else {
					await supabase.from('user_photos').insert({
						user_id: $session.user.id,
						storage_path: videoKey,
						public_url: videoUrl,
						filename: preview.filename,
						orden: photos.length,
						titulo: '',
						descripcion: '',
						thumbnail_url: thumbnailUrl,
						mime_type: preview.file.type
					});
					await loadPhotos();
				}
			}

			// limpiar preview y recargar
			preview = null;
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

	/**
	 * @param {string} url
	 * @returns {Promise<HTMLImageElement>}
	 */
	function loadImage(url) {
		return new Promise((resolve, reject) => {
			const img = new Image();
			img.crossOrigin = 'anonymous';
			img.onload = () => resolve(img);
			img.onerror = reject;
			img.src = url;
		});
	}

	/**
	 * @param {string} videoUrl
	 * @param {number} [seekTime]
	 * @returns {Promise<HTMLCanvasElement>}
	 */
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
						if (!ctx) {
							reject(new Error('No se pudo obtener el contexto 2D del canvas'));
							return;
						}
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
	/**
	 * @param {HTMLImageElement} imgEl
	 * @returns {Promise<FaceBox[]>}
	 */
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
	/**
	 * @param {HTMLCanvasElement} canvasEl
	 * @returns {Promise<FaceBox[]>}
	 */
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
	/**
	 * @param {HTMLImageElement} imgEl
	 * @param {FaceBox[]} boxes
	 * @param {number} [pixelSize]
	 * @returns {string}
	 */
	function pixelateImageElement(imgEl, boxes, pixelSize = 10) {
		const canvas = document.createElement('canvas');
		canvas.width = imgEl.naturalWidth || imgEl.width;
		canvas.height = imgEl.naturalHeight || imgEl.height;
		const ctx = canvas.getContext('2d');
		if (!ctx) throw new Error('No se pudo obtener el contexto 2D del canvas');
		ctx.drawImage(imgEl, 0, 0);
		// pixelate each box
		boxes.forEach((box) => {
			pixelateRect(ctx, box.x, box.y, box.width, box.height, pixelSize);
		});
		return canvas.toDataURL('image/png');
	}

	/**
	 * @param {HTMLCanvasElement} canvasEl
	 * @param {FaceBox[]} boxes
	 * @param {number} [pixelSize]
	 * @returns {string}
	 */
	function pixelateCanvas(canvasEl, boxes, pixelSize = 10) {
		const canvas = document.createElement('canvas');
		canvas.width = canvasEl.width;
		canvas.height = canvasEl.height;
		const ctx = canvas.getContext('2d');
		if (!ctx) throw new Error('No se pudo obtener el contexto 2D del canvas');
		ctx.drawImage(canvasEl, 0, 0);
		boxes.forEach((box) => {
			pixelateRect(ctx, box.x, box.y, box.width, box.height, pixelSize);
		});
		return canvas.toDataURL('image/png');
	}

	// pixelateRect helper: reduce resolution of rect and scale back
	/**
	 * @param {CanvasRenderingContext2D} ctx
	 * @param {number} x
	 * @param {number} y
	 * @param {number} w
	 * @param {number} h
	 * @param {number} pixelSize
	 */
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
		if (!tctx) throw new Error('No se pudo obtener el contexto 2D del canvas temporal');
		tctx.drawImage(ctx.canvas, x, y, w, h, 0, 0, w, h);
		// scale down
		const sw = Math.max(1, Math.floor(w / pixelSize));
		const sh = Math.max(1, Math.floor(h / pixelSize));
		const small = document.createElement('canvas');
		small.width = sw;
		small.height = sh;
		const sctx = small.getContext('2d');
		if (!sctx) throw new Error('No se pudo obtener el contexto 2D del canvas reducido');
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
	/**
	 * @param {string} dataurl
	 * @returns {Blob}
	 */
	function dataURLtoBlob(dataurl) {
		const arr = dataurl.split(',');
		const mime = /** @type {string} */ (arr[0].match(/:(.*?);/)?.[1] ?? '');
		const bstr = atob(arr[1]);
		let n = bstr.length;
		const u8arr = new Uint8Array(n);
		while (n--) u8arr[n] = bstr.charCodeAt(n);
		return new Blob([u8arr], { type: mime });
	}

	// Upload directo a R2 (sin preview, pero con censura facial automática si hay caras)
	async function uploadFileDirect() {
		openFileDialog(async (file) => {
			if (!file) return;
			if (!$session?.user) return;
			const problem = validateImageFile(file);
			if (problem) {
				alert(problem);
				return;
			}

			// Detectar caras y censurar si es imagen
			let fileToUpload = file;
			if (file.type.startsWith('image/')) {
				const url = URL.createObjectURL(file);
				const img = await loadImage(url);
				const detections = await detectFacesImageElement(img);
				if (detections && detections.length) {
					const censoredDataUrl = pixelateImageElement(img, detections, 12);
					const blob = dataURLtoBlob(censoredDataUrl);
					fileToUpload = new File([blob], file.name, { type: 'image/png' });
				}
				URL.revokeObjectURL(url);
			}

			// Subir a R2
			const { publicUrl, key } = await putToR2(fileToUpload, R2_FOLDERS.post);

			await supabase.from('user_photos').insert({
				user_id: $session.user.id,
				storage_path: key,
				public_url: publicUrl,
				filename: file.name,
				orden: photos.length,
				titulo: '',
				descripcion: '',
				mime_type: fileToUpload.type
			});
			await loadPhotos();
		}, 'image/*');
	}
</script>

<!-- Banner -->
<div class="relative h-64 w-full">
	{#if bannerPhotos.length > 0}
		<img
			src={bannerPhotos[currentBannerIndex]}
			alt="Banner"
			class="mx-auto block h-full rounded-lg object-fill object-center"
		/>
	{:else}
		<div class="absolute inset-0 flex items-center justify-center bg-gray-700 text-white">
			<button
				type="button"
				on:click={uploadBanner}
				class="rounded-lg bg-white/20 px-4 py-2 font-medium hover:bg-white/30"
			>
				Cargar portada
			</button>
		</div>
	{/if}

	<!-- Flechas -->
	<button
		on:click={prevBanner}
		class="absolute top-1/2 left-2 -translate-y-1/2 rounded-full bg-white/70 p-2 hover:bg-white"
		>◀</button
	>
	<button
		on:click={nextBanner}
		class="absolute top-1/2 right-2 -translate-y-1/2 rounded-full bg-white/70 p-2 hover:bg-white"
		>▶</button
	>

	<!-- Menú del banner -->
	<div class="absolute top-4 right-4">
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
						class="block w-full px-4 py-2 text-left hover:bg-gray-100">⬆️ Subir Portada</button
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
		<div class="mb-8 flex flex-col items-center gap-4 text-center sm:flex-row sm:text-left">
			<!-- Avatar -->
			<div class="relative shrink-0">
				{#if foto}
					<img
						src={foto}
						alt="Tu foto de perfil"
						class="h-24 w-24 rounded-full border border-gray-200 object-cover shadow"
					/>
				{:else}
					<div
						class="flex h-24 w-24 items-center justify-center rounded-full border-2 border-dashed border-gray-300 bg-gray-100 text-3xl font-bold text-gray-400"
						aria-hidden="true"
					>
						{nombre.slice(0, 1).toUpperCase()}
					</div>
				{/if}

				{#if avatarUploading}
					<div
						class="absolute inset-0 flex items-center justify-center rounded-full bg-black/50 text-xs font-medium text-white"
					>
						{uploadProgress}%
					</div>
				{/if}
			</div>

			<div class="min-w-0 flex-1">
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
					{email}
				</p>

				<div class="mt-3 flex flex-wrap justify-center gap-2 sm:justify-start">
					<button
						type="button"
						on:click={uploadAvatar}
						disabled={avatarUploading}
						class="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-blue-700 disabled:opacity-50"
					>
						{avatarUploading ? 'Subiendo...' : foto ? 'Cambiar foto' : 'Subir foto'}
					</button>

					{#if foto}
						<button
							type="button"
							on:click={removeAvatar}
							disabled={avatarUploading}
							class="rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 transition-colors hover:bg-gray-100 disabled:opacity-50"
						>
							Quitar foto
						</button>
					{/if}
				</div>

				{#if avatarError}
					<p class="mt-2 text-sm text-red-600">{avatarError}</p>
				{/if}

				<p class="mt-2 text-xs text-gray-500">
					JPG, PNG, WEBP o GIF. Máximo {MAX_UPLOAD_BYTES / (1024 * 1024)} MB.
				</p>
			</div>
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
					class="rounded-lg bg-blue-600 px-6 py-2 text-white hover:bg-blue-700">Agregar Foto</button
				>
				<button
					on:click={uploadFileDirect}
					class="rounded-lg bg-gray-200 px-4 py-2 hover:bg-gray-300"
					>Subir directo (censura automática)</button
				>
			</div>

			<!-- PREVIEW antes de subir -->
			{#if preview}
				<div class="mb-6 rounded-lg border bg-gray-50 p-4">
					<h3 class="mb-2 font-semibold">
						Vista previa — {preview.filename}
						{preview.uploadTarget === 'banner' ? '(Banner)' : '(Álbum)'}
					</h3>

					{#if isUploadingPreview && uploadProgress > 0}
						<div class="mb-4">
							<div class="mb-1 flex justify-between text-sm">
								<span>Subiendo a R2...</span>
								<span>{uploadProgress}%</span>
							</div>
							<div class="h-2 w-full rounded-full bg-gray-200">
								<div
									class="h-2 rounded-full bg-green-500 transition-all"
									style="width: {uploadProgress}%"
								></div>
							</div>
						</div>
					{/if}

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
			<div
				class="bg-opacity-75 fixed relative inset-0 z-50 flex items-center justify-center bg-black"
			>
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
									selectedPhoto &&
									updatePhotoDetails(selectedPhoto.id, { titulo: selectedPhoto.titulo })}
							/>
							<textarea
								bind:value={selectedPhoto.descripcion}
								placeholder="Descripción"
								rows="3"
								class="w-full rounded-lg border border-gray-300 px-3 py-2"
								on:input={() =>
									selectedPhoto &&
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
