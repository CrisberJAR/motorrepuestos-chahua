'use client';
import { ArrowRight, ScanFace } from 'lucide-react';
import Link from 'next/link';
import { FilaPermiso } from '@/components/fila-permiso';
import { GraficoDias } from '@/components/grafico-dias';
import { useYo } from '@/components/sesion';
import { Avatar, Cargando, ChipDia, Encabezado, FilaKpis, Kpi, Leyenda, MensajeError, Tarjeta, Vacio } from '@/components/ui';
import { ahoraLima, capitalizar, diaSemana, fechaCorta, fechaLarga, horaCorta, nombrePeriodo, periodoDe, rangoPeriodo, soles, ultimosLaborables } from '@/lib/fechas';
import { useConsulta, useFotos } from '@/lib/hooks';
import { supabaseNavegador } from '@/lib/supabase/navegador';
import { nombreCorto, type DiaAsistencia, type PagoPendiente, type Permiso } from '@/lib/tipos';

export default function PaginaPanel() {
  const yo = useYo();
  return yo.esAdmin ? <PanelAdmin /> : <PanelTrabajador />;
}

/* ============================== ADMINISTRADOR ============================== */
function PanelAdmin() {
  const hoy = ahoraLima().fecha;
  const dias = ultimosLaborables(hoy, 6);
  const esDomingo = diaSemana(hoy) === 0;

  const { datos, error, cargando, recargar } = useConsulta(
    async () => {
      const sb = supabaseNavegador();
      const [detalle, pendientes, personal] = await Promise.all([
        sb.rpc('detalle_asistencia', { p_desde: dias[0], p_hasta: hoy }),
        sb
          .from('permisos')
          .select('*, personal:personal_id(id, dni, nombres, apellidos, foto_rostro_url)')
          .eq('estado', 'pendiente')
          .order('created_at', { ascending: false }),
        sb.from('personal').select('id, foto_rostro_url').eq('estado', 'activo'),
      ]);
      if (detalle.error) throw new Error(detalle.error.message);
      if (pendientes.error) throw new Error(pendientes.error.message);
      return {
        detalle: (detalle.data || []) as DiaAsistencia[],
        pendientes: (pendientes.data || []) as Permiso[],
        rutas: Object.fromEntries((personal.data || []).map((p) => [p.id, p.foto_rostro_url as string | null])),
      };
    },
    [hoy],
    ['asistencias', 'permisos', 'personal'],
  );

  const fotos = useFotos(Object.values(datos?.rutas || {}));
  const foto = (id: string) => {
    const ruta = datos?.rutas[id];
    return ruta ? fotos[ruta] : undefined;
  };

  if (cargando && !datos) return <Cargando />;
  if (error && !datos) return <MensajeError texto={error} onReintentar={recargar} />;
  if (!datos) return null;

  const deHoy = datos.detalle.filter((d) => d.fecha === hoy);
  const presentes = deHoy.filter((d) => d.estado === 'asistio' || d.estado === 'tardanza').length;
  const tardanzas = deHoy.filter((d) => d.estado === 'tardanza').length;
  const sinMarcar = deHoy.filter((d) => d.estado === 'pendiente').length;
  const conPermiso = deHoy.filter((d) => d.estado === 'permiso').length;
  const trabajadores = new Set(datos.detalle.map((d) => d.personal_id)).size;

  const grafico = dias.map((dia) => {
    const del = datos.detalle.filter((d) => d.fecha === dia);
    const cuenta = (e: string) => del.filter((d) => d.estado === e).length;
    return { dia: fechaCorta(dia), asistio: cuenta('asistio'), tardanza: cuenta('tardanza'), permiso: cuenta('permiso'), falta: cuenta('falta') };
  });

  return (
    <>
      <Encabezado
        titulo="Panel del día"
        subtitulo={capitalizar(fechaLarga(hoy))}
        acciones={
          <span className="inline-flex items-center gap-1.5 font-mono text-[11px] tracking-wide text-ok uppercase">
            <i className="pulso size-2 rounded-full bg-ok" /> En vivo
          </span>
        }
      />

      <FilaKpis>
        <Kpi etiqueta="Presentes hoy" valor={<>{presentes}<span className="text-lg text-tenue">/{deHoy.length || trabajadores}</span></>} />
        <Kpi etiqueta="Tardanzas hoy" valor={tardanzas} tono={tardanzas ? 'alerta' : undefined} />
        <Kpi etiqueta="Sin marcar" valor={sinMarcar} detalle={conPermiso ? `${conPermiso} con permiso` : undefined} />
        <Kpi etiqueta="Permisos por revisar" valor={datos.pendientes.length} tono={datos.pendientes.length ? 'acento' : undefined} />
      </FilaKpis>

      <div className="grid gap-4 xl:grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)]">
        <Tarjeta titulo="Marcaciones de hoy" extra="Entrada 08:00 · tolerancia 10 min">
          {esDomingo ? (
            <Vacio titulo="Hoy es domingo" texto="No es día laborable; no se registra asistencia." />
          ) : (
            <ul className="flex flex-col">
              {deHoy.map((d) => (
                <li key={d.personal_id} className="flex items-center gap-3 border-t border-linea py-2.5 first:border-t-0 first:pt-0">
                  <Avatar persona={d} url={foto(d.personal_id)} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-semibold">{nombreCorto(d)}</p>
                    <p className="truncate text-xs text-tenue">{d.cargo}</p>
                  </div>
                  <div className="text-right">
                    <p className="cifras font-mono text-xs">
                      {horaCorta(d.hora_entrada)}
                      {d.hora_salida ? ` – ${horaCorta(d.hora_salida)}` : ''}
                    </p>
                    {d.confianza_facial != null && <p className="font-mono text-[10px] text-tenue">{Number(d.confianza_facial).toFixed(1)} % rostro</p>}
                  </div>
                  <ChipDia estado={d.estado} />
                </li>
              ))}
            </ul>
          )}
        </Tarjeta>

        <div className="flex min-w-0 flex-col gap-4">
          <Tarjeta titulo="Últimos 6 días laborables" extra={`${trabajadores} trabajadores`}>
            <GraficoDias datos={grafico} total={trabajadores} />
            <Leyenda />
          </Tarjeta>
          <Tarjeta titulo="Permisos por revisar" extra={<Link href="/permisos" className="inline-flex items-center gap-1 text-acento">Ver todos <ArrowRight className="size-3" /></Link>}>
            {datos.pendientes.length ? (
              datos.pendientes.slice(0, 4).map((p) => <FilaPermiso key={p.id} permiso={p} admin foto={foto(p.personal_id)} onCambio={recargar} />)
            ) : (
              <p className="text-[13px] text-tenue">No hay solicitudes pendientes.</p>
            )}
          </Tarjeta>
        </div>
      </div>

      <p className="flex items-center gap-2 rounded-lg border border-dashed border-linea px-3 py-2.5 text-xs text-tenue">
        <ScanFace className="size-4 shrink-0" />
        La marcación por reconocimiento facial se hace solo desde el celular del administrador. Lo que se marque aparece aquí al instante.
      </p>
    </>
  );
}

/* ============================== TRABAJADOR ============================== */
function PanelTrabajador() {
  const yo = useYo();
  const hoy = ahoraLima().fecha;
  const mes = periodoDe(hoy);
  const { desde, hasta } = rangoPeriodo(mes);

  const { datos, error, cargando, recargar } = useConsulta(
    async () => {
      const sb = supabaseNavegador();
      const [detalle, permisos, pendiente] = await Promise.all([
        sb.rpc('detalle_asistencia', { p_desde: desde, p_hasta: hasta, p_personal_id: yo.id }),
        sb.from('permisos').select('*').eq('personal_id', yo.id).order('created_at', { ascending: false }).limit(3),
        sb.rpc('pagos_pendientes', { p_personal_id: yo.id }),
      ]);
      if (detalle.error) throw new Error(detalle.error.message);
      return {
        detalle: (detalle.data || []) as DiaAsistencia[],
        permisos: (permisos.data || []) as Permiso[],
        pendiente: ((pendiente.data || []) as PagoPendiente[])[0] || null,
      };
    },
    [mes, yo.id],
    ['asistencias', 'permisos', 'pagos'],
  );

  if (cargando && !datos) return <Cargando />;
  if (error && !datos) return <MensajeError texto={error} onReintentar={recargar} />;
  if (!datos) return null;

  const dia = datos.detalle.find((d) => d.fecha === hoy);
  const cuenta = (e: string) => datos.detalle.filter((d) => d.estado === e).length;
  const asistidos = cuenta('asistio') + cuenta('tardanza');
  const pend = datos.pendiente;

  const textoHoy = !dia
    ? 'Hoy es domingo: no es día laborable.'
    : dia.estado === 'pendiente'
      ? 'Aún no tienes entrada registrada hoy. El administrador la marca con tu rostro al llegar.'
      : dia.estado === 'permiso'
        ? 'Hoy tienes permiso aprobado.'
        : `Entrada ${horaCorta(dia.hora_entrada)}${dia.hora_salida ? ` · salida ${horaCorta(dia.hora_salida)}` : ''}${dia.confianza_facial ? ` · ${Number(dia.confianza_facial).toFixed(1)} % de coincidencia facial` : ''}`;

  return (
    <>
      <Encabezado titulo={`Hola, ${yo.nombres.split(' ')[0]}`} subtitulo={`${yo.cargo} · ${yo.area}`} />

      <Tarjeta titulo={`Hoy, ${fechaLarga(hoy, false)}`} extra={dia ? <ChipDia estado={dia.estado} /> : undefined}>
        <p className="text-[13px]">{textoHoy}</p>
      </Tarjeta>

      <h2 className="text-sm font-semibold">{capitalizar(nombrePeriodo(mes))}</h2>
      <FilaKpis>
        <Kpi etiqueta="Días asistidos" valor={asistidos} />
        <Kpi etiqueta="Tardanzas" valor={cuenta('tardanza')} tono={cuenta('tardanza') ? 'alerta' : undefined} detalle="No descuentan" />
        <Kpi etiqueta="Permisos" valor={cuenta('permiso')} />
        <Kpi etiqueta="Faltas" valor={cuenta('falta')} tono={cuenta('falta') ? 'peligro' : undefined} />
      </FilaKpis>

      <div className="grid gap-4 md:grid-cols-2">
        <Tarjeta titulo="Por cobrar" extra="desde tu último pago">
          <p className="cifras font-display text-5xl font-bold">{soles(Number(pend?.monto_pendiente || 0))}</p>
          <p className="text-xs text-tenue">
            {pend && pend.desde <= pend.hasta
              ? `${pend.dias_asistidos + pend.dias_permiso_pagado} día(s) desde el ${fechaLarga(pend.desde, false)}`
              : 'Estás al día con tus pagos.'}
          </p>
          <Link href="/pagos" className="inline-flex items-center gap-1 text-[13px] font-semibold text-acento">
            Ver mis pagos <ArrowRight className="size-3.5" />
          </Link>
        </Tarjeta>
        <Tarjeta titulo="Mis permisos recientes" extra={<Link href="/permisos" className="text-acento">Ver todos</Link>}>
          {datos.permisos.length ? (
            datos.permisos.map((p) => <FilaPermiso key={p.id} permiso={p} admin={false} onCambio={recargar} />)
          ) : (
            <p className="text-[13px] text-tenue">Aún no tienes permisos registrados.</p>
          )}
        </Tarjeta>
      </div>
    </>
  );
}
