<script>
	import { enhance } from '$app/forms';

	/** @type {import('./$types').PageData} */
	export let data;

	/** @type {import('./$types').ActionData} */
	export let form;

	let search = '';
	let rejectingId = '';
	let reason = '';

	$: isAdmin = data.adminRole === 'admin';

	$: filtered = data.profiles.filter((p) => {
		if (!search.trim()) return true;
		const q = search.trim().toLowerCase();
		return (
			(p.display_name ?? '').toLowerCase().includes(q) ||
			(p.username ?? '').toLowerCase().includes(q) ||
			(p.id ?? '').toLowerCase().includes(q)
		);
	});

	$: creators = filtered.filter((p) => p.role === 'creator');
	$: fans = filtered.filter((p) => p.role !== 'creator');

	/** @param {string | null | undefined} value */
	function formatDate(value) {
		if (!value) return '-';
		try {
			return new Date(value).toLocaleDateString('es-PY', {
				day: '2-digit',
				month: '2-digit',
				year: 'numeric'
			});
		} catch {
			return value;
		}
	}

	/** @param {number | null} value */
	function formatPrice(value) {
		if (value === null || value === undefined) return '-';
		return `$${Number(value).toFixed(2)}`;
	}

	/** @param {number | null} value */
	function formatSize(value) {
		if (!value) return '-';
		return `${(Number(value) / (1024 * 1024)).toFixed(1)} MB`;
	}

	/**
	 * Iniciales para el avatar de respaldo.
	 * @param {string | null | undefined} name
	 */
	function initials(name) {
		return (name ?? '?').slice(0, 2).toUpperCase();
	}

	/** @param {string} id */
	function startReject(id) {
		rejectingId = id;
		reason = '';
	}

	function cancelReject() {
		rejectingId = '';
		reason = '';
	}
</script>

<svelte:head>
	<title>Administracion Â· Agua en la Boca</title>
</svelte:head>

<div class="mx-auto w-full max-w-6xl px-4 py-8">
	<!-- Encabezado -->
	<div class="mb-6 flex flex-wrap items-center justify-between gap-3">
		<div>
			<h1 class="text-2xl font-bold text-pink-100">Panel de administracion</h1>
			<p class="mt-1 text-sm text-pink-300/60">
				{#if isAdmin}
					Sesion de administradora: puede gestionar roles, bloqueos y solicitudes.
				{:else}
					Sesion de moderacion: puede revisar cuentas y bloqueos, pero no cambiar roles.
				{/if}
			</p>
		</div>
		<span
			class="rounded-full px-4 py-2 text-xs font-bold uppercase tracking-wide
			{isAdmin ? 'bg-purple-600/25 text-purple-200' : 'bg-pink-600/20 text-pink-300'}"
		>
			{data.adminRole}
		</span>
	</div>

	<!-- Mensajes -->
	{#if form?.message}
		<p
			class="mb-4 rounded-xl border px-4 py-3 text-sm
			{form.ok
				? 'border-green-500/30 bg-green-900/20 text-green-300'
				: 'border-red-500/30 bg-red-900/20 text-red-300'}"
		>
			{form.message}
		</p>
	{/if}

	{#if data.profilesError}
		<p class="mb-4 rounded-xl border border-red-500/30 bg-red-900/20 px-4 py-3 text-sm text-red-300">
			No se pudo leer el listado de cuentas: {data.profilesError}. Revisa que la migracion
			<code>supabase-part4-admin-panel.sql</code> este aplicada.
		</p>
	{/if}

	<!-- Solicitudes pendientes -->
	{#if isAdmin}
		<section class="mb-6 rounded-2xl border border-purple-500/30 bg-purple-950/20 p-6">
			<h2 class="mb-1 font-semibold text-purple-200">
				Solicitudes para ser creadora
				{#if data.requests.length}
					<span class="ml-2 rounded-full bg-purple-600/30 px-2 py-0.5 text-xs">
						{data.requests.length}
					</span>
				{/if}
			</h2>
			<p class="mb-4 text-sm text-purple-300/60">
				Al aprobar, la funcion <code>approve_creator_request</code> asigna el rol dentro de la
				base de datos. No hay forma de cambiarlo desde el navegador.
			</p>

			{#if data.requestsError}
				<p class="text-sm text-red-300">{data.requestsError}</p>
			{:else if data.requests.length === 0}
				<p class="text-sm text-purple-300/50">No hay solicitudes pendientes.</p>
			{:else}
				<ul class="space-y-3">
					{#each data.requests as req (req.id)}
						<li class="rounded-xl border border-white/10 bg-black/40 p-4">
							<div class="flex flex-wrap items-start justify-between gap-3">
								<div class="min-w-0">
									<p class="font-semibold text-pink-100">
										{req.display_name ?? req.username ?? 'Sin nombre'}
										{#if req.username}
											<span class="text-sm font-normal text-pink-300/50">@{req.username}</span>
										{/if}
									</p>
									<p class="text-xs text-pink-300/50">
										Rol actual: {req.current_role ?? 'fan'} Â· {formatDate(req.created_at)}
									</p>
									{#if req.message}
										<p class="mt-2 text-sm text-pink-200/80 italic">"{req.message}"</p>
									{/if}
								</div>

								<div class="flex shrink-0 flex-wrap gap-2">
									<form method="POST" action="?/approveRequest" use:enhance>
										<input type="hidden" name="request_id" value={req.id} />
										<button
											class="rounded-lg bg-emerald-600/80 px-4 py-2 text-sm font-bold text-white transition hover:bg-emerald-600"
										>
											Aprobar
										</button>
									</form>

									<button
										on:click={() => startReject(req.id)}
										class="rounded-lg bg-red-600/70 px-4 py-2 text-sm font-bold text-white transition hover:bg-red-600"
									>
										Rechazar
									</button>
								</div>
							</div>

							{#if rejectingId === req.id}
								<form
									method="POST"
									action="?/rejectRequest"
									use:enhance
									class="mt-3 flex flex-wrap gap-2 border-t border-white/10 pt-3"
								>
									<input type="hidden" name="request_id" value={req.id} />
									<input
										name="reason"
										bind:value={reason}
										maxlength="300"
										placeholder="Motivo del rechazo"
										class="min-w-[12rem] flex-1 rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
									/>
									<button
										class="rounded-lg bg-red-600 px-4 py-2 text-sm font-bold text-white transition hover:bg-red-700"
									>
										Confirmar
									</button>
									<button
										type="button"
										on:click={cancelReject}
										class="rounded-lg border border-white/10 px-4 py-2 text-sm text-pink-300 transition hover:bg-white/5"
									>
										Cancelar
									</button>
								</form>
							{/if}
						</li>
					{/each}
				</ul>
			{/if}
		</section>
	{/if}

	<!-- Buscador -->
	<div class="mb-4">
		<input
			bind:value={search}
			placeholder="Buscar por nombre, usuario o id..."
			class="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
		/>
	</div>

	<!-- Creadoras -->
	<section class="mb-6">
		<h2 class="mb-3 font-semibold text-pink-200">
			Creadoras
			<span class="ml-2 rounded-full bg-pink-600/20 px-2 py-0.5 text-xs">{creators.length}</span>
		</h2>

		{#if creators.length === 0}
			<p class="rounded-xl border border-white/5 bg-black/30 px-4 py-6 text-center text-sm text-pink-300/50">
				No hay creadoras para mostrar.
			</p>
		{:else}
			<ul class="grid gap-3 sm:grid-cols-2">
				{#each creators as p (p.id)}
					<li class="rounded-2xl border border-pink-900/30 bg-black/50 p-4">
						<div class="flex items-center gap-3">
							{#if p.avatar_key}
								<img
									src={p.avatar_key}
									alt={p.display_name ?? ''}
									class="h-12 w-12 rounded-full border border-pink-500/30 object-cover"
								/>
							{:else}
								<div
									class="flex h-12 w-12 items-center justify-center rounded-full bg-pink-900/40 text-sm font-bold text-pink-300"
								>
									{initials(p.display_name ?? p.username)}
								</div>
							{/if}
							<div class="min-w-0 flex-1">
								<p class="truncate font-semibold text-pink-100">
									{p.display_name ?? 'Sin nombre'}
								</p>
								<p class="truncate text-xs text-pink-300/50">
									{p.username ? `@${p.username}` : p.id}
								</p>
							</div>
							<span class="rounded-full bg-pink-600/20 px-2 py-0.5 text-xs font-bold text-pink-300">
								creadora
							</span>
						</div>

						<dl class="mt-3 grid grid-cols-2 gap-x-3 gap-y-1 text-xs text-pink-300/60">
							<div><dt class="inline text-pink-300/40">Precio:</dt> <dd class="inline">{formatPrice(p.subscription_price)}</dd></div>
							<div><dt class="inline text-pink-300/40">Verificada:</dt> <dd class="inline">{p.is_verified ? 'si' : 'no'}</dd></div>
							<div><dt class="inline text-pink-300/40">Ciudad:</dt> <dd class="inline">{p.city ?? '-'}</dd></div>
							<div><dt class="inline text-pink-300/40">Pais:</dt> <dd class="inline">{p.country_code ?? '-'}</dd></div>
							<div><dt class="inline text-pink-300/40">Alta:</dt> <dd class="inline">{formatDate(p.created_at)}</dd></div>
							<div><dt class="inline text-pink-300/40">Bloqueada:</dt> <dd class="inline">{p.is_banned ? 'si' : 'no'}</dd></div>
						</dl>

						<div class="mt-3 flex flex-wrap gap-2">
							<a
								href={`/admin?user=${p.id}`}
								class="rounded-lg border border-white/10 px-3 py-1.5 text-xs text-pink-200 transition hover:bg-white/5"
							>
								Ver fotos
							</a>

							{#if isAdmin}
								<form method="POST" action="?/setRole" use:enhance>
									<input type="hidden" name="user_id" value={p.id} />
									<input type="hidden" name="role" value="fan" />
									<button
										class="rounded-lg border border-white/10 px-3 py-1.5 text-xs text-pink-200 transition hover:bg-white/5"
									>
										Quitar rol de creadora
									</button>
								</form>
							{/if}

							<form method="POST" action="?/setBanned" use:enhance>
								<input type="hidden" name="user_id" value={p.id} />
								<input type="hidden" name="banned" value={p.is_banned ? 'false' : 'true'} />
								<button
									class="rounded-lg px-3 py-1.5 text-xs font-bold text-white transition
									{p.is_banned ? 'bg-emerald-600/70 hover:bg-emerald-600' : 'bg-red-600/60 hover:bg-red-600'}"
								>
									{p.is_banned ? 'Desbloquear' : 'Bloquear'}
								</button>
							</form>
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	<!-- Cuentas sin rol de creadora -->
	<section class="mb-6">
		<h2 class="mb-3 font-semibold text-pink-200">
			Otras cuentas
			<span class="ml-2 rounded-full bg-white/10 px-2 py-0.5 text-xs">{fans.length}</span>
		</h2>

		{#if fans.length === 0}
			<p class="rounded-xl border border-white/5 bg-black/30 px-4 py-6 text-center text-sm text-pink-300/50">
				No hay otras cuentas para mostrar.
			</p>
		{:else}
			<ul class="grid gap-3 sm:grid-cols-2">
				{#each fans as p (p.id)}
					<li class="rounded-2xl border border-white/10 bg-black/40 p-4">
						<div class="flex items-center gap-3">
							<div
								class="flex h-10 w-10 items-center justify-center rounded-full bg-white/5 text-xs font-bold text-pink-300"
							>
								{initials(p.display_name ?? p.username)}
							</div>
							<div class="min-w-0 flex-1">
								<p class="truncate text-sm font-semibold text-pink-100">
									{p.display_name ?? 'Sin nombre'}
								</p>
								<p class="truncate text-xs text-pink-300/50">
									{p.username ? `@${p.username}` : p.id}
								</p>
							</div>
							{#if p.is_banned}
								<span class="rounded-full bg-red-600/20 px-2 py-0.5 text-xs font-bold text-red-300">
									bloqueada
								</span>
							{/if}
						</div>

						<div class="mt-3 flex flex-wrap gap-2">
							<a
								href={`/admin?user=${p.id}`}
								class="rounded-lg border border-white/10 px-3 py-1.5 text-xs text-pink-200 transition hover:bg-white/5"
							>
								Ver fotos
							</a>

							{#if isAdmin}
								<form method="POST" action="?/setRole" use:enhance>
									<input type="hidden" name="user_id" value={p.id} />
									<input type="hidden" name="role" value="creator" />
									<button
										class="rounded-lg bg-gradient-to-r from-purple-600 to-pink-600 px-3 py-1.5 text-xs font-bold text-white transition hover:brightness-110"
									>
										Promover a creadora
									</button>
								</form>
							{/if}

							<form method="POST" action="?/setBanned" use:enhance>
								<input type="hidden" name="user_id" value={p.id} />
								<input type="hidden" name="banned" value={p.is_banned ? 'false' : 'true'} />
								<button
									class="rounded-lg px-3 py-1.5 text-xs font-bold text-white transition
									{p.is_banned ? 'bg-emerald-600/70 hover:bg-emerald-600' : 'bg-red-600/60 hover:bg-red-600'}"
								>
									{p.is_banned ? 'Desbloquear' : 'Bloquear'}
								</button>
							</form>
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	<!-- Galeria de la cuenta seleccionada -->
	{#if data.selectedId}
		<section class="rounded-2xl border border-pink-900/30 bg-black/50 p-6">
			<div class="mb-4 flex items-center justify-between gap-3">
				<h2 class="font-semibold text-pink-200">
					Fotos de {data.selectedProfile?.display_name ?? data.selectedProfile?.username ?? data.selectedId}
				</h2>
				<a href="/admin" class="text-xs text-pink-300 underline">Cerrar</a>
			</div>

			{#if data.mediaError}
				<p class="text-sm text-red-300">{data.mediaError}</p>
			{:else if !isAdmin}
				<p class="mb-4 rounded-xl border border-amber-500/30 bg-amber-900/20 px-4 py-3 text-sm text-amber-300">
					Como moderadora solo ves los datos del archivo (tipo, tamaño y fecha). El contenido
					privado de pago queda reservado a las administradoras.
				</p>
				{#if data.media.length === 0}
					<p class="text-sm text-pink-300/50">Esta cuenta todavia no subio ninguna foto.</p>
				{:else}
					<ul class="divide-y divide-white/5 rounded-xl border border-white/10">
						{#each data.media as item (item.id)}
							<li class="flex items-center justify-between gap-3 px-3 py-2 text-xs">
								<span class="min-w-0 flex-1 truncate text-pink-200/80">
									{item.filename ?? 'archivo'}
								</span>
								<span class="shrink-0 text-pink-300/50">
									{item.mime_type ?? '-'} · {formatSize(item.byte_size)}
								</span>
								<span class="shrink-0 text-pink-300/50">
									{item.visibilidad ?? '-'} · {formatDate(item.created_at)}
								</span>
							</li>
						{/each}
					</ul>
				{/if}
			{:else if data.media.length === 0}
				<p class="text-sm text-pink-300/50">Esta cuenta todavia no subio ninguna foto.</p>
			{:else}
				<ul class="grid grid-cols-2 gap-3 sm:grid-cols-4">
					{#each data.media as item (item.id)}
						<li class="overflow-hidden rounded-xl border border-white/10 bg-black/40">
							{#if item.url}
								{#if String(item.mime_type ?? '').startsWith('video/')}
									<video src={item.url} muted loop class="aspect-square w-full object-cover"></video>
								{:else}
									<img
										src={item.url}
										alt={item.filename ?? ''}
										class="aspect-square w-full object-cover"
									/>
								{/if}
							{:else}
								<div class="flex aspect-square items-center justify-center text-xs text-pink-300/40">
									sin archivo
								</div>
							{/if}
							<div class="px-2 py-1.5 text-[11px] text-pink-300/60">
								<p class="truncate">{item.filename ?? 'archivo'}</p>
								<p>{formatSize(item.byte_size)} Â· {item.visibilidad ?? '-'}</p>
							</div>
						</li>
					{/each}
				</ul>
			{/if}
		</section>
	{/if}
</div>
