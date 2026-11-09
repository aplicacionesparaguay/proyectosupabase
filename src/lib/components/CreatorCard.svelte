<script>
	/**
	 * Tarjeta de una creadora. Enlaza al perfil público /perfil/[id].
	 *
	 * La tarjeta completa es un <a>: es un elemento interactivo
	 * nativo, por lo que llega al foco con Tab y se activa con
	 * Enter sin necesidad de on:click ni role/tabindex.
	 *
	 * PORTADA Y AVATAR SON CAMPOS INDEPENDIENTES.
	 *
	 * Antes esta tarjeta tenía un único `photoUrl` que el Home llenaba
	 * con `avatar_key ?? primerBanner`: el avatar acababa ocupando el
	 * lugar de la portada. Aquí son `coverUrl` y `avatarUrl`, y ninguno
	 * sirve de sustituto del otro. Si no hay portada, `coverUrl` es null
	 * y el Home ya ha filtrado a esa creadora fuera de la grilla; el
	 * marcador de abajo solo es una red de seguridad visual.
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
	 * @property {string | null} [coverUrl] portada (imagen principal)
	 * @property {string | null} [avatarUrl] avatar (insignia secundaria)
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
	/**
	 * Portada. Viene de `user_banners.public_url`, que es una URL
	 * permanente del bucket público. Nunca es una clave privada.
	 * @type {string | null | undefined}
	 */
	export let coverUrl = null;
	/**
	 * Avatar. Viene de `profiles.avatar_key`. Se valida como URL en el
	 * servidor antes de llegar aquí: el componente no decide si es válida.
	 * @type {string | null | undefined}
	 */
	export let avatarUrl = null;
	/** @type {boolean | null | undefined} */
	export let isVerified = false;

	$: etiqueta = (displayName || username || '').trim() || 'Creadora';

	/**
	 * Iniciales para el marcador cuando no hay avatar. Evita
	 * renderizar undefined/null.
	 * @param {string} texto
	 * @returns {string}
	 */
	function iniciales(texto) {
		const partes = texto.split(/\s+/).filter(Boolean).slice(0, 2);
		if (partes.length === 0) return 'C';
		return partes.map((p) => p[0].toUpperCase()).join('');
	}

	/**
	 * Ciudad, país, o cadena vacía. El texto de la ubicación solo se
	 * pinta cuando hay algo real que mostrar: antes salía siempre
	 * "Ubicación no disponible" incluso sin ciudad ni país.
	 * @type {string}
	 */
	$: ubicacion = [city, countryName].filter(Boolean).join(', ').trim();
</script>

<a
	href="/perfil/{id}"
	class="group relative block overflow-hidden rounded-xl border border-pink-900/40 bg-black/40 shadow-sm transition hover:-translate-y-0.5 hover:border-pink-500/60 hover:shadow-md focus:outline-none focus-visible:ring-2 focus-visible:ring-pink-400 focus-visible:ring-offset-2 focus-visible:ring-offset-black"
>
	<!-- Portada: imagen principal de la tarjeta -->
	<div class="relative aspect-[4/5] w-full overflow-hidden bg-pink-950/30">
		{#if coverUrl}
			<img
				src={coverUrl}
				alt=""
				loading="lazy"
				decoding="async"
				class="h-full w-full object-cover transition duration-300 group-hover:scale-105"
			/>
		{:else}
			<div
				aria-hidden="true"
				class="h-full w-full bg-gradient-to-br from-pink-950/40 to-purple-950/40"
			></div>
		{/if}

		<!-- Verificación: sobre la portada, esquina superior derecha -->
		{#if isVerified}
			<span
				class="absolute top-3 right-3 rounded-full bg-black/70 px-2 py-0.5 text-xs text-blue-400"
				title="Perfil verificado"
				aria-label="Perfil verificado">&#10003;</span
			>
		{/if}

		<!-- Avatar: insignia secundaria, nunca sustituye a la portada -->
		<div class="absolute bottom-3 left-3">
			{#if avatarUrl}
				<img
					src={avatarUrl}
					alt=""
					loading="lazy"
					decoding="async"
					class="h-14 w-14 rounded-full border-2 border-black bg-black object-cover shadow-lg"
				/>
			{:else}
				<div
					aria-hidden="true"
					class="flex h-14 w-14 items-center justify-center rounded-full border-2 border-black bg-gradient-to-br from-pink-900 to-purple-900 text-lg font-bold text-pink-200 shadow-lg"
				>
					{iniciales(etiqueta)}
				</div>
			{/if}
		</div>
	</div>

	<!-- Nombre y ubicación -->
	<div class="flex flex-col gap-1 p-4">
		<h3 class="font-semibold text-pink-100">
			<span class="truncate">{etiqueta}</span>
		</h3>
		{#if ubicacion}
			<p class="text-sm text-pink-200/80">{ubicacion}</p>
		{/if}
	</div>
</a>