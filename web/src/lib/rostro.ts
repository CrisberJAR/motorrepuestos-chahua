import 'server-only';
import path from 'node:path';
import sharp from 'sharp';
import { ErrorHttp } from '@/lib/http';

/*
 * Visión artificial en el servidor (Vercel, Node.js) con face-api (TensorFlow.js + WebAssembly):
 *   1. SSD MobileNet v1        -> detecta rostros en la foto
 *   2. Face Landmark 68         -> ubica 68 puntos de la cara para alinearla
 *   3. Face Recognition (ResNet)-> genera un descriptor de 128 números por rostro
 * Dos fotos de la misma persona dan descriptores cercanos (distancia euclidiana baja).
 * El mismo modelo se usa para registrar (web y móvil) y para identificar, así los vectores son comparables.
 */

// face-api y tfjs se cargan con import() dinámico: Next.js los deja como paquetes externos
// (serverExternalPackages) y Vercel los incluye en la función. Pesos y .wasm se leen desde node_modules.
const MODULOS = path.join(process.cwd(), 'node_modules');
type FaceApi = typeof import('@vladmandic/face-api');
type TF = typeof import('@tensorflow/tfjs');

let faceapi: FaceApi;
let inicializacion: Promise<void> | null = null;

function inicializar() {
  if (!inicializacion) {
    inicializacion = (async () => {
      const modulo = (await import('@vladmandic/face-api/dist/face-api.node-wasm.js')) as unknown as { default?: FaceApi } & FaceApi;
      faceapi = modulo.default ?? modulo;
      const wasm = await import('@tensorflow/tfjs-backend-wasm');
      const tf = faceapi.tf as unknown as TF;
      wasm.setWasmPaths(path.join(MODULOS, '@tensorflow/tfjs-backend-wasm/dist') + path.sep);
      tf.env().set('WASM_HAS_MULTITHREAD_SUPPORT', false);
      await tf.setBackend('wasm');
      await tf.ready();
      const carpetaModelos = path.join(MODULOS, '@vladmandic/face-api/model');
      await faceapi.nets.ssdMobilenetv1.loadFromDisk(carpetaModelos);
      await faceapi.nets.faceLandmark68Net.loadFromDisk(carpetaModelos);
      await faceapi.nets.faceRecognitionNet.loadFromDisk(carpetaModelos);
    })().catch((e) => {
      inicializacion = null;
      throw e;
    });
  }
  return inicializacion;
}

export type RostroDetectado = {
  descriptor: number[];
  puntajeDeteccion: number;
  caja: { x: number; y: number; ancho: number; alto: number };
  rostrosEnFoto: number;
};

const LADO_MAXIMO = 720;
const TAMANO_MINIMO_ROSTRO = 70;

/** Prepara la foto (orientación EXIF, tamaño) y la devuelve también en JPEG para guardarla como evidencia. */
export async function normalizarFoto(buffer: Buffer) {
  try {
    return await sharp(buffer)
      .rotate()
      .resize({ width: LADO_MAXIMO, height: LADO_MAXIMO, fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: 85 })
      .toBuffer();
  } catch {
    throw new ErrorHttp(422, 'No se pudo leer la imagen. Toma la foto de nuevo.');
  }
}

/**
 * Detecta el rostro principal (el más grande) y calcula su descriptor.
 * @param unico si es true (registro de personal) exige que haya exactamente un rostro en la foto.
 */
export async function analizarRostro(jpeg: Buffer, unico = false): Promise<RostroDetectado> {
  await inicializar();
  const tf = faceapi.tf as unknown as TF;

  // Margen gris del 25 %: el detector falla cuando la cara ocupa toda la foto (fotos muy recortadas).
  const meta = await sharp(jpeg).metadata();
  const margen = Math.round(Math.max(meta.width || 0, meta.height || 0) * 0.25);
  const { data, info } = await sharp(jpeg)
    .extend({ top: margen, bottom: margen, left: margen, right: margen, background: { r: 128, g: 128, b: 128 } })
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const tensor = tf.tensor3d(new Uint8Array(data), [info.height, info.width, 3], 'int32');

  let resultados;
  try {
    resultados = await faceapi
      .detectAllFaces(tensor as never, new faceapi.SsdMobilenetv1Options({ minConfidence: 0.5, maxResults: 5 }))
      .withFaceLandmarks()
      .withFaceDescriptors();
  } finally {
    tensor.dispose();
  }

  if (!resultados.length) {
    throw new ErrorHttp(422, 'No se detectó ningún rostro. Enfoca la cara de frente, con buena luz y sin gorra ni lentes oscuros.', { codigo: 'sin_rostro' });
  }
  if (unico && resultados.length > 1) {
    throw new ErrorHttp(422, `Se detectaron ${resultados.length} rostros. La foto de registro debe tener solo a la persona que se registra.`, { codigo: 'varios_rostros' });
  }

  const principal = resultados.reduce((a, b) => (b.detection.box.area > a.detection.box.area ? b : a));
  const caja = principal.detection.box;
  if (Math.min(caja.width, caja.height) < TAMANO_MINIMO_ROSTRO) {
    throw new ErrorHttp(422, 'El rostro se ve muy pequeño. Acerca más la cámara a la cara.', { codigo: 'rostro_pequeno' });
  }

  return {
    descriptor: Array.from(principal.descriptor),
    puntajeDeteccion: Math.round(principal.detection.score * 1000) / 10,
    caja: {
      x: Math.max(0, Math.round(caja.x - margen)),
      y: Math.max(0, Math.round(caja.y - margen)),
      ancho: Math.round(caja.width),
      alto: Math.round(caja.height),
    },
    rostrosEnFoto: resultados.length,
  };
}

/**
 * Porcentaje de coincidencia que se muestra al usuario: similitud coseno entre descriptores × 100.
 * La decisión de aceptar o rechazar usa la distancia euclidiana (ROSTRO_UMBRAL_DISTANCIA, 0.55).
 * En pruebas: misma persona 0.32–0.45 (≈95–97 %), personas distintas 0.71–0.77 (≈85 %).
 */
export const porcentaje = (similitud: number) => Math.max(0, Math.min(100, Math.round(similitud * 1000) / 10));

/** Formato que acepta pgvector al enviarlo por la API de Supabase. */
export const vectorTexto = (descriptor: number[]) => `[${descriptor.map((n) => n.toFixed(6)).join(',')}]`;
