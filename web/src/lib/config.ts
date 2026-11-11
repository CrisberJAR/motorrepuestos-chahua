function requerida(nombre: string, valor: string | undefined): string {
  if (!valor) throw new Error(`Falta la variable de entorno ${nombre}`);
  return valor;
}

export const SUPABASE_URL = requerida('NEXT_PUBLIC_SUPABASE_URL', process.env.NEXT_PUBLIC_SUPABASE_URL);
export const SUPABASE_ANON_KEY = requerida('NEXT_PUBLIC_SUPABASE_ANON_KEY', process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
export const DOMINIO_LOGIN = process.env.NEXT_PUBLIC_DOMINIO_LOGIN || 'chahua.pe';

/** Convierte el DNI que escribe la persona en el correo interno de Supabase Auth. */
export const correoDesdeDni = (dni: string) => `${dni.trim()}@${DOMINIO_LOGIN}`;

/** Solo disponibles en el servidor. */
export const servidor = {
  serviceRoleKey: () => requerida('SUPABASE_SERVICE_ROLE_KEY', process.env.SUPABASE_SERVICE_ROLE_KEY),
  geminiApiKey: () => requerida('GEMINI_API_KEY', process.env.GEMINI_API_KEY),
  geminiModelo: () => process.env.GEMINI_MODEL || 'gemini-3.5-flash',
  /** Modelo principal seguido de los de respaldo (GEMINI_MODELOS_RESPALDO, separados por comas). */
  geminiModelos: () => [
    process.env.GEMINI_MODEL || 'gemini-3.5-flash',
    ...(process.env.GEMINI_MODELOS_RESPALDO ?? 'gemini-3.1-flash-lite').split(',').map((m) => m.trim()).filter(Boolean),
  ],
  umbralRostro: () => Number(process.env.ROSTRO_UMBRAL_DISTANCIA || '0.55'),
};
