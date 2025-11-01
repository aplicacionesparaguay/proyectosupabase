import { supabase } from '$lib/supabaseClient';
import { redirect } from '@sveltejs/kit';

export const handle = async ({ event, resolve }) => {
	const { data: { session } } = await supabase.auth.getSession();
	event.locals.session = session;

	// Si está logeado y va a login/register, redirige
	const protectedPaths = ['/login', '/register'];
	if (session && protectedPaths.includes(event.url.pathname)) {
		throw redirect(302, '/');
	}

	return resolve(event);
};