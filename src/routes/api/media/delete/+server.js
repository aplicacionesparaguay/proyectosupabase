// POST /api/media/delete
// Elimina un objeto de R2 y su fila en `media`. Solo la dueña.
import { json } from '@sveltejs/kit';
import { deleteObject } from '$lib/server/r2';

/** @type {import('./$types').RequestHandler} */
export async function POST({ request, locals }) {
	if (!locals.user) {
		return json({ error: 'No autorizado' }, { status: 401 });
	}

	let body;
	try {
		body = await request.json();
	} catch {
		return json({ error: 'JSON inválido' }, { status: 400 });
	}

	const { media_id } = body;
	if (!media_id) {
		return json({ error: 'Falta media_id' }, { status: 400 });
	}

	const supabase = locals.supabase;

	const { data: media, error } = await supabase
		.from('media')
		.select('user_id, storage_key, bucket')
		.eq('id', media_id)
		.single();

	if (error || !media) {
		return json({ error: 'Contenido no encontrado' }, { status: 404 });
	}
	if (media.user_id !== locals.user.id) {
		return json({ error: 'No autorizado' }, { status: 403 });
	}

	try {
		if (media.storage_key) {
			await deleteObject(media.storage_key, media.bucket);
		}
		const { error: delErr } = await supabase.from('media').delete().eq('id', media_id);
		if (delErr) {
			return json({ error: delErr.message }, { status: 500 });
		}
		return json({ ok: true });
	} catch (e) {
		console.error('delete error:', e);
		return json({ error: e instanceof Error ? e.message : 'Error al eliminar' }, { status: 500 });
	}
}
