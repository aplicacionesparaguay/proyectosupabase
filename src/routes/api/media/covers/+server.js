import { json } from '@sveltejs/kit';
import { isUuid } from '$lib/server/media';
import { coverItems } from '$lib/server/profileImages';

/** @type {import('./$types').RequestHandler} */
export async function GET({ url, locals }) {
	const userId = url.searchParams.get('user_id');
	if (!isUuid(userId)) return json({ error: 'Perfil invalido.' }, { status: 400 });
	const viewerId = locals.auth?.status === 'verified' ? locals.auth.userId : null;
	const { items, error } = await coverItems(/** @type {string} */ (userId), viewerId);
	return error ? json({ error: 'No se pudieron cargar las portadas.' }, { status: 503 })
		: json({ items }, { headers: { 'Cache-Control': 'private, no-store' } });
}
