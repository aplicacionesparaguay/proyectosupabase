const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;

/** @param {URL} url @param {number} [defaultLimit] */
export function readPage(url, defaultLimit = 40) {
	const limitText = url.searchParams.get('limit') ?? String(defaultLimit);
	const offsetText = url.searchParams.get('offset') ?? '0';
	if (!/^\d+$/.test(limitText) || !/^\d+$/.test(offsetText)) return null;
	const limit = Number(limitText), offset = Number(offsetText);
	if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100 || !Number.isSafeInteger(offset) || offset > 100000) return null;
	const cursor = url.searchParams.get('cursor');
	const [afterCreatedAt, afterId, extra] = cursor?.split('|') ?? [];
	if (cursor !== null && (offset !== 0 || extra !== undefined || !afterCreatedAt || !afterId
		|| !TIMESTAMP.test(afterCreatedAt) || !Number.isFinite(Date.parse(afterCreatedAt)) || !UUID.test(afterId))) return null;
	return { limit, offset, cursor, afterCreatedAt: afterCreatedAt ?? null, afterId: afterId ?? null };
}

/** @template {{id: string, created_at: string}} T @param {T[]} rows @param {number} limit */
export function slicePage(rows, limit) {
	const items = rows.slice(0, limit);
	const last = items.at(-1);
	return { items, nextCursor: rows.length > limit && last ? `${last.created_at}|${last.id}` : null };
}
