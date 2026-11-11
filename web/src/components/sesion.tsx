'use client';
import { createContext, useContext } from 'react';
import type { Yo } from '@/lib/tipos';

const ContextoSesion = createContext<Yo | null>(null);

export function ProveedorSesion({ yo, children }: { yo: Yo; children: React.ReactNode }) {
  return <ContextoSesion.Provider value={yo}>{children}</ContextoSesion.Provider>;
}

/** Datos de la persona que inició sesión (tabla personal). */
export function useYo(): Yo & { esAdmin: boolean } {
  const yo = useContext(ContextoSesion);
  if (!yo) throw new Error('useYo debe usarse dentro de ProveedorSesion');
  return { ...yo, esAdmin: yo.rol === 'admin' };
}
