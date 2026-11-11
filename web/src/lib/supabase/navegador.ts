'use client';
import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';
import { SUPABASE_ANON_KEY, SUPABASE_URL } from '@/lib/config';

let cliente: SupabaseClient | null = null;

/** Cliente de Supabase en el navegador: usa la sesión del usuario y respeta RLS. */
export function supabaseNavegador(): SupabaseClient {
  if (!cliente) cliente = createBrowserClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  return cliente;
}
