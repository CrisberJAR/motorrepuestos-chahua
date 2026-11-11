'use client';
import { Camera, ChevronRight, CircleHelp, FileText, Info, KeyRound, MessageCircle, ShieldCheck, Trash2, UserRound } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useRef, useState } from 'react';
import { useAvisos } from '@/components/avisos';
import { BotonSalir } from '@/components/boton-salir';
import { useYo } from '@/components/sesion';
import { Avatar, Boton, Campo, claseInput, Encabezado, MensajeError, Modal, Tarjeta } from '@/components/ui';
import { correoDesdeDni } from '@/lib/config';
import { useFotos } from '@/lib/hooks';
import { ACTUALIZADO, EMPRESA, PREGUNTAS, PRIVACIDAD, TERMINOS, VERSION_APP, type SeccionLegal } from '@/lib/legal';
import { supabaseNavegador } from '@/lib/supabase/navegador';

/** Reduce la foto a 512 px (JPEG) antes de subirla. */
async function prepararFoto(archivo: File): Promise<Blob> {
  const url = URL.createObjectURL(archivo);
  try {
    const img = await new Promise<HTMLImageElement>((ok, mal) => {
      const i = new Image();
      i.onload = () => ok(i);
      i.onerror = () => mal(new Error('No se pudo leer la imagen.'));
      i.src = url;
    });
    const lado = Math.min(img.naturalWidth, img.naturalHeight);
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = Math.min(512, lado);
    const ctx = canvas.getContext('2d')!;
    // Recorte cuadrado centrado
    ctx.drawImage(img, (img.naturalWidth - lado) / 2, (img.naturalHeight - lado) / 2, lado, lado, 0, 0, canvas.width, canvas.height);
    return await new Promise<Blob>((ok, mal) => canvas.toBlob((b) => (b ? ok(b) : mal(new Error('No se pudo procesar la imagen.'))), 'image/jpeg', 0.85));
  } finally {
    URL.revokeObjectURL(url);
  }
}

export default function PaginaConfiguracion() {
  const yo = useYo();
  const router = useRouter();
  const { avisar } = useAvisos();
  const fotosPerfil = useFotos([yo.foto_perfil_url], 'fotos_perfil');
  const fotosRostro = useFotos([yo.foto_perfil_url ? null : yo.foto_rostro_url]);
  const foto = yo.foto_perfil_url ? fotosPerfil[yo.foto_perfil_url] : yo.foto_rostro_url ? fotosRostro[yo.foto_rostro_url] : null;
  const entrada = useRef<HTMLInputElement>(null);
  const [subiendo, setSubiendo] = useState(false);
  const [legal, setLegal] = useState<{ titulo: string; secciones: SeccionLegal[] } | null>(null);
  const [ayuda, setAyuda] = useState(false);

  async function cambiarFoto(archivo: File | undefined) {
    if (!archivo) return;
    if (!archivo.type.startsWith('image/')) return avisar('Elige una imagen (JPG, PNG o WEBP).', 'error');
    setSubiendo(true);
    try {
      const blob = await prepararFoto(archivo);
      const ruta = `${yo.id}/perfil.jpg`;
      const sb = supabaseNavegador();
      const { error } = await sb.storage.from('fotos_perfil').upload(ruta, blob, { upsert: true, contentType: 'image/jpeg', cacheControl: '60' });
      if (error) throw new Error(error.message);
      const { error: e2 } = await sb.rpc('actualizar_mi_perfil', { p_foto_perfil_url: ruta });
      if (e2) throw new Error(e2.message);
      avisar('Foto de perfil actualizada.');
      router.refresh();
    } catch (e) {
      avisar(`No se pudo cambiar la foto: ${e instanceof Error ? e.message : ''}`, 'error');
    } finally {
      setSubiendo(false);
      if (entrada.current) entrada.current.value = '';
    }
  }

  async function quitarFoto() {
    setSubiendo(true);
    const sb = supabaseNavegador();
    await sb.storage.from('fotos_perfil').remove([`${yo.id}/perfil.jpg`]);
    const { error } = await sb.rpc('actualizar_mi_perfil', { p_quitar_foto: true });
    setSubiendo(false);
    if (error) return avisar(`No se pudo quitar la foto: ${error.message}`, 'error');
    avisar('Foto de perfil eliminada.');
    router.refresh();
  }

  const fila = 'flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-left text-sm hover:bg-hundido';
  return (
    <>
      <Encabezado titulo="Configuración" subtitulo="Tu perfil, tu contraseña y la información de la aplicación." />

      <div className="grid gap-4 lg:grid-cols-2">
        <Tarjeta titulo="Mi perfil" extra={<UserRound className="size-4 text-tenue" />}>
          <div className="flex flex-wrap items-center gap-4">
            <Avatar persona={yo} url={foto} tam={84} />
            <div className="min-w-0 flex-1">
              <p className="text-lg font-semibold">
                {yo.nombres} {yo.apellidos}
              </p>
              <p className="text-[13px] text-tenue">
                {yo.esAdmin ? 'Administrador' : yo.cargo} · {yo.area}
              </p>
              <p className="text-[13px] text-tenue">DNI {yo.dni}</p>
              <div className="mt-2 flex flex-wrap gap-2">
                <input ref={entrada} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={(e) => cambiarFoto(e.target.files?.[0])} />
                <Boton tam="sm" variante="secundario" icono={<Camera className="size-3.5" />} cargando={subiendo} onClick={() => entrada.current?.click()}>
                  {yo.foto_perfil_url ? 'Cambiar foto' : 'Subir foto'}
                </Boton>
                {yo.foto_perfil_url && (
                  <Boton tam="sm" variante="fantasma" icono={<Trash2 className="size-3.5" />} disabled={subiendo} onClick={quitarFoto}>
                    Quitar
                  </Boton>
                )}
              </div>
            </div>
          </div>
          <p className="mt-3 text-xs text-tenue">
            La foto de perfil es solo para mostrar. La foto para el reconocimiento facial la registra el administrador y no cambia con esta opción.
          </p>
          <DatosContacto />
        </Tarjeta>

        <Tarjeta titulo="Seguridad" extra={<KeyRound className="size-4 text-tenue" />}>
          <CambiarClave />
        </Tarjeta>

        <Tarjeta titulo="Información y ayuda">
          <div className="-mx-2 flex flex-col">
            <button className={fila} onClick={() => setLegal({ titulo: 'Términos y condiciones', secciones: TERMINOS })}>
              <FileText className="size-4 text-tenue" /> <span className="flex-1">Términos y condiciones</span> <ChevronRight className="size-4 text-tenue" />
            </button>
            <button className={fila} onClick={() => setLegal({ titulo: 'Política de privacidad', secciones: PRIVACIDAD })}>
              <ShieldCheck className="size-4 text-tenue" /> <span className="flex-1">Política de privacidad y datos biométricos</span> <ChevronRight className="size-4 text-tenue" />
            </button>
            <button className={fila} onClick={() => setAyuda(true)}>
              <CircleHelp className="size-4 text-tenue" /> <span className="flex-1">Preguntas frecuentes</span> <ChevronRight className="size-4 text-tenue" />
            </button>
            <a className={fila} href={`https://wa.me/51${EMPRESA.whatsapp}`} target="_blank" rel="noopener noreferrer">
              <MessageCircle className="size-4 text-tenue" /> <span className="flex-1">Soporte por WhatsApp · {EMPRESA.whatsapp}</span> <ChevronRight className="size-4 text-tenue" />
            </a>
          </div>
        </Tarjeta>

        <Tarjeta titulo="Acerca de" extra={<Info className="size-4 text-tenue" />}>
          <dl className="text-[13px] [&>div]:flex [&>div]:justify-between [&>div]:gap-3 [&>div]:border-b [&>div]:border-linea [&>div]:py-1.5 [&_dt]:text-tenue">
            <div>
              <dt>Aplicación</dt>
              <dd>Chahua Personal</dd>
            </div>
            <div>
              <dt>Versión</dt>
              <dd>{VERSION_APP}</dd>
            </div>
            <div>
              <dt>Empresa</dt>
              <dd>{EMPRESA.nombre}</dd>
            </div>
            <div>
              <dt>Horario</dt>
              <dd>{EMPRESA.horario}</dd>
            </div>
          </dl>
          <div className="mt-3">
            <BotonSalir className="border border-linea text-peligro hover:bg-peligro-suave" />
          </div>
        </Tarjeta>
      </div>

      <Modal abierto={!!legal} titulo={legal?.titulo || ''} onCerrar={() => setLegal(null)} ancho="max-w-2xl">
        <p className="mb-3 text-xs text-tenue">Última actualización: {ACTUALIZADO}</p>
        <div className="flex flex-col gap-4 text-sm leading-relaxed">
          {legal?.secciones.map((s) => (
            <section key={s.titulo}>
              <h3 className="mb-1 font-semibold">{s.titulo}</h3>
              {s.parrafos.map((p, i) => (
                <p key={i} className="mb-1.5 text-tenue">
                  {p}
                </p>
              ))}
            </section>
          ))}
        </div>
      </Modal>
      <Modal abierto={ayuda} titulo="Preguntas frecuentes" onCerrar={() => setAyuda(false)}>
        <div className="flex flex-col gap-3 text-sm">
          {PREGUNTAS.map((q) => (
            <div key={q.p}>
              <p className="font-semibold">{q.p}</p>
              <p className="text-tenue">{q.r}</p>
            </div>
          ))}
        </div>
      </Modal>
    </>
  );
}

function DatosContacto() {
  const yo = useYo();
  const router = useRouter();
  const { avisar } = useAvisos();
  const [telefono, setTelefono] = useState(yo.telefono || '');
  const [correo, setCorreo] = useState(yo.correo || '');
  const [guardando, setGuardando] = useState(false);
  const cambio = telefono !== (yo.telefono || '') || correo !== (yo.correo || '');

  async function guardar() {
    setGuardando(true);
    const { error } = await supabaseNavegador().rpc('actualizar_mi_perfil', { p_telefono: telefono.trim(), p_correo: correo.trim() });
    setGuardando(false);
    if (error) return avisar(error.message, 'error');
    avisar('Datos de contacto guardados.');
    router.refresh();
  }

  return (
    <div className="mt-4 grid gap-3 border-t border-linea pt-4 sm:grid-cols-2">
      <Campo etiqueta="Teléfono">
        <input className={claseInput} inputMode="tel" maxLength={15} value={telefono} onChange={(e) => setTelefono(e.target.value.replace(/[^0-9+ ]/g, ''))} placeholder="9XXXXXXXX" />
      </Campo>
      <Campo etiqueta="Correo">
        <input className={claseInput} type="email" maxLength={80} value={correo} onChange={(e) => setCorreo(e.target.value)} placeholder="nombre@correo.com" />
      </Campo>
      <div className="sm:col-span-2">
        <Boton tam="sm" disabled={!cambio} cargando={guardando} onClick={guardar}>
          Guardar datos
        </Boton>
      </div>
    </div>
  );
}

function CambiarClave() {
  const yo = useYo();
  const { avisar } = useAvisos();
  const [actual, setActual] = useState('');
  const [nueva, setNueva] = useState('');
  const [repetir, setRepetir] = useState('');
  const [ver, setVer] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  async function cambiar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!actual) return setError('Escribe tu contraseña actual.');
    if (nueva.length < 6) return setError('La nueva contraseña debe tener al menos 6 caracteres.');
    if (nueva.length > 72) return setError('La nueva contraseña no puede superar los 72 caracteres.');
    if (nueva !== repetir) return setError('Las contraseñas nuevas no coinciden.');
    if (nueva === actual) return setError('La nueva contraseña debe ser distinta de la actual.');
    if (nueva === yo.dni) return setError('Por seguridad, no uses tu DNI como contraseña.');
    setGuardando(true);
    const sb = supabaseNavegador();
    const { error: e1 } = await sb.auth.signInWithPassword({ email: correoDesdeDni(yo.dni), password: actual });
    if (e1) {
      setGuardando(false);
      return setError('La contraseña actual no es correcta.');
    }
    const { error: e2 } = await sb.auth.updateUser({ password: nueva });
    setGuardando(false);
    if (e2) return setError(`No se pudo cambiar: ${e2.message}`);
    setActual('');
    setNueva('');
    setRepetir('');
    avisar('Contraseña cambiada. Úsala la próxima vez que ingreses.');
  }

  return (
    <form onSubmit={cambiar} className="flex flex-col gap-3" noValidate>
      <p className="text-[13px] text-tenue">Tu contraseña inicial es tu DNI. Cámbiala por una que solo tú conozcas.</p>
      <Campo etiqueta="Contraseña actual">
        <input className={claseInput} type={ver ? 'text' : 'password'} autoComplete="current-password" value={actual} onChange={(e) => setActual(e.target.value)} />
      </Campo>
      <Campo etiqueta="Nueva contraseña" ayuda="Mínimo 6 caracteres.">
        <input className={claseInput} type={ver ? 'text' : 'password'} autoComplete="new-password" value={nueva} onChange={(e) => setNueva(e.target.value)} />
      </Campo>
      <Campo etiqueta="Repite la nueva contraseña">
        <input className={claseInput} type={ver ? 'text' : 'password'} autoComplete="new-password" value={repetir} onChange={(e) => setRepetir(e.target.value)} />
      </Campo>
      <label className="flex items-center gap-2 text-[13px]">
        <input type="checkbox" checked={ver} onChange={(e) => setVer(e.target.checked)} /> Mostrar contraseñas
      </label>
      {error && <MensajeError texto={error} />}
      <div>
        <Boton type="submit" icono={<KeyRound className="size-4" />} cargando={guardando}>
          Cambiar contraseña
        </Boton>
      </div>
    </form>
  );
}
