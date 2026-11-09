import { json } from '@sveltejs/kit';
import { createPresignedDownload } from '$lib/server/r2';
import { isUuid } from '$lib/server/media';
import { mediaServerQuery } from '$lib/server/mediaDb';
import { readPage, slicePage } from '$lib/media/pagination';

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
export async function GET({ url, locals }) {
	const userId = url.searchParams.get('user_id');

	if (!isUuid(userId)) {
		return json({ error: 'Falta el perfil solicitado.' }, { status: 400 });
	}

	const page = readPage(url);
	if (!page) return json({ error: 'Paginacion invalida.' }, { status: 400 });

	const { data, error } = await mediaServerQuery((db) => db.rpc('public_media_list', {
		p_user_id: userId,
		p_limit: page.limit + 1,
		p_offset: page.offset,
		p_after_created_at: page.afterCreatedAt,
		p_after_id: page.afterId
	}));

	if (error) {
		return json({ error: 'La galeria publica no esta disponible.' }, { status: 503 });
	}

	const { items: rows, nextCursor } = slicePage(Array.isArray(data) ? data : [], page.limit);

	const items = await Promise.all(
		rows.map(async (row) => {
			const previewKey = row.thumb_key ?? row.protected_key;
			const [thumbUrl, fullUrl] = await Promise.all([sign(previewKey), sign(row.protected_key)]);

			return {
				id: row.id,
				owner_id: row.owner_id,
				title: row.title,
				description: row.description,
				mime_type: row.mime_type,
				width: row.width,
				height: row.height,
				created_at: row.created_at,
				previewUrl: thumbUrl,
				fullUrl
			};
		})
	);

	return json({ items, nextCursor }, { headers: { 'Cache-Control': 'private, no-store' } });
}
