<script>
	import { supabase } from '$lib/supabaseClient';
	import {
		uploadToR2,
		R2_FOLDERS,
		validateImageFile,
		MAX_UPLOAD_BYTES
	} from '$lib/upload/r2Upload';

	/** @type {string} */
	export let userId = '';

	/** @type {(publicUrl: string) => void} */
	export let onUpload = () => {};

	/** @type {string} */
	export let folder = R2_FOLDERS.avatar;

	/** @type {FileList | null} */
	let files = null;

	let uploading = false;
	let error = '';
	let progress = 0;

	async function uploadPhoto() {
		const file = files?.[0];

		if (!file) {
			error = 'Selecciona un archivo';
			return;
		}

		uploading = true;
		error = '';
		progress = 0;

		try {
			// Validación de cliente para dar feedback inmediato. La autoridad
			// es el servidor: valida fileSize antes de firmar y en el commit
			// comprueba el objeto real en R2 con HeadObject.
			const clientError = validateImageFile(file);
			if (clientError) throw new Error(clientError);

			// publicUrl la calcula y devuelve el servidor con R2_PUBLIC_URL.
			const { publicUrl } = await uploadToR2(file, folder, {
				onProgress: (percent) => (progress = percent)
			});

			// Fuente canónica del avatar: profiles.avatar_key.
			// Antes se escribía en la tabla legacy `users.profile_pic`.
			const { error: updateError } = await supabase
				.from('profiles')
				.update({ avatar_key: publicUrl })
				.eq('id', userId);

			if (updateError) {
				throw updateError;
			}

			onUpload(publicUrl);
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
			console.error('UploadPhoto error:', e);
		} finally {
			uploading = false;
			progress = 0;
		}
	}
</script>

<div class="mt-4">
	<input
		type="file"
		accept="image/jpeg,image/png,image/webp,image/gif"
		bind:files
		class="mb-2 w-full rounded-lg border p-2"
	/>

	<p class="mb-2 text-xs text-gray-500">
		JPG, PNG, WEBP o GIF. Máximo {MAX_UPLOAD_BYTES / (1024 * 1024)} MB.
	</p>

	{#if uploading && progress > 0}
		<div class="mb-2">
			<div class="mb-1 flex justify-between text-sm">
				<span>Subiendo...</span>
				<span>{progress}%</span>
			</div>

			<div class="h-2 w-full rounded-full bg-gray-200">
				<div class="h-2 rounded-full bg-green-500 transition-all" style="width: {progress}%"></div>
			</div>
		</div>
	{/if}

	<button
		on:click={uploadPhoto}
		disabled={uploading}
		class="w-full rounded-lg bg-green-500 px-4 py-2 text-white disabled:opacity-50"
	>
		{uploading ? 'Subiendo...' : 'Subir Foto'}
	</button>

	{#if error}
		<p class="mt-2 text-red-500">{error}</p>
	{/if}
</div>
