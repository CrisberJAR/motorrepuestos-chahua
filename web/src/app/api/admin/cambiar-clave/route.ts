import { exigirSesion } from '@/lib/auth';
import { ErrorHttp, json, manejar } from '@/lib/http';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { asegurarUsuario } from '@/lib/usuarios';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/**
 * POST /api/admin/cambiar-clave
 * Solo el administrador. Cambia la contraseña de cualquier trabajador o la suya.
 * JSON: { "personal_id": "<uuid>" | "dni": "72345678", "nueva_clave": "..." }
 * Para volver a la contraseña inicial, envía el DNI como nueva_clave.
 */
export const POST = manejar(async (req) => {
  const sesion = await exigirSesion(req, 'admin');
  const cuerpo = (await req.json().catch(() => null)) as { personal_id?: string; dni?: string; nueva_clave?: string } | null;
  if (!cuerpo) throw new ErrorHttp(400, 'Envía un JSON con personal_id o dni y nueva_clave.');

  const clave = (cuerpo.nueva_clave || '').trim();
  if (clave.length < 6) throw new ErrorHttp(400, 'La contraseña debe tener al menos 6 caracteres.');
  if (clave.length > 72) throw new ErrorHttp(400, 'La contraseña no puede superar los 72 caracteres.');

  const sb = supabaseAdmin();
  let consulta = sb.from('personal').select('id, dni, nombres, apellidos, rol, user_id');
  if (cuerpo.personal_id) consulta = consulta.eq('id', cuerpo.personal_id);
  else if (cuerpo.dni) consulta = consulta.eq('dni', cuerpo.dni.trim());
  else throw new ErrorHttp(400, 'Indica personal_id o dni.');

  const { data: trabajador } = await consulta.maybeSingle();
  if (!trabajador) throw new ErrorHttp(404, 'No existe ese trabajador.');

  if (!trabajador.user_id) {
    await asegurarUsuario(trabajador, clave);
  } else {
    const { error } = await sb.auth.admin.updateUserById(trabajador.user_id, { password: clave });
    if (error) throw new ErrorHttp(400, `No se pudo cambiar la contraseña: ${error.message}`);
  }

  const propia = trabajador.id === sesion.personal.id;
  return json({
    ok: true,
    mensaje: propia
      ? 'Tu contraseña fue cambiada. Úsala la próxima vez que inicies sesión.'
      : `Contraseña de ${trabajador.nombres} ${trabajador.apellidos} cambiada.`,
  });
});
