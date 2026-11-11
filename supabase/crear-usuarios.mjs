// Crea en Supabase Auth un usuario por cada fila de la tabla personal.
//   Usuario (lo que escribe la persona): su DNI
//   Correo interno en Supabase:          <dni>@chahua.pe
//   Contraseña inicial:                   su DNI
// Uso:  node supabase/crear-usuarios.mjs
// Requiere haber ejecutado antes supabase/01_esquema_chahua.sql

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const carpeta = dirname(fileURLToPath(import.meta.url));
const env = Object.fromEntries(
  readFileSync(join(carpeta, '.env'), 'utf8')
    .split(/\r?\n/)
    .filter((l) => l.trim() && !l.trim().startsWith('#') && l.includes('='))
    .map((l) => {
      const i = l.indexOf('=');
      return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
    }),
);

const BASE = env.SUPABASE_URL;
const KEY = env.SUPABASE_SERVICE_ROLE_KEY;
const DOMINIO = env.DOMINIO_LOGIN || 'chahua.pe';

if (!BASE || !KEY) {
  console.error('Faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en supabase/.env');
  process.exit(1);
}

async function api(ruta, opciones = {}) {
  const res = await fetch(BASE + ruta, {
    ...opciones,
    headers: {
      apikey: KEY,
      Authorization: `Bearer ${KEY}`,
      'Content-Type': 'application/json',
      ...(opciones.headers || {}),
    },
  });
  const texto = await res.text();
  let cuerpo = null;
  try {
    cuerpo = texto ? JSON.parse(texto) : null;
  } catch {
    cuerpo = texto;
  }
  return { ok: res.ok, status: res.status, cuerpo };
}

const personal = await api('/rest/v1/personal?select=id,dni,nombres,apellidos,rol,user_id&order=rol.asc,apellidos.asc');
if (!personal.ok) {
  console.error('No se pudo leer la tabla personal. ¿Ya ejecutaste 01_esquema_chahua.sql?');
  console.error(personal.status, personal.cuerpo);
  process.exit(1);
}

const existentes = new Map();
for (let pagina = 1; ; pagina++) {
  const r = await api(`/auth/v1/admin/users?page=${pagina}&per_page=200`);
  if (!r.ok) {
    console.error('No se pudo listar los usuarios de Auth:', r.status, r.cuerpo);
    process.exit(1);
  }
  const usuarios = r.cuerpo?.users || [];
  usuarios.forEach((u) => existentes.set((u.email || '').toLowerCase(), u));
  if (usuarios.length < 200) break;
}

let errores = 0;
for (const p of personal.cuerpo) {
  const email = `${p.dni}@${DOMINIO}`.toLowerCase();
  let usuario = existentes.get(email);
  let accion = 'ya existía';

  if (!usuario) {
    const r = await api('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify({
        email,
        password: p.dni,
        email_confirm: true,
        user_metadata: { dni: p.dni, nombres: p.nombres, apellidos: p.apellidos, rol: p.rol },
      }),
    });
    if (!r.ok) {
      errores++;
      console.error(`ERROR  ${p.dni}  ${p.nombres} ${p.apellidos}:`, r.status, r.cuerpo);
      continue;
    }
    usuario = r.cuerpo;
    accion = 'creado';
  }

  if (p.user_id !== usuario.id) {
    const v = await api(`/rest/v1/personal?id=eq.${p.id}`, {
      method: 'PATCH',
      headers: { Prefer: 'return=minimal' },
      body: JSON.stringify({ user_id: usuario.id }),
    });
    if (!v.ok) {
      errores++;
      console.error(`ERROR al vincular ${p.dni}:`, v.status, v.cuerpo);
      continue;
    }
  }

  const etiqueta = p.rol === 'admin' ? 'ADMIN ' : 'PERSONAL';
  console.log(`${etiqueta.padEnd(8)}  usuario ${p.dni}  clave ${p.dni}  ${p.nombres} ${p.apellidos}  (${accion})`);
}

console.log(errores ? `\nTerminado con ${errores} error(es).` : '\nListo: todos los usuarios pueden iniciar sesión con su DNI.');
