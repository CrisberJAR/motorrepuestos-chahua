import { exigirSesion } from '@/lib/auth';
import { servidor } from '@/lib/config';
import { ahoraLima, hora12 } from '@/lib/fechas';
import { ErrorHttp, json, leerImagen, manejar } from '@/lib/http';
import { buscarCandidatos, nombreCorto } from '@/lib/personal-rostro';
import { analizarRostro, normalizarFoto, porcentaje } from '@/lib/rostro';
import { supabaseAdmin } from '@/lib/supabase/admin';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const maxDuration = 30;

/** Diferencia mínima de distancia entre el 1.er y 2.º candidato para no confundir a dos personas parecidas. */
const MARGEN_AMBIGUEDAD = 0.06;

type Marcacion = {
  tipo: 'entrada' | 'salida' | 'duplicado' | 'completo' | 'no_laborable';
  mensaje: string;
  asistencia?: { id: string; fecha: string; hora_entrada: string | null; hora_salida: string | null; estado: string };
};

/**
 * POST /api/ia/identificar-rostro
 * Solo el administrador. Recibe la foto tomada con su celular, identifica al trabajador (1:N)
 * y registra su entrada o salida del día.
 *
 * Entrada: multipart/form-data { imagen: File, solo_identificar?: "true" }
 *       o JSON { imagen_base64: "data:image/jpeg;base64,...", solo_identificar?: true }
 * Encabezado: Authorization: Bearer <access_token del administrador>
 */
export const POST = manejar(async (req) => {
  await exigirSesion(req, 'admin');
  const imagen = await leerImagen(req);
  const soloIdentificar = imagen!.campos.solo_identificar === 'true';

  const jpeg = await normalizarFoto(imagen!.buffer);
  const rostro = await analizarRostro(jpeg);
  const candidatos = await buscarCandidatos(rostro.descriptor, 2);

  if (!candidatos.length) {
    throw new ErrorHttp(404, 'Todavía no hay rostros registrados. Registra primero la foto oficial de cada trabajador.', { codigo: 'sin_registros' });
  }

  const umbral = servidor.umbralRostro();
  const [mejor, segundo] = candidatos;
  const confianza = porcentaje(mejor.similitud);

  if (mejor.distancia > umbral) {
    return json(
      {
        ok: false,
        reconocido: false,
        codigo: 'no_reconocido',
        error: 'Rostro no reconocido. La persona no está registrada o la foto no es clara; intenta de nuevo de frente y con buena luz.',
        mejor_coincidencia: confianza,
      },
      404,
    );
  }

  if (segundo && segundo.distancia <= umbral && segundo.distancia - mejor.distancia < MARGEN_AMBIGUEDAD) {
    return json(
      {
        ok: false,
        reconocido: false,
        codigo: 'ambiguo',
        error: `No se pudo distinguir entre ${nombreCorto(mejor)} y ${nombreCorto(segundo)}. Acerca la cámara y vuelve a escanear.`,
      },
      409,
    );
  }

  const trabajador = {
    id: mejor.personal_id,
    dni: mejor.dni,
    nombres: mejor.nombres,
    apellidos: mejor.apellidos,
    nombre_corto: nombreCorto(mejor),
    cargo: mejor.cargo,
    area: mejor.area,
    foto_rostro_url: mejor.foto_rostro_url,
  };

  if (soloIdentificar) {
    return json({ ok: true, reconocido: true, registrado: false, trabajador, confianza, distancia: mejor.distancia });
  }

  const sb = supabaseAdmin();
  const { fecha, hora } = ahoraLima();
  const rutaEvidencia = `${mejor.personal_id}/${fecha}_${hora.replace(/:/g, '')}.jpg`;
  const subida = await sb.storage.from('capturas_asistencia').upload(rutaEvidencia, jpeg, { contentType: 'image/jpeg', upsert: true });
  const evidencia = subida.error ? null : rutaEvidencia;
  if (subida.error) console.error('[identificar-rostro] no se guardó la evidencia', subida.error.message);

  const { data, error } = await sb.rpc('registrar_marcacion', {
    p_personal_id: mejor.personal_id,
    p_confianza: confianza,
    p_foto_url: evidencia,
  });
  if (error) throw new ErrorHttp(400, error.message);
  const marcacion = data as Marcacion;

  const registrado = marcacion.tipo === 'entrada' || marcacion.tipo === 'salida';
  if (!registrado && evidencia) {
    await sb.storage.from('capturas_asistencia').remove([evidencia]);
  }

  const asistencia = marcacion.asistencia;
  const horaMarcada = marcacion.tipo === 'salida' ? asistencia?.hora_salida : asistencia?.hora_entrada;
  const mensaje = registrado && horaMarcada
    ? `Rostro identificado: ${trabajador.nombre_corto} - ${confianza}% coincidencia - ${marcacion.tipo === 'entrada' ? 'Entrada' : 'Salida'} registrada ${hora12(horaMarcada)}`
    : `Rostro identificado: ${trabajador.nombre_corto} - ${confianza}% coincidencia - ${marcacion.mensaje}`;

  return json({
    ok: true,
    reconocido: true,
    registrado,
    tipo: marcacion.tipo,
    mensaje,
    trabajador,
    confianza,
    distancia: Math.round(mejor.distancia * 1000) / 1000,
    asistencia: asistencia
      ? { id: asistencia.id, fecha: asistencia.fecha, hora_entrada: asistencia.hora_entrada, hora_salida: asistencia.hora_salida, estado: asistencia.estado }
      : null,
    foto_evidencia_url: registrado ? evidencia : null,
    rostro: { caja: rostro.caja, puntaje_deteccion: rostro.puntajeDeteccion, rostros_en_foto: rostro.rostrosEnFoto },
  });
});
