import { describe, expect, it } from 'vitest';
import { readPage, slicePage } from './pagination';

const ID = '22222222-2222-4222-8222-222222222222';
describe('paginacion acotada y cursores estables', () => {
	it.each(['limit=1.5', 'limit=Infinity', 'limit=101', 'limit=0', 'offset=-1', 'offset=100001', 'offset=1.5', 'cursor=incorrecto'])('rechaza %s', (query) => {
		expect(readPage(new URL(`http://localhost/?${query}`))).toBeNull();
	});
	it('conserva los microsegundos de PostgreSQL y desempata con UUID', () => {
		const cursor = `2026-11-08T12:34:56.123456+00:00|${ID}`;
		const url = new URL('http://localhost/'); url.searchParams.set('cursor', cursor);
		expect(readPage(url)).toMatchObject({ afterCreatedAt: '2026-11-08T12:34:56.123456+00:00', afterId: ID });
		url.searchParams.set('offset', '1');
		expect(readPage(url)).toBeNull();
	});
	it('no firma ni devuelve la fila lookahead y genera cursor desde la ultima visible', () => {
		const rows = [{ id: ID, created_at: '2026-11-08T12:00:00.123456Z' }, { id: 'next', created_at: '2026-11-08T12:00:00.123455Z' }];
		expect(slicePage(rows, 1)).toEqual({ items: [rows[0]], nextCursor: `${rows[0].created_at}|${ID}` });
		expect(slicePage(rows.slice(0, 1), 1).nextCursor).toBeNull();
	});
});
