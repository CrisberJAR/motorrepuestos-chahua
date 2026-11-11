export const ZONA = 'America/Lima';

const DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'setiembre', 'octubre', 'noviembre', 'diciembre'];

const p2 = (n: number) => String(n).padStart(2, '0');

/** Fecha (AAAA-MM-DD) y hora (HH:MM:SS) actuales en Lima. */
export function ahoraLima() {
  const partes = new Intl.DateTimeFormat('en-CA', {
    timeZone: ZONA, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  }).formatToParts(new Date());
  const v = (t: string) => partes.find((x) => x.type === t)?.value || '00';
  const hora = v('hour') === '24' ? '00' : v('hour');
  return { fecha: `${v('year')}-${v('month')}-${v('day')}`, hora: `${hora}:${v('minute')}:${v('second')}` };
}

const aFecha = (iso: string) => {
  const [a, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(a, m - 1, d));
};
const aIso = (f: Date) => `${f.getUTCFullYear()}-${p2(f.getUTCMonth() + 1)}-${p2(f.getUTCDate())}`;

export const esFechaIso = (s: unknown): s is string =>
  typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && aIso(aFecha(s)) === s;

export function sumarDias(iso: string, dias: number) {
  const f = aFecha(iso);
  f.setUTCDate(f.getUTCDate() + dias);
  return aIso(f);
}

export const diaSemana = (iso: string) => aFecha(iso).getUTCDay(); // 0 = domingo

export const periodoDe = (iso: string) => iso.slice(0, 7);

export function rangoPeriodo(periodo: string) {
  const [a, m] = periodo.split('-').map(Number);
  const fin = new Date(Date.UTC(a, m, 0));
  return { desde: `${periodo}-01`, hasta: aIso(fin) };
}

export const esPeriodo = (s: unknown): s is string => typeof s === 'string' && /^\d{4}-(0[1-9]|1[0-2])$/.test(s);

/** "lunes 9 de noviembre de 2026" */
export function fechaLarga(iso: string, conAnio = true) {
  const f = aFecha(iso);
  return `${DIAS[f.getUTCDay()]} ${f.getUTCDate()} de ${MESES[f.getUTCMonth()]}${conAnio ? ' de ' + f.getUTCFullYear() : ''}`;
}

/** "noviembre de 2026" */
export function nombrePeriodo(periodo: string) {
  const [a, m] = periodo.split('-').map(Number);
  return `${MESES[m - 1]} de ${a}`;
}

/** "07:56:12" -> "07:56 a. m." */
export function hora12(hhmmss: string) {
  const [h, m] = hhmmss.split(':').map(Number);
  const sufijo = h < 12 ? 'a. m.' : 'p. m.';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${p2(h12)}:${p2(m)} ${sufijo}`;
}

export const soles = (n: number) =>
  'S/ ' + Number(n).toLocaleString('es-PE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const DIAS_CORTOS = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
const MESES_CORTOS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];

/** "lun 9 nov" */
export function fechaCorta(iso: string) {
  const f = aFecha(iso);
  return `${DIAS_CORTOS[f.getUTCDay()]} ${f.getUTCDate()} ${MESES_CORTOS[f.getUTCMonth()]}`;
}

/** "9 nov" */
export const diaMes = (iso: string) => `${aFecha(iso).getUTCDate()} ${MESES_CORTOS[aFecha(iso).getUTCMonth()]}`;

export const diaCorto = (iso: string) => DIAS_CORTOS[diaSemana(iso)];
export const numeroDia = (iso: string) => aFecha(iso).getUTCDate();

/** Lunes de la semana de la fecha dada. */
export const inicioSemana = (iso: string) => sumarDias(iso, -((diaSemana(iso) + 6) % 7));

export function sumarMeses(periodo: string, meses: number) {
  const [a, m] = periodo.split('-').map(Number);
  const f = new Date(Date.UTC(a, m - 1 + meses, 1));
  return `${f.getUTCFullYear()}-${p2(f.getUTCMonth() + 1)}`;
}

/** Días de lunes a sábado entre dos fechas (incluidas). */
export function diasLaborables(desde: string, hasta: string) {
  const dias: string[] = [];
  for (let d = desde; d <= hasta; d = sumarDias(d, 1)) if (diaSemana(d) !== 0) dias.push(d);
  return dias;
}

/** Los últimos n días laborables hasta la fecha dada (incluida si es laborable). */
export function ultimosLaborables(hasta: string, n: number) {
  const dias: string[] = [];
  for (let d = hasta; dias.length < n; d = sumarDias(d, -1)) if (diaSemana(d) !== 0) dias.unshift(d);
  return dias;
}

export const capitalizar = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
export const horaCorta = (h: string | null) => (h ? h.slice(0, 5) : '--:--');
