'use client';
import { Banknote, ChevronLeft, ChevronRight, RefreshCw, Undo2 } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { useAvisos } from '@/components/avisos';
import { useYo } from '@/components/sesion';
import { Avatar, Boton, Cargando, Chip, Encabezado, FilaKpis, Kpi, MensajeError, Tarjeta, Vacio } from '@/components/ui';
import { ahoraLima, capitalizar, fechaLarga, nombrePeriodo, periodoDe, rangoPeriodo, soles, sumarMeses } from '@/lib/fechas';
import { useConsulta, useFotos } from '@/lib/hooks';
import { supabaseNavegador } from '@/lib/supabase/navegador';
import { nombreCorto, type DiaAsistencia, type Pago } from '@/lib/tipos';

const REGLA = (
  <p className="rounded-lg bg-hundido px-3 py-2.5 text-xs leading-relaxed text-tenue">
    <strong className="text-tinta">Cálculo:</strong> (días asistidos + días de permiso con goce) × pago por día − descuentos + bonos. Los días con tardanza
    cuentan como asistidos y no descuentan. Las faltas y los permisos sin goce no se pagan.
  </p>
);

function ChipPago({ pago, mesActual }: { pago: Pago; mesActual: boolean }) {
  if (pago.estado_pago === 'pagado') return <Chip clase="bg-ok-suave text-ok">Pagado{pago.fecha_pago ? ` · ${fechaLarga(pago.fecha_pago, false)}` : ''}</Chip>;
  return mesActual ? <Chip clase="bg-hundido text-tenue">Mes en curso</Chip> : <Chip clase="bg-alerta-suave text-alerta">Por pagar</Chip>;
}

export default function PaginaPagos() {
  const yo = useYo();
  return yo.esAdmin ? <PagosAdmin /> : <PagosTrabajador />;
}

/* ============================== ADMINISTRADOR ============================== */
function PagosAdmin() {
  const { avisar } = useAvisos();
  const mesActual = periodoDe(ahoraLima().fecha);
  const [periodo, setPeriodo] = useState(mesActual);
  const [generando, setGenerando] = useState(false);
  const recalculado = useRef<string | null>(null);

  const { datos, error, cargando, recargar } = useConsulta(
    async () => {
      const sb = supabaseNavegador();
      // El mes en curso se recalcula al abrirlo para reflejar la asistencia de hoy
      // (solo una vez: las recargas por tiempo real no vuelven a recalcular).
      if (periodo === mesActual && recalculado.current !== periodo) {
        recalculado.current = periodo;
        const { error: e } = await sb.rpc('generar_planilla', { p_periodo: periodo });
        if (e) throw new Error(e.message);
      }
      const { data, error: e } = await sb
        .from('pagos')
        .select('*, personal:personal_id(id, dni, nombres, apellidos, cargo, foto_rostro_url)')
        .eq('periodo_mes', periodo);
      if (e) throw new Error(e.message);
      return ((data || []) as Pago[]).sort((a, b) => (a.personal?.apellidos || '').localeCompare(b.personal?.apellidos || ''));
    },
    [periodo],
    ['pagos'],
  );
  const fotos = useFotos(datos?.map((p) => p.personal?.foto_rostro_url) || []);

  async function generar() {
    setGenerando(true);
    const { error: e } = await supabaseNavegador().rpc('generar_planilla', { p_periodo: periodo });
    setGenerando(false);
    if (e) return avisar(e.message, 'error');
    avisar(`Planilla de ${nombrePeriodo(periodo)} calculada. Los pagos ya realizados no se modificaron.`);
    recargar();
  }

  const total = datos?.reduce((s, p) => s + Number(p.total_pagar), 0) || 0;
  const pagado = datos?.filter((p) => p.estado_pago === 'pagado').reduce((s, p) => s + Number(p.total_pagar), 0) || 0;
  const futuro = periodo > mesActual;

  return (
    <>
      <Encabezado
        titulo="Pagos y planilla"
        subtitulo="Se calcula con la asistencia, los permisos con goce, los descuentos y los bonos del mes."
        acciones={
          !futuro && (
            <Boton variante="secundario" icono={<RefreshCw className="size-4" />} cargando={generando} onClick={generar}>
              Recalcular planilla
            </Boton>
          )
        }
      />

      <div className="flex items-center gap-2">
        <Boton variante="secundario" tam="sm" aria-label="Mes anterior" onClick={() => setPeriodo(sumarMeses(periodo, -1))}>
          <ChevronLeft className="size-4" />
        </Boton>
        <span className="min-w-40 text-center text-[13px] font-semibold">
          {capitalizar(nombrePeriodo(periodo))}
          {periodo === mesActual && <span className="font-normal text-tenue"> · en curso</span>}
        </span>
        <Boton variante="secundario" tam="sm" aria-label="Mes siguiente" onClick={() => setPeriodo(sumarMeses(periodo, 1))}>
          <ChevronRight className="size-4" />
        </Boton>
      </div>

      {cargando && !datos ? (
        <Cargando />
      ) : error && !datos ? (
        <MensajeError texto={error} onReintentar={recargar} />
      ) : !datos?.length ? (
        <Vacio
          titulo={futuro ? 'Este mes aún no empieza' : 'No hay planilla para este mes'}
          texto={futuro ? undefined : 'Genera la planilla para calcular el pago de cada trabajador con su asistencia.'}
          accion={!futuro && <Boton cargando={generando} onClick={generar}>Generar planilla</Boton>}
        />
      ) : (
        <>
          <FilaKpis>
            <Kpi etiqueta="Total planilla" valor={<span className="text-[26px]">{soles(total)}</span>} />
            <Kpi etiqueta="Pagado" valor={<span className="text-[26px]">{soles(pagado)}</span>} tono="ok" />
            <Kpi etiqueta="Por pagar" valor={<span className="text-[26px]">{soles(total - pagado)}</span>} tono={total - pagado > 0 && periodo < mesActual ? 'acento' : undefined} />
            <Kpi etiqueta="Trabajadores" valor={datos.length} />
          </FilaKpis>

          <div className="overflow-x-auto rounded-xl border border-linea bg-superficie">
            <table className="w-full border-collapse text-[13px]">
              <thead>
                <tr className="[&>th]:border-b [&>th]:border-linea [&>th]:bg-hundido [&>th]:px-3 [&>th]:py-2.5 [&>th]:text-[11px] [&>th]:font-semibold [&>th]:tracking-wide [&>th]:whitespace-nowrap [&>th]:text-tenue [&>th]:uppercase">
                  <th className="text-left">Trabajador</th>
                  <th className="text-right">Pago/día</th>
                  <th className="text-right">Asist.</th>
                  <th className="text-right">Perm. pagados</th>
                  <th className="text-right">Faltas</th>
                  <th className="text-right">Tard.</th>
                  <th className="text-right">Base</th>
                  <th className="text-right">Descuentos</th>
                  <th className="text-right">Bonos</th>
                  <th className="text-right">Total</th>
                  <th className="text-left">Estado</th>
                  <th />
                </tr>
              </thead>
              <tbody className="[&>tr:last-child>td]:border-b-0">
                {datos.map((p) => (
                  <FilaPago
                    key={p.id}
                    pago={p}
                    foto={p.personal?.foto_rostro_url ? fotos[p.personal.foto_rostro_url] : undefined}
                    mesActual={periodo === mesActual}
                    onCambio={recargar}
                  />
                ))}
              </tbody>
            </table>
          </div>
          {REGLA}
        </>
      )}
    </>
  );
}

function FilaPago({ pago, foto, mesActual, onCambio }: { pago: Pago; foto?: string; mesActual: boolean; onCambio: () => void }) {
  const { avisar } = useAvisos();
  const [descuentos, setDescuentos] = useState(String(pago.descuentos));
  const [bonos, setBonos] = useState(String(pago.bonos));
  const [ocupado, setOcupado] = useState(false);
  const pagado = pago.estado_pago === 'pagado';

  useEffect(() => {
    setDescuentos(String(pago.descuentos));
    setBonos(String(pago.bonos));
  }, [pago.descuentos, pago.bonos]);

  async function actualizar(cambios: Partial<Pago>, mensaje: string) {
    setOcupado(true);
    const { error } = await supabaseNavegador().from('pagos').update(cambios).eq('id', pago.id);
    setOcupado(false);
    if (error) return avisar(`No se pudo guardar: ${error.message}`, 'error');
    avisar(mensaje);
    onCambio();
  }

  function guardarMonto(campo: 'descuentos' | 'bonos', texto: string) {
    const valor = Math.round(Number(texto.replace(',', '.')) * 100) / 100;
    if (!Number.isFinite(valor) || valor < 0) {
      avisar('Ingresa un monto válido (0 o más).', 'error');
      return campo === 'descuentos' ? setDescuentos(String(pago.descuentos)) : setBonos(String(pago.bonos));
    }
    if (valor === Number(pago[campo])) return;
    actualizar({ [campo]: valor }, campo === 'descuentos' ? 'Descuento actualizado.' : 'Bono actualizado.');
  }

  const persona = pago.personal;
  const td = 'border-b border-linea px-3 py-2.5 align-middle';
  const entrada = 'w-24 rounded-md border border-linea bg-superficie px-2 py-1 text-right cifras';

  return (
    <tr>
      <td className={td}>
        {persona && (
          <div className="flex min-w-44 items-center gap-2.5">
            <Avatar persona={persona} url={foto} tam={30} />
            <span>
              <span className="block font-semibold whitespace-nowrap">{nombreCorto(persona)}</span>
              <span className="block text-xs text-tenue">DNI {persona.dni}</span>
            </span>
          </div>
        )}
      </td>
      <td className={`${td} cifras text-right whitespace-nowrap`}>{soles(Number(pago.pago_por_dia))}</td>
      <td className={`${td} cifras text-right`}>{pago.dias_asistidos}</td>
      <td className={`${td} cifras text-right`} title={`${pago.dias_permiso} días de permiso en total`}>
        {pago.dias_permiso_pagado}
        <span className="text-tenue">/{pago.dias_permiso}</span>
      </td>
      <td className={`${td} cifras text-right`}>{pago.dias_falta}</td>
      <td className={`${td} cifras text-right`}>{pago.tardanzas_acumuladas}</td>
      <td className={`${td} cifras text-right whitespace-nowrap`}>{soles(Number(pago.monto_base))}</td>
      <td className={`${td} text-right`}>
        {pagado ? (
          <span className="cifras whitespace-nowrap">{soles(Number(pago.descuentos))}</span>
        ) : (
          <input
            aria-label="Descuentos"
            className={entrada}
            inputMode="decimal"
            value={descuentos}
            disabled={ocupado}
            onChange={(e) => setDescuentos(e.target.value)}
            onBlur={(e) => guardarMonto('descuentos', e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()}
          />
        )}
      </td>
      <td className={`${td} text-right`}>
        {pagado ? (
          <span className="cifras whitespace-nowrap">{soles(Number(pago.bonos))}</span>
        ) : (
          <input
            aria-label="Bonos"
            className={entrada}
            inputMode="decimal"
            value={bonos}
            disabled={ocupado}
            onChange={(e) => setBonos(e.target.value)}
            onBlur={(e) => guardarMonto('bonos', e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && (e.target as HTMLInputElement).blur()}
          />
        )}
      </td>
      <td className={`${td} cifras text-right font-semibold whitespace-nowrap`}>{soles(Number(pago.total_pagar))}</td>
      <td className={td}>
        <ChipPago pago={pago} mesActual={mesActual} />
      </td>
      <td className={`${td} text-right`}>
        {pagado ? (
          <Boton variante="fantasma" tam="sm" icono={<Undo2 className="size-3.5" />} cargando={ocupado} onClick={() => actualizar({ estado_pago: 'pendiente' }, 'Pago revertido a pendiente.')}>
            Revertir
          </Boton>
        ) : (
          !mesActual && (
            <Boton variante="ok" tam="sm" icono={<Banknote className="size-3.5" />} cargando={ocupado} onClick={() => actualizar({ estado_pago: 'pagado' }, `Pago de ${persona ? nombreCorto(persona) : ''} marcado como pagado.`)}>
              Marcar pagado
            </Boton>
          )
        )}
      </td>
    </tr>
  );
}

/* ============================== TRABAJADOR ============================== */
function PagosTrabajador() {
  const yo = useYo();
  const hoy = ahoraLima().fecha;
  const mes = periodoDe(hoy);
  const { desde, hasta } = rangoPeriodo(mes);

  const { datos, error, cargando, recargar } = useConsulta(
    async () => {
      const sb = supabaseNavegador();
      const [pagos, detalle] = await Promise.all([
        sb.from('pagos').select('*').eq('personal_id', yo.id).order('periodo_mes', { ascending: false }),
        sb.rpc('detalle_asistencia', { p_desde: desde, p_hasta: hasta, p_personal_id: yo.id }),
      ]);
      if (pagos.error) throw new Error(pagos.error.message);
      return { pagos: (pagos.data || []) as Pago[], detalle: (detalle.data || []) as DiaAsistencia[] };
    },
    [yo.id, mes],
    ['pagos', 'asistencias', 'permisos'],
  );

  if (cargando && !datos) return <Cargando />;
  if (error && !datos) return <MensajeError texto={error} onReintentar={recargar} />;
  if (!datos) return null;

  // Mes en curso: cálculo en vivo con la asistencia registrada hasta hoy.
  const cuenta = (f: (d: DiaAsistencia) => boolean) => datos.detalle.filter(f).length;
  const asistidos = cuenta((d) => d.estado === 'asistio' || d.estado === 'tardanza');
  const permisos = cuenta((d) => d.estado === 'permiso');
  const permisosPagados = cuenta((d) => d.estado === 'permiso' && d.permiso_con_goce);
  const guardado = datos.pagos.find((p) => p.periodo_mes === mes);
  const vivo: Pago = {
    id: 'vivo',
    personal_id: yo.id,
    periodo_mes: mes,
    dias_asistidos: asistidos,
    dias_permiso: permisos,
    dias_permiso_pagado: permisosPagados,
    dias_falta: cuenta((d) => d.estado === 'falta'),
    tardanzas_acumuladas: cuenta((d) => d.estado === 'tardanza'),
    pago_por_dia: yo.pago_por_dia,
    monto_base: (asistidos + permisosPagados) * yo.pago_por_dia,
    descuentos: Number(guardado?.descuentos || 0),
    bonos: Number(guardado?.bonos || 0),
    total_pagar: Math.max(0, (asistidos + permisosPagados) * yo.pago_por_dia - Number(guardado?.descuentos || 0) + Number(guardado?.bonos || 0)),
    estado_pago: guardado?.estado_pago || 'pendiente',
    fecha_pago: guardado?.fecha_pago || null,
    observacion: null,
  };
  const lista = [vivo, ...datos.pagos.filter((p) => p.periodo_mes !== mes)];

  return (
    <>
      <Encabezado titulo="Mis pagos" subtitulo="Calculados con tu asistencia registrada. El mes en curso se actualiza cada día." />
      <div className="grid gap-4 md:grid-cols-2">
        {lista.map((p) => (
          <Tarjeta
            key={p.periodo_mes}
            titulo={capitalizar(nombrePeriodo(p.periodo_mes)) + (p.periodo_mes === mes ? ' (hasta hoy)' : '')}
            extra={<ChipPago pago={p} mesActual={p.periodo_mes === mes} />}
          >
            <p className="cifras font-display text-5xl font-bold">{soles(Number(p.total_pagar))}</p>
            <dl className="text-[13px] [&>div]:flex [&>div]:justify-between [&>div]:gap-3 [&>div]:border-t [&>div]:border-linea [&>div]:py-1.5 [&_dd]:cifras">
              <div>
                <dt>Días asistidos ({p.dias_asistidos} × {soles(Number(p.pago_por_dia))})</dt>
                <dd>{soles(p.dias_asistidos * Number(p.pago_por_dia))}</dd>
              </div>
              <div>
                <dt>Permisos con goce ({p.dias_permiso_pagado} de {p.dias_permiso})</dt>
                <dd>{soles(p.dias_permiso_pagado * Number(p.pago_por_dia))}</dd>
              </div>
              <div>
                <dt>Descuentos</dt>
                <dd>− {soles(Number(p.descuentos))}</dd>
              </div>
              <div>
                <dt>Bonos</dt>
                <dd>{soles(Number(p.bonos))}</dd>
              </div>
              <div className="text-tenue">
                <dt>Faltas (no se pagan) · tardanzas (no descuentan)</dt>
                <dd>
                  {p.dias_falta} · {p.tardanzas_acumuladas}
                </dd>
              </div>
            </dl>
          </Tarjeta>
        ))}
      </div>
      {REGLA}
    </>
  );
}
