<script>
	/** @type {import('./$types').PageData} */
	export let data;
	/** @type {any} */
	export let form;

	/** @param {string} name */
	function actionUrl(name) {
		return `?/${name}&limit=${data.limit}${data.cursor ? `&cursor=${encodeURIComponent(data.cursor)}` : ''}`;
	}
</script>

<div class="mx-auto w-full max-w-6xl px-4 py-8">
	<div class="mb-6 flex flex-wrap items-end justify-between gap-3">
		<div>
			<h1 class="text-2xl font-bold text-pink-100">Moderacion de fotos</h1>
			<p class="mt-1 text-sm text-pink-300/60">
				Aqui solo se muestra la copia protegida. El original privado no se expone en este panel.
			</p>
		</div>
		<p class="text-sm text-pink-400/60">{data.items.length} fotos en esta pagina</p>
	</div>

	{#if form?.message}
		<p
			class="mb-4 rounded-xl border px-4 py-3 text-sm {form.ok
				? 'border-emerald-500/30 bg-emerald-900/20 text-emerald-300'
				: 'border-red-500/30 bg-red-900/20 text-red-300'}"
		>
			{form.message}
		</p>
	{/if}

	{#if data.queueError}
		<p
			class="mb-4 rounded-xl border border-red-500/30 bg-red-900/20 px-4 py-3 text-sm text-red-300"
		>
			{data.queueError}
		</p>
	{/if}

	{#if data.items.length === 0 && !data.queueError}
		<p
			class="rounded-xl border border-dashed border-pink-900/40 bg-black/20 px-6 py-12 text-center text-sm text-pink-300/50"
		>
			No hay fotografias pendientes de revision.
		</p>
	{:else}
		<ul class="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
			{#each data.items as item (item.id)}
				<li class="overflow-hidden rounded-2xl border border-white/10 bg-black/40">
					<div class="flex aspect-[4/3] items-center justify-center bg-black/50">
						{#if item.url}
							<img src={item.url} alt="Copia protegida" class="h-full w-full object-contain" />
						{:else}
							<p class="px-4 text-center text-sm text-red-300">
								No se pudo firmar la copia protegida.
							</p>
						{/if}
					</div>

					<div class="space-y-3 p-4">
						<div>
							<p class="truncate text-sm font-semibold text-pink-100">
								{item.title ?? 'Sin titulo'}
							</p>
							<p class="text-xs text-pink-300/50">
								{item.display_name ?? item.username ?? item.owner_id}
							</p>
						</div>

						<dl class="grid grid-cols-2 gap-2 text-[11px] text-pink-300/60">
							<div>
								<dt class="text-pink-400/40">Dimensiones</dt>
								<dd>{item.width ?? '?'} × {item.height ?? '?'}</dd>
							</div>
							<div>
								<dt class="text-pink-400/40">Rostros detectados</dt>
								<dd>{item.faces_detected}</dd>
							</div>
							<div>
								<dt class="text-pink-400/40">Proteccion</dt>
								<dd>{item.protection_mode} {item.protection_strength}%</dd>
							</div>
							<div>
								<dt class="text-pink-400/40">Verificacion</dt>
								<dd>{item.verification_status}</dd>
							</div>
							<div>
								<dt class="text-pink-400/40">Detector</dt>
								<dd>{item.detector_name ?? '-'} {item.detector_version ?? ''}</dd>
							</div>
							<div>
								<dt class="text-pink-400/40">Enviada</dt>
								<dd>{new Date(item.created_at).toLocaleString('es-ES')}</dd>
							</div>
						</dl>

						<form method="POST" action={actionUrl('approve')}>
							<input type="hidden" name="media_id" value={item.id} />
							<button
								disabled={!item.url}
								class="w-full rounded-xl bg-emerald-600 px-4 py-2.5 text-sm font-bold text-white transition hover:bg-emerald-500"
							>
								Aprobar y publicar
							</button>
						</form>

						<form method="POST" action={actionUrl('reject')} class="space-y-2">
							<input type="hidden" name="media_id" value={item.id} />
							<textarea
								aria-label="Motivo del rechazo"
								name="reason"
								rows="2"
								maxlength="500"
								required
								placeholder="Motivo del rechazo (visible para la autora)"
								class="w-full resize-none rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-sm text-white placeholder-white/30 focus:border-red-500 focus:outline-none"
							></textarea>
							<button
								class="w-full rounded-xl border border-red-500/40 px-4 py-2 text-sm font-semibold text-red-300 transition hover:bg-red-500/10"
							>
								Rechazar
							</button>
						</form>
					</div>
				</li>
			{/each}
		</ul>
	{/if}
	<nav class="mt-6 flex gap-4 text-sm text-pink-200" aria-label="Paginas de moderacion">
		{#if data.cursor || data.offset}<a href="?limit={data.limit}" class="underline">Volver al inicio</a>{/if}
		{#if data.nextCursor}<a href="?limit={data.limit}&cursor={encodeURIComponent(data.nextCursor)}" class="underline">Siguiente pagina</a>{/if}
	</nav>

	<section class="mt-10 border-t border-white/10 pt-6">
		<h2 class="text-xl font-semibold text-pink-100">Recuperacion de trabajos (dead-letter)</h2>
		{#if data.deadError}
			<p class="mt-3 text-sm text-red-300">No se pudo consultar dead-letter.</p>
		{:else if data.deadJobs.length === 0}
			<p class="mt-3 text-sm text-pink-300/60">No hay trabajos agotados.</p>
		{:else}
			<p class="mt-2 text-sm text-pink-300/60">Se muestran hasta 50 trabajos. Cada recuperacion conserva el payload y registra el motivo.</p>
			{#each data.deadJobs as job (job.id)}
				<form method="POST" action={actionUrl('retryJob')} class="mt-3 flex flex-wrap items-center gap-3 rounded-xl border border-white/10 p-3">
					<input type="hidden" name="job_id" value={job.id} />
					<span class="text-sm text-pink-200">{job.kind} · {job.attempts}/{job.max_attempts} intentos</span>
					<input name="reason" aria-label="Motivo de recuperacion" required minlength="3" maxlength="500" placeholder="Motivo de recuperacion" class="min-w-0 flex-1 rounded-lg bg-white/5 px-3 py-2 text-sm text-white" />
					<button class="rounded-lg bg-purple-700 px-4 py-2 text-sm text-white">Reencolar</button>
				</form>
			{/each}
		{/if}
	</section>
</div>
