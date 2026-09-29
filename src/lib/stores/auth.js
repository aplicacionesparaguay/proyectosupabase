// src/lib/stores/auth.js
import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

/** @type {import('svelte/store').Writable<import('@supabase/supabase-js').Session | null>} */
export const session = writable(null);
/** @type {import('svelte/store').Writable<import('@supabase/supabase-js').User | null>} */
export const user = writable(null);

// Los stores se llenan en dos lugares y solo estos dos:
// 1. +layout.svelte, desde los `data` que devuelve +layout.server.js (fuente de verdad del servidor).
// 2. El unico `onAuthStateChange` de la app, montado en el onMount de +layout.svelte.
// Este modulo no debe ejecutar nada al importarse: se importa durante SSR.

export async function logout() {
  const { error } = await supabase.auth.signOut();
  if (error) {
    console.error('Error logging out:', error);
    throw error;
  }
}