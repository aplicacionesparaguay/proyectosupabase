import { createServerClient } from '@supabase/ssr';
import { redirect } from '@sveltejs/kit';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';

/**
 * Cache de identidades verificadas: access_token -> { userId, exp }.
 *
 * `getSession()` solo lee la cookie instalada (auth-js 2.115.0,
 * `__loadSession`): NO valida la firma del JWT ni consulta al servidor de
 * Auth. Para no pagar una verificacion remota en cada peticion, cada token
 * nuevo se verifica UNA vez y el resultado se reutiliza mientras dure su
 * vigencia. Solo se cachean resultados VERIFICADOS: los invalidos y los
 * errores se reevaluan en la siguiente peticion (permiten recuperacion).
 *
 * @type {Map<string, { userId: string, exp: number }>}
 */
const verifiedTokens = new Map();
const MAX_VERIFIED_TOKENS = 500;

/**
 * Clasifica un fallo de verificacion:
 *
 *  - 'invalid': Auth rechazo el token (4xx, JWT invalido, refresh caducado).
 *    No es temporal: el cliente debe volver a iniciar sesion → 401.
 *  - 'error': fallo temporal (red, 5xx, 429). NUNCA autoriza y tampoco se
 *    convierte en sesion autenticada → 503.
 *
 * @param {any} err
 * @returns {'invalid' | 'error'}
 */
function classifyAuthError(err) {
	if (!err) return 'invalid';

	const status = typeof err.status === 'number' ? err.status : undefined;
	if (status !== undefined) {
		if (status >= 500 || status === 429) return 'error';
		if (status >= 400 && status < 500) return 'invalid';
	}

	if (
		err.name === 'AuthRetryableFetchError' ||
		err.name === 'TypeError' ||
		err instanceof TypeError
	) {
		return 'error';
	}

	return 'invalid';
}

/**
 * Verifica la identidad del access_token de una sesion leida de la cookie.
 *
 * Usa `getClaims()` de la version instalada (auth-js 2.115.0). Comportamiento
 * REAL de esa version (verificado en el codigo fuente instalado):
 *
 *  - Decodifica y valida `exp`.
 *  - Si el JWT es asimetrico (RS256/ES256 con `kid`), verifica la firma en
 *    local con la JWKS del proyecto → sin llamada de red por peticion.
 *  - Si es simetrico (HS256, la configuracion por defecto; este proyecto usa
 *    clave `sb_publishable_` y no expone secreto JWT en el entorno, asi que
 *    no podemos firmar/localmente) delega en `getUser(token)`, que consulta
 *    al servidor de Auth. En ambos caminos el `sub` resultante es autentico.
 *
 * Un resultado 'verified' solo se emite con un `sub` con forma de UUID.
 *
 * @param {import('@supabase/supabase-js').SupabaseClient} supabase
 * @param {import('@supabase/supabase-js').Session} session
 * @returns {Promise<{ status: 'verified' | 'invalid' | 'error', userId: string | null }>}
 */
async function verifySessionIdentity(supabase, session) {
	const token = session.access_token;
	if (typeof token !== 'string' || token.length === 0) {
		return { status: 'invalid', userId: null };
	}

	const cached = verifiedTokens.get(token);
	if (cached) {
		// Margen de 30 s para no servir un token a punto de caducar.
		if (cached.exp * 1000 > Date.now() + 30_000) {
			return { status: 'verified', userId: cached.userId };
		}
		verifiedTokens.delete(token);
	}

	try {
		const { data, error } = await supabase.auth.getClaims(token);

		if (error || !data?.claims) {
			return { status: classifyAuthError(error), userId: null };
		}

		const sub = data.claims.sub;
		if (typeof sub !== 'string' || !/^[0-9a-f-]{36}$/i.test(sub)) {
			return { status: 'invalid', userId: null };
		}

		const exp =
			typeof data.claims.exp === 'number'
				? data.claims.exp
				: Math.floor(Date.now() / 1000) + 60;

		verifiedTokens.set(token, { userId: sub, exp });

		if (verifiedTokens.size > MAX_VERIFIED_TOKENS) {
			const nowSec = Math.floor(Date.now() / 1000);
			for (const [key, entry] of verifiedTokens) {
				if (entry.exp <= nowSec) verifiedTokens.delete(key);
			}
			while (verifiedTokens.size > MAX_VERIFIED_TOKENS) {
				const oldest = verifiedTokens.keys().next().value;
				if (oldest === undefined) break;
				verifiedTokens.delete(oldest);
			}
		}

		return { status: 'verified', userId: sub };
	} catch (err) {
		// `getClaims()` relanza los errores que no son de Auth (p. ej. fallo
		// de red al consultar al servidor): es un problema temporal.
		return { status: classifyAuthError(err), userId: null };
	}
}

export const handle = async ({ event, resolve }) => {
	event.locals.supabase = createServerClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
		cookies: {
			getAll: () => event.cookies.getAll(),
			setAll: (cookiesToSet) => {
				cookiesToSet.forEach(({ name, value, options }) => {
					event.cookies.set(name, value, { ...options, path: '/' });
				});
			}
		}
	});

	// Lectura de la cookie (con renovacion si el token caduco). Esto NO
	// verifica la identidad: solo obtiene el contenido de la cookie.
	const {
		data: { session },
		error: sessionError
	} = await event.locals.supabase.auth.getSession();

	/**
	 * @type {{ status: 'none' | 'verified' | 'invalid' | 'error', userId: string | null }}
	 */
	let auth = { status: 'none', userId: null };

	if (session?.access_token) {
		const verified = await verifySessionIdentity(event.locals.supabase, session);
		auth = { status: verified.status, userId: verified.userId };
	} else if (sessionError) {
		// Habia cookie pero la lectura/renovacion fallo (refresh rechazado
		// o red caida): no hay sesion utilizable; se distingue el motivo.
		auth = { status: classifyAuthError(sessionError), userId: null };
	}

	// Contrato de locals:
	//
	//  · `session` y `user` solo existen con identidad VERIFICADA. El id que
	//    se expone es SIEMPRE el `sub` confirmado por Auth, nunca el campo
	//    `user.id` de la cookie (que podria haberse manipulado).
	//  · Una sesion invalida o un fallo temporal NUNCA se expone como
	//    sesion autenticada (fallo cerrado). El motivo sigue disponible en
	//    `locals.auth.status` para que los endpoints respondan 401 vs 503.
	//  · `getSession()` conserva su firma pero devuelve la sesion ya
	//    verificada, de modo que cualquier consumidor que la consulte sin
	//    mirar `auth` tambien quede protegido.
	const verifiedSession =
		auth.status === 'verified' && session && auth.userId
			? { ...session, user: { ...session.user, id: auth.userId } }
			: null;

	event.locals.auth = auth;
	event.locals.session = verifiedSession;
	event.locals.user = verifiedSession?.user ?? null;
	event.locals.getSession = async () => event.locals.session;

	const protectedPaths = ['/login', '/register'];

	if (event.locals.session && protectedPaths.includes(event.url.pathname)) {
		throw redirect(302, '/');
	}

	return resolve(event);
};
