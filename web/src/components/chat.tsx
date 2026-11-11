'use client';
import { Bot, Send, Sparkles } from 'lucide-react';
import { Fragment, useEffect, useRef, useState } from 'react';
import { useYo } from '@/components/sesion';

type Accion = { herramienta: string; ok: boolean; resultado: Record<string, unknown> };
type Mensaje = { rol: 'usuario' | 'asistente'; texto: string; acciones?: Accion[]; error?: boolean };

const SUGERENCIAS_ADMIN = [
  '¿Quiénes llegaron tarde esta semana? Revisa a Carlos Gómez',
  '¿Qué días faltó José Ramos en octubre y cuánto se le pagó?',
  'Registra un permiso de salud para mañana al DNI 73561249 por cita médica',
  '¿Cuántos minutos de tolerancia hay?',
];
const SUGERENCIAS_TRABAJADOR = [
  '¿Cuántos días he asistido este mes?',
  '¿Qué días tengo falta?',
  '¿Cuánto me toca cobrar en mi pago de este mes?',
  '¿Ya aprobaron mi permiso?',
  'Necesito pedir permiso para mañana por cita médica',
];

/** Texto con **negritas** y listas simples, sin HTML externo. */
function TextoFormateado({ texto }: { texto: string }) {
  const lineas = texto.split('\n');
  return (
    <>
      {lineas.map((linea, i) => {
        const vineta = /^\s*[*-]\s+/.test(linea);
        const contenido = linea.replace(/^\s*[*-]\s+/, '');
        const partes = contenido.split(/(\*\*[^*]+\*\*)/g).map((p, j) =>
          p.startsWith('**') && p.endsWith('**') ? <strong key={j}>{p.slice(2, -2)}</strong> : <Fragment key={j}>{p}</Fragment>,
        );
        if (!linea.trim()) return <div key={i} className="h-2" />;
        return vineta ? (
          <div key={i} className="flex gap-2 pl-1">
            <span aria-hidden>•</span>
            <span>{partes}</span>
          </div>
        ) : (
          <p key={i}>{partes}</p>
        );
      })}
    </>
  );
}

function EtiquetaAccion({ a }: { a: Accion }) {
  if (a.herramienta === 'registrar_permiso_chat') {
    return a.resultado?.registrado ? (
      <span className="rounded-md bg-ok-suave px-2 py-1 font-mono text-[11px] text-ok">Permiso registrado · {String(a.resultado.estado)}</span>
    ) : (
      <span className="rounded-md bg-alerta-suave px-2 py-1 font-mono text-[11px] text-alerta">Permiso no registrado</span>
    );
  }
  return <span className="rounded-md bg-info-suave px-2 py-1 font-mono text-[11px] text-info">Consultó datos en tiempo real</span>;
}

export function Chat({ alto = 'h-[calc(100dvh-230px)] min-h-[420px]' }: { alto?: string }) {
  const yo = useYo();
  const [mensajes, setMensajes] = useState<Mensaje[]>([
    {
      rol: 'asistente',
      texto: yo.esAdmin
        ? 'Hola. Puedo consultar la asistencia, los pagos y los permisos de cualquier trabajador por DNI o nombre, explicar el reglamento y registrar permisos.'
        : `Hola, ${yo.nombres.split(' ')[0]}. Puedo decirte tus asistencias, faltas y tardanzas, cuánto te toca cobrar, cómo va tu permiso, y registrar una solicitud de permiso.`,
    },
  ]);
  const [texto, setTexto] = useState('');
  const [enviando, setEnviando] = useState(false);
  const fin = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fin.current?.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }, [mensajes, enviando]);

  async function enviar(contenido: string) {
    const limpio = contenido.trim();
    if (!limpio || enviando) return;
    const historial: Mensaje[] = [...mensajes, { rol: 'usuario', texto: limpio }];
    setMensajes(historial);
    setTexto('');
    setEnviando(true);
    try {
      const r = await fetch('/api/ia/chatbot', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          origen: 'web',
          mensajes: historial.filter((m, i) => i > 0 && !m.error).map((m) => ({ rol: m.rol, texto: m.texto })),
        }),
      });
      const datos = await r.json();
      if (!r.ok || !datos.ok) throw new Error(datos.error || 'El asistente no respondió.');
      setMensajes((m) => [...m, { rol: 'asistente', texto: datos.respuesta, acciones: datos.acciones }]);
    } catch (e) {
      setMensajes((m) => [...m, { rol: 'asistente', texto: e instanceof Error ? e.message : 'No se pudo conectar con el asistente.', error: true }]);
    } finally {
      setEnviando(false);
    }
  }

  const sugerencias = yo.esAdmin ? SUGERENCIAS_ADMIN : SUGERENCIAS_TRABAJADOR;

  return (
    <div className={`flex min-h-0 flex-col overflow-hidden rounded-xl border border-linea bg-superficie ${alto}`}>
      <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto p-4" aria-live="polite">
        {mensajes.map((m, i) =>
          m.rol === 'usuario' ? (
            <div key={i} className="max-w-[85%] self-end rounded-2xl rounded-br-md bg-acento px-3.5 py-2.5 text-[13.5px] text-acento-tinta">
              {m.texto}
            </div>
          ) : (
            <div key={i} className="flex max-w-[88%] gap-2.5">
              <span className="mt-0.5 grid size-7 shrink-0 place-items-center rounded-full bg-lateral text-acento">
                <Bot className="size-4" />
              </span>
              <div className="flex min-w-0 flex-col gap-1.5">
                {m.acciones && m.acciones.length > 0 && (
                  <div className="flex flex-wrap gap-1.5">
                    {m.acciones.map((a, j) => (
                      <EtiquetaAccion key={j} a={a} />
                    ))}
                  </div>
                )}
                <div
                  className={`space-y-1 rounded-2xl rounded-tl-md border px-3.5 py-2.5 text-[13.5px] leading-relaxed ${
                    m.error ? 'border-peligro/40 bg-peligro-suave text-peligro' : 'border-linea bg-hundido'
                  }`}
                >
                  <TextoFormateado texto={m.texto} />
                </div>
              </div>
            </div>
          ),
        )}
        {enviando && (
          <div className="flex items-center gap-2.5 text-xs text-tenue">
            <span className="grid size-7 place-items-center rounded-full bg-lateral text-acento">
              <Bot className="size-4" />
            </span>
            <span className="pulso">Consultando…</span>
          </div>
        )}
        <div ref={fin} />
      </div>

      <div className="flex gap-2 overflow-x-auto border-t border-linea px-3 py-2">
        <Sparkles className="mt-1.5 size-3.5 shrink-0 text-tenue" aria-hidden />
        {sugerencias.map((s) => (
          <button
            key={s}
            type="button"
            disabled={enviando}
            onClick={() => enviar(s)}
            className="shrink-0 rounded-full border border-linea px-3 py-1.5 text-xs whitespace-nowrap hover:bg-hundido disabled:opacity-50"
          >
            {s}
          </button>
        ))}
      </div>

      <form
        className="flex gap-2 border-t border-linea p-3"
        onSubmit={(e) => {
          e.preventDefault();
          enviar(texto);
        }}
      >
        <input
          id="mensaje-chat"
          className="min-w-0 flex-1 rounded-lg border border-linea bg-superficie px-3 py-2 text-sm"
          placeholder={yo.esAdmin ? 'Pregunta por un trabajador (DNI o nombre)…' : 'Escribe tu consulta…'}
          value={texto}
          maxLength={1500}
          onChange={(e) => setTexto(e.target.value)}
          aria-label="Mensaje para el asistente"
          autoComplete="off"
        />
        <button
          type="submit"
          disabled={enviando || !texto.trim()}
          aria-label="Enviar"
          className="grid size-10 shrink-0 place-items-center rounded-lg bg-acento text-acento-tinta disabled:opacity-50"
        >
          <Send className="size-4" />
        </button>
      </form>
    </div>
  );
}
