// src/lib/authProfile.js
// Parte 1 · Registro y autenticación
// Garantiza que todo usuario autenticado tenga su fila en `profiles` con role = 'fan'.
//
// Estructura REAL de `profiles` (verificada contra la base activa):
//   id, username, display_name, role, bio, avatar_key, banner_key,
//   subscription_price, is_verified, is_banned, created_at, updated_at
// El email NO se duplica en profiles: vive en auth.users.
import { supabase } from '$lib/supabaseClient';

const FALLBACK_NAME = 'Usuario';

/**
 * Deriva un nombre legible desde la metadata de Auth o desde el email.
 * @param {import('@supabase/supabase-js').User | null | undefined} authUser
 */
export function deriveDisplayName(authUser) {
	const meta = authUser?.user_metadata ?? {};
	const candidates = [meta.display_name, meta.nombre, meta.full_name, meta.name];

	for (const candidate of candidates) {
		if (typeof candidate === 'string' && candidate.trim()) return candidate.trim();
	}

	if (typeof authUser?.email === 'string' && authUser.email.includes('@')) {
		return authUser.email.split('@')[0];
	}

	return FALLBACK_NAME;
}

/**
 * Crea la fila en `profiles` una sola vez.
 * - Si ya existe, no la toca: nunca degrada un `role` ya establecido.
 * - Si el perfil ya fue creado por el trigger de la BD, no duplica nada.
 * @param {import('@supabase/supabase-js').User | null | undefined} authUser
 */
export async function ensureProfile(authUser) {
	const id = authUser?.id;
	if (!id) return { data: null, error: new Error('No hay usuario de autenticación') };

	const { data: existing, error: readError } = await supabase
		.from('profiles')
		.select('id, role')
		.eq('id', id)
		.maybeSingle();

	if (readError) return { data: null, error: readError };
	if (existing) return { data: existing, error: null };

	const { data, error } = await supabase
		.from('profiles')
		.insert({ id, role: 'fan', display_name: deriveDisplayName(authUser) })
		.select('id, role')
		.maybeSingle();

	if (error) {
		// 23505 = unique_violation -> el perfil ya existe (trigger o doble ejecución)
		if (error.code === '23505') {
			const { data: current } = await supabase
				.from('profiles')
				.select('id, role')
				.eq('id', id)
				.maybeSingle();
			return { data: current, error: null };
		}
		return { data: null, error };
	}

	return { data, error: null };
}

/**
 * Traduce errores de Supabase Auth a mensajes claros en español.
 * @param {unknown} err
 * @param {string} [fallback]
 */
export function authErrorMessage(err, fallback = 'Ocurrió un error. Intentá de nuevo.') {
	const message = /** @type {{ message?: string } | null | undefined} */ (err)?.message || '';
	const raw = message.toLowerCase();
	if (!raw) return fallback;

	const phoneDisabled =
		(raw.includes('phone') && (raw.includes('disabled') || raw.includes('not enabled'))) ||
		raw.includes('sms provider');
	if (phoneDisabled) {
		return 'El registro por teléfono no está habilitado en Supabase por el momento. Usá email o Google.';
	}

	if (raw.includes('signups not allowed for otp')) {
		return 'Supabase no permite crear cuentas nuevas por teléfono, solo iniciar sesión de usuarios ya registrados.';
	}

	if (
		raw.includes('provider is not enabled') ||
		raw.includes('google') ||
		raw.includes('oauth')
	) {
		return 'El inicio de sesión con Google no está habilitado en Supabase todavía.';
	}

	if (
		raw.includes('already registered') ||
		raw.includes('already been registered') ||
		raw.includes('already exists')
	) {
		return 'Ese correo ya está registrado. Iniciá sesión en vez de registrarte.';
	}

	if (raw.includes('rate limit') || raw.includes('too many') || raw.includes('security purposes')) {
		return 'Demasiados intentos seguidos. Esperá un momento e intentá de nuevo.';
	}

	if (raw.includes('password should be at least') || raw.includes('at least 6 characters')) {
		return 'La contraseña debe tener al menos 6 caracteres.';
	}

	if (raw.includes('unable to validate email') || raw.includes('invalid email')) {
		return 'El formato del correo no es válido.';
	}

	if (raw.includes('token has expired') || raw.includes('otp has expired') || raw.includes('expired')) {
		return 'El código expiró. Pedí uno nuevo.';
	}

	if (raw.includes('token is invalid') || raw.includes('invalid token') || raw.includes('incorrect')) {
		return 'El código es incorrecto. Revisá e intentá de nuevo.';
	}

	if (raw.includes('email not confirmed')) {
		return 'Primero confirmá tu correo. Te enviamos el enlace.';
	}

	if (raw.includes('invalid login credentials')) {
		return 'Credenciales incorrectas. Revisá tus datos.';
	}

	return message || fallback;
}
