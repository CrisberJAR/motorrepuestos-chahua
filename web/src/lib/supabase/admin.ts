import 'server-only';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { SUPABASE_URL, servidor } from '@/lib/config';

let cliente: SupabaseClient | null = null;

/**
 * Cliente con service_role: ignora RLS. Solo se usa en endpoints del servidor
 * DESPUÉS de comprobar quién hace la petición y qué rol tiene.
 */
export function supabaseAdmin(): SupabaseClient {
  if (!cliente) {
    cliente = createClient(SUPABASE_URL, servidor.serviceRoleKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return cliente;
}
