'use client';
import { supabaseNavegador } from '@/lib/supabase/navegador';
import type { EstadoPermiso, Permiso } from '@/lib/tipos';

// Los pagos pendientes se calculan en vivo (función pagos_pendientes), así que
// aprobar un permiso o cambiar su goce se refleja al instante sin recalcular nada.

export async function revisarPermiso(p: Permiso, estado: Exclude<EstadoPermiso, 'pendiente'>) {
  const { error } = await supabaseNavegador().from('permisos').update({ estado }).eq('id', p.id);
  if (error) throw new Error(`No se pudo actualizar el permiso: ${error.message}`);
}

export async function cambiarGoce(p: Permiso, conGoce: boolean) {
  const { error } = await supabaseNavegador().from('permisos').update({ con_goce: conGoce }).eq('id', p.id);
  if (error) throw new Error(`No se pudo actualizar el permiso: ${error.message}`);
}

export async function crearPermiso(datos: Omit<Permiso, 'id' | 'created_at' | 'fecha_revision' | 'observacion' | 'personal'>) {
  const { error } = await supabaseNavegador().from('permisos').insert(datos);
  if (error) {
    throw new Error(
      error.code === '42501' ? 'No tienes permiso para registrar esta solicitud.' : `No se pudo registrar el permiso: ${error.message}`,
    );
  }
}
