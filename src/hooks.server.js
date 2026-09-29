// @ts-nocheck
import { redirect } from '@sveltejs/kit';
import { createSupabaseServerClient } from '$lib/server/supabase';

export const handle = async ({ event, resolve }) => {
	event.locals.supabase = createSupabaseServerClient(event.cookies);
	event.locals.session = null;
	event.locals.user = null;

	const {
		data: { user },
		error,
	} = await event.locals.supabase.auth.getUser();
	if (!error) {
		event.locals.user = user;
	}

	// La sesión se resuelve acá en el servidor y viaja al cliente vía +layout.server.js,
	// para que la UI no dependa de un fetch posterior en onMount.
	const {
		data: { session },
	} = await event.locals.supabase.auth.getSession();
	event.locals.session = session;

	const pathname = event.url.pathname;

	// Usuario logueado no necesita ver login/register
	const authPaths = ['/login', '/register'];
	if (event.locals.user && authPaths.includes(pathname)) {
		throw redirect(302, '/');
	}

	// El panel de perfil propio requiere sesión (las vistas públicas /perfil/[id] no)
	if (!event.locals.user && pathname === '/perfil') {
		throw redirect(302, '/login');
	}

	return resolve(event);
};
