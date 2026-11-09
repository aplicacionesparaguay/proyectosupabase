import { error as httpError, fail } from '@sveltejs/kit';
import { requireMediaStaff } from '$lib/server/admin';
import { createPresignedDownload } from '$lib/server/r2';
import { isUuid, safeRpcMessage } from '$lib/server/media';
import { mediaServerQuery } from '$lib/server/mediaDb';
import { readPage, slicePage } from '$lib/media/pagination';

/**
 * @param {string | null | undefined} key
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

/** @type {import('./$types').PageServerLoad} */
export async function load({ locals, url, setHeaders }) {
	const { mediaRole, user } = await requireMediaStaff(locals);
	setHeaders({ 'Cache-Control': 'private, no-store', 'Referrer-Policy': 'no-referrer' });

	const page = readPage(url, 30);
	if (!page) httpError(400, 'Paginacion invalida.');
	const { limit, offset, cursor } = page;
	const { data: deadRows, error: deadError } = await locals.supabase.rpc('media_dead_jobs', { p_limit: 50 });
	const deadJobs = (Array.isArray(deadRows) ? deadRows : []).map((row) => ({
		id: row.id, kind: row.kind, media_id: row.media_id, attempts: row.attempts, max_attempts: row.max_attempts
	}));

	const { data, error } = await mediaServerQuery((db) => db.rpc('media_moderation_queue', {
		p_actor_id: user.id,
		p_limit: limit + 1,
		p_offset: offset,
		p_after_created_at: page.afterCreatedAt,
		p_after_id: page.afterId
	}));

	if (error) {
		console.error('No se pudo cargar la cola de moderacion');
		return {
			mediaRole,
			items: [],
			queueError: 'No se pudo cargar la cola de moderacion.',
			limit, offset, cursor, nextCursor: null, deadJobs, deadError: !!deadError
		};
	}

	const { items: rows, nextCursor } = slicePage(Array.isArray(data) ? data : [], limit);

	const items = await Promise.all(
		rows.map(async (row) => ({
			id: row.id,
			owner_id: row.owner_id,
			display_name: row.display_name,
			username: row.username,
			title: row.title,
			mime_type: row.mime_type,
			byte_size: row.byte_size,
			width: row.width,
			height: row.height,
			faces_detected: row.faces_detected,
			detector_name: row.detector_name,
			detector_version: row.detector_version,
			protection_mode: row.protection_mode,
			protection_strength: row.protection_strength,
			verification_status: row.verification_status,
			created_at: row.created_at,
			url: await sign(row.protected_key ?? row.thumb_key)
		}))
	);

	return { mediaRole, items, queueError: '', limit, offset, cursor, nextCursor, deadJobs, deadError: !!deadError };
}

/**
 * @param {FormData} data
 * @param {string} key
 */
function field(data, key) {
	const value = data.get(key);
	return typeof value === 'string' ? value.trim() : '';
}

export const actions = {
	retryJob: async ({ request, locals }) => {
		await requireMediaStaff(locals);
		const data = await request.formData();
		const jobId = field(data, 'job_id');
		const reason = field(data, 'reason');
		if (!isUuid(jobId) || reason.length < 3 || reason.length > 500) return fail(400, { message: 'Indica el trabajo y un motivo de 3 a 500 caracteres.' });
		const { error } = await locals.supabase.rpc('media_retry_dead_job', { p_job_id: jobId, p_reason: reason });
		return error ? fail(400, { message: safeRpcMessage(error) ?? 'No se pudo recuperar el trabajo.' })
			: { ok: true, message: 'Trabajo reencolado con auditoria.' };
	},
	approve: async ({ request, locals }) => {
		await requireMediaStaff(locals);

		const data = await request.formData();
		const mediaId = field(data, 'media_id');

		if (!isUuid(mediaId)) {
			return fail(400, { message: 'Falta la fotografia.' });
		}

		const { error } = await locals.supabase.rpc('media_approve', { p_media_id: mediaId });

		if (error) {
			const message = safeRpcMessage(error);
			if (!message) console.error('media_approve no disponible');
			return fail(400, { message: message ?? 'No se pudo aprobar la fotografia.' });
		}

		return { ok: true, message: 'Fotografia aprobada.' };
	},

	reject: async ({ request, locals }) => {
		await requireMediaStaff(locals);

		const data = await request.formData();
		const mediaId = field(data, 'media_id');
		const reason = field(data, 'reason');

		if (!isUuid(mediaId)) {
			return fail(400, { message: 'Falta la fotografia.' });
		}

		if (reason.length < 3 || reason.length > 500) {
			return fail(400, { message: 'El motivo debe tener entre 3 y 500 caracteres.' });
		}

		const { error } = await locals.supabase.rpc('media_reject', {
			p_media_id: mediaId,
			p_reason: reason
		});

		if (error) {
			const message = safeRpcMessage(error);
			if (!message) console.error('media_reject no disponible');
			return fail(400, { message: message ?? 'No se pudo rechazar la fotografia.' });
		}

		return { ok: true, message: 'Fotografia rechazada.' };
	}
};
