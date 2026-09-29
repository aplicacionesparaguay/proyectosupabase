// src/routes/+layout.server.js
// Expone al cliente la sesion que ya resolvio hooks.server.js desde las cookies.
// Asi el HTML que se renderiza en el servidor y el primer render del cliente
// coinciden, sin depender de un fetch extra en onMount.
export function load({ locals }) {
	return {
		session: locals.session,
		user: locals.user
	};
}
