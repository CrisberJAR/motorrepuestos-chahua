'use client';
import { Check, X } from 'lucide-react';
import { useState } from 'react';
import { useAvisos } from '@/components/avisos';
import { Avatar, Boton, Chip, ChipPermiso } from '@/components/ui';
import { cambiarGoce, revisarPermiso } from '@/lib/acciones';
import { fechaCorta } from '@/lib/fechas';
import { ETIQUETA_ORIGEN, ETIQUETA_TIPO, nombreCorto, type Permiso } from '@/lib/tipos';

const rango = (p: Permiso) => (p.fecha_inicio === p.fecha_fin ? fechaCorta(p.fecha_inicio) : `${fechaCorta(p.fecha_inicio)} al ${fechaCorta(p.fecha_fin)}`);

export function FilaPermiso({ permiso, admin, foto, onCambio }: { permiso: Permiso; admin: boolean; foto?: string; onCambio?: () => void }) {
  const { avisar } = useAvisos();
  const [ocupado, setOcupado] = useState<string | null>(null);
  const persona = permiso.personal;

  async function ejecutar(clave: string, accion: () => Promise<void>, mensaje: string) {
    setOcupado(clave);
    try {
      await accion();
      avisar(mensaje);
      onCambio?.();
    } catch (e) {
      avisar(e instanceof Error ? e.message : 'No se pudo completar la acción.', 'error');
    } finally {
      setOcupado(null);
    }
  }

  return (
    <div className="flex flex-wrap items-center gap-3 border-t border-linea py-3 first:border-t-0 first:pt-0 last:pb-0">
      {persona && <Avatar persona={persona} url={foto} />}
      <div className="flex min-w-[200px] flex-1 flex-col">
        <div className="flex flex-wrap items-center gap-2">
          {persona && <span className="font-semibold">{nombreCorto(persona)}</span>}
          <Chip clase="ring-1 ring-linea ring-inset text-tenue font-mono font-medium">{ETIQUETA_TIPO[permiso.tipo_permiso]}</Chip>
          {permiso.estado === 'aprobado' && (
            <Chip clase={permiso.con_goce ? 'bg-ok-suave text-ok' : 'bg-hundido text-tenue'}>{permiso.con_goce ? 'Con goce (se paga)' : 'Sin goce'}</Chip>
          )}
        </div>
        <span className="text-[13px]">
          <span className="font-medium">{rango(permiso)}</span> · {permiso.motivo}
        </span>
        <span className="text-xs text-tenue">Solicitado desde: {ETIQUETA_ORIGEN[permiso.origen]}</span>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {admin && permiso.estado === 'pendiente' ? (
          <>
            <Boton
              variante="ok"
              tam="sm"
              icono={<Check className="size-3.5" />}
              cargando={ocupado === 'ok'}
              disabled={!!ocupado}
              onClick={() => ejecutar('ok', () => revisarPermiso(permiso, 'aprobado'), 'Permiso aprobado.')}
            >
              Aprobar
            </Boton>
            <Boton
              variante="secundario"
              tam="sm"
              icono={<X className="size-3.5" />}
              cargando={ocupado === 'no'}
              disabled={!!ocupado}
              onClick={() => ejecutar('no', () => revisarPermiso(permiso, 'rechazado'), 'Permiso rechazado.')}
            >
              Rechazar
            </Boton>
          </>
        ) : (
          <ChipPermiso estado={permiso.estado} />
        )}
        {admin && permiso.estado === 'aprobado' && (
          <label className="inline-flex cursor-pointer items-center gap-2 text-xs text-tenue">
            <input
              type="checkbox"
              className="size-4 accent-[var(--ok)]"
              checked={permiso.con_goce}
              disabled={!!ocupado}
              onChange={(e) => {
                const valor = e.target.checked;
                ejecutar('goce', () => cambiarGoce(permiso, valor), valor ? 'Estos días se pagarán.' : 'Estos días ya no se pagarán.');
              }}
            />
            Pagar estos días
          </label>
        )}
      </div>
    </div>
  );
}
