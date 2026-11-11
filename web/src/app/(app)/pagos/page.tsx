'use client';
import { AlertTriangle, Banknote, FileDown, History, Trash2, Wallet } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { useAvisos } from '@/components/avisos';
import { BotonReportes, descargarReporte } from '@/components/reportes';
import { useYo } from '@/components/sesion';
import { Avatar, Boton, Campo, Cargando, Chip, ChipDia, claseInput, Encabezado, FilaKpis, Kpi, MensajeError, Modal, Segmentado, Tarjeta, Vacio } from '@/components/ui';
import { ahoraLima, diaCorto, diaMes, fechaLarga, horaCorta, inicioSemana, rangoCorto, soles, sumarDias } from '@/lib/fechas';
import { useConsulta, useFotos } from '@/lib/hooks';
import { supabaseNavegador } from '@/lib/supabase/navegador';
import { ETIQUETA_METODO, METODOS_PAGO, nombreCorto, type DiaPago, type MetodoPago, type Pago, type PagoPendiente } from '@/lib/tipos';

const REGLA = (
  <p className="rounded-lg bg-hundido px-3 py-2.5 text-xs leading-relaxed text-tenue">
    <strong className="text-tinta">Cálculo:</strong> se suma lo ganado en cada día asistido (pago por día fijo, o el monto por rendimiento que registra el
    administrador) más los permisos con goce, más bonos y menos descuentos. Se puede pagar en cualquier momento: por semana, quincena, mes o días sueltos.
    Las tardanzas no descuentan; las faltas y los permisos sin goce no se pagan.
  </p>
);

const num = (t: string) => Math.round(Number(t.replace(',', '.')) * 100) / 100;

function ChipTipo({ tipo, tarifa }: { tipo: 'fijo' | 'variable'; tarifa: number }) {
  return tipo === 'variable' ? <Chip clase="bg-info-suave text-info">Por rendimiento</Chip> : <Chip clase="bg-hundido text-tenue">Fijo {soles(tarifa)}/día</Chip>;
}

function ChipMetodo({ pago }: { pago: Pago }) {
  return (
    <span className="text-xs">
      <span className="font-semibold">{ETIQUETA_METODO[pago.metodo_pago] || pago.metodo_pago}</span>
      {pago.numero_operacion && <span className="text-tenue"> · Op. {pago.numero_operacion}</span>}
    </span>
  );
}

async function comprobante(id: string, avisar: (t: string, tipo?: 'ok' | 'error') => void) {
  try {
    await descargarReporte({ tipo: 'comprobante', formato: 'pdf', id });
  } catch (e) {
    avisar(e instanceof Error ? e.message : 'No se pudo descargar.', 'error');
  }
}

export default function PaginaPagos() {
  const yo = useYo();
  return yo.esAdmin ? <PagosAdmin /> : <PagosTrabajador />;
}

/* ============================== ADMINISTRADOR ============================== */
function PagosAdmin() {
  const [vista, setVista] = useState<'pendientes' | 'historial'>('pendientes');
  return (
    <>
      <Encabezado
        titulo="Pagos"
        subtitulo="Paga cuando el trabajador lo solicite: por semana, por mes o por días. Lo pendiente se calcula en vivo con la asistencia."
        acciones={<BotonReportes tipo="pagos" />}
      />
      <Segmentado
        etiqueta="Vista"
        opciones={[
          ['pendientes', 'Por pagar'],
          ['historial', 'Pagos realizados'],
        ]}
        valor={vista}
        onCambio={setVista}
      />
      {vista === 'pendientes' ? <Pendientes /> : <Historial />}
    </>
  );
}

function Pendientes() {
  const [elegido, setElegido] = useState<PagoPendiente | null>(null);
  const { datos, error, cargando, recargar } = useConsulta(
    async () => {
      const sb = supabaseNavegador();
      const hoy = ahoraLima().fecha;
      const [pend, mes] = await Promise.all([
        sb.rpc('pagos_pendientes', { p_personal_id: null }),
        sb.from('pagos').select('total_pagar').gte('fecha_pago', `${hoy.slice(0, 7)}-01`),
      ]);
      if (pend.error) throw new Error(pend.error.message);
      return {
        lista: (pend.data || []) as PagoPendiente[],
        pagadoMes: (mes.data || []).reduce((s, p) => s + Number(p.total_pagar), 0),
      };
    },
    [],
    ['pagos', 'asistencias', 'permisos', 'personal'],
  );
  const fotos = useFotos(datos?.lista.map((p) => p.foto_rostro_url) || []);

  if (cargando && !datos) return <Cargando />;
  if (error && !datos) return <MensajeError texto={error} onReintentar={recargar} />;
  if (!datos) return null;
  const total = datos.lista.reduce((s, p) => s + Number(p.monto_pendiente), 0);
  const conSaldo = datos.lista.filter((p) => Number(p.monto_pendiente) > 0).length;

  return (
    <>
      <FilaKpis>
        <Kpi etiqueta="Total por pagar" valor={<span className="text-[26px]">{soles(total)}</span>} tono={total > 0 ? 'acento' : undefined} />
        <Kpi etiqueta="Con saldo" valor={conSaldo} detalle={`de ${datos.lista.length} trabajadores`} />
        <Kpi etiqueta="Pagado este mes" valor={<span className="text-[26px]">{soles(datos.pagadoMes)}</span>} tono="ok" />
      </FilaKpis>

      {!datos.lista.length ? (
        <Vacio titulo="No hay trabajadores activos" />
      ) : (
        <div className="grid gap-3 md:grid-cols-2">
          {datos.lista.map((p) => (
            <Tarjeta key={p.personal_id}>
              <div className="flex items-start gap-3">
                <Avatar persona={p} url={p.foto_rostro_url ? fotos[p.foto_rostro_url] : undefined} tam={40} />
                <div className="min-w-0 flex-1">
                  <p className="truncate font-semibold">{nombreCorto(p)}</p>
                  <p className="truncate text-xs text-tenue">
                    {p.cargo} · DNI {p.dni}
                  </p>
                  <div className="mt-1.5">
                    <ChipTipo tipo={p.tipo_pago} tarifa={Number(p.pago_por_dia)} />
                  </div>
                </div>
                <div className="text-right">
                  <p className="cifras font-display text-3xl leading-none font-bold">{soles(Number(p.monto_pendiente))}</p>
                  <p className="mt-1 text-[11px] text-tenue">por pagar</p>
                </div>
              </div>
              <dl className="mt-3 grid grid-cols-3 gap-2 border-t border-linea pt-3 text-center text-xs [&_dd]:cifras [&_dd]:text-base [&_dd]:font-semibold [&_dt]:text-tenue">
                <div>
                  <dt>Días a pagar</dt>
                  <dd>{p.dias_asistidos + p.dias_permiso_pagado}</dd>
                </div>
                <div>
                  <dt>Faltas</dt>
                  <dd>{p.dias_falta}</dd>
                </div>
                <div>
                  <dt>Tardanzas</dt>
                  <dd>{p.tardanzas}</dd>
                </div>
              </dl>
              <p className="mt-2 text-xs text-tenue">
                {p.desde <= p.hasta ? <>Desde el {fechaLarga(p.desde, false)} hasta hoy.</> : 'Al día.'}{' '}
                {p.ultimo_pago_hasta ? `Último pago cubrió hasta el ${diaMes(p.ultimo_pago_hasta)}.` : 'Aún no tiene pagos registrados.'}
              </p>
              {p.tipo_pago === 'variable' && p.dias_sin_monto > 0 && (
                <p className="mt-2 flex items-start gap-1.5 rounded-md bg-alerta-suave px-2.5 py-1.5 text-xs text-alerta">
                  <AlertTriangle className="mt-px size-3.5 shrink-0" />
                  {p.dias_sin_monto} día(s) sin monto de rendimiento: se calculan con {soles(Number(p.pago_por_dia))} hasta que los registres.
                </p>
              )}
              <div className="mt-3 flex justify-end">
                <Boton variante="ok" icono={<Banknote className="size-4" />} disabled={p.desde > p.hasta} onClick={() => setElegido(p)}>
                  Registrar pago
                </Boton>
              </div>
            </Tarjeta>
          ))}
        </div>
      )}
      {REGLA}
      {elegido && <ModalPago pendiente={elegido} onCerrar={() => setElegido(null)} onPagado={recargar} />}
    </>
  );
}

/* ---------- Registrar pago (rango libre, montos por día, método) ---------- */
function ModalPago({ pendiente, onCerrar, onPagado }: { pendiente: PagoPendiente; onCerrar: () => void; onPagado: () => void }) {
  const { avisar } = useAvisos();
  const hoy = ahoraLima().fecha;
  const sabadoPasado = sumarDias(inicioSemana(hoy), -2);
  const [desde, setDesde] = useState(pendiente.desde);
  const [hasta, setHasta] = useState(hoy);
  const [dias, setDias] = useState<DiaPago[] | null>(null);
  const [montos, setMontos] = useState<Record<string, string>>({});
  const [cargandoDias, setCargandoDias] = useState(false);
  const [bonos, setBonos] = useState('0');
  const [descuentos, setDescuentos] = useState('0');
  const [metodo, setMetodo] = useState<MetodoPago>('efectivo');
  const [operacion, setOperacion] = useState('');
  const [observacion, setObservacion] = useState('');
  const [guardando, setGuardando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const variable = pendiente.tipo_pago === 'variable';
  const tarifa = Number(pendiente.pago_por_dia);

  useEffect(() => {
    if (!desde || !hasta || hasta < desde) return setDias([]);
    let vigente = true;
    setCargandoDias(true);
    supabaseNavegador()
      .rpc('detalle_pago', { p_personal_id: pendiente.personal_id, p_desde: desde, p_hasta: hasta })
      .then(({ data, error: e }) => {
        if (!vigente) return;
        setCargandoDias(false);
        if (e) return setError(e.message);
        const lista = (data || []) as DiaPago[];
        setDias(lista);
        setMontos(Object.fromEntries(lista.filter((d) => d.monto_dia != null).map((d) => [d.fecha, String(d.monto_dia)])));
      });
    return () => {
      vigente = false;
    };
  }, [desde, hasta, pendiente.personal_id]);

  const montoDe = (d: DiaPago) => {
    if (!d.pagable) return 0;
    if (d.estado === 'permiso') return tarifa;
    const t = montos[d.fecha];
    return t !== undefined && t.trim() !== '' && Number.isFinite(num(t)) ? num(t) : tarifa;
  };
  const resumen = useMemo(() => {
    const lista = dias || [];
    return {
      base: lista.reduce((s, d) => s + montoDe(d), 0),
      pagables: lista.filter((d) => d.pagable).length,
      yaPagados: lista.filter((d) => d.pagado).length,
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dias, montos]);
  const total = Math.max(0, resumen.base + (num(bonos) || 0) - (num(descuentos) || 0));

  async function pagar() {
    setError(null);
    if (!desde || !hasta || hasta < desde) return setError('Revisa las fechas del periodo.');
    if (resumen.yaPagados) return setError('El periodo incluye días ya pagados. Empieza desde el día siguiente al último pago.');
    if (!resumen.pagables) return setError('No hay días por pagar en ese periodo.');
    const b = num(bonos || '0'), dsc = num(descuentos || '0');
    if (!Number.isFinite(b) || !Number.isFinite(dsc) || b < 0 || dsc < 0) return setError('Bonos y descuentos deben ser 0 o más.');
    const cambios = (dias || [])
      .filter((d) => d.pagable && d.estado !== 'permiso')
      .map((d) => ({ d, t: (montos[d.fecha] ?? '').trim() }))
      .filter(({ d, t }) => (t === '' ? d.monto_dia != null : num(t) !== Number(d.monto_dia)))
      .map(({ d, t }) => ({ fecha: d.fecha, monto: t === '' ? null : num(t) }));
    if (cambios.some((c) => c.monto !== null && (!Number.isFinite(c.monto) || c.monto < 0))) return setError('Hay montos por día no válidos.');

    setGuardando(true);
    const sb = supabaseNavegador();
    if (cambios.length) {
      const { error: e } = await sb.rpc('fijar_montos_dia', { p_personal_id: pendiente.personal_id, p_montos: cambios });
      if (e) {
        setGuardando(false);
        return setError(e.message);
      }
    }
    const { error: e } = await sb.rpc('registrar_pago', {
      p_personal_id: pendiente.personal_id,
      p_desde: desde,
      p_hasta: hasta,
      p_metodo: metodo,
      p_bonos: b,
      p_descuentos: dsc,
      p_numero_operacion: metodo === 'efectivo' ? null : operacion,
      p_observacion: observacion,
    });
    setGuardando(false);
    if (e) return setError(e.message);
    avisar(`Pago de ${soles(total)} a ${nombreCorto(pendiente)} registrado (${ETIQUETA_METODO[metodo]}).`);
    onPagado();
    onCerrar();
  }

  return (
    <Modal abierto titulo={`Pagar a ${nombreCorto(pendiente)}`} onCerrar={onCerrar} ancho="max-w-2xl">
      <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-2">
          <ChipTipo tipo={pendiente.tipo_pago} tarifa={tarifa} />
          <span className="text-xs text-tenue">
            {pendiente.ultimo_pago_hasta ? `Último pago hasta el ${diaMes(pendiente.ultimo_pago_hasta)}` : 'Sin pagos anteriores'}
          </span>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Campo etiqueta="Desde">
            <input type="date" className={claseInput} value={desde} min={pendiente.desde} max={hasta} onChange={(e) => setDesde(e.target.value)} />
          </Campo>
          <Campo etiqueta="Hasta">
            <input type="date" className={claseInput} value={hasta} min={desde} max={hoy} onChange={(e) => setHasta(e.target.value)} />
          </Campo>
        </div>
        <div className="-mt-2 flex flex-wrap gap-1.5">
          <Boton tam="sm" variante="secundario" onClick={() => setHasta(hoy)}>
            Hasta hoy
          </Boton>
          {sabadoPasado >= pendiente.desde && (
            <Boton tam="sm" variante="secundario" onClick={() => setHasta(sabadoPasado)}>
              Hasta el sábado {diaMes(sabadoPasado)}
            </Boton>
          )}
          {sumarDias(`${hoy.slice(0, 7)}-01`, -1) >= pendiente.desde && (
            <Boton tam="sm" variante="secundario" onClick={() => setHasta(sumarDias(`${hoy.slice(0, 7)}-01`, -1))}>
              Hasta fin del mes pasado
            </Boton>
          )}
        </div>

        <div className="rounded-lg border border-linea">
          <div className="flex items-center justify-between border-b border-linea bg-hundido px-3 py-2 text-[11px] font-semibold tracking-wide text-tenue uppercase">
            <span>Días del periodo</span>
            <span>{variable ? 'Monto por rendimiento' : 'Monto'}</span>
          </div>
          <div className="max-h-64 overflow-y-auto">
            {cargandoDias && !dias ? (
              <Cargando />
            ) : !dias?.length ? (
              <p className="px-3 py-4 text-sm text-tenue">Sin días en ese rango.</p>
            ) : (
              dias.map((d) => (
                <div key={d.fecha} className={`flex items-center gap-3 border-b border-linea px-3 py-1.5 text-[13px] last:border-b-0 ${d.pagado ? 'opacity-50' : ''}`}>
                  <span className="w-20 shrink-0 capitalize">
                    {diaCorto(d.fecha)} {diaMes(d.fecha)}
                  </span>
                  <span className="flex-1">
                    <ChipDia estado={d.estado} />
                    {d.pagado && <span className="ml-1.5 text-xs text-tenue">ya pagado</span>}
                    {d.hora_entrada && <span className="ml-1.5 text-xs text-tenue">{horaCorta(d.hora_entrada)}</span>}
                  </span>
                  {d.pagable && !d.pagado && d.estado !== 'permiso' ? (
                    <input
                      aria-label={`Monto del ${diaMes(d.fecha)}`}
                      inputMode="decimal"
                      className="w-24 rounded-md border border-linea bg-superficie px-2 py-1 text-right cifras"
                      placeholder={tarifa.toFixed(2)}
                      value={montos[d.fecha] ?? ''}
                      onChange={(e) => setMontos((m) => ({ ...m, [d.fecha]: e.target.value }))}
                    />
                  ) : (
                    <span className="cifras w-24 text-right text-tenue">{d.pagable ? soles(montoDe(d)) : '—'}</span>
                  )}
                </div>
              ))
            )}
          </div>
        </div>
        <p className="-mt-2 text-xs text-tenue">
          {variable
            ? 'Escribe lo que ganó cada día según su rendimiento. Si dejas un día vacío se usa el monto de referencia.'
            : 'Puedes cambiar el monto de un día si ese día ganó distinto. Vacío = pago por día normal.'}
        </p>

        <div className="grid grid-cols-2 gap-3">
          <Campo etiqueta="Bonos (S/)">
            <input inputMode="decimal" className={`${claseInput} text-right cifras`} value={bonos} onChange={(e) => setBonos(e.target.value)} />
          </Campo>
          <Campo etiqueta="Descuentos (S/)">
            <input inputMode="decimal" className={`${claseInput} text-right cifras`} value={descuentos} onChange={(e) => setDescuentos(e.target.value)} />
          </Campo>
        </div>

        <Campo etiqueta="Método de pago">
          <Segmentado etiqueta="Método de pago" opciones={METODOS_PAGO} valor={metodo} onCambio={setMetodo} />
        </Campo>
        {metodo !== 'efectivo' && (
          <Campo etiqueta="N° de operación (opcional)">
            <input className={claseInput} value={operacion} maxLength={40} onChange={(e) => setOperacion(e.target.value)} placeholder="Ej. 00482917" />
          </Campo>
        )}
        <Campo etiqueta="Observación (opcional)">
          <input className={claseInput} value={observacion} maxLength={200} onChange={(e) => setObservacion(e.target.value)} placeholder="Ej. Pago de la semana a pedido del trabajador" />
        </Campo>

        <div className="rounded-xl bg-hundido p-4">
          <dl className="space-y-1 text-[13px] [&>div]:flex [&>div]:justify-between [&_dd]:cifras">
            <div>
              <dt>{resumen.pagables} día(s) a pagar</dt>
              <dd>{soles(resumen.base)}</dd>
            </div>
            <div>
              <dt>Bonos</dt>
              <dd>+ {soles(num(bonos) || 0)}</dd>
            </div>
            <div>
              <dt>Descuentos</dt>
              <dd>- {soles(num(descuentos) || 0)}</dd>
            </div>
          </dl>
          <div className="mt-2 flex items-end justify-between border-t border-linea pt-2">
            <span className="font-semibold">Total a pagar</span>
            <span className="cifras font-display text-4xl font-bold">{soles(total)}</span>
          </div>
        </div>

        {error && <MensajeError texto={error} />}
        <div className="flex justify-end gap-2">
          <Boton variante="secundario" onClick={onCerrar}>
            Cancelar
          </Boton>
          <Boton variante="ok" icono={<Banknote className="size-4" />} cargando={guardando} disabled={cargandoDias} onClick={pagar}>
            Confirmar pago
          </Boton>
        </div>
      </div>
    </Modal>
  );
}

/* ---------- Pagos realizados ---------- */
function Historial() {
  const { avisar } = useAvisos();
  const hoy = ahoraLima().fecha;
  const [desde, setDesde] = useState(`${sumarDias(`${hoy.slice(0, 7)}-01`, -1).slice(0, 7)}-01`);
  const [hasta, setHasta] = useState(hoy);
  const [anular, setAnular] = useState<Pago | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const { datos, error, cargando, recargar } = useConsulta(
    async () => {
      const { data, error: e } = await supabaseNavegador()
        .from('pagos')
        .select('*, personal:personal_id(id, dni, nombres, apellidos, cargo, foto_rostro_url)')
        .gte('fecha_pago', desde)
        .lte('fecha_pago', hasta)
        .order('fecha_pago', { ascending: false })
        .order('created_at', { ascending: false });
      if (e) throw new Error(e.message);
      return (data || []) as Pago[];
    },
    [desde, hasta],
    ['pagos'],
  );
  const fotos = useFotos(datos?.map((p) => p.personal?.foto_rostro_url) || []);

  async function confirmarAnular() {
    if (!anular) return;
    setOcupado(true);
    const { error: e } = await supabaseNavegador().from('pagos').delete().eq('id', anular.id);
    setOcupado(false);
    if (e) return avisar(`No se pudo anular: ${e.message}`, 'error');
    avisar('Pago anulado. Esos días vuelven a figurar como pendientes.');
    setAnular(null);
    recargar();
  }

  const total = datos?.reduce((s, p) => s + Number(p.total_pagar), 0) || 0;
  return (
    <>
      <div className="flex flex-wrap items-end gap-3">
        <Campo etiqueta="Pagados desde">
          <input type="date" className={claseInput} value={desde} max={hasta} onChange={(e) => setDesde(e.target.value)} />
        </Campo>
        <Campo etiqueta="Hasta">
          <input type="date" className={claseInput} value={hasta} min={desde} onChange={(e) => setHasta(e.target.value)} />
        </Campo>
        <p className="pb-2 text-[13px] text-tenue">
          {datos?.length || 0} pago(s) · <strong className="cifras text-tinta">{soles(total)}</strong>
        </p>
      </div>
      {cargando && !datos ? (
        <Cargando />
      ) : error && !datos ? (
        <MensajeError texto={error} onReintentar={recargar} />
      ) : !datos?.length ? (
        <Vacio titulo="No hay pagos en esas fechas" texto="Cambia el rango o registra un pago desde la pestaña Por pagar." />
      ) : (
        <div className="overflow-x-auto rounded-xl border border-linea bg-superficie">
          <table className="w-full border-collapse text-[13px]">
            <thead>
              <tr className="[&>th]:border-b [&>th]:border-linea [&>th]:bg-hundido [&>th]:px-3 [&>th]:py-2.5 [&>th]:text-[11px] [&>th]:font-semibold [&>th]:tracking-wide [&>th]:whitespace-nowrap [&>th]:text-tenue [&>th]:uppercase">
                <th className="text-left">Trabajador</th>
                <th className="text-left">Periodo pagado</th>
                <th className="text-right">Días</th>
                <th className="text-right">Bonos / Desc.</th>
                <th className="text-right">Total</th>
                <th className="text-left">Método</th>
                <th className="text-left">Pagado el</th>
                <th />
              </tr>
            </thead>
            <tbody className="[&>tr:last-child>td]:border-b-0 [&_td]:border-b [&_td]:border-linea [&_td]:px-3 [&_td]:py-2.5">
              {datos.map((p) => (
                <tr key={p.id}>
                  <td>
                    {p.personal && (
                      <div className="flex min-w-40 items-center gap-2.5">
                        <Avatar persona={p.personal} url={p.personal.foto_rostro_url ? fotos[p.personal.foto_rostro_url] : undefined} tam={30} />
                        <span className="font-semibold whitespace-nowrap">{nombreCorto(p.personal)}</span>
                      </div>
                    )}
                  </td>
                  <td className="whitespace-nowrap">{rangoCorto(p.fecha_desde, p.fecha_hasta)}</td>
                  <td className="cifras text-right">{p.dias_asistidos + p.dias_permiso_pagado}</td>
                  <td className="cifras text-right whitespace-nowrap text-tenue">
                    +{Number(p.bonos).toFixed(2)} / -{Number(p.descuentos).toFixed(2)}
                  </td>
                  <td className="cifras text-right font-semibold whitespace-nowrap">{soles(Number(p.total_pagar))}</td>
                  <td className="whitespace-nowrap">
                    <ChipMetodo pago={p} />
                  </td>
                  <td className="whitespace-nowrap">{p.fecha_pago ? diaMes(p.fecha_pago) : '—'}</td>
                  <td className="text-right whitespace-nowrap">
                    <Boton variante="fantasma" tam="sm" icono={<FileDown className="size-3.5" />} onClick={() => comprobante(p.id, avisar)}>
                      Comprobante
                    </Boton>
                    <Boton variante="fantasma" tam="sm" icono={<Trash2 className="size-3.5" />} onClick={() => setAnular(p)} aria-label="Anular pago" />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Modal abierto={!!anular} titulo="Anular pago" onCerrar={() => setAnular(null)}>
        {anular && (
          <div className="flex flex-col gap-4">
            <p className="text-sm">
              Se anulará el pago de <strong>{soles(Number(anular.total_pagar))}</strong> a {anular.personal ? nombreCorto(anular.personal) : ''} por el periodo{' '}
              {rangoCorto(anular.fecha_desde, anular.fecha_hasta)}. Esos días volverán a figurar como pendientes. Úsalo solo si el pago se registró por error.
            </p>
            <div className="flex justify-end gap-2">
              <Boton variante="secundario" onClick={() => setAnular(null)}>
                Cancelar
              </Boton>
              <Boton variante="peligro" icono={<Trash2 className="size-4" />} cargando={ocupado} onClick={confirmarAnular}>
                Anular pago
              </Boton>
            </div>
          </div>
        )}
      </Modal>
    </>
  );
}

/* ============================== TRABAJADOR ============================== */
function PagosTrabajador() {
  const yo = useYo();
  const { avisar } = useAvisos();
  const [verDias, setVerDias] = useState(false);
  const { datos, error, cargando, recargar } = useConsulta(
    async () => {
      const sb = supabaseNavegador();
      const [pend, pagos] = await Promise.all([
        sb.rpc('pagos_pendientes', { p_personal_id: yo.id }),
        sb.from('pagos').select('*').eq('personal_id', yo.id).order('fecha_hasta', { ascending: false }),
      ]);
      if (pend.error) throw new Error(pend.error.message);
      if (pagos.error) throw new Error(pagos.error.message);
      const pendiente = ((pend.data || []) as PagoPendiente[])[0] || null;
      let dias: DiaPago[] = [];
      if (pendiente && pendiente.desde <= pendiente.hasta) {
        const r = await sb.rpc('detalle_pago', { p_personal_id: yo.id, p_desde: pendiente.desde, p_hasta: pendiente.hasta });
        dias = (r.data || []) as DiaPago[];
      }
      return { pendiente, pagos: (pagos.data || []) as Pago[], dias };
    },
    [yo.id],
    ['pagos', 'asistencias', 'permisos'],
  );

  if (cargando && !datos) return <Cargando />;
  if (error && !datos) return <MensajeError texto={error} onReintentar={recargar} />;
  if (!datos) return null;
  const p = datos.pendiente;

  return (
    <>
      <Encabezado titulo="Mis pagos" subtitulo="Lo que llevas ganado desde tu último pago y el historial de lo que ya cobraste." acciones={<BotonReportes tipo="pagos" />} />
      {p && (
        <Tarjeta titulo="Por cobrar" extra={<ChipTipo tipo={p.tipo_pago} tarifa={Number(p.pago_por_dia)} />}>
          <p className="cifras font-display text-5xl font-bold">{soles(Number(p.monto_pendiente))}</p>
          <p className="mt-1 text-[13px] text-tenue">
            {p.desde <= p.hasta ? `Del ${fechaLarga(p.desde, false)} a hoy` : 'Estás al día'} · {p.dias_asistidos + p.dias_permiso_pagado} día(s) a pagar · {p.dias_falta} falta(s)
          </p>
          {p.tipo_pago === 'variable' && p.dias_sin_monto > 0 && (
            <p className="mt-2 text-xs text-tenue">
              {p.dias_sin_monto} día(s) aún sin monto de rendimiento: se muestran con {soles(Number(p.pago_por_dia))} de referencia.
            </p>
          )}
          {datos.dias.length > 0 && (
            <>
              <Boton variante="fantasma" tam="sm" className="mt-2 -ml-2" icono={<Wallet className="size-3.5" />} onClick={() => setVerDias((v) => !v)}>
                {verDias ? 'Ocultar detalle' : 'Ver detalle por día'}
              </Boton>
              {verDias && (
                <ul className="mt-2 divide-y divide-linea rounded-lg border border-linea text-[13px]">
                  {datos.dias.map((d) => (
                    <li key={d.fecha} className="flex items-center gap-3 px-3 py-1.5">
                      <span className="w-20 capitalize">
                        {diaCorto(d.fecha)} {diaMes(d.fecha)}
                      </span>
                      <span className="flex-1">
                        <ChipDia estado={d.estado} />
                      </span>
                      <span className="cifras">{d.pagable ? soles(Number(d.monto)) : '—'}</span>
                    </li>
                  ))}
                </ul>
              )}
            </>
          )}
        </Tarjeta>
      )}

      <h2 className="flex items-center gap-2 font-semibold">
        <History className="size-4 text-tenue" /> Pagos recibidos
      </h2>
      {!datos.pagos.length ? (
        <Vacio titulo="Todavía no tienes pagos registrados" />
      ) : (
        <div className="grid gap-3 md:grid-cols-2">
          {datos.pagos.map((pg) => (
            <Tarjeta key={pg.id} titulo={rangoCorto(pg.fecha_desde, pg.fecha_hasta)} extra={<Chip clase="bg-ok-suave text-ok">Pagado {pg.fecha_pago ? diaMes(pg.fecha_pago) : ''}</Chip>}>
              <p className="cifras font-display text-4xl font-bold">{soles(Number(pg.total_pagar))}</p>
              <dl className="mt-1 text-[13px] [&>div]:flex [&>div]:justify-between [&>div]:gap-3 [&>div]:border-t [&>div]:border-linea [&>div]:py-1.5 [&_dd]:cifras">
                <div>
                  <dt>Días pagados ({pg.dias_asistidos} + {pg.dias_permiso_pagado} permiso)</dt>
                  <dd>{soles(Number(pg.monto_base))}</dd>
                </div>
                <div>
                  <dt>Bonos / descuentos</dt>
                  <dd>
                    +{Number(pg.bonos).toFixed(2)} / -{Number(pg.descuentos).toFixed(2)}
                  </dd>
                </div>
                <div>
                  <dt>Método</dt>
                  <dd>
                    <ChipMetodo pago={pg} />
                  </dd>
                </div>
              </dl>
              <Boton variante="secundario" tam="sm" className="mt-2" icono={<FileDown className="size-3.5" />} onClick={() => comprobante(pg.id, avisar)}>
                Comprobante PDF
              </Boton>
            </Tarjeta>
          ))}
        </div>
      )}
      {REGLA}
    </>
  );
}
