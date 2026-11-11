import 'server-only';
import { correoDesdeDni } from '@/lib/config';
import { supabaseAdmin } from '@/lib/supabase/admin';

/** Busca un usuario de Supabase Auth por su correo interno (<dni>@dominio). */
export async function buscarUsuarioPorDni(dni: string) {
  const correo = correoDesdeDni(dni).toLowerCase();
  const sb = supabaseAdmin();
  for (let pagina = 1; pagina < 50; pagina++) {
    const { data, error } = await sb.auth.admin.listUsers({ page: pagina, perPage: 200 });
    if (error) throw new Error(error.message);
    const usuario = data.users.find((u) => (u.email || '').toLowerCase() === correo);
    if (usuario) return usuario;
    if (data.users.length < 200) return null;
  }
  return null;
}

/**
 * Crea (o recupera) la cuenta de acceso de un trabajador: usuario = DNI, contraseña inicial = DNI.
 * Deja vinculado personal.user_id.
 */
export async function asegurarUsuario(personal: { id: string; dni: string; nombres: string; apellidos: string; rol: string }, clave?: string) {
  const sb = supabaseAdmin();
  let usuario = await buscarUsuarioPorDni(personal.dni);

  if (!usuario) {
    const { data, error } = await sb.auth.admin.createUser({
      email: correoDesdeDni(personal.dni),
      password: clave || personal.dni,
      email_confirm: true,
      user_metadata: { dni: personal.dni, nombres: personal.nombres, apellidos: personal.apellidos, rol: personal.rol },
    });
    if (error || !data.user) throw new Error(`No se pudo crear el acceso: ${error?.message}`);
    usuario = data.user;
  }

  const { error } = await sb.from('personal').update({ user_id: usuario.id }).eq('id', personal.id);
  if (error) throw new Error(`No se pudo vincular el acceso: ${error.message}`);
  return usuario;
}
