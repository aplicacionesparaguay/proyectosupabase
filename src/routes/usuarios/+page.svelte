<script>
	import { supabase } from '$lib/supabaseClient';
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';

	/**
	 * Fila de `profiles` tal como la devuelve el select de este archivo.
	 * @typedef {Object} Usuario
	 * @property {string} id
	 * @property {string | null} [username]
	 * @property {string | null} [display_name]
	 * @property {boolean | null} [is_verified]
	 * @property {string} [created_at]
	 */

	/** @type {Usuario[]} */
	let usuarios = [];

	onMount(async () => {
		const { data, error } = await supabase
			.from('profiles')
			.select('id, username, display_name, role, is_verified, created_at')
			.order('created_at', { ascending: false });

		if (error) {
			console.error('Error cargando usuarios:', error);
		} else {
			usuarios = data || [];
		}
	});

	/**
	 * @param {string} id
	 */
	function verPerfil(id) {
		goto(`/usuarios/${id}`);
	}
</script>

<h1 class="mb-4 text-2xl font-bold">Usuarios registrados</h1>

{#if usuarios.length > 0}
	<ul class="space-y-2">
		{#each usuarios as u}
			<li
				class="cursor-pointer rounded-lg border p-3 transition hover:bg-gray-100"
				on:click={() => verPerfil(u.id)}
			>
				<p class="font-semibold text-green-600">
					{u.display_name || u.username || 'Usuario'}

					{#if u.is_verified}
						<span class="ml-1 text-blue-500">✓</span>
					{/if}
				</p>

				{#if u.username}
					<p class="text-sm text-gray-600">
						@{u.username}
					</p>
				{/if}

				<p class="text-xs text-gray-400">
					Creado:
					{new Date(u.created_at ?? '').toLocaleString()}
				</p>
			</li>
		{/each}
	</ul>
{:else}
	<p class="text-gray-500">No hay usuarios registrados.</p>
{/if}
