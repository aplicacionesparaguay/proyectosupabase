import { createHash } from 'node:crypto';
import {
	HeadObjectCommand,
	GetObjectCommand,
	PutObjectCommand,
	DeleteObjectCommand
} from '@aws-sdk/client-s3';
import { MAX_PHOTO_BYTES } from '../src/lib/media/constants.js';
import * as defaultProcessing from './processing.js';
import { LeaseLostError } from './lease.js';

// Dependencias inyectadas: importar este modulo no abre conexiones ni arranca el worker.
export function createWorkerRuntime({ pool, r2, bucket, publicBucket = 'aguaenlaboca-public', workerId, leaseSeconds, processing = defaultProcessing, logger = console.log }) {
const { createThumbnail, decodeImage, detectFaces, detectorInfo, protectAndVerify, encodeProfileImage } = processing;
function bucketName(kind) {
	if (kind === 'private') return bucket;
	if (kind === 'public') return publicBucket;
	throw new Error('Bucket invalido.');
}

function log(message, details) {
	const suffix = details ? ` ${JSON.stringify(details)}` : '';
	logger(`[worker ${workerId}] ${message}${suffix}`);
}

function sha256(buffer) {
	return createHash('sha256').update(buffer).digest('hex');
}

function operationSignal(job) {
	return job?.signal
		? AbortSignal.any([job.signal, AbortSignal.timeout(30000)])
		: AbortSignal.timeout(30000);
}

async function lockJob(client, job) {
	if (job.signal?.aborted) throw new LeaseLostError();
	const { rows } = await client.query(
		`SELECT id FROM media_jobs WHERE id = $1 AND status = 'processing'
		 AND locked_by = $2 AND lease_token = $3 AND locked_until > clock_timestamp() FOR UPDATE`,
		[job.id, workerId, job.lease_token]
	);
	if (!rows[0]) throw new LeaseLostError();
}

// El lock del asset serializa publicacion/borrado. El lock del job impide
// reclamar su lease durante una escritura R2 acotada a 30 segundos.
async function withFencedAsset(job, callback) {
	return withTransaction(async (client) => {
		await lockJob(client, job);
		const { rows } = await client.query('SELECT * FROM media_assets WHERE id = $1 FOR UPDATE', [job.media_id]);
		const asset = rows[0];
		if (!asset || asset.deleted_at || !['pending', 'pending_review'].includes(asset.moderation_status)) return null;
		const result = await callback(client, asset);
		// now() queda congelado al iniciar la transaccion; el fence final usa
		// reloj real para revertir tambien una escritura que agoto su lease.
		await lockJob(client, job);
		return result;
	});
}

async function withTransaction(callback) {
	const client = await pool.connect();
	try {
		await client.query('BEGIN');
		const result = await callback(client);
		await client.query('COMMIT');
		return result;
	} catch (error) {
		await client.query('ROLLBACK');
		throw error;
	} finally {
		client.release();
	}
}

async function headKey(key, job, bucketKind = 'private') {
	try {
		return await r2.send(new HeadObjectCommand({ Bucket: bucketName(bucketKind), Key: key }), { abortSignal: operationSignal(job) });
	} catch (error) {
		const name = /** @type {{ name?: string, $metadata?: { httpStatusCode?: number } }} */ (error);
		if (
			name.name === 'NotFound' ||
			name.name === 'NoSuchKey' ||
			name.$metadata?.httpStatusCode === 404
		) {
			return null;
		}
		throw error;
	}
}

async function getKeyBytes(key, job, maxBytes = MAX_PHOTO_BYTES, bucketKind = 'private') {
	const head = await headKey(key, job, bucketKind);
	if (!head) {
		const error = new Error('Objeto de origen no encontrado.');
		error.name = 'NoSuchKey';
		throw error;
	}

	if (typeof head.ContentLength === 'number' && head.ContentLength > maxBytes) {
		throw new Error('El objeto supera el limite de tamano.');
	}

	const response = await r2.send(new GetObjectCommand({ Bucket: bucketName(bucketKind), Key: key, IfMatch: head.ETag }), { abortSignal: operationSignal(job) });
	if (!response.Body) throw new Error('El objeto no tiene contenido.');

	const chunks = [];
	let total = 0;

	for await (const chunk of response.Body) {
		const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
		total += buffer.length;
		if (total > maxBytes) throw new Error('El objeto supera el limite de tamano.');
		chunks.push(buffer);
	}

	return Buffer.concat(chunks, total);
}

async function putKey(key, body, contentType, job) {
	await r2.send(
		new PutObjectCommand({
			Bucket: bucket,
			Key: key,
			Body: body,
			ContentType: contentType,
			CacheControl: 'private, no-store'
		}), { abortSignal: operationSignal(job) }
	);
}

async function deleteKey(key, job, bucketKind = 'private') {
	try {
		await r2.send(new DeleteObjectCommand({ Bucket: bucketName(bucketKind), Key: key }), { abortSignal: operationSignal(job) });
	} catch (error) {
		const name = /** @type {{ name?: string, $metadata?: { httpStatusCode?: number } }} */ (error);
		if (
			name.name === 'NoSuchKey' ||
			name.name === 'NotFound' ||
			name.$metadata?.httpStatusCode === 404
		) {
			return;
		}
		throw error;
	}
}

async function claimJob() {
	return withTransaction(async (client) => {
		await client.query(
			`UPDATE media_jobs
			 SET status = 'dead', locked_by = NULL, locked_until = NULL, lease_token = NULL,
			     last_error = COALESCE(last_error, 'lease expirada')
			 WHERE id IN (SELECT id FROM media_jobs
			 WHERE status = 'processing' AND (locked_until < clock_timestamp() OR locked_until IS NULL) AND attempts >= max_attempts
			 LIMIT 100 FOR UPDATE SKIP LOCKED)`
		);

		await client.query(
			`UPDATE media_jobs
			 SET status = 'pending', locked_by = NULL, locked_until = NULL, lease_token = NULL,
			     run_after = now(), last_error = COALESCE(last_error, 'lease expirada')
			 WHERE id IN (SELECT id FROM media_jobs
			 WHERE status = 'processing' AND (locked_until < clock_timestamp() OR locked_until IS NULL) AND attempts < max_attempts
			 LIMIT 100 FOR UPDATE SKIP LOCKED)`
		);

		const { rows } = await client.query(
			`WITH candidate AS (
			   SELECT id
			   FROM media_jobs
			   WHERE status = 'pending' AND run_after <= now() AND attempts < max_attempts
			   ORDER BY run_after ASC, created_at ASC
			   FOR UPDATE SKIP LOCKED
			   LIMIT 1
			 )
			 UPDATE media_jobs j
			 SET status = 'processing',
			     locked_by = $1,
			     lease_token = gen_random_uuid(), heartbeat_at = now(),
			     locked_until = clock_timestamp() + ($2::text || ' seconds')::interval,
			     attempts = attempts + 1,
			     last_error = NULL
			 FROM candidate c
			 WHERE j.id = c.id
			 RETURNING j.*`,
			[workerId, leaseSeconds]
		);

		return rows[0] ?? null;
	});
}

async function heartbeatJob(job) {
	const result = await pool.query(
		`UPDATE media_jobs SET locked_until = clock_timestamp() + ($4::text || ' seconds')::interval, heartbeat_at = now()
		 WHERE id = $1 AND status = 'processing' AND locked_by = $2
		 AND lease_token = $3 AND locked_until > clock_timestamp()`,
		[job.id, workerId, job.lease_token, leaseSeconds]
	);
	return result.rowCount === 1;
}

async function completeJob(job) {
	const result = await pool.query(
		`UPDATE media_jobs
		 SET status = 'done', locked_by = NULL, locked_until = NULL, lease_token = NULL,
		     completed_at = now(), last_error = NULL
		 WHERE id = $1 AND status = 'processing' AND locked_by = $2
		 AND lease_token = $3 AND locked_until > clock_timestamp()`,
		[job.id, workerId, job.lease_token]
	);

	if (result.rowCount === 0) {
		log(`job ${job.id} ya no pertenece a este worker; no se marca como done`);
	}
}

async function failJob(job, error) {
	const message = error instanceof DeferredJobError ? error.message :
		error?.name === 'NoSuchKey' ? 'Objeto de origen no encontrado.' : 'No se pudo completar el trabajo.';
	const dead = job.attempts >= job.max_attempts;
	const delaySeconds = Math.min(3600, Math.max(15, 15 * 2 ** Math.min(job.attempts, 8)));
	return withTransaction(async (client) => {
	await lockJob(client, job);
	const deferred = error instanceof DeferredJobError;
	const result = await client.query(
		`UPDATE media_jobs
		 SET status = $2,
		     locked_by = NULL,
		     locked_until = NULL,
		     lease_token = NULL,
		     attempts = CASE WHEN $7 THEN greatest(0, attempts - 1) ELSE attempts END,
		     run_after = CASE WHEN $2 = 'pending' THEN now() + ($3::text || ' seconds')::interval ELSE run_after END,
		     last_error = $4
		 WHERE id = $1 AND status = 'processing' AND locked_by = $5 AND lease_token = $6 AND locked_until > clock_timestamp()`,
		[job.id, !deferred && dead ? 'dead' : 'pending', deferred ? 300 : delaySeconds, message, workerId, job.lease_token, deferred]
	);

	if (result.rowCount === 0) {
		log(`job ${job.id} ya no pertenece a este worker; no se registra el fallo`);
		return;
	}

	if (job.media_id && job.kind === 'process' && !deferred) {
		await client.query(
			`UPDATE media_assets
			 SET processing_status = $2, processing_error = $3
			 WHERE id = $1 AND moderation_status = 'pending' AND deleted_at IS NULL`,
			[job.media_id, dead ? 'failed' : 'queued', message]
		);
	}

	log(`job ${job.id} fallo (${dead ? 'dead' : 'reintento'})`, { error: message });
	});
}

class DeferredJobError extends Error {}

async function getAsset(mediaId) {
	const { rows } = await pool.query('SELECT * FROM media_assets WHERE id = $1', [mediaId]);
	return rows[0] ?? null;
}

async function getStagingKey(mediaId) {
	const { rows } = await pool.query(
		`SELECT object_key
		 FROM media_upload_intents
		 WHERE media_id = $1 AND status = 'committed'
		 ORDER BY committed_at DESC NULLS LAST
		 LIMIT 1`,
		[mediaId]
	);
	return rows[0]?.object_key ?? null;
}

async function markProcessing(job) {
	return withFencedAsset(job, async (client) => {
	await client.query(
		`UPDATE media_assets
		 SET processing_status = 'processing', processing_error = NULL
		 WHERE id = $1 AND moderation_status NOT IN ('approved', 'deleted')`,
		[job.media_id]
	);
	return true;
	});
}

async function upsertObject(client, object) {
	if (object.state !== 'deleted') {
		const tombstones = await client.query(
			`SELECT 1 FROM object_tombstones WHERE bucket = $2 AND object_key = $1`, [object.key, object.bucket ?? 'private']
		);
		if (tombstones.rows.length) throw new Error('No se puede reutilizar una clave eliminada.');
	}
	await client.query(
		`INSERT INTO storage_objects
		   (bucket, object_key, kind, media_id, state, sha256, byte_size)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 ON CONFLICT (bucket, object_key) DO UPDATE
		 SET kind = EXCLUDED.kind,
		     media_id = EXCLUDED.media_id,
		     state = EXCLUDED.state,
		     sha256 = COALESCE(EXCLUDED.sha256, storage_objects.sha256),
		     byte_size = COALESCE(EXCLUDED.byte_size, storage_objects.byte_size),
		     deleted_at = CASE WHEN EXCLUDED.state = 'deleted' THEN now() ELSE storage_objects.deleted_at END`,
		[
			object.bucket ?? 'private',
			object.key,
			object.kind,
			object.mediaId,
			object.state,
			object.sha256 ?? null,
			object.byteSize ?? null
		]
	);
}

async function tombstone(client, key, mediaId, reason, bucketKind = 'private') {
	await client.query(
		`INSERT INTO object_tombstones (bucket, object_key, media_id, reason)
		 VALUES ($4, $1, $2, $3)
		 ON CONFLICT (bucket, object_key) DO NOTHING`,
		[key, mediaId, reason, bucketKind]
	);
}

async function copyStagingToOriginal(job, asset, bytes) {
	const originalKey = asset.original_key;
	if (!originalKey) throw new Error('La fila no tiene clave de original.');

	// Reserva durable antes de escribir en R2. Una caida entre PUT y COMMIT
	// deja un objeto conocido por el ledger, recuperable por reintento/borrado.
	const reserved = await withFencedAsset(job, async (client) => {
		await upsertObject(client, {
			key: originalKey,
			kind: 'original',
			mediaId: asset.id,
			state: 'pending',
			sha256: asset.sha256_original,
			byteSize: asset.byte_size
		});
		return true;
	});
	if (!reserved) return false;
	return withFencedAsset(job, async (client) => {
		// Se escriben los bytes ya hasheados, NO se vuelve a copiar una clave
		// staging mutable (TOCTOU entre GET, hash y CopyObject).
		await putKey(originalKey, bytes, asset.mime_type, job);
		await upsertObject(client, { key: originalKey, kind: 'original', mediaId: asset.id,
			state: 'present', sha256: asset.sha256_original, byteSize: bytes.length });
		return true;
	});
}

async function loadSource(asset, job) {
	const stagingKey = await getStagingKey(asset.id);

	if (stagingKey) {
		try {
			const bytes = await getKeyBytes(stagingKey, job);
			return { bytes, key: stagingKey, kind: 'staging' };
		} catch (error) {
			const name = /** @type {{ name?: string }} */ (error)?.name;
			if (name !== 'NoSuchKey') throw error;
			log(`staging ausente para ${asset.id}; usando original privado`);
		}
	}

	if (asset.original_key) {
		const bytes = await getKeyBytes(asset.original_key, job);
		return { bytes, key: asset.original_key, kind: 'original' };
	}

	throw new Error('No se encontro el archivo de origen.');
}

async function blockAsset(job, asset, facesDetected) {
	const reason =
		'La verificacion no pudo eliminar todos los rostros detectados. La foto no se publicara.';

	await withFencedAsset(job, async (client) => {
		await client.query(
			`UPDATE media_assets
			 SET processing_status = 'failed',
			     moderation_status = 'blocked',
			     visibility = 'private',
			     faces_detected = $2,
			     detector_name = $3,
			     detector_version = $4,
			     verification_status = 'failed',
			     processing_error = $5,
			     protected_key = NULL,
			     thumb_key = NULL
			 WHERE id = $1`,
			[asset.id, facesDetected, detectorInfo.name, detectorInfo.version, reason]
		);

		await client.query(
			`INSERT INTO media_jobs (kind, media_id, payload, run_after, idempotency_key)
			 VALUES (
			   'purge_original',
			   $1,
			   jsonb_build_object('bucket', 'private', 'object_key', $2::text, 'retention_days', 30),
			   now() + interval '30 days',
			   'blocked_original:' || $1::text
			 )
			 ON CONFLICT (idempotency_key) DO NOTHING`,
			[asset.id, asset.original_key]
		);

		await client.query(
			`INSERT INTO media_audit_log (actor_id, action, media_id, metadata)
			 VALUES (NULL, 'media_blocked', $1, jsonb_build_object('faces_detected', $2::integer, 'reason', $3::text))`,
			[asset.id, facesDetected, reason]
		);
	});
}

async function processJob(job) {
	const asset = await getAsset(job.media_id);
	if (!asset) {
		log(`asset ${job.media_id} no existe; job omitido`);
		return;
	}

	if (asset.deleted_at || asset.moderation_status === 'deleted') return;
	if (asset.moderation_status === 'approved' || asset.moderation_status === 'rejected') return;
	if (asset.moderation_status === 'blocked') return;
	if (
		asset.moderation_status === 'pending_review' &&
		asset.processing_status === 'protected' &&
		asset.protected_key
	) {
		return;
	}

	if (!(await markProcessing(job))) return;

	const source = await loadSource(asset, job);

	if (asset.sha256_original) {
		const actualHash = sha256(source.bytes);
		if (actualHash !== asset.sha256_original) {
			throw new Error('El hash del archivo de origen no coincide con el registrado.');
		}
	} else throw new Error('Falta el hash del archivo original.');

	const normalized = await decodeImage(source.bytes, asset.mime_type);
	if (source.bytes.length !== Number(asset.byte_size) || normalized.width !== asset.width || normalized.height !== asset.height) {
		throw new Error('Los metadatos del archivo no coinciden con los registrados.');
	}
	if (source.kind === 'staging' && !(await copyStagingToOriginal(job, asset, source.bytes))) return;
	const initialFaces = await detectFaces(normalized.pixels, normalized.width, normalized.height);

	let result = await protectAndVerify(
		normalized,
		initialFaces,
		asset.protection_mode === 'blur' ? 'blur' : 'pixelate',
		Number(asset.protection_strength) || 100
	);

	if (!result.verified && result.mode === 'pixelate') {
		log(`pixelado insuficiente para ${asset.id}; probando desenfoque`);
		result = await protectAndVerify(normalized, initialFaces, 'blur', 100);
	}

	if (!result.verified) {
		await blockAsset(job, asset, result.facesDetected);
		log(`asset ${asset.id} bloqueado por verificacion facial`);
		return;
	}

	// Una lease antigua nunca puede sobrescribir las derivadas de otra.
	const generation = job.lease_token;
	const protectedKey = `protected/${asset.owner_id}/${asset.id}/${generation}/protected.webp`;
	const thumbKey = `thumbs/${asset.owner_id}/${asset.id}/${generation}/thumb.webp`;
	const protectedHash = sha256(result.protectedBuffer);
	const thumbnail = await createThumbnail(result.protectedBuffer);
	const thumbImage = await decodeImage(thumbnail, 'image/webp');
	const thumbFaces = await detectFaces(thumbImage.pixels, thumbImage.width, thumbImage.height);
	if (thumbFaces.length) {
		await blockAsset(job, asset, Math.max(result.facesDetected, thumbFaces.length));
		return;
	}
	const thumbnailHash = sha256(thumbnail);

	const reservations = [
		{ key: protectedKey, kind: 'protected', mediaId: asset.id, state: 'pending', sha256: protectedHash, byteSize: result.protectedBuffer.length },
		{ key: thumbKey, kind: 'thumb', mediaId: asset.id, state: 'pending', sha256: thumbnailHash, byteSize: thumbnail.length }
	];
	const reserved = await withFencedAsset(job, async (client) => {
		for (const object of reservations) await upsertObject(client, object);
		return true;
	});
	if (!reserved) return;

	await withFencedAsset(job, async (client) => {
		await putKey(protectedKey, result.protectedBuffer, 'image/webp', job);
		await putKey(thumbKey, thumbnail, 'image/webp', job);
		await client.query(
			`UPDATE media_assets
			 SET processing_status = 'protected',
			     moderation_status = 'pending_review',
			     visibility = 'private',
			     faces_detected = $2,
			     detector_name = $3,
			     detector_version = $4,
			     protection_mode = $5,
			     protection_strength = $6,
			     verification_status = 'passed',
			     protected_key = $7,
			     thumb_key = $8,
			     sha256_protected = $9,
			     processing_error = NULL,
			     processed_at = now()
			 WHERE id = $1`,
			[
				asset.id,
				result.facesDetected,
				detectorInfo.name,
				detectorInfo.version,
				result.mode,
				result.strength,
				protectedKey,
				thumbKey,
				protectedHash
			]
		);

		await upsertObject(client, {
			key: protectedKey,
			kind: 'protected',
			mediaId: asset.id,
			state: 'present',
			sha256: protectedHash,
			byteSize: result.protectedBuffer.length
		});
		await upsertObject(client, {
			key: thumbKey,
			kind: 'thumb',
			mediaId: asset.id,
			state: 'present',
			sha256: thumbnailHash,
			byteSize: thumbnail.length
		});

		await client.query(
			`INSERT INTO media_audit_log (actor_id, action, media_id, metadata)
			 VALUES (
			   NULL, 'media_processed', $1,
			   jsonb_build_object(
			     'faces_detected', $2::integer,
			     'mode', $3::text,
			     'strength', $4::integer,
			     'verification_status', 'passed'
			   )
			 )`,
			[asset.id, result.facesDetected, result.mode, result.strength]
		);
	});

	log(`asset ${asset.id} procesado`, {
		faces: result.facesDetected,
		mode: result.mode,
		strength: result.strength
	});
}

function assertObjectKey(key) {
	if (typeof key !== 'string' || !/^(staging|originals|protected|thumbs|covers|avatars)\/[a-zA-Z0-9/_.-]+$/.test(key)
		|| key.split('/').some((part) => !part || part === '.' || part === '..')) {
		throw new Error('Clave de almacenamiento no valida.');
	}
}

async function deleteObjectsFromPayload(job, reason) {
	if (!Array.isArray(job.payload?.objects)) throw new Error('Payload de borrado invalido.');
	const objects = [...job.payload.objects];
	if (job.media_id) {
		// Incluye reservas de generaciones parciales, no solo las claves que
		// llegaron a publicarse en media_assets.
		const { rows } = await pool.query(
			`SELECT bucket, object_key, kind FROM storage_objects WHERE media_id = $1
			 AND state <> 'deleted' AND ($2 OR kind IN ('protected', 'thumb'))`,
			[job.media_id, job.kind === 'delete_all']
		);
		objects.push(...rows);
	}

	for (const object of objects) {
		if (object?.object_key == null) continue; // snapshots sin derivadas todavia
		assertObjectKey(object.object_key);
		const bucketKind = object.bucket ?? 'private';
		if (bucketKind !== 'private' && !(bucketKind === 'public' && ['avatar', 'cover'].includes(object.kind))) throw new Error('Bucket de borrado invalido.');
		if (['avatar', 'cover'].includes(object.kind) !== /^(avatars|covers)\//.test(object.object_key)) throw new Error('Tipo de objeto invalido.');

		await withTransaction(async (client) => {
			await lockJob(client, job);
			await deleteKey(object.object_key, job, bucketKind);
			await upsertObject(client, {
				key: object.object_key,
				bucket: bucketKind,
				kind: object.kind ?? 'protected',
				mediaId: job.media_id,
				state: 'deleted'
			});
			await tombstone(client, object.object_key, job.media_id, reason, bucketKind);
		});
	}
}

async function purgeOriginal(job) {
	const key = job.payload?.object_key;
	assertObjectKey(key);
	if (!key.startsWith('originals/')) throw new Error('La purga solo acepta originales.');

	await withTransaction(async (client) => {
		await lockJob(client, job);
		if (job.media_id) {
			const { rows } = await client.query('SELECT * FROM media_assets WHERE id = $1 FOR UPDATE', [job.media_id]);
			if (rows[0] && !['rejected', 'blocked', 'deleted'].includes(rows[0].moderation_status)) return;
		}
		await deleteKey(key, job);
		await upsertObject(client, {
			key,
			kind: 'original',
			mediaId: job.media_id,
			state: 'deleted'
		});
		await tombstone(client, key, job.media_id, 'retention_expired');

		if (job.media_id) {
			await client.query(
				`UPDATE media_assets
				 SET original_key = NULL, original_deleted_at = now()
				 WHERE id = $1 AND moderation_status IN ('rejected', 'blocked', 'deleted')`,
				[job.media_id]
			);
			await client.query(
				`INSERT INTO media_audit_log (actor_id, action, media_id, metadata)
				 VALUES (NULL, 'original_purged', $1, jsonb_build_object('reason', 'retention_expired'))`,
				[job.media_id]
			);
		}
	});
}

async function deleteStaging(job) {
	const key = job.payload?.object_key;
	assertObjectKey(key);
	if (!key.startsWith('staging/')) throw new Error('La limpieza solo acepta staging.');

	await withTransaction(async (client) => {
		await lockJob(client, job);
		// La limpieza no puede adelantar la expiracion real del PUT.
		const { rows } = await client.query(
			`SELECT i.expires_at, i.status, a.id AS media_id, a.created_at,
			 a.deleted_at, a.original_key, o.state AS original_state
			 FROM media_upload_intents i LEFT JOIN media_assets a ON a.id = i.media_id
			 LEFT JOIN storage_objects o ON o.bucket = 'private' AND o.object_key = a.original_key
			 WHERE i.object_key = $1`, [key]
		);
		const intent = rows[0];
		if (intent && new Date(intent.expires_at).getTime() + 300000 > Date.now()) {
			throw new DeferredJobError('El PUT todavia puede estar vigente.');
		}
		if (intent?.media_id && !intent.deleted_at && intent.original_state !== 'present'
			&& new Date(intent.created_at).getTime() + 30 * 86400000 > Date.now()) {
			throw new DeferredJobError('Se conserva staging hasta recuperar el original.');
		}
		await deleteKey(key, job);
		await upsertObject(client, {
			key,
			kind: 'staging',
			mediaId: job.media_id,
			state: 'deleted'
		});
		await tombstone(client, key, job.media_id, 'staging_deleted');
	});
}

async function reconcileJob(job) {
	const { rows } = await pool.query(
		`SELECT object_key, state, kind, media_id, created_at, bucket
		 FROM storage_objects
		 ORDER BY updated_at ASC, id ASC
		 LIMIT 500`
	);

	for (const row of rows) {
		const bucketKind = row.bucket ?? 'private';
		const exists = await headKey(row.object_key, job, bucketKind);
		const state = exists ? 'present' : 'missing';
		await withTransaction(async (client) => {
			await lockJob(client, job);
			const { rows: deleted } = await client.query(
				`SELECT 1 FROM object_tombstones WHERE bucket = $2 AND object_key = $1`, [row.object_key, bucketKind]
			);
			let orphan = false;
			if (['protected', 'thumb'].includes(row.kind) && new Date(row.created_at).getTime() + 3600000 < Date.now()) {
				const { rows: assets } = await client.query('SELECT * FROM media_assets WHERE id = $1 FOR UPDATE', [row.media_id]);
				const { rows: activeJobs } = await client.query(
					`SELECT 1 FROM media_jobs WHERE media_id = $1 AND kind = 'process' AND status IN ('pending', 'processing')`, [row.media_id]
				);
				orphan = !activeJobs.length && ![assets[0]?.protected_key, assets[0]?.thumb_key].includes(row.object_key);
			}
			if (row.state === 'deleted' || deleted.length || orphan) {
				if (exists) await deleteKey(row.object_key, job, bucketKind);
				await tombstone(client, row.object_key, row.media_id, orphan ? 'orphan_generation' : 'reappeared', bucketKind);
			}
			// Tocar incluso las filas sin cambios permite rotar todo el ledger.
			await client.query(
				`UPDATE storage_objects
				 SET state = $2, updated_at = now()
				 WHERE bucket = $3 AND object_key = $1`,
				[row.object_key, row.state === 'deleted' || deleted.length || orphan ? 'deleted' : state, bucketKind]
			);
		});
	}
}

async function deleteProfileOrphan(job) {
	const { object_key: key, bucket: bucketKind, kind, user_id: userId } = job.payload ?? {};
	assertObjectKey(key);
	if (!['avatar', 'cover'].includes(kind) || !key.startsWith(`${kind === 'avatar' ? 'avatars' : 'covers'}/${userId}/`)) throw new Error('Payload de imagen invalido.');
	if (!['private', 'public'].includes(bucketKind) || (kind === 'avatar' && bucketKind !== 'public')) throw new Error('Bucket de imagen invalido.');
	return withTransaction(async (client) => {
		await lockJob(client, job);
		const { rows } = await client.query(kind === 'cover'
			? `SELECT 1 FROM user_banners WHERE user_id = $1 AND regexp_replace(COALESCE(storage_path, public_url, ''), '^https?://[^/]+/', '') = $2 AND storage_bucket = $3 FOR UPDATE`
			: `SELECT 1 FROM profiles WHERE id = $1 AND right(avatar_key, length($2)) = $2 FOR UPDATE`,
			kind === 'cover' ? [userId, key, bucketKind] : [userId, key]);
		if (rows.length) return;
		await deleteKey(key, job, bucketKind);
		await upsertObject(client, { key, bucket: bucketKind, kind, mediaId: null, state: 'deleted' });
		await tombstone(client, key, null, 'profile_orphan', bucketKind);
	});
}

async function migrateCover(job) {
	const { rows } = await pool.query('SELECT * FROM user_banners WHERE id = $1', [job.payload?.banner_id]);
	const row = rows[0];
	if (!row || row.storage_bucket !== 'public') return;
	const sourceKey = String(row.storage_path ?? row.public_url ?? '').replace(/^https?:\/\/[^/]+\//, '');
	assertObjectKey(sourceKey);
	if (!sourceKey.startsWith(`covers/${row.user_id}/`)) throw new Error('La portada requiere reconciliacion manual.');
	const bytes = await getKeyBytes(sourceKey, job, MAX_PHOTO_BYTES, 'public');
	const canonical = await encodeProfileImage(await decodeImage(bytes));
	if (canonical.length > MAX_PHOTO_BYTES) throw new Error('La portada supera el limite.');
	const key = `covers/${row.user_id}/${row.id}/${job.lease_token}/migrated.webp`;
	const object = { key, kind: 'cover', mediaId: null, state: 'pending', sha256: sha256(canonical), byteSize: canonical.length };
	await withTransaction(async (client) => {
		await lockJob(client, job);
		await upsertObject(client, object);
		await client.query(`INSERT INTO media_jobs (kind, payload, run_after, idempotency_key)
		 VALUES ('delete_profile_orphan', jsonb_build_object('bucket', 'private', 'kind', 'cover', 'object_key', $1::text, 'user_id', $2::text),
		 now() + interval '1 hour', $3) ON CONFLICT (idempotency_key) DO NOTHING`,
		 [key, row.user_id, `migrate_cover_orphan:${row.id}:${job.lease_token}`]);
	});
	await withTransaction(async (client) => {
		await lockJob(client, job);
		const { rows: current } = await client.query('SELECT * FROM user_banners WHERE id = $1 FOR UPDATE', [row.id]);
		if (!current[0] || current[0].storage_bucket !== 'public') return;
		if (current[0].storage_path !== row.storage_path || current[0].public_url !== row.public_url) throw new Error('La portada cambio durante la migracion.');
		await putKey(key, canonical, 'image/webp', job);
		await upsertObject(client, { ...object, state: 'present' });
		await client.query(`UPDATE user_banners SET storage_path = $2, storage_bucket = 'private', public_url = NULL WHERE id = $1`, [row.id, key]);
		await client.query(`INSERT INTO media_jobs (kind, payload, idempotency_key)
		 VALUES ('delete_profile_orphan', jsonb_build_object('bucket', 'public', 'kind', 'cover', 'object_key', $1::text, 'user_id', $2::text), $3)
		 ON CONFLICT (idempotency_key) DO NOTHING`, [sourceKey, row.user_id, `migrated_cover_source:${row.id}`]);
		await lockJob(client, job);
	});
}

async function runJob(job) {
	if (job.kind === 'process') return processJob(job);
	if (job.kind === 'delete_staging') return deleteStaging(job);
	if (job.kind === 'delete_protected')
		return deleteObjectsFromPayload(job, 'rejected');
	if (job.kind === 'delete_all')
		return deleteObjectsFromPayload(job, 'owner_deleted');
	if (job.kind === 'purge_original') return purgeOriginal(job);
	if (job.kind === 'reconcile') return reconcileJob(job);
	if (job.kind === 'delete_profile_orphan') return deleteProfileOrphan(job);
	if (job.kind === 'migrate_cover') return migrateCover(job);
	throw new Error(`Tipo de trabajo desconocido: ${job.kind}`);
}

async function maintenance() {
	await withTransaction(async (client) => {
		await client.query(
			`UPDATE media_assets a
			 SET processing_status = 'failed',
			     processing_error = 'El worker no completo el procesamiento.'
			 FROM media_jobs j
			 WHERE j.media_id = a.id
			   AND j.kind = 'process'
			   AND j.status = 'dead'
			   AND a.processing_status IN ('processing', 'queued')
			   AND a.moderation_status = 'pending' AND a.deleted_at IS NULL`
		);

		await client.query(
			`INSERT INTO media_jobs (kind, payload, idempotency_key)
			 VALUES (
			   'reconcile',
			   '{}'::jsonb,
			   'reconcile:' || to_char(now(), 'YYYY-MM-DD-HH24')
			 )
			 ON CONFLICT (idempotency_key) DO NOTHING`
		);

		await client.query(
			`UPDATE media_upload_intents
			 SET status = 'expired'
			 WHERE status = 'created' AND expires_at < now()
			 RETURNING id, object_key`
		);
		// Repara tambien intents anteriores a R18 y cierres abruptos previos.
		await client.query(
			`INSERT INTO storage_objects (bucket, object_key, kind, media_id, state)
			 SELECT 'private', object_key, 'staging', media_id, 'pending' FROM media_upload_intents
			 ON CONFLICT (bucket, object_key) DO NOTHING`
		);
		await client.query(
			`INSERT INTO media_jobs (kind, media_id, payload, run_after, idempotency_key)
			 SELECT 'delete_staging', media_id, jsonb_build_object('bucket', 'private', 'object_key', object_key),
			 expires_at + interval '5 minutes', 'expire:' || id::text FROM media_upload_intents
			 ON CONFLICT (idempotency_key) DO NOTHING`
		);
	});
}

return { claimJob, heartbeatJob, completeJob, failJob, runJob, maintenance, withFencedAsset };
}
