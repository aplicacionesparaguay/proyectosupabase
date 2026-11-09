import { json } from '@sveltejs/kit';
import { createPresignedDownload } from '$lib/server/r2';
import { authFailure, verifiedUserId } from '$lib/server/media';
import { mediaServerQuery } from '$lib/server/mediaDb';
import { readPage, slicePage } from '$lib/media/pagination';

const OWNER_SELECT =
	'id, upload_status, processing_status, moderation_status, visibility, title, description, original_filename, mime_type, byte_size, width, height, faces_detected, protection_mode, protection_strength, verification_status, rejection_reason, original_deleted_at, deleted_at, created_at, thumb_key, protected_key, original_key';

/**
 * @param {string} key
 * @returns {Promise<string | null>}
 */
async function sign(key) {
	if (!key) return null;
	try {
		return await createPresignedDownload(key, 'private', 300);
	} catch {
		return null;
	}
}

/** @type {import('./$types').RequestHandler} */
export async function GET({ locals, url }) {
	const denied = authFailure(locals);
	if (denied) return denied;

	const userId = verifiedUserId(locals);
	const page = readPage(url);
	if (!page) return json({ error: 'Paginacion invalida.' }, { status: 400 });

	const { data, error } = await mediaServerQuery((db) => {
		let query = db
		.from('media_assets')
		.select(OWNER_SELECT)
		.eq('owner_id', userId)
		.is('deleted_at', null)
		.order('created_at', { ascending: false }).order('id', { ascending: false });
		if (page.afterCreatedAt && page.afterId) query = query.or(`created_at.lt.${page.afterCreatedAt},and(created_at.eq.${page.afterCreatedAt},id.lt.${page.afterId})`);
		return query.range(page.offset, page.offset + page.limit);
	});

	if (error) {
		return json({ error: 'No se pudo cargar la galeria.' }, { status: 503 });
	}

	const { items: rows, nextCursor } = slicePage(Array.isArray(data) ? data : [], page.limit);

	const items = await Promise.all(
		rows.map(async (row) => {
			let previewKey = row.thumb_key ?? row.protected_key;
			let fullKey = row.protected_key;
			let originalAvailable = false;

			if (!previewKey && row.moderation_status === 'rejected' && row.original_key) {
				const { data: allowed } = await locals.supabase.rpc('media_log_owner_original_access', {
					p_media_id: row.id
				});

				if (allowed === true) {
					previewKey = row.original_key;
					fullKey = row.original_key;
					originalAvailable = true;
				}
			}

			const [previewUrl, fullUrl] = await Promise.all([sign(previewKey), sign(fullKey)]);

			// Nunca se devuelven las claves al navegador: solo URLs firmadas de
			// vida corta. La clave queda en el servidor.
			return {
				id: row.id,
				upload_status: row.upload_status,
				processing_status: row.processing_status,
				moderation_status: row.moderation_status,
				visibility: row.visibility,
				title: row.title,
				description: row.description,
				original_filename: row.original_filename,
				mime_type: row.mime_type,
				byte_size: row.byte_size,
				width: row.width,
				height: row.height,
				faces_detected: row.faces_detected,
				protection_mode: row.protection_mode,
				protection_strength: row.protection_strength,
				verification_status: row.verification_status,
				rejection_reason: row.rejection_reason,
				original_deleted_at: row.original_deleted_at,
				created_at: row.created_at,
				previewUrl,
				fullUrl,
				originalAvailable
			};
		})
	);

	return json({ items, nextCursor }, { headers: { 'Cache-Control': 'private, no-store' } });
}
