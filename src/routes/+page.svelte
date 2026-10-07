<script>
	import { onMount } from 'svelte';
	import { supabase } from '$lib/supabaseClient';
	import { session } from '$lib/stores/auth';
	import { goto } from '$app/navigation';
	import CreatorCard from '$lib/components/CreatorCard.svelte';

	/**
	 * @typedef {{
	 *   id: string;
	 *   username: string | null;
	 *   display_name: string | null;
	 *   role: string | null;
	 *   is_verified: boolean | null;
	 * }} Profile
	 */

	/**
	 * @typedef {{
	 *   user_id: string;
	 *   public_url: string | null;
	 *   orden: number | null;
	 * }} Banner
	 */

	/**
	 * @typedef {{
	 *   id: string;
	 *   nombre: string;
	 *   username: string;
	 *   role: string;
	 *   is_verified: boolean;
	 *   banners: string[];
	 *   currentIndex: number;
	 * }} Publicacion
	 */

	/** @type {{
	 *   id: string;
	 *   nombre: string;
	 *   username: string;
	 *   role: string;
	 *   is_verified: boolean;
	 *   banners: string[];
	 *   currentIndex: number;
	 * }[]} */
	let publicaciones = [];

	/**
	 * Datos de las creadoras públicas, resueltos en el servidor por
	 * src/routes/+page.server.js. Llega como prop `data.creadoras`.
	 *
	 * @typedef {Object} Creadora
	 * @property {string} id
	 * @property {string | null} displayName
	 * @property {string | null} username
	 * @property {string | null} city
	 * @property {string | null} countryName
	 * @property {string | null} photoUrl
	 * @property {boolean} isVerified
	 */

	/** @type {{ creadoras: Creadora[] }} */
	export let data;

	$: creadoras = data?.creadoras ?? [];

	$: logeado = $session !== null;

	async function loadProfilesWithBanners() {
		const { data: profiles, error: pErr } = await supabase
			.from('profiles')
			.select('id, username, display_name, role, is_verified')
			.order('display_name', { ascending: true });

		if (pErr) {
			console.error('Error cargando perfiles:', pErr);
			publicaciones = [];
			return;
		}

		/** @type {Profile[]} */
		const profileList = profiles ?? [];

		if (profileList.length === 0) {
			publicaciones = [];
			return;
		}

		const ids = profileList.map((p) => p.id);

		const { data: banners, error: bErr } = await supabase
			.from('user_banners')
			.select('user_id, public_url, orden')
			.in('user_id', ids)
			.order('orden', { ascending: true });

		if (bErr) {
			console.error('Error cargando banners:', bErr);
		}

		/** @type {Banner[]} */
		const bannerList = banners ?? [];

		/** @type {Record<string, string[]>} */
		const bannersByUser = {};

		for (const b of bannerList) {
			if (!bannersByUser[b.user_id]) {
				bannersByUser[b.user_id] = [];
			}

			if (b.public_url) {
				bannersByUser[b.user_id].push(b.public_url);
			}
		}

		const lista = profileList
			.map((p) => {
				const userBanners = bannersByUser[p.id] ?? [];

				if (userBanners.length === 0) {
					return null;
				}

				return {
					id: p.id,
					nombre: p.display_name || p.username || 'Usuario',
					username: p.username || '',
					role: p.role || 'fan',
					is_verified: p.is_verified || false,
					banners: userBanners,
					currentIndex: 0
				};
			})
			.filter(
				/** @returns {value is Publicacion} */
				(value) => value !== null
			);

		// Aleatorizar
		for (let i = lista.length - 1; i > 0; i--) {
			const j = Math.floor(Math.random() * (i + 1));
			[lista[i], lista[j]] = [lista[j], lista[i]];
		}

		publicaciones = lista;
	}

	/**
	 * @param {{
	 *   banners: string[];
	 *   currentIndex: number;
	 * }} pub
	 */
	function prevBanner(pub) {
		if (!pub.banners.length) return;

		pub.currentIndex = (pub.currentIndex - 1 + pub.banners.length) % pub.banners.length;

		publicaciones = publicaciones;
	}

	/**
	 * @param {{
	 *   banners: string[];
	 *   currentIndex: number;
	 * }} pub
	 */
	function nextBanner(pub) {
		if (!pub.banners.length) return;

		pub.currentIndex = (pub.currentIndex + 1) % pub.banners.length;

		publicaciones = publicaciones;
	}

	/**
	 * @param {string} id
	 */
	function verPerfil(id) {
		goto(`/perfil/${id}`);
	}

	onMount(() => {
		loadProfilesWithBanners();
	});
</script>

<section class="mx-auto w-full max-w-6xl px-4 py-10">
	<h2
		class="mb-1 bg-gradient-to-r from-pink-400 to-purple-400 bg-clip-text text-2xl font-bold text-transparent md:text-3xl"
	>
		Creadoras
	</h2>
	<p class="mb-6 text-sm text-pink-300">Perfiles disponibles en la plataforma.</p>

	{#if creadoras.length > 0}
		<ul
			class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5"
		>
			{#each creadoras as creadora (creadora.id)}
				<li>
					<CreatorCard
						id={creadora.id}
						displayName={creadora.displayName}
						username={creadora.username}
						city={creadora.city}
						countryName={creadora.countryName}
						photoUrl={creadora.photoUrl}
						isVerified={creadora.isVerified}
					/>
				</li>
			{/each}
		</ul>
	{:else}
		<p
			class="rounded-xl border border-dashed border-pink-900/40 bg-black/20 px-6 py-12 text-center text-pink-300"
		>
			No hay creadoras disponibles todavía.
		</p>
	{/if}
</section>
