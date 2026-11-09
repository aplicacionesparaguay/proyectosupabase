import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Revision ESTATICA: no conecta, no ejecuta SQL y no acredita RLS en PostgreSQL.
const sql = readFileSync(new URL('../supabase-media-pipeline.sql', import.meta.url), 'utf8');
const functions = new Map([...sql.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)\(([\s\S]*?)\)\s+RETURNS([\s\S]*?)AS \$\$([\s\S]*?)\$\$;/g)]
	.map((m) => [m[1], { args: m[2], options: m[3], body: m[4] }]));
const grants = [...sql.matchAll(/GRANT EXECUTE ON FUNCTION public\.(\w+)\([^;]*?\) TO ([^;]+);/g)]
	.map((m) => ({ name: m[1], roles: m[2].split(/,\s*/) }));

/** @param {string} name */
function definition(name) {
	const found = functions.get(name);
	if (!found) throw new Error(`Falta funcion SQL: ${name}`);
	return found;
}

describe('contrato SQL preparado (analisis estatico, sin ejecutar)', () => {
	it('todos los definers fijan un search_path seguro', () => {
		expect(functions.size).toBeGreaterThan(15);
		for (const f of functions.values()) if (/SECURITY DEFINER/.test(f.options)) {
			expect(f.options).toMatch(/SET search_path = pg_catalog, public/);
		}
	});
	it('los dos guards de staff rechazan explicitamente NULL', () => {
		for (const name of ['media_require_staff', 'media_require_actor_staff']) {
			expect(definition(name).body).toMatch(/v_role IS NULL OR v_role NOT IN/);
		}
	});
	it('ninguna RPC de claves/metadatos confiables tiene EXECUTE de navegador', () => {
		for (const name of ['media_create_upload_intent', 'media_commit_upload', 'public_media_list', 'media_moderation_queue', 'media_staff_list_owner_media', 'media_prepare_profile_image', 'media_commit_profile_image']) {
			expect(grants.filter((g) => g.name === name).map((g) => g.roles)).toEqual([['service_role']]);
		}
	});
	it('se cierran sobrecargas antiguas y los grants por columna', () => {
		expect(sql).toMatch(/p\.oid::regprocedure/);
		expect(sql).toMatch(/REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role/);
		expect(sql).toMatch(/REVOKE SELECT \(%1\$s\), INSERT/);
		expect(sql).toMatch(/AS RESTRICTIVE FOR ALL TO anon, authenticated USING \(false\) WITH CHECK \(false\)/);
		expect(sql).not.toMatch(/GRANT SELECT ON TABLE public\.(media_assets|media_upload_intents) TO authenticated/);
	});
	it('commit comprueba creadora activa, tamano exacto y limite de pixeles', () => {
		const f = definition('media_commit_upload');
		expect(f.args).toMatch(/p_actor_id\s+uuid/);
		expect(f.body).toMatch(/media_is_active_creator\(v_uid\)/);
		expect(f.body).toMatch(/p_byte_size <> v_intent.declared_size/);
		expect(f.body).toMatch(/p_width::bigint \* p_height::bigint > 50000000/);
	});
	it('se registra limpieza diferida antes de devolver la intencion de PUT', () => {
		const body = definition('media_create_upload_intent').body;
		expect(body.indexOf('INSERT INTO public.storage_objects')).toBeLessThan(body.indexOf('RETURN jsonb_build_object'));
		expect(body).toMatch(/v_expires \+ interval '5 minutes'/);
		expect(body).toMatch(/pg_advisory_xact_lock/);
	});
	it('no publica portadas con visibilidad desconocida y limita policies heredadas', () => {
		expect(sql).toMatch(/SET visibilidad = 'privado'\s+WHERE visibilidad IS NULL/);
		expect(sql).toMatch(/visibilidad SET DEFAULT 'privado'/);
		expect(sql).toMatch(/AS RESTRICTIVE FOR SELECT TO anon, authenticated/);
	});
	it('listado y contador publico excluyen cuentas inactivas', () => {
		for (const name of ['public_media_list', 'public_approved_media_count']) {
			expect(definition(name).body).toContain('public.media_is_active_creator(a.owner_id)');
		}
	});
	it('paginacion usa tuplas con desempate y las revisiones usan bloqueo de fila', () => {
		expect(definition('public_media_list').body).toContain('(a.created_at, a.id) < (p_after_created_at, p_after_id)');
		expect(definition('media_moderation_queue').body).toContain('(a.created_at, a.id) > (p_after_created_at, p_after_id)');
		for (const name of ['media_approve', 'media_reject', 'media_request_delete', 'media_retry_dead_job']) expect(definition(name).body).toContain('FOR UPDATE');
	});
	it('las cascadas conservan objetos y reencolar mantiene payload e idempotencia', () => {
		expect(sql).toContain('BEFORE DELETE ON public.media_assets');
		expect(sql).toContain('BEFORE DELETE ON public.user_banners');
		const retry = definition('media_retry_dead_job').body;
		expect(retry).not.toMatch(/SET\s+payload|SET\s+idempotency_key/);
		expect(retry).toContain('dead_job_retried');
	});
	it('los parametros del worker en jsonb_build_object tienen tipo explicito', () => {
		const source = readFileSync(new URL('../worker/jobs.js', import.meta.url), 'utf8');
		for (const match of source.matchAll(/jsonb_build_object\(([\s\S]*?)\)/g)) {
			expect(match[1]).not.toMatch(/\$\d+(?![\d:]|::)/);
		}
	});
});
