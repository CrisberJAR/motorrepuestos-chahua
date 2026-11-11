'use client';
import { CircleAlert, CircleCheck, X } from 'lucide-react';
import { createContext, useCallback, useContext, useState } from 'react';

type Aviso = { id: number; texto: string; tipo: 'ok' | 'error' };
type Contexto = { avisar: (texto: string, tipo?: 'ok' | 'error') => void };

const ContextoAvisos = createContext<Contexto>({ avisar: () => {} });

export function ProveedorAvisos({ children }: { children: React.ReactNode }) {
  const [avisos, setAvisos] = useState<Aviso[]>([]);

  const avisar = useCallback((texto: string, tipo: 'ok' | 'error' = 'ok') => {
    const id = Date.now() + Math.random();
    setAvisos((a) => [...a, { id, texto, tipo }]);
    setTimeout(() => setAvisos((a) => a.filter((x) => x.id !== id)), tipo === 'error' ? 6000 : 3500);
  }, []);

  return (
    <ContextoAvisos.Provider value={{ avisar }}>
      {children}
      <div aria-live="polite" className="pointer-events-none fixed inset-x-0 bottom-4 z-50 flex flex-col items-center gap-2 px-4">
        {avisos.map((a) => (
          <div
            key={a.id}
            role="status"
            className={`pointer-events-auto flex max-w-md items-start gap-2 rounded-lg px-4 py-3 text-sm shadow-lg ${
              a.tipo === 'ok' ? 'bg-tinta text-fondo' : 'bg-peligro text-superficie'
            }`}
          >
            {a.tipo === 'ok' ? <CircleCheck className="mt-0.5 size-4 shrink-0" /> : <CircleAlert className="mt-0.5 size-4 shrink-0" />}
            <span className="flex-1">{a.texto}</span>
            <button aria-label="Cerrar aviso" onClick={() => setAvisos((x) => x.filter((y) => y.id !== a.id))}>
              <X className="size-4 opacity-70" />
            </button>
          </div>
        ))}
      </div>
    </ContextoAvisos.Provider>
  );
}

export const useAvisos = () => useContext(ContextoAvisos);
