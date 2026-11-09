/** TLS siempre autentica al servidor. La CA se entrega como PEM en el entorno. */
export function databaseConfig(env) {
	if (!env.DATABASE_URL) throw new Error('Falta DATABASE_URL.');
	const url = new URL(env.DATABASE_URL);
	if (!['postgres:', 'postgresql:'].includes(url.protocol)) throw new Error('DATABASE_URL invalida.');
	// pg permite que los parametros de la URL reemplacen ssl. Se rechazan
	// opciones ambiguas o que puedan leer ficheros de claves por su cuenta.
	for (const key of url.searchParams.keys()) {
		if (/^ssl/i.test(key)) throw new Error('Configura TLS con DATABASE_CA_PEM, sin parametros ssl en DATABASE_URL.');
	}
	if (env.DATABASE_SSL && env.DATABASE_SSL !== 'true') throw new Error('El worker requiere TLS verificado.');
	return {
		connectionString: url.toString(),
		ssl: { rejectUnauthorized: true, ...(env.DATABASE_CA_PEM ? { ca: env.DATABASE_CA_PEM } : {}) },
		max: Math.min(8, Math.max(2, Number(env.WORKER_DB_POOL) || 4)),
		connectionTimeoutMillis: 10000,
		statement_timeout: 45000,
		options: '-c search_path=pg_catalog,public',
		idle_in_transaction_session_timeout: 60000
	};
}
