import 'server-only';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import ExcelJS from 'exceljs';
import { jsPDF } from 'jspdf';
import { autoTable, type RowInput } from 'jspdf-autotable';
import { ErrorHttp } from '@/lib/http';
import { ahoraLima, diaCorto, fechaNum, horaCorta } from '@/lib/fechas';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { ETIQUETA_DIA, ETIQUETA_METODO, type DiaAsistencia, type DiaPago, type MetodoPago, type Pago, type PagoPendiente } from '@/lib/tipos';

export type TipoReporte = 'asistencia' | 'pagos' | 'comprobante';
export type Formato = 'pdf' | 'xlsx';

type Columna = { titulo: string; ancho: number; dinero?: boolean; numero?: boolean };
type Seccion = { titulo: string; columnas: Columna[]; filas: (string | number)[][]; totales?: (string | number)[] };
export type Reporte = { titulo: string; subtitulo: string; nombreArchivo: string; secciones: Seccion[]; notas?: string[] };

const EMPRESA = 'Motorrepuestos Chahua';
const dinero = (n: number) => `S/ ${Number(n).toFixed(2)}`;
const persona = (p: { nombres: string; apellidos: string }) => `${p.apellidos}, ${p.nombres}`;
const archivo = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-zA-Z0-9_-]+/g, '_');

/* ============================== Datos ============================== */

/** Asistencia día por día y resumen por trabajador. */
export async function reporteAsistencia(desde: string, hasta: string, personalId: string | null): Promise<Reporte> {
  const sb = supabaseAdmin();
  const { data, error } = await sb.rpc('detalle_asistencia', { p_desde: desde, p_hasta: hasta, p_personal_id: personalId });
  if (error) throw new ErrorHttp(500, `No se pudo leer la asistencia: ${error.message}`);
  const dias = ((data || []) as DiaAsistencia[]).filter((d) => d.estado !== 'futuro');

  const resumen = new Map<string, { nombre: string; dni: string; cargo: string; a: number; t: number; p: number; f: number }>();
  for (const d of dias) {
    const r = resumen.get(d.personal_id) || { nombre: persona(d), dni: d.dni, cargo: d.cargo, a: 0, t: 0, p: 0, f: 0 };
    if (d.estado === 'asistio') r.a++;
    if (d.estado === 'tardanza') r.t++;
    if (d.estado === 'permiso') r.p++;
    if (d.estado === 'falta') r.f++;
    resumen.set(d.personal_id, r);
  }
  const filasResumen = [...resumen.values()].map((r) => [r.nombre, r.dni, r.cargo, r.a + r.t, r.t, r.p, r.f]);
  const unico = personalId && dias[0] ? persona(dias[0]) : null;

  return {
    titulo: 'Reporte de asistencia',
    subtitulo: `${unico ? unico + ' · ' : ''}Del ${fechaNum(desde)} al ${fechaNum(hasta)}`,
    nombreArchivo: `asistencia_${unico ? archivo(unico) + '_' : ''}${desde}_${hasta}`,
    secciones: [
      {
        titulo: 'Resumen por trabajador',
        columnas: [
          { titulo: 'Trabajador', ancho: 34 }, { titulo: 'DNI', ancho: 12 }, { titulo: 'Cargo', ancho: 24 },
          { titulo: 'Asistió', ancho: 10, numero: true }, { titulo: 'Tardanzas', ancho: 11, numero: true },
          { titulo: 'Permisos', ancho: 10, numero: true }, { titulo: 'Faltas', ancho: 9, numero: true },
        ],
        filas: filasResumen,
        totales: ['TOTAL', '', '', ...[3, 4, 5, 6].map((i) => filasResumen.reduce((s, f) => s + Number(f[i]), 0))],
      },
      {
        titulo: 'Detalle por día',
        columnas: [
          { titulo: 'Fecha', ancho: 12 }, { titulo: 'Día', ancho: 6 }, { titulo: 'Trabajador', ancho: 34 }, { titulo: 'DNI', ancho: 11 },
          { titulo: 'Estado', ancho: 12 }, { titulo: 'Entrada', ancho: 9 }, { titulo: 'Salida', ancho: 9 }, { titulo: 'Confianza', ancho: 10 },
        ],
        filas: dias.map((d) => [
          fechaNum(d.fecha), diaCorto(d.fecha), persona(d), d.dni,
          ETIQUETA_DIA[d.estado] + (d.estado === 'permiso' ? (d.permiso_con_goce ? ' (con goce)' : ' (sin goce)') : ''),
          d.hora_entrada ? horaCorta(d.hora_entrada) : '-', d.hora_salida ? horaCorta(d.hora_salida) : '-',
          d.confianza_facial != null ? `${Number(d.confianza_facial).toFixed(1)}%` : '-',
        ]),
      },
    ],
    notas: ['Horario: lunes a sábado de 08:00 a 19:00. Tolerancia de 10 minutos; desde las 08:11 es tardanza (no descuenta).'],
  };
}

/** Pagos realizados en el rango (por fecha de pago) y saldo pendiente a hoy. */
export async function reportePagos(desde: string, hasta: string, personalId: string | null): Promise<Reporte> {
  const sb = supabaseAdmin();
  let q = sb
    .from('pagos')
    .select('*, personal:personal_id(id, dni, nombres, apellidos, cargo, foto_rostro_url)')
    .gte('fecha_pago', desde)
    .lte('fecha_pago', hasta)
    .order('fecha_pago')
    .order('created_at');
  if (personalId) q = q.eq('personal_id', personalId);
  const [{ data, error }, pend] = await Promise.all([q, sb.rpc('pagos_pendientes', { p_personal_id: personalId })]);
  if (error) throw new ErrorHttp(500, `No se pudieron leer los pagos: ${error.message}`);
  if (pend.error) throw new ErrorHttp(500, `No se pudo calcular lo pendiente: ${pend.error.message}`);
  const pagos = (data || []) as Pago[];
  const pendientes = ((pend.data || []) as PagoPendiente[]).filter((p) => !personalId || p.personal_id === personalId);

  const filas = pagos.map((p) => [
    fechaNum(p.fecha_pago || p.fecha_hasta), p.personal ? persona(p.personal) : '', p.personal?.dni || '',
    `${fechaNum(p.fecha_desde)} - ${fechaNum(p.fecha_hasta)}`, p.dias_asistidos, p.dias_permiso_pagado,
    Number(p.monto_base), Number(p.bonos), Number(p.descuentos), Number(p.total_pagar),
    ETIQUETA_METODO[p.metodo_pago as MetodoPago] || p.metodo_pago, p.numero_operacion || '-',
  ]);
  const suma = (i: number) => filas.reduce((s, f) => s + Number(f[i]), 0);
  const unico = personalId ? (pagos[0]?.personal ? persona(pagos[0].personal) : pendientes[0] ? persona(pendientes[0]) : null) : null;

  return {
    titulo: 'Reporte de pagos',
    subtitulo: `${unico ? unico + ' · ' : ''}Pagos realizados del ${fechaNum(desde)} al ${fechaNum(hasta)}`,
    nombreArchivo: `pagos_${unico ? archivo(unico) + '_' : ''}${desde}_${hasta}`,
    secciones: [
      {
        titulo: 'Pagos realizados',
        columnas: [
          { titulo: 'Fecha pago', ancho: 11 }, { titulo: 'Trabajador', ancho: 30 }, { titulo: 'DNI', ancho: 10 },
          { titulo: 'Periodo pagado', ancho: 22 }, { titulo: 'Días', ancho: 6, numero: true }, { titulo: 'Perm. pag.', ancho: 8, numero: true },
          { titulo: 'Base', ancho: 11, dinero: true }, { titulo: 'Bonos', ancho: 10, dinero: true }, { titulo: 'Desc.', ancho: 10, dinero: true },
          { titulo: 'Total', ancho: 12, dinero: true }, { titulo: 'Método', ancho: 13 }, { titulo: 'N° operación', ancho: 13 },
        ],
        filas,
        totales: ['TOTAL', '', '', '', suma(4), suma(5), suma(6), suma(7), suma(8), suma(9), '', ''],
      },
      {
        titulo: `Saldo pendiente al ${fechaNum(ahoraLima().fecha)}`,
        columnas: [
          { titulo: 'Trabajador', ancho: 30 }, { titulo: 'DNI', ancho: 10 }, { titulo: 'Tipo de pago', ancho: 20 },
          { titulo: 'Último pago hasta', ancho: 15 }, { titulo: 'Pendiente desde', ancho: 15 },
          { titulo: 'Días', ancho: 7, numero: true }, { titulo: 'Faltas', ancho: 7, numero: true }, { titulo: 'Por pagar', ancho: 13, dinero: true },
        ],
        filas: pendientes.map((p) => [
          persona(p), p.dni, p.tipo_pago === 'variable' ? 'Por rendimiento' : `Fijo ${dinero(Number(p.pago_por_dia))}/día`,
          p.ultimo_pago_hasta ? fechaNum(p.ultimo_pago_hasta) : 'Sin pagos', fechaNum(p.desde),
          p.dias_asistidos + p.dias_permiso_pagado, p.dias_falta, Number(p.monto_pendiente),
        ]),
        totales: ['TOTAL', '', '', '', '', '', '', pendientes.reduce((s, p) => s + Number(p.monto_pendiente), 0)],
      },
    ],
    notas: [
      'Cálculo: suma del monto de cada día asistido (pago por día o monto por rendimiento) + permisos con goce + bonos - descuentos.',
      'Las tardanzas no descuentan. Las faltas y los permisos sin goce no se pagan.',
    ],
  };
}

/** Comprobante de un pago con el detalle de cada día. */
export async function reporteComprobante(pagoId: string): Promise<{ reporte: Reporte; personalId: string }> {
  const sb = supabaseAdmin();
  const { data: pago, error } = await sb
    .from('pagos')
    .select('*, personal:personal_id(id, dni, nombres, apellidos, cargo, foto_rostro_url)')
    .eq('id', pagoId)
    .maybeSingle();
  if (error || !pago) throw new ErrorHttp(404, 'No existe ese pago.');
  const p = pago as Pago;
  const { data: dias, error: e2 } = await sb.rpc('detalle_pago', { p_personal_id: p.personal_id, p_desde: p.fecha_desde, p_hasta: p.fecha_hasta });
  if (e2) throw new ErrorHttp(500, `No se pudo leer el detalle: ${e2.message}`);
  const nombre = p.personal ? persona(p.personal) : '';

  return {
    personalId: p.personal_id,
    reporte: {
      titulo: 'Comprobante de pago',
      subtitulo: `${nombre} · DNI ${p.personal?.dni || ''} · ${p.personal?.cargo || ''}`,
      nombreArchivo: `comprobante_${archivo(nombre)}_${p.fecha_desde}_${p.fecha_hasta}`,
      secciones: [
        {
          titulo: 'Datos del pago',
          columnas: [{ titulo: 'Concepto', ancho: 40 }, { titulo: 'Detalle', ancho: 50 }],
          filas: [
            ['Periodo pagado', `Del ${fechaNum(p.fecha_desde)} al ${fechaNum(p.fecha_hasta)}`],
            ['Fecha de pago', p.fecha_pago ? fechaNum(p.fecha_pago) : '-'],
            ['Método de pago', ETIQUETA_METODO[p.metodo_pago as MetodoPago] || p.metodo_pago],
            ['N° de operación', p.numero_operacion || '-'],
            ['Días pagados', `${p.dias_asistidos} asistidos + ${p.dias_permiso_pagado} de permiso con goce`],
            ['Monto por días', dinero(Number(p.monto_base))],
            ['Bonos', dinero(Number(p.bonos))],
            ['Descuentos', dinero(Number(p.descuentos))],
            ['TOTAL PAGADO', dinero(Number(p.total_pagar))],
            ...(p.observacion ? [['Observación', p.observacion]] : []),
          ],
        },
        {
          titulo: 'Detalle por día',
          columnas: [
            { titulo: 'Fecha', ancho: 12 }, { titulo: 'Día', ancho: 6 }, { titulo: 'Estado', ancho: 18 },
            { titulo: 'Entrada', ancho: 9 }, { titulo: 'Salida', ancho: 9 }, { titulo: 'Monto', ancho: 12, dinero: true },
          ],
          filas: ((dias || []) as DiaPago[]).map((d) => [
            fechaNum(d.fecha), diaCorto(d.fecha),
            ETIQUETA_DIA[d.estado] + (d.estado === 'permiso' ? (d.permiso_con_goce ? ' (con goce)' : ' (sin goce)') : ''),
            d.hora_entrada ? horaCorta(d.hora_entrada) : '-', d.hora_salida ? horaCorta(d.hora_salida) : '-', Number(d.monto),
          ]),
          totales: ['TOTAL DÍAS', '', '', '', '', Number(p.monto_base)],
        },
      ],
      notas: ['Firma del trabajador: ______________________________', 'Firma del administrador: ___________________________'],
    },
  };
}

/* ============================== Archivos ============================== */

let logoCache: string | null = null;
async function logoBase64() {
  if (logoCache === null) {
    try {
      logoCache = (await readFile(path.join(process.cwd(), 'public', 'logo-reporte.png'))).toString('base64');
    } catch {
      logoCache = '';
    }
  }
  return logoCache;
}

export async function aPdf(r: Reporte): Promise<Buffer> {
  const columnasMax = Math.max(...r.secciones.map((s) => s.columnas.length));
  const doc = new jsPDF({ orientation: columnasMax > 8 ? 'landscape' : 'portrait', unit: 'mm', format: 'a4' });
  const ancho = doc.internal.pageSize.getWidth();
  const generado = ahoraLima();

  const logo = await logoBase64();
  if (logo) doc.addImage(logo, 'PNG', 14, 10, 20, 20);
  doc.setFont('helvetica', 'bold').setFontSize(16).setTextColor(20, 20, 20).text(r.titulo.toUpperCase(), 38, 17);
  doc.setFont('helvetica', 'normal').setFontSize(10).setTextColor(90, 90, 90).text(EMPRESA, 38, 22.5);
  doc.text(r.subtitulo, 38, 27.5, { maxWidth: ancho - 52 });
  doc.setFontSize(8).text(`Generado: ${fechaNum(generado.fecha)} ${generado.hora.slice(0, 5)}`, ancho - 14, 12, { align: 'right' });
  doc.setDrawColor(200, 30, 30).setLineWidth(0.6).line(14, 33, ancho - 14, 33);

  let y = 40;
  for (const s of r.secciones) {
    if (y > doc.internal.pageSize.getHeight() - 30) {
      doc.addPage();
      y = 18;
    }
    doc.setFont('helvetica', 'bold').setFontSize(11).setTextColor(20, 20, 20).text(s.titulo, 14, y);
    const formato = (v: string | number, c: Columna) => (typeof v === 'number' ? (c.dinero ? dinero(v) : String(v)) : v);
    const cuerpo: RowInput[] = s.filas.length
      ? s.filas.map((f) => f.map((v, i) => formato(v, s.columnas[i])))
      : [[{ content: 'Sin registros en este rango.', colSpan: s.columnas.length, styles: { textColor: [120, 120, 120], fontStyle: 'italic' } }]];
    autoTable(doc, {
      startY: y + 2,
      head: [s.columnas.map((c) => c.titulo)],
      body: cuerpo,
      foot:
        s.totales && s.filas.length
          ? [s.totales.map((v, i) => ({ content: formato(v, s.columnas[i]), styles: { halign: s.columnas[i].dinero || s.columnas[i].numero ? ('right' as const) : ('left' as const) } }))]
          : undefined,
      theme: 'grid',
      styles: { fontSize: 8, cellPadding: 1.6, lineColor: [225, 225, 225], textColor: [30, 30, 30] },
      headStyles: { fillColor: [24, 24, 27], textColor: 255, fontStyle: 'bold' },
      footStyles: { fillColor: [245, 245, 245], textColor: [20, 20, 20], fontStyle: 'bold' },
      alternateRowStyles: { fillColor: [250, 250, 250] },
      columnStyles: Object.fromEntries(s.columnas.map((c, i) => [i, { halign: c.dinero || c.numero ? 'right' : 'left' }])),
      margin: { left: 14, right: 14 },
    });
    y = (doc as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + 10;
  }
  if (r.notas?.length) {
    doc.setFont('helvetica', 'normal').setFontSize(8.5).setTextColor(90, 90, 90);
    for (const n of r.notas) {
      if (y > doc.internal.pageSize.getHeight() - 15) {
        doc.addPage();
        y = 18;
      }
      doc.text(n, 14, y, { maxWidth: ancho - 28 });
      y += 6;
    }
  }
  const paginas = doc.getNumberOfPages();
  for (let i = 1; i <= paginas; i++) {
    doc.setPage(i);
    doc.setFontSize(7.5).setTextColor(140, 140, 140);
    doc.text(`${EMPRESA} · Sistema de gestión de personal`, 14, doc.internal.pageSize.getHeight() - 8);
    doc.text(`Página ${i} de ${paginas}`, ancho - 14, doc.internal.pageSize.getHeight() - 8, { align: 'right' });
  }
  return Buffer.from(doc.output('arraybuffer'));
}

export async function aXlsx(r: Reporte): Promise<Buffer> {
  const libro = new ExcelJS.Workbook();
  libro.creator = EMPRESA;
  libro.created = new Date();
  const generado = ahoraLima();

  for (const s of r.secciones) {
    const hoja = libro.addWorksheet(s.titulo.slice(0, 31).replace(/[\\/?*[\]:]/g, '-'), { views: [{ state: 'frozen', ySplit: 4 }] });
    hoja.columns = s.columnas.map((c) => ({ width: Math.max(c.ancho, c.titulo.length + 2) }));
    hoja.mergeCells(1, 1, 1, s.columnas.length);
    hoja.getCell(1, 1).value = `${EMPRESA} · ${r.titulo}`;
    hoja.getCell(1, 1).font = { bold: true, size: 14 };
    hoja.mergeCells(2, 1, 2, s.columnas.length);
    hoja.getCell(2, 1).value = `${r.subtitulo} · ${s.titulo} · Generado ${fechaNum(generado.fecha)} ${generado.hora.slice(0, 5)}`;
    hoja.getCell(2, 1).font = { color: { argb: 'FF555555' } };

    const cabecera = hoja.getRow(4);
    s.columnas.forEach((c, i) => {
      const celda = cabecera.getCell(i + 1);
      celda.value = c.titulo;
      celda.font = { bold: true, color: { argb: 'FFFFFFFF' } };
      celda.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF18181B' } };
      celda.alignment = { horizontal: c.dinero || c.numero ? 'right' : 'left' };
    });
    const formatear = (fila: ExcelJS.Row) =>
      s.columnas.forEach((c, i) => {
        if (c.dinero) fila.getCell(i + 1).numFmt = '"S/" #,##0.00';
      });
    s.filas.forEach((f) => formatear(hoja.addRow(f)));
    if (s.totales && s.filas.length) {
      const total = hoja.addRow(s.totales);
      total.font = { bold: true };
      total.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFF2F2F2' } };
      formatear(total);
    }
    if (!s.filas.length) hoja.addRow(['Sin registros en este rango.']);
    if (s.filas.length) hoja.autoFilter = { from: { row: 4, column: 1 }, to: { row: 4, column: s.columnas.length } };
  }
  if (r.notas?.length) {
    const hoja = libro.addWorksheet('Notas');
    hoja.columns = [{ width: 110 }];
    r.notas.forEach((n) => hoja.addRow([n]));
  }
  return Buffer.from(await libro.xlsx.writeBuffer());
}
