import 'server-only';
import { servidor } from '@/lib/config';
import { ErrorHttp } from '@/lib/http';
import { analizarRostro, porcentaje, vectorTexto, type RostroDetectado } from '@/lib/rostro';
import { supabaseAdmin } from '@/lib/supabase/admin';

export type Candidato = {
  personal_id: string;
  dni: string;
  nombres: string;
  apellidos: string;
  cargo: string;
  area: string;
  foto_rostro_url: string | null;
  distancia: number;
  similitud: number;
};

/** Busca en la base los rostros más parecidos (1:N con pgvector). */
export async function buscarCandidatos(descriptor: number[], limite = 2): Promise<Candidato[]> {
  const { data, error } = await supabaseAdmin().rpc('buscar_rostro', {
    p_descriptor: vectorTexto(descriptor),
    p_limite: limite,
  });
  if (error) throw new Error(`buscar_rostro: ${error.message}`);
  return (data || []) as Candidato[];
}

export const nombreCorto = (c: { nombres: string; apellidos: string }) =>
  `${c.nombres.split(' ')[0]} ${c.apellidos.split(' ')[0]}`;

/**
 * Analiza la foto oficial de un trabajador, verifica que ese rostro no pertenezca
 * ya a otra persona, la guarda en el bucket rostros_personal y actualiza su descriptor.
 */
export async function guardarRostroOficial(personalId: string, jpeg: Buffer): Promise<{ ruta: string; rostro: RostroDetectado }> {
  const rostro = await analizarRostro(jpeg, true);
  await verificarRostroNoDuplicado(rostro.descriptor, personalId);

  const sb = supabaseAdmin();
  const ruta = `${personalId}/rostro.jpg`;
  const subida = await sb.storage.from('rostros_personal').upload(ruta, jpeg, { contentType: 'image/jpeg', upsert: true });
  if (subida.error) throw new Error(`No se pudo guardar la foto: ${subida.error.message}`);

  const { error } = await sb
    .from('personal')
    .update({ foto_rostro_url: ruta, descriptor_facial: vectorTexto(rostro.descriptor) })
    .eq('id', personalId);
  if (error) throw new Error(`No se pudo guardar el descriptor facial: ${error.message}`);

  return { ruta, rostro };
}

/** Lanza 409 si el rostro ya está registrado a nombre de otro trabajador. */
export async function verificarRostroNoDuplicado(descriptor: number[], personalIdPropio?: string) {
  const candidatos = await buscarCandidatos(descriptor, 3);
  const otro = candidatos.find((c) => c.personal_id !== personalIdPropio && c.distancia <= servidor.umbralRostro());
  if (otro) {
    throw new ErrorHttp(
      409,
      `Este rostro ya está registrado a nombre de ${nombreCorto(otro)} (DNI ${otro.dni}, ${porcentaje(otro.similitud)} % de coincidencia).`,
      { codigo: 'rostro_duplicado' },
    );
  }
}
