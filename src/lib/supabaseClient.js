// src/lib/supabaseClient.js
// Cliente de Supabase para el navegador.
import { createBrowserClient } from '@supabase/ssr';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error(
        'Missing Supabase environment variables. Make sure VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY are set.'
    );
}

export const supabase = createBrowserClient(
    SUPABASE_URL,
    SUPABASE_ANON_KEY
);

// Helper útil
export async function getCurrentSession() {
    return await supabase.auth.getSession();
}