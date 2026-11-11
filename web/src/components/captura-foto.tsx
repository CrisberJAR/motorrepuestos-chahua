'use client';
import { Camera, ImagePlus, RefreshCw } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { Boton } from '@/components/ui';

/**
 * Foto oficial del rostro: desde la cámara de la PC (webcam) o subiendo un archivo.
 * Entrega un Blob JPEG al formulario.
 */
export function CapturaFoto({ foto, onCambio }: { foto: Blob | null; onCambio: (f: Blob | null) => void }) {
  const video = useRef<HTMLVideoElement>(null);
  const flujo = useRef<MediaStream | null>(null);
  const [camaraActiva, setCamaraActiva] = useState(false);
  const [error, setError] = useState('');
  const [vista, setVista] = useState<string | null>(null);

  useEffect(() => {
    if (!foto) return setVista(null);
    const url = URL.createObjectURL(foto);
    setVista(url);
    return () => URL.revokeObjectURL(url);
  }, [foto]);

  const apagar = () => {
    flujo.current?.getTracks().forEach((t) => t.stop());
    flujo.current = null;
    setCamaraActiva(false);
  };
  useEffect(() => apagar, []);

  async function encender() {
    setError('');
    try {
      const s = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'user', width: { ideal: 960 }, height: { ideal: 720 } }, audio: false });
      flujo.current = s;
      setCamaraActiva(true);
      onCambio(null);
      requestAnimationFrame(() => {
        if (video.current) {
          video.current.srcObject = s;
          video.current.play().catch(() => {});
        }
      });
    } catch {
      setError('No se pudo abrir la cámara. Revisa el permiso del navegador o sube una foto.');
    }
  }

  function capturar() {
    const v = video.current;
    if (!v || !v.videoWidth) return;
    const lienzo = document.createElement('canvas');
    lienzo.width = v.videoWidth;
    lienzo.height = v.videoHeight;
    const ctx = lienzo.getContext('2d')!;
    ctx.translate(lienzo.width, 0);
    ctx.scale(-1, 1);
    ctx.drawImage(v, 0, 0);
    lienzo.toBlob((b) => {
      if (b) {
        onCambio(b);
        apagar();
      }
    }, 'image/jpeg', 0.9);
  }

  function elegirArchivo(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    e.target.value = '';
    if (!f) return;
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(f.type)) return setError('Usa una imagen JPG, PNG o WEBP.');
    if (f.size > 5 * 1024 * 1024) return setError('La imagen pesa más de 5 MB.');
    setError('');
    apagar();
    onCambio(f);
  }

  return (
    <div className="flex flex-col gap-3 rounded-xl border border-dashed border-linea p-3">
      <div className="grid aspect-[4/3] w-full max-w-sm place-items-center self-center overflow-hidden rounded-lg bg-lateral text-lateral-tenue">
        {camaraActiva ? (
          <video ref={video} className="size-full -scale-x-100 object-cover" playsInline muted />
        ) : vista ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={vista} alt="Foto del rostro" className="size-full object-cover" />
        ) : (
          <div className="flex flex-col items-center gap-2 p-4 text-center text-xs">
            <Camera className="size-8" />
            De frente, con buena luz, sin gorra ni lentes oscuros. Solo una persona en la foto.
          </div>
        )}
      </div>
      <div className="flex flex-wrap justify-center gap-2">
        {camaraActiva ? (
          <>
            <Boton icono={<Camera className="size-4" />} onClick={capturar}>
              Tomar foto
            </Boton>
            <Boton variante="secundario" onClick={apagar}>
              Cancelar
            </Boton>
          </>
        ) : (
          <>
            <Boton variante="secundario" icono={foto ? <RefreshCw className="size-4" /> : <Camera className="size-4" />} onClick={encender}>
              {foto ? 'Tomar otra' : 'Usar cámara'}
            </Boton>
            <label className="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-linea bg-superficie px-3.5 py-2 text-[13px] font-semibold hover:bg-hundido">
              <ImagePlus className="size-4" /> Subir foto
              <input type="file" accept="image/jpeg,image/png,image/webp" className="sr-only" onChange={elegirArchivo} />
            </label>
          </>
        )}
      </div>
      {error && <p className="text-center text-xs text-peligro">{error}</p>}
    </div>
  );
}
