'use client';
import { LoaderCircle, X } from 'lucide-react';
import { useEffect } from 'react';
import { ETIQUETA_DIA, iniciales, type EstadoDia, type EstadoPermiso } from '@/lib/tipos';

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

/* ---------- Botón ---------- */
type VarianteBoton = 'primario' | 'secundario' | 'ok' | 'peligro' | 'fantasma';
const VARIANTES: Record<VarianteBoton, string> = {
  primario: 'bg-acento text-acento-tinta hover:brightness-110',
  secundario: 'border border-linea bg-superficie text-tinta hover:bg-hundido',
  ok: 'bg-ok text-superficie hover:brightness-110',
  peligro: 'bg-peligro text-superficie hover:brightness-110',
  fantasma: 'text-tenue hover:bg-hundido hover:text-tinta',
};

export function Boton({
  variante = 'primario',
  tam = 'md',
  cargando = false,
  icono,
  className,
  children,
  disabled,
  ...resto
}: React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variante?: VarianteBoton;
  tam?: 'sm' | 'md';
  cargando?: boolean;
  icono?: React.ReactNode;
}) {
  return (
    <button
      type="button"
      disabled={disabled || cargando}
      className={cx(
        'inline-flex items-center justify-center gap-2 rounded-lg font-semibold whitespace-nowrap transition disabled:cursor-not-allowed disabled:opacity-55',
        tam === 'sm' ? 'px-2.5 py-1.5 text-xs' : 'px-3.5 py-2 text-[13px]',
        VARIANTES[variante],
        className,
      )}
      {...resto}
    >
      {cargando ? <LoaderCircle className="size-4 animate-spin" /> : icono}
      {children}
    </button>
  );
}

/* ---------- Contenedores ---------- */
export function Tarjeta({ titulo, extra, children, className }: { titulo?: React.ReactNode; extra?: React.ReactNode; children: React.ReactNode; className?: string }) {
  return (
    <section className={cx('flex min-w-0 flex-col gap-3 rounded-xl border border-linea bg-superficie p-4', className)}>
      {(titulo || extra) && (
        <header className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
          {titulo && <h2 className="text-sm font-semibold">{titulo}</h2>}
          {extra && <div className="text-xs text-tenue">{extra}</div>}
        </header>
      )}
      {children}
    </section>
  );
}

export function Encabezado({ titulo, subtitulo, acciones }: { titulo: string; subtitulo?: React.ReactNode; acciones?: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h1 className="titulo-display text-3xl text-balance">{titulo}</h1>
        {subtitulo && <p className="mt-1 text-[13px] text-tenue">{subtitulo}</p>}
      </div>
      {acciones && <div className="flex flex-wrap items-center gap-2">{acciones}</div>}
    </div>
  );
}

export function Kpi({ etiqueta, valor, detalle, tono }: { etiqueta: string; valor: React.ReactNode; detalle?: React.ReactNode; tono?: 'alerta' | 'peligro' | 'acento' | 'ok' }) {
  const color = tono === 'alerta' ? 'text-alerta' : tono === 'peligro' ? 'text-peligro' : tono === 'acento' ? 'text-acento' : tono === 'ok' ? 'text-ok' : '';
  return (
    <div className="min-w-0 rounded-xl border border-linea bg-superficie px-4 py-3">
      <div className="truncate text-[11px] tracking-wide text-tenue uppercase">{etiqueta}</div>
      <div className={cx('cifras font-display text-[32px] leading-tight font-bold', color)}>{valor}</div>
      {detalle && <div className="truncate text-xs text-tenue">{detalle}</div>}
    </div>
  );
}

export function FilaKpis({ children }: { children: React.ReactNode }) {
  return <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">{children}</div>;
}

/* ---------- Chips de estado ---------- */
const COLOR_DIA: Record<EstadoDia, string> = {
  asistio: 'bg-ok-suave text-ok',
  tardanza: 'bg-alerta-suave text-alerta',
  falta: 'bg-peligro-suave text-peligro',
  permiso: 'bg-info-suave text-info',
  pendiente: 'bg-hundido text-tenue ring-1 ring-linea ring-inset',
  futuro: 'bg-hundido text-tenue',
};
export const RELLENO_DIA: Record<EstadoDia, string> = {
  asistio: 'bg-ok',
  tardanza: 'bg-alerta',
  falta: 'bg-peligro',
  permiso: 'bg-info',
  pendiente: 'ring-1 ring-tenue ring-inset',
  futuro: 'bg-linea',
};

export function Chip({ children, clase }: { children: React.ReactNode; clase: string }) {
  return <span className={cx('inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-semibold whitespace-nowrap', clase)}>{children}</span>;
}

export const ChipDia = ({ estado }: { estado: EstadoDia }) => <Chip clase={COLOR_DIA[estado]}>{ETIQUETA_DIA[estado]}</Chip>;

const COLOR_PERMISO: Record<EstadoPermiso, string> = {
  pendiente: 'bg-alerta-suave text-alerta',
  aprobado: 'bg-ok-suave text-ok',
  rechazado: 'bg-peligro-suave text-peligro',
};
export const ChipPermiso = ({ estado }: { estado: EstadoPermiso }) => (
  <Chip clase={COLOR_PERMISO[estado]}>{estado.charAt(0).toUpperCase() + estado.slice(1)}</Chip>
);

export function Leyenda() {
  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-tenue">
      {(['asistio', 'tardanza', 'permiso', 'falta'] as EstadoDia[]).map((e) => (
        <span key={e} className="inline-flex items-center gap-1.5">
          <i className={cx('inline-block size-2.5 rounded-[3px]', RELLENO_DIA[e])} />
          {ETIQUETA_DIA[e]}
        </span>
      ))}
    </div>
  );
}

/* ---------- Avatar ---------- */
export function Avatar({ persona, url, tam = 34 }: { persona: { nombres: string; apellidos: string }; url?: string | null; tam?: number }) {
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={url} alt="" width={tam} height={tam} className="shrink-0 rounded-full object-cover" style={{ width: tam, height: tam }} />;
  }
  return (
    <span
      className="inline-grid shrink-0 place-items-center rounded-full bg-acento-suave text-xs font-bold text-acento"
      style={{ width: tam, height: tam }}
      aria-hidden
    >
      {iniciales(persona)}
    </span>
  );
}

/* ---------- Formularios ---------- */
export const claseInput =
  'w-full min-w-0 rounded-lg border border-linea bg-superficie px-3 py-2 text-sm text-tinta placeholder:text-tenue/70 disabled:opacity-60';

export function Campo({ etiqueta, children, ancho, ayuda }: { etiqueta: string; children: React.ReactNode; ancho?: boolean; ayuda?: string }) {
  return (
    <label className={cx('flex min-w-0 flex-col gap-1', ancho && 'sm:col-span-2')}>
      <span className="text-[11px] tracking-wide text-tenue uppercase">{etiqueta}</span>
      {children}
      {ayuda && <span className="text-xs text-tenue">{ayuda}</span>}
    </label>
  );
}

export function Segmentado<T extends string>({ opciones, valor, onCambio, etiqueta }: { opciones: [T, string][]; valor: T; onCambio: (v: T) => void; etiqueta: string }) {
  return (
    <div role="group" aria-label={etiqueta} className="inline-flex flex-wrap gap-0.5 rounded-lg border border-linea bg-hundido p-[3px]">
      {opciones.map(([v, texto]) => (
        <button
          key={v}
          type="button"
          aria-pressed={valor === v}
          onClick={() => onCambio(v)}
          className={cx(
            'rounded-md px-3 py-1.5 text-[13px] font-medium transition',
            valor === v ? 'bg-superficie text-tinta shadow-sm' : 'text-tenue hover:text-tinta',
          )}
        >
          {texto}
        </button>
      ))}
    </div>
  );
}

/* ---------- Estados de carga / vacío / error ---------- */
export function Cargando({ texto = 'Cargando…' }: { texto?: string }) {
  return (
    <div className="flex items-center gap-2 py-10 text-tenue">
      <LoaderCircle className="size-4 animate-spin" /> {texto}
    </div>
  );
}

export function Vacio({ titulo, texto, accion }: { titulo: string; texto?: string; accion?: React.ReactNode }) {
  return (
    <div className="flex flex-col items-start gap-2 rounded-lg border border-dashed border-linea p-5">
      <p className="font-semibold">{titulo}</p>
      {texto && <p className="text-[13px] text-tenue">{texto}</p>}
      {accion}
    </div>
  );
}

export function MensajeError({ texto, onReintentar }: { texto: string; onReintentar?: () => void }) {
  return (
    <div className="flex flex-wrap items-center gap-3 rounded-lg border border-peligro/40 bg-peligro-suave px-4 py-3 text-[13px] text-peligro">
      <span className="flex-1">{texto}</span>
      {onReintentar && (
        <Boton variante="secundario" tam="sm" onClick={onReintentar}>
          Reintentar
        </Boton>
      )}
    </div>
  );
}

/* ---------- Modal ---------- */
export function Modal({ abierto, titulo, onCerrar, children, ancho = 'max-w-lg' }: { abierto: boolean; titulo: string; onCerrar: () => void; children: React.ReactNode; ancho?: string }) {
  useEffect(() => {
    if (!abierto) return;
    const tecla = (e: KeyboardEvent) => e.key === 'Escape' && onCerrar();
    window.addEventListener('keydown', tecla);
    return () => window.removeEventListener('keydown', tecla);
  }, [abierto, onCerrar]);

  if (!abierto) return null;
  return (
    <div className="fixed inset-0 z-40 flex items-end justify-center bg-black/45 p-0 sm:items-center sm:p-4" onMouseDown={(e) => e.target === e.currentTarget && onCerrar()}>
      <div role="dialog" aria-modal="true" aria-label={titulo} className={cx('max-h-[92vh] w-full overflow-y-auto rounded-t-2xl bg-superficie p-5 shadow-2xl sm:rounded-2xl', ancho)}>
        <div className="mb-4 flex items-center justify-between gap-3">
          <h2 className="titulo-display text-2xl">{titulo}</h2>
          <button aria-label="Cerrar" onClick={onCerrar} className="rounded-md p-1 text-tenue hover:bg-hundido">
            <X className="size-5" />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}
