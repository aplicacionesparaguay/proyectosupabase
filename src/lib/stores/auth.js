// src/lib/stores/auth.js
import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient'; // Tu cliente que funciona

/** @type {import('svelte/store').Writable<import('@supabase/supabase-js').Session | null>} */
export const session = writable(null);
/** @type {import('svelte/store').Writable<import('@supabase/supabase-js').User | null>} */
export const user = writable(null);

// Inicializar al cargar la app
supabase.auth.getSession().then(({ data: { session: initialSession }, error }) => {
  if (error) {
    console.error('Error getting initial session:', error);
    return;
  }
  
  session.set(initialSession);
  user.set(initialSession?.user ?? null);
}).catch(err => {
  console.error('Error initializing auth:', err);
});

// Escuchar cambios de sesión en tiempo real
supabase.auth.onAuthStateChange((event, currentSession) => {
  console.log('Auth event:', event, currentSession?.user?.email);
  
  session.set(currentSession);
  user.set(currentSession?.user ?? null);
});

// Agrega al final de auth.js
export async function logout() {
  const { error } = await supabase.auth.signOut();
  if (error) {
    console.error('Error logging out:', error);
    throw error;
  }
}