/**
 * Carga SSR del listado público de CREADORAS para el Home.
 *
 * Se ejecuta en el servidor usando `locals.supabase` (creado en
 * src/hooks.server.js). NO se importa $lib/supabaseClient: ese
 * cliente es exclusivamente de navegador.
 *
 * RLS: la política pública de `profiles` ya permite esta lectura.
 * Este módulo nunca pide `select('*')`: pide columna por columna
 * para no arrastrar subscription_price, is_banned ni datos de admin.
 *
 * NOTA SOBRE LOS STRINGS DE SELECT: van escritos a mano y no se
 * arman con .join() a propósito. supabase-js deduce los tipos de la
 * columna devuelta solo si puede parsear el literal; con un string
 * dinámico degrada todo el resultado a un tipo de error genérico.
 */

import { dev } from '$app/environment';

/** Máximo de creadoras devueltas al Home. */
const LIMIT = 24;

/**
 * Códigos de error con los que PostgREST/Postgres reports que una
 * columna del select no existe.
 *
 * Verificado contra este proyecto: pedir `country_code` antes de
 * aplicar supabase-part3-creators.sql responde
 *   HTTP 400 {"code":"42703","message":"column profiles.country_code does not exist"}
 * que es el código nativo de Postgres (undefined_column).
 * PGRST204 es la forma que usa PostgREST cuando el fallo ocurre en
 * el schema cache. Se aceptan ambos porque la respuesta depende de
 * la versión de PostgREST del proyecto.
 */
const MISSING_COLUMN_CODES = new Set(['PGRST204', '42703']);

/**
 * Forma pública de una creadora que consume CreatorCard.
 * @typedef {Object} Creadora
 * @property {string} id
 * @property {string | null} displayName
 * @property {string | null} username
 * @property {string | null} city
 * @property {string | null} countryName
 * @property {string | null} photoUrl
 * @property {boolean} isVerified
 */

/**
 * Fila de `profiles` usada por la tarjeta.
 *
 * country_code y city son opcionales a propósito: se.selected de
 * forma distinta según la migración esté aplicada o no, y ambos
 * resultados son compatibles con esta forma.
 *
 * @typedef {Object} CreadoraRow
 * @property {string} id
 * @property {string | null} [display_name]
 * @property {string | null} [username]
 * @property {boolean | null} [is_verified]
 * @property {string | null} [avatar_key]
 * @property {string | null} [country_code]
 * @property {string | null} [city]
 */

/**
 * Una URL utilizable para <img src>. Filtra valores vacíos y null/undefined,
 * y descarta restos no-URL que quedaron guardados en la base de datos cuando
 * el cliente armaba la URL pública con una variable de entorno inexistente.
 * La URL pública correcta la calcula hoy el servidor en
 * /api/upload/r2 a partir de R2_PUBLIC_URL.
 * @param {string | null | undefined} value
 * @returns {string | null}
 */
function usableUrl(value) {
	if (typeof value !== 'string') return null;
	const trimmed = value.trim();
	return /^https?:\/\//i.test(trimmed) ? trimmed : null;
}

/** @type {import('./$types').PageServerLoad} */
export async function load({ locals }) {
	// 1) Creadoras. Columnas explícitas, nunca '*'.
	//    Ni email, ni teléfono, ni subscription_price, ni is_banned.
	const primary = await locals.supabase
		.from('profiles')
		.select(
			'id, display_name, username, role, is_verified, avatar_key, country_code, city, created_at'
		)
		.eq('role', 'creator')
		.order('created_at', { ascending: false })
		.limit(LIMIT);

	/** @type {CreadoraRow[] | null} */
	let creatorRows = primary.data;

	if (primary.error) {
		// La columna aún no existe: ocurre mientras
		// supabase-part3-creators.sql no se haya ejecutado. Se
		// reintenta sin city/country_code para no romper el Home.
		if (primary.error.code && MISSING_COLUMN_CODES.has(primary.error.code)) {
			const fallback = await locals.supabase
				.from('profiles')
				.select('id, display_name, username, role, is_verified, avatar_key, created_at')
				.eq('role', 'creator')
				.order('created_at', { ascending: false })
				.limit(LIMIT);

			if (fallback.error) {
				console.error('Error cargando creadoras:', fallback.error);
				return { creadoras: [] };
			}

			creatorRows = fallback.data;
		} else {
			console.error('Error cargando creadoras:', primary.error);
			return { creadoras: [] };
		}
	}

	const rows = creatorRows ?? [];

	if (rows.length === 0) {
		return { creadoras: [] };
	}

	const ids = rows.map((row) => row.id);

	// 2) Catálogo de países. Tabla pública y diminuta: una sola
	//    consulta arma el mapa código -> nombre. Se evita el embed
	//    countries(name) porque PostgREST no reconoce la relación
	//    hasta que exista la FK, y hasta que se recargue su schema
	//    cache. Con este mapa el Home funciona igual antes y después
	//    de la migración.
	const countryQuery = await locals.supabase.from('countries').select('code, name');

	if (countryQuery.error && dev) {
		console.error('Error cargando countries:', countryQuery.error);
	}

	/** @type {Map<string, string>} */
	const countryByCode = new Map();

	for (const row of countryQuery.data ?? []) {
		countryByCode.set(row.code, row.name);
	}

	// 3) Foto de cada creadora: una sola consulta para todas.
	//    Se asocia el primer banner por orden. Sin N+1.
	const bannerQuery = await locals.supabase
		.from('user_banners')
		.select('user_id, public_url, orden')
		.in('user_id', ids)
		.order('orden', { ascending: true });

	if (bannerQuery.error && dev) {
		console.error('Error cargando banners de creadoras:', bannerQuery.error);
	}

	/** @type {Map<string, string>} */
	const firstBannerByUser = new Map();

	for (const row of bannerQuery.data ?? []) {
		if (firstBannerByUser.has(row.user_id)) continue;
		const url = usableUrl(row.public_url);
		if (url) firstBannerByUser.set(row.user_id, url);
	}

	// 4) Proyección a la forma que consume CreatorCard.
	//    Solo campos públicos: nada de email, subscription_price,
	//    is_banned ni información de creator_requests/admin_users.
	/** @type {Creadora[]} */
	const creadoras = rows.map((row) => ({
		id: row.id,
		displayName: row.display_name ?? null,
		username: row.username ?? null,
		city: row.city ?? null,
		countryName: row.country_code ? (countryByCode.get(row.country_code) ?? null) : null,
		photoUrl: usableUrl(row.avatar_key) ?? firstBannerByUser.get(row.id) ?? null,
		isVerified: row.is_verified === true
	}));

	return { creadoras };
}
