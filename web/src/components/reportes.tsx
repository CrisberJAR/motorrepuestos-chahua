'use client';
import { Download, FileSpreadsheet, FileText } from 'lucide-react';
import { useEffect, useState } from 'react';
import { useAvisos } from '@/components/avisos';
import { useYo } from '@/components/sesion';
import { Boton, Campo, claseInput, Modal, Segmentado } from '@/components/ui';
import { ahoraLima, inicioSemana, sumarDias } from '@/lib/fechas';
import { supabaseNavegador } from '@/lib/supabase/navegador';
import { nombreCorto } from '@/lib/tipos';

type Tipo = 'asistencia' | 'pagos';
type Formato = 'pdf' | 'xlsx';

/** Descarga un archivo de /api/reportes mostrando los errores como aviso. */
export async function descargarReporte(params: Record<string, string>) {
  const r = await fetch(`/api/reportes?${new URLSearchParams(params)}`);
  if (!r.ok) {
    const e = await r.json().catch(() => null);
    throw new Error(e?.error || `No se pudo generar el reporte (${r.status}).`);
  }
  const nombre = /filename="([^"]+)"/.exec(r.headers.get('content-disposition') || '')?.[1] || `reporte.${params.formato}`;
  const url = URL.createObjectURL(await r.blob());
  const a = document.createElement('a');
  a.href = url;
  a.download = nombre;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

const RANGOS = [
  ['semana', 'Esta semana'],
  ['mes', 'Este mes'],
  ['anterior', 'Mes anterior'],
  ['libre', 'Elegir fechas'],
] as const;

function rangoRapido(clave: (typeof RANGOS)[number][0], hoy: string) {
  if (clave === 'semana') return { desde: inicioSemana(hoy), hasta: hoy };
  if (clave === 'mes') return { desde: `${hoy.slice(0, 7)}-01`, hasta: hoy };
  const finAnterior = sumarDias(`${hoy.slice(0, 7)}-01`, -1);
  return { desde: `${finAnterior.slice(0, 7)}-01`, hasta: finAnterior };
}

export function BotonReportes({ tipo: tipoInicial = 'asistencia', variante = 'secundario' }: { tipo?: Tipo; variante?: 'secundario' | 'primario' }) {
  const yo = useYo();
  const { avisar } = useAvisos();
  const hoy = ahoraLima().fecha;
  const [abierto, setAbierto] = useState(false);
  const [tipo, setTipo] = useState<Tipo>(tipoInicial);
  const [formato, setFormato] = useState<Formato>('pdf');
  const [rango, setRango] = useState<(typeof RANGOS)[number][0]>('mes');
  const [desde, setDesde] = useState(`${hoy.slice(0, 7)}-01`);
  const [hasta, setHasta] = useState(hoy);
  const [persona, setPersona] = useState('');
  const [lista, setLista] = useState<{ id: string; nombres: string; apellidos: string }[]>([]);
  const [ocupado, setOcupado] = useState(false);

  useEffect(() => {
    if (!abierto || !yo.esAdmin || lista.length) return;
    supabaseNavegador()
      .from('personal')
      .select('id, nombres, apellidos')
      .eq('estado', 'activo')
      .order('apellidos')
      .then(({ data }) => setLista(data || []));
  }, [abierto, yo.esAdmin, lista.length]);

  function elegirRango(c: (typeof RANGOS)[number][0]) {
    setRango(c);
    if (c !== 'libre') {
      const r = rangoRapido(c, hoy);
      setDesde(r.desde);
      setHasta(r.hasta);
    }
  }

  async function descargar() {
    if (!desde || !hasta || hasta < desde) return avisar('Revisa las fechas: la final no puede ser anterior a la inicial.', 'error');
    setOcupado(true);
    try {
      await descargarReporte({ tipo, formato, desde, hasta, ...(yo.esAdmin && persona ? { personal_id: persona } : {}) });
      avisar('Reporte descargado.');
      setAbierto(false);
    } catch (e) {
      avisar(e instanceof Error ? e.message : 'No se pudo descargar.', 'error');
    } finally {
      setOcupado(false);
    }
  }

  return (
    <>
      <Boton variante={variante} icono={<Download className="size-4" />} onClick={() => setAbierto(true)}>
        Descargar reporte
      </Boton>
      <Modal abierto={abierto} titulo="Descargar reporte" onCerrar={() => setAbierto(false)}>
        <div className="flex flex-col gap-4">
          <Campo etiqueta="Reporte">
            <Segmentado etiqueta="Tipo de reporte" opciones={[['asistencia', 'Asistencia'], ['pagos', 'Pagos']]} valor={tipo} onCambio={setTipo} />
          </Campo>
          <Campo etiqueta="Periodo">
            <Segmentado etiqueta="Periodo" opciones={RANGOS.map(([v, t]) => [v, t])} valor={rango} onCambio={elegirRango} />
          </Campo>
          <div className="grid grid-cols-2 gap-3">
            <Campo etiqueta="Desde">
              <input type="date" className={claseInput} value={desde} max={hasta || hoy} onChange={(e) => (setRango('libre'), setDesde(e.target.value))} />
            </Campo>
            <Campo etiqueta="Hasta">
              <input type="date" className={claseInput} value={hasta} min={desde} onChange={(e) => (setRango('libre'), setHasta(e.target.value))} />
            </Campo>
          </div>
          {yo.esAdmin && (
            <Campo etiqueta="Trabajador">
              <select className={claseInput} value={persona} onChange={(e) => setPersona(e.target.value)}>
                <option value="">Todo el personal</option>
                {lista.map((p) => (
                  <option key={p.id} value={p.id}>
                    {nombreCorto(p)}
                  </option>
                ))}
              </select>
            </Campo>
          )}
          <Campo etiqueta="Formato">
            <div className="grid grid-cols-2 gap-2">
              {(
                [
                  ['pdf', 'PDF', 'Para imprimir o enviar', FileText],
                  ['xlsx', 'Excel', 'Para editar y filtrar', FileSpreadsheet],
                ] as const
              ).map(([v, t, d, Icono]) => (
                <button
                  key={v}
                  type="button"
                  aria-pressed={formato === v}
                  onClick={() => setFormato(v)}
                  className={`flex items-center gap-2.5 rounded-lg border p-3 text-left transition ${formato === v ? 'border-acento bg-acento-suave' : 'border-linea hover:bg-hundido'}`}
                >
                  <Icono className={`size-5 ${formato === v ? 'text-acento' : 'text-tenue'}`} />
                  <span>
                    <span className="block text-sm font-semibold">{t}</span>
                    <span className="block text-xs text-tenue">{d}</span>
                  </span>
                </button>
              ))}
            </div>
          </Campo>
          {!yo.esAdmin && <p className="text-xs text-tenue">El reporte incluye solo tu información.</p>}
          <Boton icono={<Download className="size-4" />} cargando={ocupado} onClick={descargar}>
            Descargar {formato === 'pdf' ? 'PDF' : 'Excel'}
          </Boton>
        </div>
      </Modal>
    </>
  );
}
