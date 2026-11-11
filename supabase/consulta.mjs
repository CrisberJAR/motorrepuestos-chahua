// Ejecuta una consulta SQL corta y muestra el resultado: node consulta.mjs "select ..."
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
const carpeta = dirname(fileURLToPath(import.meta.url));
const env = Object.fromEntries(readFileSync(join(carpeta, '.env'), 'utf8').split(/\r?\n/).filter((l) => l.includes('=') && !l.startsWith('#')).map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]));
const c = new pg.Client({ connectionString: env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
await c.connect();
try { const r = await c.query(process.argv[2]); console.table(r.rows); } catch (e) { console.error('ERROR:', e.message); process.exitCode = 1; } finally { await c.end(); }
