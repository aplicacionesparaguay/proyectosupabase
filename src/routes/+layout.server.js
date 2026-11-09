// src/routes/+layout.server.js
// Expone al cliente la sesion que ya resolvio hooks.server.js desde las cookies.
// Asi el HTML que se renderiza en el servidor y el primer render del cliente
// coinciden, sin depender de un fetch extra en onMount.
import { resolveAdminRole, resolveMediaRole } from '$lib/server/admin';

export async function load({ locals }) {
	// El rol administrativo se resuelve en el servidor, con la sesion de la
	// persona. Si la funcion `my_admin_role()` todavia no existe en la base,
	// el resultado es null y el menu de administracion no aparece: el panel
	// queda cerrado, nunca abierto.
	const adminRole = locals.user ? await resolveAdminRole(locals) : null;
	const mediaRole = locals.user ? await resolveMediaRole(locals) : null;

	return {
		session: locals.session,
		user: locals.user,
		adminRole,
		mediaRole
	};
}
