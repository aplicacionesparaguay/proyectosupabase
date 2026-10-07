<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { session, user, logout } from '$lib/stores/auth';
	import { supabase } from '$lib/supabaseClient';

	let loading = true;
	let saving = false;
	let saveMessage = '';
	let saveError = '';

	let displayName = '';
	let username = '';
	let bio = '';
	let subscriptionPrice = '';
	let isCreator = false;

	onMount(async () => {
		if (!$session?.user) {
			goto('/login');
			return;
		}

		const { data } = await supabase
			.from('profiles')
			.select('display_name, username, bio, subscription_price, role')
			.eq('id', /** @type {string} */ ($user?.id))
			.single();

		if (data) {
			displayName = data.display_name ?? '';
			username = data.username ?? '';
			bio = data.bio ?? '';
			subscriptionPrice = data.subscription_price ? String(data.subscription_price) : '';
			isCreator = data.role === 'creator';
		}

		loading = false;
	});

	async function save() {
		if (saving || !$user) return;
		saving = true;
		saveMessage = '';
		saveError = '';

		const updates = {
			display_name: displayName.trim() || null,
			username: username.trim() || null,
			bio: bio.trim() || null
		};

		if (isCreator) {
			const price = parseFloat(subscriptionPrice);
			/** @type {any} */ (updates).subscription_price = !isNaN(price) && price >= 0 ? price : null;
		}

		const { error } = await supabase
			.from('profiles')
			.update(updates)
			.eq('id', /** @type {string} */ ($user?.id));

		if (error) {
			saveError = error.message;
		} else {
			saveMessage = 'Guardado correctamente.';
			setTimeout(() => (saveMessage = ''), 3000);
		}

		saving = false;
	}

	async function becomeCreator() {
		if (saving || !$user) return;
		saving = true;

		const { error } = await supabase
			.from('profiles')
			.update({ role: 'creator' })
			.eq('id', /** @type {string} */ ($user?.id));

		if (!error) {
			isCreator = true;
			saveMessage = '¡Ya eres creadora! Configura tu precio de suscripción.';
		}

		saving = false;
	}

	async function handleLogout() {
		await logout();
		goto('/login');
	}
</script>

{#if loading}
	<div class="flex min-h-[60vh] items-center justify-center">
		<div
			class="h-10 w-10 animate-spin rounded-full border-2 border-pink-500 border-t-transparent"
		></div>
	</div>
{:else}
	<div class="mx-auto w-full max-w-lg px-4 py-8">
		<h1 class="mb-6 text-2xl font-bold text-pink-100">Configuración</h1>

		<!-- Perfil -->
		<div class="mb-6 rounded-2xl border border-pink-900/30 bg-black/50 p-6">
			<h2 class="mb-4 font-semibold text-pink-200">Perfil público</h2>

			<div class="space-y-4">
				<div>
					<label for="displayName" class="mb-1 block text-sm font-medium text-pink-300"
						>Nombre visible</label
					>
					<input
						id="displayName"
						bind:value={displayName}
						maxlength="50"
						placeholder="Tu nombre o alias"
						class="w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
					/>
				</div>

				<div>
					<label for="username" class="mb-1 block text-sm font-medium text-pink-300"
						>Nombre de usuario</label
					>
					<div
						class="flex items-center rounded-xl border border-white/10 bg-white/5 px-4 py-3 focus-within:border-pink-500"
					>
						<span class="mr-1 text-pink-400/50">@</span>
						<input
							id="username"
							bind:value={username}
							maxlength="30"
							placeholder="username"
							class="flex-1 bg-transparent text-white placeholder-white/30 focus:outline-none"
						/>
					</div>
				</div>

				<div>
					<label for="bio" class="mb-1 block text-sm font-medium text-pink-300">Biografía</label>
					<textarea
						id="bio"
						bind:value={bio}
						maxlength="500"
						rows="4"
						placeholder="Cuéntales sobre ti..."
						class="w-full resize-none rounded-xl border border-white/10 bg-white/5 px-4 py-3 text-white placeholder-white/30 focus:border-pink-500 focus:outline-none"
					></textarea>
					<p class="mt-1 text-right text-xs text-white/30">{bio.length}/500</p>
				</div>
			</div>
		</div>

		<!-- Creadora -->
		{#if !isCreator}
			<div class="mb-6 rounded-2xl border border-purple-500/30 bg-purple-950/20 p-6">
				<h2 class="mb-2 font-semibold text-purple-200">¿Quieres ser creadora?</h2>
				<p class="mb-4 text-sm text-purple-300/70">
					Publica contenido, construye tu audiencia y gana con suscripciones.
				</p>
				<button
					on:click={becomeCreator}
					disabled={saving}
					class="rounded-xl bg-gradient-to-r from-purple-600 to-pink-600 px-6 py-2.5 font-bold text-white transition hover:brightness-110 disabled:opacity-50"
				>
					Convertirme en creadora
				</button>
			</div>
		{:else}
			<div class="mb-6 rounded-2xl border border-pink-500/30 bg-pink-950/20 p-6">
				<div class="mb-4 flex items-center gap-2">
					<span class="rounded-full bg-pink-600/20 px-3 py-1 text-xs font-bold text-pink-400"
						>CUENTA DE CREADORA</span
					>
				</div>
				<div>
					<label for="price" class="mb-1 block text-sm font-medium text-pink-300"
						>Precio de suscripción mensual (USD)</label
					>
					<div
						class="flex items-center rounded-xl border border-white/10 bg-white/5 px-4 py-3 focus-within:border-pink-500"
					>
						<span class="mr-1 text-pink-400/50">$</span>
						<input
							id="price"
							bind:value={subscriptionPrice}
							type="number"
							min="0"
							step="0.01"
							placeholder="0.00"
							class="flex-1 bg-transparent text-white placeholder-white/30 focus:outline-none"
						/>
					</div>
					<p class="mt-1 text-xs text-pink-300/40">Deja en 0 para contenido gratuito.</p>
				</div>
			</div>
		{/if}

		<!-- Mensajes de estado -->
		{#if saveMessage}
			<p
				class="mb-4 rounded-xl border border-green-500/30 bg-green-900/20 px-4 py-3 text-sm text-green-400"
			>
				{saveMessage}
			</p>
		{/if}
		{#if saveError}
			<p
				class="mb-4 rounded-xl border border-red-500/30 bg-red-900/20 px-4 py-3 text-sm text-red-400"
			>
				{saveError}
			</p>
		{/if}

		<!-- Guardar -->
		<button
			on:click={save}
			disabled={saving}
			class="mb-4 w-full rounded-xl bg-gradient-to-r from-pink-600 to-purple-600 py-3 font-bold text-white shadow-lg transition hover:brightness-110 disabled:opacity-40"
		>
			{saving ? 'Guardando...' : 'Guardar cambios'}
		</button>

		<!-- Enlaces -->
		<div class="mb-6 space-y-1 rounded-2xl border border-white/5 bg-black/30">
			<a
				href="/perfil"
				class="flex items-center justify-between px-5 py-4 text-sm text-pink-300 transition hover:bg-white/5"
			>
				<span>Mi perfil</span>
				<span class="text-white/20">›</span>
			</a>
			<a
				href="/suscripciones"
				class="flex items-center justify-between border-t border-white/5 px-5 py-4 text-sm text-pink-300 transition hover:bg-white/5"
			>
				<span>Mis suscripciones</span>
				<span class="text-white/20">›</span>
			</a>
			<a
				href="/publicar"
				class="flex items-center justify-between border-t border-white/5 px-5 py-4 text-sm text-pink-300 transition hover:bg-white/5"
			>
				<span>Nueva publicación</span>
				<span class="text-white/20">›</span>
			</a>
		</div>

		<!-- Cerrar sesión -->
		<button
			on:click={handleLogout}
			class="w-full rounded-xl border border-red-500/30 py-3 text-sm font-medium text-red-400 transition hover:bg-red-900/20"
		>
			Cerrar sesión
		</button>
	</div>
{/if}
