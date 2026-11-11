import path from 'node:path';
import type { NextConfig } from 'next';

const rutasIA = ['/api/ia/identificar-rostro', '/api/ia/registrar-rostro', '/api/admin/personal'];

const archivosIA = [
  ...['ssd_mobilenetv1_model', 'face_landmark_68_model', 'face_recognition_model'].flatMap((modelo) => [
    `./node_modules/@vladmandic/face-api/model/${modelo}-weights_manifest.json`,
    `./node_modules/@vladmandic/face-api/model/${modelo}.bin`,
  ]),
  './node_modules/@tensorflow/tfjs-backend-wasm/dist/tfjs-backend-wasm.wasm',
  './node_modules/@tensorflow/tfjs-backend-wasm/dist/tfjs-backend-wasm-simd.wasm',
];

const nextConfig: NextConfig = {
  outputFileTracingRoot: path.join(__dirname),

  // Se cargan desde node_modules en tiempo de ejecución (no se empaquetan con webpack).
  serverExternalPackages: ['@vladmandic/face-api', '@tensorflow/tfjs', '@tensorflow/tfjs-backend-wasm', 'sharp'],

  // Vercel debe incluir los pesos de los modelos y los binarios WebAssembly en las funciones de IA.
  outputFileTracingIncludes: Object.fromEntries(rutasIA.map((ruta) => [ruta, archivosIA])),
};

export default nextConfig;
