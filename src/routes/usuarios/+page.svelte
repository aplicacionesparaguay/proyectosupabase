<script>
	import { supabase } from '$lib/supabaseClient';
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';

	let usuarios = [];

	onMount(async () => {
		const { data, error } = await supabase.from('profiles').select('id, username, email, created_at');
		if (error) console.error(error);
		else usuarios = data;
	});

	function verPerfil(id) {
		goto(`/usuarios/${id}`);
	}
</script>

<h1 class="text-2xl font-bold mb-4">Usuarios registrados</h1>

{#if usuarios.length > 0}
	<ul class="space-y-2">
		{#each usuarios as u}
			<li
				class="p-3 border rounded-lg cursor-pointer hover:bg-gray-100 transition"
				on:click={() => verPerfil(u.id)}
			>
				<p class="font-semibold text-green-600">{u.username}</p>
				<p class="text-sm text-gray-600">{u.email}</p>
				<p class="text-xs text-gray-400">Creado: {new Date(u.created_at).toLocaleString()}</p>
			</li>
		{/each}
	</ul>
{:else}
	<p class="text-gray-500">No hay usuarios registrados.</p>
{/if}
