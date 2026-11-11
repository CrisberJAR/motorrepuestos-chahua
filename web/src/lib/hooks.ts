'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import { supabaseNavegador } from '@/lib/supabase/navegador';

/**
 * Carga datos y los vuelve a cargar cuando cambian las dependencias o cuando
 * Supabase Realtime avisa de cambios en alguna de las tablas indicadas
 * (lo que se marque desde la app móvil aparece aquí al instante).
 */
export function useConsulta<T>(cargar: () => Promise<T>, deps: unknown[], tablas: string[] = []) {
  const [datos, setDatos] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(true);
  const funcion = useRef(cargar);
  funcion.current = cargar;
  const turno = useRef(0);

  const recargar = useCallback(async () => {
    const mio = ++turno.current;
    try {
      const resultado = await funcion.current();
      if (mio === turno.current) {
        setDatos(resultado);
        setError(null);
      }
    } catch (e) {
      if (mio === turno.current) setError(e instanceof Error ? e.message : 'No se pudieron cargar los datos.');
    } finally {
      if (mio === turno.current) setCargando(false);
    }
  }, []);

  useEffect(() => {
    setCargando(true);
    recargar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  const claveTablas = tablas.join(',');
  useEffect(() => {
    if (!claveTablas) return;
    const sb = supabaseNavegador();
    let espera: ReturnType<typeof setTimeout> | undefined;
    const canal = sb.channel(`rt-${claveTablas}-${Math.random().toString(36).slice(2)}`);
    claveTablas.split(',').forEach((tabla) =>
      canal.on('postgres_changes', { event: '*', schema: 'public', table: tabla }, () => {
        clearTimeout(espera);
        espera = setTimeout(recargar, 400);
      }),
    );
    canal.subscribe();
    return () => {
      clearTimeout(espera);
      sb.removeChannel(canal);
    };
  }, [claveTablas, recargar]);

  return { datos, error, cargando, recargar };
}

/** URLs firmadas (1 hora) para las fotos de un bucket privado (por defecto, rostros_personal). */
export function useFotos(rutas: (string | null | undefined)[], bucket = 'rostros_personal') {
  const [urls, setUrls] = useState<Record<string, string>>({});
  const clave = rutas.filter(Boolean).sort().join('|');

  useEffect(() => {
    const lista = clave ? clave.split('|') : [];
    if (!lista.length) return;
    let vigente = true;
    supabaseNavegador()
      .storage.from(bucket)
      .createSignedUrls(lista, 3600)
      .then(({ data }) => {
        if (!vigente || !data) return;
        const mapa: Record<string, string> = {};
        data.forEach((d) => d.path && d.signedUrl && (mapa[d.path] = d.signedUrl));
        setUrls(mapa);
      });
    return () => {
      vigente = false;
    };
  }, [clave, bucket]);

  return urls;
}

/** Llama a los endpoints propios (/api/...) con la sesión de cookies. */
export async function llamarApi<T = Record<string, unknown>>(ruta: string, cuerpo: FormData | Record<string, unknown>): Promise<T> {
  const esForm = cuerpo instanceof FormData;
  const r = await fetch(ruta, {
    method: 'POST',
    headers: esForm ? undefined : { 'Content-Type': 'application/json' },
    body: esForm ? cuerpo : JSON.stringify(cuerpo),
  });
  const datos = await r.json().catch(() => ({ ok: false, error: 'Respuesta inválida del servidor.' }));
  if (!r.ok || datos.ok === false) throw new Error(datos.error || `Error ${r.status}`);
  return datos as T;
}
