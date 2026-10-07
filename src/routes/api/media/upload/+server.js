// POST /api/media/upload
// Genera una URL firmada para subir un archivo directo a R2.
// El navegador recibe { uploadUrl } y hace el PUT; luego inserta la fila en `media`.
import { json } from '@sveltejs/kit';

import { createPresignedUpload, publicUrl } from '$lib/server/r2';

const TIPOS = ['avatar', 'banner', 'photo', 'video'];

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

	const { tipo, filename, contentType, es_privado } = body;

	if (!TIPOS.includes(tipo) || !filename || !contentType) {
		return json({ error: 'Faltan campos: tipo, filename, contentType' }, { status: 400 });
	}

	const bucket = es_privado ? 'private' : 'public';
	const safeName = String(filename)
		.replace(/[^a-zA-Z0-9._-]/g, '-')
		.slice(-80);
	const storageKey = `${locals.user.id}/${crypto.randomUUID()}-${safeName}`;

	try {
		const uploadUrl = await createPresignedUpload(storageKey, bucket, contentType);
		return json({
			storage_key: storageKey,
			bucket,
			upload_url: uploadUrl,
			public_url: bucket === 'public' ? publicUrl(storageKey) : null
		});
	} catch (e) {
		console.error('upload presign error:', e);
		return json(
			{ error: e instanceof Error ? e.message : 'Error generando URL de subida' },
			{ status: 500 }
		);
	}
}
