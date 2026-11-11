'use client';
import { ArrowLeft, ChevronLeft, ChevronRight } from 'lucide-react';
import { useState } from 'react';
import { useYo } from '@/components/sesion';
import { Avatar, Boton, Cargando, ChipDia, Encabezado, FilaKpis, Kpi, Leyenda, MensajeError, RELLENO_DIA, Segmentado, Tarjeta } from '@/components/ui';
import {
  ahoraLima, capitalizar, diaCorto, diaMes, diaSemana, fechaCorta, fechaLarga, horaCorta, inicioSemana, nombrePeriodo,
  numeroDia, periodoDe, rangoPeriodo, sumarDias, sumarMeses,
} from '@/lib/fechas';
import { useConsulta, useFotos } from '@/lib/hooks';
import { supabaseNavegador } from '@/lib/supabase/navegador';
import { ETIQUETA_DIA, nombreCorto, type DiaAsistencia } from '@/lib/tipos';

type Modo = 'semana' | 'mes';
type Fila = { id: string; persona: DiaAsistencia; dias: DiaAsistencia[] };

const contar = (dias: DiaAsistencia[]) => {
  const c = (e: string) => dias.filter((d) => d.estado === e).length;
  return { asistidos: c('asistio') + c('tardanza'), tardanzas: c('tardanza'), permisos: c('permiso'), faltas: c('falta') };
};

export default function PaginaAsistencia() {
  const yo = useYo();
  const hoy = ahoraLima().fecha;
  const [modo, setModo] = useState<Modo>('semana');
  const [ancla, setAncla] = useState(hoy);
  const [elegido, setElegido] = useState<string | null>(yo.esAdmin ? null : yo.id);

  const rango =
    modo === 'semana'
      ? { desde: inicioSemana(ancla), hasta: sumarDias(inicioSemana(ancla), 5) }
      : rangoPeriodo(periodoDe(ancla));
  const etiqueta = modo === 'semana' ? `${diaMes(rango.desde)} – ${diaMes(rango.hasta)}` : capitalizar(nombrePeriodo(periodoDe(ancla)));

  const { datos, error, cargando, recargar } = useConsulta(
    async () => {
      const sb = supabaseNavegador();
      const [detalle, personal] = await Promise.all([
        sb.rpc('detalle_asistencia', { p_desde: rango.desde, p_hasta: rango.hasta, p_personal_id: yo.esAdmin ? null : yo.id }),
        sb.from('personal').select('id, foto_rostro_url'),
      ]);
      if (detalle.error) throw new Error(detalle.error.message);
      return {
        detalle: (detalle.data || []) as DiaAsistencia[],
        rutas: Object.fromEntries((personal.data || []).map((p) => [p.id, p.foto_rostro_url as string | null])),
      };
    },
    [rango.desde, rango.hasta, yo.id],
    ['asistencias', 'permisos'],
  );
  const fotos = useFotos(Object.values(datos?.rutas || {}));

  const mover = (paso: number) => setAncla(modo === 'semana' ? sumarDias(ancla, paso * 7) : `${sumarMeses(periodoDe(ancla), paso)}-01`);

  const filas: Fila[] = [];
  datos?.detalle.forEach((d) => {
    let f = filas.find((x) => x.id === d.personal_id);
    if (!f) filas.push((f = { id: d.personal_id, persona: d, dias: [] }));
    f.dias.push(d);
  });
  const fechas = Array.from(new Set(datos?.detalle.map((d) => d.fecha) || [])).sort();
  const filaElegida = elegido ? filas.find((f) => f.id === elegido) : undefined;
  const visibles = filaElegida ? [filaElegida] : filas;
  const totales = contar(visibles.flatMap((f) => f.dias));
  const foto = (id: string) => (datos?.rutas[id] ? fotos[datos.rutas[id]!] : undefined);

  return (
    <>
      <Encabezado
        titulo={yo.esAdmin ? (filaElegida ? nombreCorto(filaElegida.persona) : 'Monitoreo de asistencia') : 'Mi asistencia'}
        subtitulo={
          yo.esAdmin && filaElegida
            ? `${filaElegida.persona.cargo} · DNI ${filaElegida.persona.dni}`
            : yo.esAdmin
              ? 'Asistencias, tardanzas, permisos y faltas de cada trabajador. Toca un nombre para ver su detalle.'
              : 'Tu registro por semana y por mes.'
        }
        acciones={
          yo.esAdmin && filaElegida ? (
            <Boton variante="secundario" icono={<ArrowLeft className="size-4" />} onClick={() => setElegido(null)}>
              Todo el personal
            </Boton>
          ) : undefined
        }
      />

      <div className="flex flex-wrap items-center justify-between gap-3">
        <Segmentado etiqueta="Periodo" opciones={[['semana', 'Semana'], ['mes', 'Mes']]} valor={modo} onCambio={setModo} />
        <div className="flex items-center gap-2">
          <Boton variante="secundario" tam="sm" aria-label="Periodo anterior" onClick={() => mover(-1)}>
            <ChevronLeft className="size-4" />
          </Boton>
          <span className="min-w-36 text-center text-[13px] font-semibold">{etiqueta}</span>
          <Boton variante="secundario" tam="sm" aria-label="Periodo siguiente" onClick={() => mover(1)}>
            <ChevronRight className="size-4" />
          </Boton>
          <Boton variante="fantasma" tam="sm" onClick={() => setAncla(hoy)}>
            Hoy
          </Boton>
        </div>
      </div>

      {cargando && !datos ? (
        <Cargando />
      ) : error && !datos ? (
        <MensajeError texto={error} onReintentar={recargar} />
      ) : (
        <>
          <FilaKpis>
            <Kpi etiqueta="Días asistidos" valor={totales.asistidos} />
            <Kpi etiqueta="Tardanzas" valor={totales.tardanzas} tono={totales.tardanzas ? 'alerta' : undefined} />
            <Kpi etiqueta="Permisos" valor={totales.permisos} />
            <Kpi etiqueta="Faltas" valor={totales.faltas} tono={totales.faltas ? 'peligro' : undefined} />
          </FilaKpis>

          {filaElegida ? (
            modo === 'semana' ? (
              <ListaSemana fila={filaElegida} />
            ) : (
              <CalendarioMes fila={filaElegida} />
            )
          ) : modo === 'semana' ? (
            <TablaSemana filas={filas} fechas={fechas} foto={foto} onElegir={setElegido} />
          ) : (
            <TablaMes filas={filas} foto={foto} onElegir={setElegido} />
          )}
          <Leyenda />
        </>
      )}
    </>
  );
}

function CeldaPersona({ fila, foto, onElegir }: { fila: Fila; foto?: string; onElegir: (id: string) => void }) {
  return (
    <button type="button" onClick={() => onElegir(fila.id)} className="flex min-w-44 items-center gap-2.5 text-left hover:text-acento">
      <Avatar persona={fila.persona} url={foto} tam={30} />
      <span>
        <span className="block font-semibold whitespace-nowrap">{nombreCorto(fila.persona)}</span>
        <span className="block text-xs whitespace-nowrap text-tenue">{fila.persona.cargo}</span>
      </span>
    </button>
  );
}

const th = 'border-b border-linea bg-hundido px-3 py-2.5 text-left text-[11px] font-semibold tracking-wide whitespace-nowrap text-tenue uppercase';
const td = 'border-b border-linea px-3 py-2.5 align-middle';

function Totales({ dias }: { dias: DiaAsistencia[] }) {
  const t = contar(dias);
  return (
    <>
      <td className={`${td} cifras text-right`}>{t.asistidos}</td>
      <td className={`${td} cifras text-right`}>{t.tardanzas}</td>
      <td className={`${td} cifras text-right`}>{t.permisos}</td>
      <td className={`${td} cifras text-right`}>{t.faltas}</td>
    </>
  );
}
const CabeceraTotales = () => (
  <>
    {['Asist.', 'Tard.', 'Perm.', 'Faltas'].map((t) => (
      <th key={t} className={`${th} text-right`}>{t}</th>
    ))}
  </>
);

function TablaSemana({ filas, fechas, foto, onElegir }: { filas: Fila[]; fechas: string[]; foto: (id: string) => string | undefined; onElegir: (id: string) => void }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-linea bg-superficie">
      <table className="w-full border-collapse text-[13px]">
        <thead>
          <tr>
            <th className={th}>Trabajador</th>
            {fechas.map((f) => (
              <th key={f} className={th}>{fechaCorta(f)}</th>
            ))}
            <CabeceraTotales />
          </tr>
        </thead>
        <tbody className="[&>tr:last-child>td]:border-b-0">
          {filas.map((fila) => (
            <tr key={fila.id}>
              <td className={td}><CeldaPersona fila={fila} foto={foto(fila.id)} onElegir={onElegir} /></td>
              {fechas.map((f) => {
                const d = fila.dias.find((x) => x.fecha === f);
                return (
                  <td key={f} className={td}>
                    {!d || d.estado === 'futuro' ? (
                      <span className="text-tenue">—</span>
                    ) : (
                      <div className="flex flex-col items-start gap-1">
                        <ChipDia estado={d.estado} />
                        {d.hora_entrada && (
                          <span className="cifras font-mono text-[11px] text-tenue">
                            {horaCorta(d.hora_entrada)}
                            {d.hora_salida ? `–${horaCorta(d.hora_salida)}` : ''}
                          </span>
                        )}
                      </div>
                    )}
                  </td>
                );
              })}
              <Totales dias={fila.dias} />
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function TablaMes({ filas, foto, onElegir }: { filas: Fila[]; foto: (id: string) => string | undefined; onElegir: (id: string) => void }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-linea bg-superficie">
      <table className="w-full border-collapse text-[13px]">
        <thead>
          <tr>
            <th className={th}>Trabajador</th>
            <th className={th}>Día a día (lunes a sábado)</th>
            <CabeceraTotales />
          </tr>
        </thead>
        <tbody className="[&>tr:last-child>td]:border-b-0">
          {filas.map((fila) => (
            <tr key={fila.id}>
              <td className={td}><CeldaPersona fila={fila} foto={foto(fila.id)} onElegir={onElegir} /></td>
              <td className={td}>
                <div className="flex min-w-72 flex-wrap gap-[3px]">
                  {fila.dias.map((d) => (
                    <span
                      key={d.fecha}
                      title={`${fechaCorta(d.fecha)}: ${ETIQUETA_DIA[d.estado]}${d.hora_entrada ? ` (${horaCorta(d.hora_entrada)})` : ''}`}
                      className={`inline-block size-3.5 rounded-[3px] ${RELLENO_DIA[d.estado]}`}
                    />
                  ))}
                </div>
              </td>
              <Totales dias={fila.dias} />
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ListaSemana({ fila }: { fila: Fila }) {
  return (
    <Tarjeta>
      <ul>
        {fila.dias.map((d) => (
          <li key={d.fecha} className="flex items-center gap-3 border-t border-linea py-2.5 first:border-t-0 first:pt-0 last:pb-0">
            <div className="min-w-0 flex-1">
              <p className="font-semibold">{capitalizar(fechaLarga(d.fecha, false))}</p>
              <p className="text-xs text-tenue">
                {d.hora_entrada
                  ? `Entrada ${horaCorta(d.hora_entrada)}${d.hora_salida ? ` · salida ${horaCorta(d.hora_salida)}` : ''}${d.confianza_facial ? ` · ${Number(d.confianza_facial).toFixed(1)} % rostro` : ''}`
                  : d.estado === 'permiso'
                    ? 'Permiso aprobado' + (d.permiso_con_goce ? ' (con goce)' : '')
                    : d.estado === 'futuro'
                      ? 'Día por venir'
                      : d.estado === 'pendiente'
                        ? 'Esperando marcación'
                        : 'Sin entrada registrada'}
              </p>
            </div>
            {d.estado !== 'futuro' && <ChipDia estado={d.estado} />}
          </li>
        ))}
      </ul>
    </Tarjeta>
  );
}

const FONDO_DIA: Record<string, string> = {
  asistio: 'bg-ok-suave text-ok',
  tardanza: 'bg-alerta-suave text-alerta',
  falta: 'bg-peligro-suave text-peligro',
  permiso: 'bg-info-suave text-info',
  pendiente: 'bg-hundido text-tenue ring-1 ring-linea ring-inset',
  futuro: 'bg-hundido text-tenue/60',
};

function CalendarioMes({ fila }: { fila: Fila }) {
  const desfase = fila.dias.length ? (diaSemana(fila.dias[0].fecha) + 6) % 7 : 0;
  return (
    <Tarjeta>
      <div className="grid grid-cols-6 gap-1.5 sm:gap-2">
        {['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'].map((d) => (
          <div key={d} className="text-center text-[11px] tracking-wide text-tenue uppercase">{d}</div>
        ))}
        {Array.from({ length: desfase }).map((_, i) => (
          <div key={`v${i}`} />
        ))}
        {fila.dias.map((d) => (
          <div
            key={d.fecha}
            title={`${diaCorto(d.fecha)} ${numeroDia(d.fecha)}: ${ETIQUETA_DIA[d.estado]}`}
            className={`flex aspect-[1/0.85] min-w-0 flex-col justify-between rounded-lg p-1.5 sm:p-2 ${FONDO_DIA[d.estado]}`}
          >
            <span className="text-[13px] font-semibold">{numeroDia(d.fecha)}</span>
            <span className="cifras truncate font-mono text-[10px]">{d.hora_entrada ? horaCorta(d.hora_entrada) : d.estado === 'futuro' ? '' : ETIQUETA_DIA[d.estado]}</span>
          </div>
        ))}
      </div>
    </Tarjeta>
  );
}
