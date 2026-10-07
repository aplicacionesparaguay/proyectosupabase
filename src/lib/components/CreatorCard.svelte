<script>
	/**
	 * Tarjeta de una creadora. Enlaza al perfil público /perfil/[id].
	 *
	 * La tarjeta completa es un <a>: es un elemento interactivo
	 * nativo, por lo que llega al foco con Tab y se activa con
	 * Enter sin necesidad de on:click ni role/tabindex.
	 *
	 * Cada prop se anota por separado: Svelte no admite un typedef
	 * compartido para un bloque de export let.
	 *
	 * @typedef {Object} Creadora
	 * @property {string} id
	 * @property {string | null} [displayName]
	 * @property {string | null} [username]
	 * @property {string | null} [city]
	 * @property {string | null} [countryName]
	 * @property {string | null} [photoUrl]
	 * @property {boolean | null} [isVerified]
	 */

	/** @type {string} */
	export let id;
	/** @type {string | null | undefined} */
	export let displayName = null;
	/** @type {string | null | undefined} */
	export let username = null;
	/** @type {string | null | undefined} */
	export let city = null;
	/** @type {string | null | undefined} */
	export let countryName = null;
	/** @type {string | null | undefined} */
	export let photoUrl = null;
	/** @type {boolean | null | undefined} */
	export let isVerified = false;

	$: nombre = (displayName || username || '').trim();
	$: etiqueta = nombre || 'Creadora';

	/**
	 * Iniciales para el placeholder. Evita renderizar undefined/null.
	 * @param {string} texto
	 * @returns {string}
	 */
	function iniciales(texto) {
		const partes = texto.split(/\s+/).filter(Boolean).slice(0, 2);
		if (partes.length === 0) return 'C';
		return partes.map((p) => p[0].toUpperCase()).join('');
	}

	/**
	 * Ciudad, país, o mensaje de ubicación no disponible.
	 * Nunca devuelve undefined/null/"N/A".
	 * @type {string}
	 */
	$: ubicacion = [city, countryName].filter(Boolean).join(', ').trim();
</script>

<a
	href="/perfil/{id}"
	class="group flex flex-col overflow-hidden rounded-xl border border-pink-900/40 bg-black/40 shadow-sm transition hover:-translate-y-0.5 hover:border-pink-500/60 hover:shadow-md focus:outline-none focus-visible:ring-2 focus-visible:ring-pink-400 focus-visible:ring-offset-2 focus-visible:ring-offset-black"
>
	<div class="relative aspect-[4/5] w-full overflow-hidden bg-pink-950/30">
		{#if photoUrl}
			<img
				src={photoUrl}
				alt=""
				loading="lazy"
				decoding="async"
				class="h-full w-full object-cover transition duration-300 group-hover:scale-105"
			/>
		{:else}
			<div
				aria-hidden="true"
				class="flex h-full w-full items-center justify-center bg-gradient-to-br from-pink-950/40 to-purple-950/40 text-4xl font-semibold text-pink-400"
			>
				{iniciales(etiqueta)}
			</div>
		{/if}
	</div>

	<div class="flex flex-col gap-1 p-4">
		<h3 class="flex items-center gap-1.5 font-semibold text-pink-100">
			<span class="truncate">{etiqueta}</span>
			{#if isVerified}
				<span
					class="shrink-0 text-blue-500"
					title="Perfil verificado"
					aria-label="Perfil verificado">&#10003;</span
				>
			{/if}
		</h3>

		<p class="text-sm text-pink-200/80">
			{#if ubicacion}
				{ubicacion}
			{:else}
				<span class="text-pink-300/60 italic">Ubicación no disponible</span>
			{/if}
		</p>
	</div>
</a>
