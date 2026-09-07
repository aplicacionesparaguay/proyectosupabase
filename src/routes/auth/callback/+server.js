import { redirect } from '@sveltejs/kit';
import { createSupabaseServerClient } from '$lib/server/supabase';

// Intercambia el código de confirmación (email / reset de contraseña) por una sesión.
export const GET = async (event) => {
	const supabase = createSupabaseServerClient(event.cookies);

	const { searchParams, origin } = new URL(event.url);
	const code = searchParams.get('code');
	const next = searchParams.get('next') ?? '/';

	if (code) {
		const { error } = await supabase.auth.exchangeCodeForSession(code);
		if (error) {
			console.error('auth callback error:', error.message);
		}
	}

	throw redirect(303, `${origin}${next}`);
};
