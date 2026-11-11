'use client';
import { ahoraLima, periodoDe, sumarMeses } from '@/lib/fechas';
import { supabaseNavegador } from '@/lib/supabase/navegador';
import type { EstadoPermiso, Permiso } from '@/lib/tipos';

/** Meses (AAAA-MM) que abarca un permiso, sin pasar del mes actual. */
function mesesDelPermiso(p: Pick<Permiso, 'fecha_inicio' | 'fecha_fin'>) {
  const actual = periodoDe(ahoraLima().fecha);
  const meses: string[] = [];
  for (let m = periodoDe(p.fecha_inicio); m <= periodoDe(p.fecha_fin) && m <= actual; m = sumarMeses(m, 1)) meses.push(m);
  return meses;
}

/** Recalcula la planilla de los meses afectados (no toca pagos ya pagados). */
async function recalcularPlanilla(p: Pick<Permiso, 'fecha_inicio' | 'fecha_fin'>) {
  const sb = supabaseNavegador();
  for (const mes of mesesDelPermiso(p)) {
    const { error } = await sb.rpc('generar_planilla', { p_periodo: mes });
    if (error) throw new Error(`Se guardó el permiso, pero no se pudo recalcular la planilla de ${mes}: ${error.message}`);
  }
}

export async function revisarPermiso(p: Permiso, estado: Exclude<EstadoPermiso, 'pendiente'>) {
  const { error } = await supabaseNavegador().from('permisos').update({ estado }).eq('id', p.id);
  if (error) throw new Error(`No se pudo actualizar el permiso: ${error.message}`);
  await recalcularPlanilla(p);
}

export async function cambiarGoce(p: Permiso, conGoce: boolean) {
  const { error } = await supabaseNavegador().from('permisos').update({ con_goce: conGoce }).eq('id', p.id);
  if (error) throw new Error(`No se pudo actualizar el permiso: ${error.message}`);
  await recalcularPlanilla(p);
}

export async function crearPermiso(datos: Omit<Permiso, 'id' | 'created_at' | 'fecha_revision' | 'observacion' | 'personal'>) {
  const { error } = await supabaseNavegador().from('permisos').insert(datos);
  if (error) {
    throw new Error(
      error.code === '42501' ? 'No tienes permiso para registrar esta solicitud.' : `No se pudo registrar el permiso: ${error.message}`,
    );
  }
  if (datos.estado === 'aprobado') await recalcularPlanilla(datos);
}
