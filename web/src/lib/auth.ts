import 'server-only';
import { ErrorHttp } from '@/lib/http';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { supabaseServidor } from '@/lib/supabase/server';

export type Rol = 'admin' | 'trabajador';

export type Sesion = {
  userId: string;
  personal: {
    id: string;
    dni: string;
    nombres: string;
    apellidos: string;
    cargo: string;
    area: string;
    rol: Rol;
  };
};

/**
 * Identifica a quien llama al endpoint.
 *  - App Flutter: encabezado "Authorization: Bearer <access_token de Supabase>".
 *  - Web Next.js: cookies de sesión de @supabase/ssr.
 * Devuelve null si no hay sesión válida o si el trabajador está inactivo.
 */
export async function obtenerSesion(req: Request): Promise<Sesion | null> {
  const encabezado = req.headers.get('authorization') || '';
  const token = encabezado.match(/^Bearer\s+(.+)$/i)?.[1];

  let userId: string | null = null;
  if (token) {
    const { data, error } = await supabaseAdmin().auth.getUser(token);
    if (!error && data.user) userId = data.user.id;
  } else {
    const sb = await supabaseServidor();
    const { data } = await sb.auth.getUser();
    userId = data.user?.id ?? null;
  }
  if (!userId) return null;

  const { data: personal } = await supabaseAdmin()
    .from('personal')
    .select('id, dni, nombres, apellidos, cargo, area, rol, estado')
    .eq('user_id', userId)
    .maybeSingle();

  if (!personal || personal.estado !== 'activo') return null;
  return {
    userId,
    personal: {
      id: personal.id, dni: personal.dni, nombres: personal.nombres, apellidos: personal.apellidos,
      cargo: personal.cargo, area: personal.area, rol: personal.rol as Rol,
    },
  };
}

/** Exige sesión; si se indica "admin", exige además el rol de administrador. */
export async function exigirSesion(req: Request, rol?: 'admin'): Promise<Sesion> {
  const sesion = await obtenerSesion(req);
  if (!sesion) throw new ErrorHttp(401, 'Tu sesión expiró o no es válida. Vuelve a iniciar sesión.');
  if (rol === 'admin' && sesion.personal.rol !== 'admin') {
    throw new ErrorHttp(403, 'Esta acción solo la puede realizar el administrador.');
  }
  return sesion;
}
