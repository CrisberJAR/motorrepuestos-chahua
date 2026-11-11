// Ejecuta un archivo .sql contra la base de Supabase usando DATABASE_URL de supabase/.env
// Uso: node ejecutar-sql.mjs 01_esquema_chahua.sql
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

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

const archivo = process.argv[2];
if (!archivo) {
  console.error('Indica el archivo .sql a ejecutar');
  process.exit(1);
}
const sql = readFileSync(resolve(carpeta, archivo), 'utf8');

const cliente = new pg.Client({ connectionString: env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
cliente.on('notice', (n) => console.log('AVISO:', n.message));

try {
  await cliente.connect();
  const resultado = await cliente.query(sql);
  const lista = Array.isArray(resultado) ? resultado : [resultado];
  const ultimo = lista[lista.length - 1];
  console.log(`OK: ${archivo} ejecutado (${lista.length} sentencias).`);
  if (ultimo?.rows?.length) console.table(ultimo.rows);
} catch (e) {
  console.error('ERROR:', e.message);
  if (e.position) {
    const pos = Number(e.position);
    const linea = sql.slice(0, pos).split('\n').length;
    console.error(`En la línea ${linea} del archivo:`);
    console.error(sql.split('\n').slice(Math.max(0, linea - 3), linea + 2).join('\n'));
  }
  if (e.where) console.error('Contexto:', e.where);
  process.exitCode = 1;
} finally {
  await cliente.end().catch(() => {});
}
