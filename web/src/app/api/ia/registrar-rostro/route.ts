import { exigirSesion } from '@/lib/auth';
import { ErrorHttp, json, leerImagen, manejar } from '@/lib/http';
import { guardarRostroOficial } from '@/lib/personal-rostro';
import { normalizarFoto } from '@/lib/rostro';
import { supabaseAdmin } from '@/lib/supabase/admin';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const maxDuration = 30;

/**
 * POST /api/ia/registrar-rostro
 * Solo el administrador. Registra o reemplaza la foto oficial de un trabajador existente
 * y genera su descriptor facial para el reconocimiento.
 * Entrada: multipart { personal_id, imagen } o JSON { personal_id, imagen_base64 }
 */
export const POST = manejar(async (req) => {
  await exigirSesion(req, 'admin');
  const imagen = await leerImagen(req);
  const personalId = imagen!.campos.personal_id;
  if (!personalId) throw new ErrorHttp(400, 'Falta personal_id.');

  const { data: trabajador } = await supabaseAdmin()
    .from('personal')
    .select('id, dni, nombres, apellidos')
    .eq('id', personalId)
    .maybeSingle();
  if (!trabajador) throw new ErrorHttp(404, 'No existe un trabajador con ese id.');

  const jpeg = await normalizarFoto(imagen!.buffer);
  const { ruta, rostro } = await guardarRostroOficial(personalId, jpeg);

  return json({
    ok: true,
    mensaje: `Rostro de ${trabajador.nombres} ${trabajador.apellidos} registrado. Ya puede marcar asistencia.`,
    foto_rostro_url: ruta,
    rostro: { caja: rostro.caja, puntaje_deteccion: rostro.puntajeDeteccion },
  });
});
