/**
 * Arnés de pruebas de seguridad para el flujo de subida.
 *
 * ARNES HEREDADO anterior a Revision 18; conservado como referencia.
 * npm run test:security ejecuta ahora las regresiones OFFLINE actuales.
 * Este arnes no acredita el contrato nuevo y requiere activacion explicita.
 *
 * Requisitos
 * ----------
 *  · Servidor local levantado (por defecto http://localhost:5173; cambiar con
 *    SECURITY_TEST_BASE).
 *  · Variables de entorno en el proceso (no hace falta que estén en .env):
 *
 *    SEG_A_EMAIL / SEG_A_PASSWORD     usuaria atacante (para aislamiento;
 *                                     debe ser `creator` para que los casos
 *                                     de propiedad midan lo que dicen)
 *    SEG_B_EMAIL / SEG_B_PASSWORD     usuaria víctima
 *    SEG_FAN_EMAIL / SEG_FAN_PASSWORD cuenta con role=fan
 *    SEG_CREATOR_EMAIL / SEG_CREATOR_PASSWORD  cuenta con role=creator
 *    SEG_BANNED_EMAIL / SEG_BANNED_PASSWORD    cuenta con is_banned=true
 *
 * Qué verifica
 * ------------
 *  1. Sin sesión, ninguna acción responde 200.
 *  2. El bucket privado no sirve objetos sin firma.
 *  3. Gate de rol `posts`: fan y baneada → 403 en upload/commit/sign/discard;
 *     creadora supera el gate (puede fallar más adelante por validación).
 *  4. Una fan no evita el gate cambiando `folder` o usando una clave de otra
 *     carpeta.
 *  5. Aislamiento entre usuarias (claves ajenas, traversal).
 *  6. Una cookie de sesion forjada en el cliente NO permite actuar como
 *     otra usuaria en upload/r2, media/delete, delete-cover ni presign.
 *  7. Cookies malformadas o caducadas se rechazan con 401.
 *  8. Las paginas publicas siguen respondiendo 200 (el hooks de verificacion
 *     no rompe el acceso anonimo).
 *
 * Sesiones
 * --------
 * El endpoint usa `@supabase/ssr` con cookies, NO el header Authorization.
 * El arnes construye la cookie `sb-<ref>-auth-token` con codificación
 * `base64-` + base64url(JSON) y comprueba con una sonda que la sesión vale
 * antes de ejecutar los casos autenticados. Si la sonda falla, los casos se
 * omiten con un mensaje claro (no se cuentan como PASS).
 *
 * Qué NO verifica
 * ---------------
 *  · Que las políticas RLS de `user_photos` estén aplicadas.
 *  · El aislamiento real entre buckets (depende de Cloudflare).
 *  · `npm run check` ni la lógica de inserción en Supabase.
 *
 * No imprime tokens, cookies ni URLs firmadas.
 */

import { S3Client, GetObjectCommand, HeadBucketCommand } from '@aws-sdk/client-s3';

if (process.env.MEDIA_LEGACY_SECURITY_TEST !== '1') {
	console.error('Arnes legacy inactivo. Usa npm run test:security para Revision 18 (offline).');
	process.exit(1);
}
const cfg = process.env;

const BASE = process.env.SECURITY_TEST_BASE ?? 'http://localhost:5173';
const PRIVATE_BUCKET = cfg.R2_PRIVATE_BUCKET;

let pass = 0;
let fail = 0;
let skip = 0;

/**
 * @param {boolean} ok
 * @param {string} name
 * @param {string} [detail]
 */
function check(ok, name, detail = '') {
	if (ok) {
		pass += 1;
		console.log(`  PASS  ${name}`);
	} else {
		fail += 1;
		console.log(`  FAIL  ${name}${detail ? ` -> ${detail}` : ''}`);
	}
}

/**
 * @param {string} name
 * @param {string} why
 */
function skipTest(name, why) {
	skip += 1;
	console.log(`  SKIP  ${name} (${why})`);
}

/**
 * Inicia sesion con la API de Supabase Auth (password grant) y devuelve la
 * carga util del token, o null.
 * @param {string} email
 * @param {string} password
 * @returns {Promise<Record<string, any> | null>}
 */
async function signIn(email, password) {
	const response = await fetch(`${cfg.PUBLIC_SUPABASE_URL}/auth/v1/token?grant_type=password`, {
		method: 'POST',
		headers: {
			apikey: cfg.PUBLIC_SUPABASE_ANON_KEY,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify({ email, password })
	});

	if (!response.ok) return null;

	return await response.json();
}

/**
 * Construye la cookie de sesion que espera `@supabase/ssr`
 * (`cookieEncoding: base64url` → prefijo `base64-`).
 *
 * @param {Record<string, any>} auth carga util de password grant
 * @returns {string} valor de Cookie completo (sin imprimirlo en logs)
 */
function buildAuthCookie(auth) {
	const ref = new URL(cfg.PUBLIC_SUPABASE_URL).hostname.split('.')[0];
	const now = Math.floor(Date.now() / 1000);
	const session = {
		access_token: auth.access_token,
		token_type: auth.token_type ?? 'bearer',
		expires_in: auth.expires_in ?? 3600,
		expires_at: auth.expires_at ?? now + (auth.expires_in ?? 3600),
		refresh_token: auth.refresh_token,
		user: auth.user
	};
	const encoded = Buffer.from(JSON.stringify(session), 'utf8').toString('base64url');
	return `sb-${ref}-auth-token=base64-${encoded}`;
}

/**
 * Llama al endpoint. `cookie` es la sesion SSR; `token` (Authorization) se
 * mantiene solo por compatibilidad con arneses antiguos.
 * @param {{ cookie?: string, token?: string } | null} auth
 * @param {Record<string, unknown>} payload
 * @param {string} [path] ruta del endpoint (por defecto /api/upload/r2)
 * @returns {Promise<{ status: number, body: any }>}
 */
async function callApi(auth, payload, path = '/api/upload/r2') {
	const headers = { 'Content-Type': 'application/json' };
	if (auth?.cookie) headers.Cookie = auth.cookie;
	if (auth?.token) headers.Authorization = `Bearer ${auth.token}`;

	const response = await fetch(`${BASE}${path}`, {
		method: 'POST',
		headers,
		body: JSON.stringify(payload)
	});

	let body = null;
	try {
		body = await response.json();
	} catch {
		body = null;
	}

	return { status: response.status, body };
}

/**
 * Comprueba que una cookie de sesion es aceptada por el endpoint.
 * Sonda con folder=avatars (fuera del gate de rol): 401 = sesion invalida.
 * @param {string} cookie
 * @returns {Promise<boolean>}
 */
async function sessionWorks(cookie) {
	const { status } = await callApi(
		{ cookie },
		{ action: 'sign', folder: 'avatars', key: 'avatars/00000000-0000-0000-0000-000000000000/x.png' }
	);
	return status !== 401;
}

/**
 * Abre sesion y distingue el motivo de fallo para informar SKIP con precision.
 * @param {string | undefined} email
 * @param {string | undefined} password
 * @returns {Promise<{ session: { cookie: string, userId: string } | null, reason: string }>}
 */
async function openSessionDetailed(email, password) {
	if (!email || !password) {
		return { session: null, reason: 'faltan variables de entorno' };
	}
	const auth = await signIn(email, password);
	if (!auth?.access_token || !auth?.user?.id) {
		return { session: null, reason: 'signIn rechazado por Supabase Auth' };
	}
	const cookie = buildAuthCookie(auth);
	if (!(await sessionWorks(cookie))) {
		return { session: null, reason: 'cookie SSR no aceptada por el endpoint' };
	}
	return { session: { cookie, userId: auth.user.id }, reason: '' };
}

console.log(`\nPruebas de seguridad · ${BASE}`);

// ---------------------------------------------------------------------
// Preflight: el servidor local tiene que estar levantado.
// ---------------------------------------------------------------------
try {
	await fetch(BASE, { method: 'GET', redirect: 'manual' });
} catch {
	console.error(
		`\nNo se pudo contactar con ${BASE}.\n` +
			'Levanta el servidor local (npm run dev) y reintenta.\n' +
			'Ninguna prueba se ejecuto.\n'
	);
	process.exit(1);
}

// ---------------------------------------------------------------------
console.log('1. Sin sesion');
// ---------------------------------------------------------------------
for (const payload of [
	{ action: 'upload', folder: 'posts', fileName: 'a.png', contentType: 'image/png', fileSize: 100 },
	{ action: 'commit', folder: 'posts', key: 'posts/alice/x.png' },
	{ action: 'sign', folder: 'posts', key: 'posts/alice/x.png' },
	{ action: 'discard', folder: 'posts', key: 'posts/alice/x.png' }
]) {
	const { status } = await callApi(null, payload);
	check(status === 401, `${payload.action} sin sesion -> 401`, `recibido ${status}`);
}

// ---------------------------------------------------------------------
console.log('\n2. Aislamiento entre buckets');
// ---------------------------------------------------------------------
{
	const r2 = new S3Client({
		region: 'auto',
		endpoint: `https://${cfg.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
		requestChecksumCalculation: 'WHEN_REQUIRED',
		credentials: {
			accessKeyId: cfg.R2_ACCESS_KEY_ID,
			secretAccessKey: cfg.R2_SECRET_ACCESS_KEY
		}
	});

	let privateExists = true;
	try {
		await r2.send(new HeadBucketCommand({ Bucket: PRIVATE_BUCKET }));
	} catch {
		privateExists = false;
	}

	check(
		privateExists,
		`el bucket privado ${PRIVATE_BUCKET} existe`,
		'crealo en Cloudflare antes de subir archivos reales'
	);

	// Un objeto privado firmado no debe ser accesible sin firma.
	if (privateExists) {
		const key = `posts/00000000-0000-0000-0000-000000000000/${crypto.randomUUID()}-prueba.png`;
		const signed = await (
			await import('@aws-sdk/s3-request-presigner')
		).getSignedUrl(r2, new GetObjectCommand({ Bucket: PRIVATE_BUCKET, Key: key }), {
			expiresIn: 300
		});

		const anon = await fetch(
			`https://${PRIVATE_BUCKET}.${cfg.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${key}`
		);
		check(
			anon.status === 400 || anon.status === 403,
			'objeto privado sin firmar -> rechazado',
			`recibido ${anon.status}`
		);

		const viaFirmada = await fetch(signed);
		check(
			viaFirmada.status === 200 || viaFirmada.status === 404,
			'la URL firmada responde (200 con objeto, 404 si no existe)'
		);
	}
}

// ---------------------------------------------------------------------
console.log('\n3. Gate de rol sobre la carpeta posts');
// ---------------------------------------------------------------------
{
	const fan = await openSessionDetailed(process.env.SEG_FAN_EMAIL, process.env.SEG_FAN_PASSWORD);
	const creator = await openSessionDetailed(
		process.env.SEG_CREATOR_EMAIL,
		process.env.SEG_CREATOR_PASSWORD
	);
	const banned = await openSessionDetailed(
		process.env.SEG_BANNED_EMAIL,
		process.env.SEG_BANNED_PASSWORD
	);

	const postsActions = [
		{ action: 'upload', folder: 'posts', fileName: 'a.png', contentType: 'image/png', fileSize: 100 },
		{ action: 'commit', folder: 'posts', key: 'posts/00000000-0000-0000-0000-000000000000/x.png' },
		{ action: 'sign', folder: 'posts', key: 'posts/00000000-0000-0000-0000-000000000000/x.png' },
		{ action: 'discard', folder: 'posts', key: 'posts/00000000-0000-0000-0000-000000000000/x.png' }
	];

	if (!fan.session) {
		skipTest('fan: 403 en las cuatro acciones de posts', `SEG_FAN_*: ${fan.reason}`);
	} else {
		for (const payload of postsActions) {
			const { status } = await callApi(fan.session, payload);
			check(status === 403, `fan ${payload.action} posts -> 403`, `recibido ${status}`);
		}

		// Evadir el gate: folder=avatars con clave de posts. El gate no corre
		// (folder != posts) pero isOwnedKey exige el prefijo de la carpeta.
		const smuggle = await callApi(fan.session, {
			action: 'sign',
			folder: 'avatars',
			key: 'posts/00000000-0000-0000-0000-000000000000/x.png'
		});
		check(
			smuggle.status === 403 || smuggle.status === 400,
			'fan no firma clave posts declarandola como avatars',
			`recibido ${smuggle.status}`
		);

		// folder=posts en cualquier orden de claves del JSON: el gate mira
		// el valor ya parseado, no el orden.
		const reordered = await callApi(fan.session, {
			key: 'posts/00000000-0000-0000-0000-000000000000/x.png',
			action: 'sign',
			fileName: 'x.png',
			folder: 'posts'
		});
		check(reordered.status === 403, 'fan sign posts con claves reordenadas -> 403', `recibido ${reordered.status}`);
	}

	if (!banned.session) {
		skipTest('baneada: 403 en upload y sign posts', `SEG_BANNED_*: ${banned.reason}`);
	} else {
		const { status } = await callApi(banned.session, postsActions[0]);
		check(status === 403, 'baneada upload posts -> 403', `recibido ${status}`);
		const sign = await callApi(banned.session, postsActions[2]);
		check(sign.status === 403, 'baneada sign posts -> 403', `recibido ${sign.status}`);
	}

	if (!creator.session) {
		skipTest('creadora: supera el gate de rol', `SEG_CREATOR_*: ${creator.reason}`);
	} else {
		// Debe pasar la autorizacion de rol. Otros errores (400 por tipo,
		// 503 sin bucket, etc.) demuestran que NO vino del gate 403.
		const { status } = await callApi(creator.session, postsActions[2]);
		check(
			status !== 401 && status !== 403,
			'creadora sign posts supera el gate (no 401/403)',
			`recibido ${status}`
		);
		const up = await callApi(creator.session, postsActions[0]);
		check(
			up.status !== 401 && up.status !== 403,
			'creadora upload posts supera el gate (no 401/403)',
			`recibido ${up.status}`
		);
	}
}

// ---------------------------------------------------------------------
console.log('\n4. Aislamiento entre usuarias (requiere credenciales de prueba)');
// ---------------------------------------------------------------------
const emailA = process.env.SEG_A_EMAIL;
const passA = process.env.SEG_A_PASSWORD;
const emailB = process.env.SEG_B_EMAIL;
const passB = process.env.SEG_B_PASSWORD;

if (!emailA || !passA || !emailB || !passB) {
	skipTest(
		'ataque cruzado A -> B',
		'faltan SEG_A_EMAIL/SEG_A_PASSWORD/SEG_B_EMAIL/SEG_B_PASSWORD'
	);
} else {
	const sessionA = await openSessionDetailed(emailA, passA);
	const sessionB = await openSessionDetailed(emailB, passB);

	if (!sessionA.session || !sessionB.session) {
		skipTest(
			'ataque cruzado A -> B',
			`A: ${sessionA.session ? 'ok' : sessionA.reason} · B: ${sessionB.session ? 'ok' : sessionB.reason}` +
				'; SEG_A debe ser creator para que el gate de posts no rehaga el caso con 403'
		);
	} else {
		const idB = sessionB.session.userId;
		const claveB = `posts/${idB}/archivo-de-b.png`;

		const signB = await callApi(sessionA.session, { action: 'sign', folder: 'posts', key: claveB });
		check(signB.status === 403, 'A no puede firmar la clave de B', `recibido ${signB.status}`);

		const discardB = await callApi(sessionA.session, { action: 'discard', folder: 'posts', key: claveB });
		check(discardB.status === 403, 'A no puede descartar la clave de B', `recibido ${discardB.status}`);

		const commitB = await callApi(sessionA.session, { action: 'commit', folder: 'posts', key: claveB });
		check(
			commitB.status === 403,
			'A no puede confirmar (sobrescribir) la clave de B',
			`recibido ${commitB.status}`
		);

		const traversal = await callApi(sessionA.session, {
			action: 'sign',
			folder: 'posts',
			key: `posts/${idB}/../../avatars/${idB}/x.png`
		});
		check(
			traversal.status === 403,
			'A no puede salir del prefijo con ..',
			`recibido ${traversal.status}`
		);
	}
}

// ---------------------------------------------------------------------
// 5. Sesion manipulada: cookie de sesion forjada en el cliente.
//
// No usa credenciales: fabrica la cookie `sb-<ref>-auth-token` con un JWT
// que afirma ser otra usuaria (sub = victim) y expiracion futura. El SDK
// instalado (getSession) solo mira la cookie, asi que SIN verificacion de
// identidad en el servidor esta sesion se aceptaria y las operaciones se
// ejecutarian con el id de la victima. Cada caso exige 401.
// ---------------------------------------------------------------------
console.log('\n5. Sesion manipulada (cookie forjada, sin credenciales)');

const VICTIM_ID = '11111111-1111-1111-1111-111111111111';

/**
 * Construye una cookie de sesion completamente fabricada en el cliente.
 * @param {string} userId id que se quiere suplantar
 * @param {{ expired?: boolean }} [opts] expired=true fuerza un refresh fallido
 * @returns {string}
 */
function forgeAuthCookie(userId, opts = {}) {
	const ref = new URL(cfg.PUBLIC_SUPABASE_URL).hostname.split('.')[0];
	const now = Math.floor(Date.now() / 1000);
	const exp = opts.expired ? now - 3600 : now + 3600;
	const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
	const payload = Buffer.from(
		JSON.stringify({
			sub: userId,
			exp,
			iat: now - 3600,
			aud: 'authenticated',
			role: 'authenticated',
			session_id: crypto.randomUUID(),
			iss: 'supabase-forjado'
		})
	).toString('base64url');
	const token = `${header}.${payload}.${Buffer.from('firma-invalida').toString('base64url')}`;
	const session = {
		access_token: token,
		refresh_token: 'refresh-forjado',
		expires_in: 3600,
		expires_at: exp,
		token_type: 'bearer',
		user: {
			id: userId,
			aud: 'authenticated',
			role: 'authenticated',
			email: 'forjada@ejemplo.test',
			user_metadata: {},
			app_metadata: {},
			created_at: new Date().toISOString()
		}
	};
	return `sb-${ref}-auth-token=base64-${Buffer.from(JSON.stringify(session)).toString('base64url')}`;
}

const forged = { cookie: forgeAuthCookie(VICTIM_ID) };

const forgedCases = [
	['sign avatars con id de la victima', '/api/upload/r2', { action: 'sign', folder: 'avatars', key: `avatars/${VICTIM_ID}/x.png` }],
	['discard avatars con id de la victima', '/api/upload/r2', { action: 'discard', folder: 'avatars', key: `avatars/${VICTIM_ID}/no-existe-${crypto.randomUUID()}.png` }],
	['upload posts con id de la victima', '/api/upload/r2', { action: 'upload', folder: 'posts', fileName: 'a.png', contentType: 'image/png', fileSize: 100 }],
	['sign posts con id de la victima', '/api/upload/r2', { action: 'sign', folder: 'posts', key: `posts/${VICTIM_ID}/x.png` }],
	['media/delete con id de la victima', '/api/media/delete', { photo_id: crypto.randomUUID() }],
	['media/delete-cover con id de la victima', '/api/media/delete-cover', { banner_id: crypto.randomUUID() }],
	['media/presign con id de la victima', '/api/media/presign', { media_id: crypto.randomUUID() }]
];

for (const [name, path, payload] of forgedCases) {
	const { status } = await callApi(forged, payload, path);
	check(status === 401, `${name} -> 401`, `recibido ${status}`);
}

// ---------------------------------------------------------------------
// 6. Sesiones invalidas: cookie malformada y caducada.
// ---------------------------------------------------------------------
console.log('\n6. Sesiones invalidas');

{
	const ref6 = new URL(cfg.PUBLIC_SUPABASE_URL).hostname.split('.')[0];
	const malformed = { cookie: `sb-${ref6}-auth-token=base64-no-es-json` };
	const { status: s1 } = await callApi(malformed, {
		action: 'sign',
		folder: 'avatars',
		key: `avatars/${VICTIM_ID}/x.png`
	});
	check(s1 === 401, 'cookie malformada -> 401', `recibido ${s1}`);

	const expired = { cookie: forgeAuthCookie(VICTIM_ID, { expired: true }) };
	const { status: s2 } = await callApi(expired, {
		action: 'sign',
		folder: 'avatars',
		key: `avatars/${VICTIM_ID}/x.png`
	});
	check(s2 === 401, 'sesion caducada con refresh invalido -> 401', `recibido ${s2}`);
}

// ---------------------------------------------------------------------
// 7. Operaciones publicas: las paginas publicas siguen respondiendo.
// (Si el hooks de verificacion rompiera el acceso publico, esto falla.)
// ---------------------------------------------------------------------
console.log('\n7. Operaciones publicas');

for (const route of ['/', '/login', '/register', '/terminos']) {
	try {
		const response = await fetch(`${BASE}${route}`, { redirect: 'manual' });
		check(
			response.status === 200,
			`GET ${route} publico -> 200`,
			`recibido ${response.status}`
		);
	} catch (e) {
		check(false, `GET ${route} publico -> 200`, `error de red: ${e instanceof Error ? e.message : e}`);
	}
}

// ---------------------------------------------------------------------
console.log(`\nResumen: ${pass} PASS · ${fail} FAIL · ${skip} SKIP\n`);
process.exit(fail > 0 ? 1 : 0);
