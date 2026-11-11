import { GoogleGenAI, type Content } from '@google/genai';
import { exigirSesion } from '@/lib/auth';
import { DECLARACIONES, ejecutarHerramienta, type Origen } from '@/lib/chatbot/herramientas';
import { construirInstrucciones } from '@/lib/chatbot/prompt';
import { servidor } from '@/lib/config';
import { ErrorHttp, json, manejar } from '@/lib/http';
import { supabaseAdmin } from '@/lib/supabase/admin';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const maxDuration = 60;

const MAX_MENSAJES = 20;
const MAX_CARACTERES = 1500;
const MAX_VUELTAS_HERRAMIENTAS = 5;

type MensajeEntrada = { rol: 'usuario' | 'asistente'; texto: string };
type Accion = { herramienta: string; argumentos: Record<string, unknown>; ok: boolean; resultado: Record<string, unknown> };

let ia: GoogleGenAI | null = null;
const cliente = () => (ia ??= new GoogleGenAI({ apiKey: servidor.geminiApiKey() }));

const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms));
const estadoDe = (e: unknown) => Number((e as { status?: number })?.status || 0);
const esTemporal = (e: unknown) => [429, 500, 503].includes(estadoDe(e));

/**
 * Llama a Gemini con reintentos.
 *  - En el primer turno, si el modelo principal está saturado (503) o sin cuota (429),
 *    prueba los modelos de respaldo (cada modelo tiene su propia cuota en el plan gratuito).
 *  - A mitad de una cadena de herramientas se queda con el mismo modelo (las firmas de
 *    razonamiento de Gemini 3 solo son válidas para el modelo que las generó) y reintenta.
 */
async function generar(contenidos: Content[], config: Record<string, unknown>, modeloFijo?: string) {
  const modelos = modeloFijo ? [modeloFijo] : servidor.geminiModelos();
  let ultimoError: unknown;
  for (let intento = 0; intento < 2; intento++) {
    for (const modelo of modelos) {
      try {
        const resultado = await cliente().models.generateContent({ model: modelo, contents: contenidos, config });
        return { resultado, modelo };
      } catch (e) {
        ultimoError = e;
        if (!esTemporal(e)) throw e;
        console.warn(`[chatbot] ${modelo} no disponible (${estadoDe(e)}), probando otra opción`);
      }
    }
    if (intento === 0) await esperar(4000);
  }
  throw ultimoError;
}

/**
 * POST /api/ia/chatbot  — mismo endpoint para la app móvil y la web.
 * Encabezado: Authorization: Bearer <access_token> (móvil) o cookies de sesión (web).
 * JSON: {
 *   "mensajes": [{ "rol": "usuario", "texto": "¿Cuántos días he asistido este mes?" }, ...],
 *   "origen": "movil" | "web"
 * }
 * Respuesta: { ok, respuesta, acciones: [{ herramienta, argumentos, ok, resultado }] }
 *   "acciones" permite a la interfaz mostrar, p. ej., "Permiso registrado" y refrescar la lista.
 */
export const POST = manejar(async (req) => {
  const sesion = await exigirSesion(req);
  const cuerpo = (await req.json().catch(() => null)) as { mensajes?: MensajeEntrada[]; origen?: string } | null;

  const mensajes = (cuerpo?.mensajes || [])
    .filter((m) => m && typeof m.texto === 'string' && m.texto.trim() && (m.rol === 'usuario' || m.rol === 'asistente'))
    .slice(-MAX_MENSAJES);
  if (!mensajes.length || mensajes[mensajes.length - 1].rol !== 'usuario') {
    throw new ErrorHttp(400, 'Envía al menos un mensaje y que el último sea del usuario.');
  }
  if (mensajes.some((m) => m.texto.length > MAX_CARACTERES)) {
    throw new ErrorHttp(400, `Cada mensaje puede tener como máximo ${MAX_CARACTERES} caracteres.`);
  }
  const origen: Origen = cuerpo?.origen === 'movil' ? 'movil' : 'web';

  const { data: reglas } = await supabaseAdmin()
    .from('conocimiento_empresa')
    .select('categoria, pregunta_frecuente, respuesta_politica')
    .eq('activo', true)
    .order('categoria');

  const contenidos: Content[] = mensajes.map((m) => ({
    role: m.rol === 'usuario' ? 'user' : 'model',
    parts: [{ text: m.texto.trim() }],
  }));

  const config = {
    systemInstruction: construirInstrucciones(sesion, reglas || []),
    tools: [{ functionDeclarations: DECLARACIONES }],
    temperature: 0.3,
  };

  const acciones: Accion[] = [];
  let respuesta = '';
  let modeloUsado: string | undefined;

  for (let vuelta = 0; vuelta <= MAX_VUELTAS_HERRAMIENTAS; vuelta++) {
    let resultado;
    try {
      const r = await generar(contenidos, config, modeloUsado);
      resultado = r.resultado;
      modeloUsado = r.modelo;
    } catch (e) {
      console.error('[chatbot] Gemini', e);
      if (acciones.some((a) => a.herramienta === 'registrar_permiso_chat' && a.ok)) {
        respuesta = 'Tu permiso quedó registrado. Puedes ver su estado en el módulo de Permisos.';
        break;
      }
      throw new ErrorHttp(
        estadoDe(e) === 429 ? 429 : 502,
        estadoDe(e) === 429
          ? 'El asistente alcanzó el límite de consultas por minuto. Espera unos segundos y vuelve a intentarlo.'
          : 'El asistente no está disponible en este momento. Intenta de nuevo en unos segundos.',
      );
    }

    const llamadas = resultado.functionCalls || [];
    if (!llamadas.length || vuelta === MAX_VUELTAS_HERRAMIENTAS) {
      respuesta = (resultado.text || '').trim();
      break;
    }

    // Se devuelve el contenido del modelo tal cual (incluye las firmas de razonamiento que exige Gemini 3).
    const contenidoModelo = resultado.candidates?.[0]?.content;
    if (contenidoModelo) contenidos.push(contenidoModelo);

    const respuestas = [];
    for (const llamada of llamadas) {
      const nombre = llamada.name || '';
      const argumentos = (llamada.args || {}) as Record<string, unknown>;
      const salida = await ejecutarHerramienta(nombre, argumentos, { sesion, origen });
      acciones.push({ herramienta: nombre, argumentos, ok: !salida.error, resultado: salida });
      respuestas.push({ functionResponse: { id: llamada.id, name: nombre, response: salida } });
    }
    contenidos.push({ role: 'user', parts: respuestas });
  }

  if (!respuesta) {
    respuesta = 'No pude generar una respuesta. ¿Puedes repetir tu consulta con otras palabras?';
  }

  return json({ ok: true, respuesta, acciones, modelo: modeloUsado });
});
