import 'server-only';
import { NextResponse } from 'next/server';

export class ErrorHttp extends Error {
  constructor(
    public status: number,
    message: string,
    public extra?: Record<string, unknown>,
  ) {
    super(message);
  }
}

export function json(datos: unknown, status = 200) {
  return NextResponse.json(datos, { status });
}

/** Envuelve un handler: convierte ErrorHttp y errores inesperados en respuestas JSON. */
export function manejar(handler: (req: Request) => Promise<Response>) {
  return async (req: Request) => {
    try {
      return await handler(req);
    } catch (e) {
      if (e instanceof ErrorHttp) {
        return json({ ok: false, error: e.message, ...(e.extra || {}) }, e.status);
      }
      console.error('[api] error inesperado', e);
      return json({ ok: false, error: 'Ocurrió un error inesperado en el servidor. Intenta de nuevo.' }, 500);
    }
  };
}

const TIPOS_IMAGEN = ['image/jpeg', 'image/png', 'image/webp'];
const MAX_BYTES = 5 * 1024 * 1024;

export type ImagenRecibida = { buffer: Buffer; tipo: string; campos: Record<string, string> };

/**
 * Lee una imagen enviada como:
 *  - multipart/form-data con el campo "imagen" (app Flutter y formularios web), o
 *  - JSON { "imagen_base64": "data:image/jpeg;base64,..." } (captura desde la webcam).
 * Devuelve también los demás campos de texto recibidos.
 */
export async function leerImagen(req: Request, requerida = true): Promise<ImagenRecibida | null> {
  const tipoContenido = req.headers.get('content-type') || '';
  const campos: Record<string, string> = {};
  let buffer: Buffer | null = null;
  let tipo = 'image/jpeg';

  if (tipoContenido.includes('multipart/form-data')) {
    const form = await req.formData();
    for (const [clave, valor] of form.entries()) {
      if (typeof valor === 'string') campos[clave] = valor;
    }
    const archivo = form.get('imagen');
    if (archivo && typeof archivo !== 'string') {
      buffer = Buffer.from(await archivo.arrayBuffer());
      tipo = archivo.type || tipo;
    }
  } else if (tipoContenido.includes('application/json')) {
    const cuerpo = (await req.json().catch(() => null)) as Record<string, unknown> | null;
    if (!cuerpo) throw new ErrorHttp(400, 'El cuerpo de la petición no es un JSON válido.');
    for (const [clave, valor] of Object.entries(cuerpo)) {
      if (clave !== 'imagen_base64' && valor != null) campos[clave] = String(valor);
    }
    const b64 = typeof cuerpo.imagen_base64 === 'string' ? cuerpo.imagen_base64 : null;
    if (b64) {
      const coincide = b64.match(/^data:(image\/[a-z]+);base64,(.*)$/);
      tipo = coincide ? coincide[1] : tipo;
      buffer = Buffer.from(coincide ? coincide[2] : b64, 'base64');
    }
  } else {
    throw new ErrorHttp(415, 'Envía la imagen como multipart/form-data (campo "imagen") o JSON (campo "imagen_base64").');
  }

  if (!buffer || buffer.length === 0) {
    if (requerida) throw new ErrorHttp(400, 'No se recibió ninguna imagen.');
    return null;
  }
  if (buffer.length > MAX_BYTES) throw new ErrorHttp(413, 'La imagen pesa más de 5 MB.');
  if (!TIPOS_IMAGEN.includes(tipo)) throw new ErrorHttp(415, 'Formato no permitido: usa JPG, PNG o WEBP.');
  return { buffer, tipo, campos };
}
