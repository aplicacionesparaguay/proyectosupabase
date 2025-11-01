// src/lib/supabaseClient.js
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

// Incluir logs sólo en desarrollo
if (import.meta.env.MODE === 'development') {
  console.info('🔍 Supabase client (dev) init');
  console.info('URL:', SUPABASE_URL);
  console.info('KEY exists:', !!SUPABASE_ANON_KEY);
}

// Validar variables de entorno temprano
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  throw new Error(
    'Missing Supabase environment variables. Make sure VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY are set.'
  );
}

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    detectSessionInUrl: true,
  },
});

// Helper útil
export async function getCurrentSession() {
  return await supabase.auth.getSession();
}