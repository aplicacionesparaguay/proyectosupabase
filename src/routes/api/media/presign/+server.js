// POST /api/media/presign
// Devuelve una URL firmada para ver contenido privado (paywall).
// Solo la dueña del contenido o sus suscriptoras activas pueden obtenerla.
import { json } from '@sveltejs/kit';
import { createPresignedDownload } from '$lib/server/r2';

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
		.select('user_id, storage_key, bucket, es_privado')
		.eq('id', media_id)
		.single();

	if (error || !media) {
		return json({ error: 'Contenido no encontrado' }, { status: 404 });
	}

	// Contenido público: se sirve por URL pública, no hace falta firmar.
	if (!media.es_privado && media.bucket !== 'private') {
		return json({ public_url: true, url: null });
	}

	const isOwner = media.user_id === locals.user.id;
	if (!isOwner) {
		const { data: sub } = await supabase
			.from('suscripciones')
			.select('id')
			.eq('creator_id', media.user_id)
			.eq('subscriber_id', locals.user.id)
			.eq('status', 'activa')
			.maybeSingle();

		if (!sub) {
			return json({ error: 'Debes ser suscriptora para ver este contenido' }, { status: 403 });
		}
	}

	try {
		const url = await createPresignedDownload(media.storage_key, media.bucket);
		return json({ url });
	} catch (e) {
		console.error('presign error:', e);
		return json({ error: e instanceof Error ? e.message : 'Error generando URL' }, { status: 500 });
	}
}
