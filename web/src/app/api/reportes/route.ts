import { exigirSesion } from '@/lib/auth';
import { ahoraLima, esFechaIso } from '@/lib/fechas';
import { ErrorHttp, manejar } from '@/lib/http';
import { aPdf, aXlsx, reporteAsistencia, reporteComprobante, reportePagos, type Formato, type Reporte, type TipoReporte } from '@/lib/reportes';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const TIPOS: TipoReporte[] = ['asistencia', 'pagos', 'comprobante'];

/**
 * GET /api/reportes?tipo=asistencia|pagos|comprobante&formato=pdf|xlsx&desde=AAAA-MM-DD&hasta=AAAA-MM-DD[&personal_id=uuid][&id=<pago>]
 * Web (cookies) o app móvil (Authorization: Bearer). El trabajador solo descarga lo suyo;
 * el administrador, de todos o de uno.
 */
export const GET = manejar(async (req) => {
  const sesion = await exigirSesion(req);
  const url = new URL(req.url);
  const tipo = url.searchParams.get('tipo') as TipoReporte;
  const formato = (url.searchParams.get('formato') || 'pdf') as Formato;
  if (!TIPOS.includes(tipo)) throw new ErrorHttp(400, 'Tipo de reporte no válido.');
  if (formato !== 'pdf' && formato !== 'xlsx') throw new ErrorHttp(400, 'Formato no válido: usa pdf o xlsx.');

  const esAdmin = sesion.personal.rol === 'admin';
  let reporte: Reporte;

  if (tipo === 'comprobante') {
    const id = url.searchParams.get('id') || '';
    const r = await reporteComprobante(id);
    if (!esAdmin && r.personalId !== sesion.personal.id) throw new ErrorHttp(403, 'Solo puedes descargar tus propios comprobantes.');
    reporte = r.reporte;
  } else {
    const hoy = ahoraLima().fecha;
    const desde = url.searchParams.get('desde') || `${hoy.slice(0, 7)}-01`;
    const hasta = url.searchParams.get('hasta') || hoy;
    if (!esFechaIso(desde) || !esFechaIso(hasta)) throw new ErrorHttp(400, 'Fechas no válidas: usa AAAA-MM-DD.');
    if (hasta < desde) throw new ErrorHttp(400, 'La fecha final no puede ser anterior a la inicial.');
    const dias = (Date.parse(hasta) - Date.parse(desde)) / 86400000;
    if (dias > 400) throw new ErrorHttp(400, 'El rango máximo es de un año.');
    const pedido = url.searchParams.get('personal_id') || null;
    const personalId = esAdmin ? pedido : sesion.personal.id;
    reporte = tipo === 'asistencia' ? await reporteAsistencia(desde, hasta, personalId) : await reportePagos(desde, hasta, personalId);
  }

  const contenido = formato === 'pdf' ? await aPdf(reporte) : await aXlsx(reporte);
  const nombre = `${reporte.nombreArchivo}.${formato}`;
  return new Response(new Uint8Array(contenido), {
    headers: {
      'Content-Type': formato === 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'Content-Disposition': `attachment; filename="${nombre}"`,
      'Cache-Control': 'no-store',
    },
  });
});
