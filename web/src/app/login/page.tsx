'use client';
import { Eye, EyeOff, LogIn, ScanFace } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { Boton, Campo, claseInput } from '@/components/ui';
import { correoDesdeDni } from '@/lib/config';
import { supabaseNavegador } from '@/lib/supabase/navegador';

export default function PaginaLogin() {
  const router = useRouter();
  const [dni, setDni] = useState('');
  const [clave, setClave] = useState('');
  const [verClave, setVerClave] = useState(false);
  const [error, setError] = useState('');
  const [cargando, setCargando] = useState(false);

  async function ingresar(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (!/^\d{8}$/.test(dni)) return setError('Tu usuario es tu DNI: 8 dígitos.');
    if (!clave) return setError('Escribe tu contraseña.');
    setCargando(true);
    const { error: err } = await supabaseNavegador().auth.signInWithPassword({ email: correoDesdeDni(dni), password: clave });
    if (err) {
      setCargando(false);
      return setError(
        err.message.includes('Invalid login')
          ? 'DNI o contraseña incorrectos. Si olvidaste tu contraseña, pide al administrador que la restablezca.'
          : 'No se pudo iniciar sesión. Revisa tu conexión e intenta de nuevo.',
      );
    }
    router.replace('/panel');
    router.refresh();
  }

  return (
    <main className="grid min-h-dvh lg:grid-cols-[1.1fr_1fr]">
      <section className="relative hidden flex-col justify-between overflow-hidden bg-lateral p-10 text-lateral-tinta lg:flex">
        <div>
          <p className="font-mono text-[11px] tracking-[0.12em] text-lateral-tenue uppercase">Motorrepuestos</p>
          <p className="titulo-display text-6xl tracking-wider">
            CHA<span className="text-acento">HUA</span>
          </p>
        </div>
        <div className="max-w-md space-y-4">
          <h1 className="titulo-display text-4xl text-balance">Gestión de personal, asistencia y pagos</h1>
          <p className="text-[15px] leading-relaxed text-lateral-tenue">
            La asistencia se marca con reconocimiento facial desde el celular del administrador. Aquí cada trabajador ve sus días, permisos y pagos en tiempo real.
          </p>
          <ul className="space-y-2 text-[13px]">
            <li className="flex items-center gap-2"><ScanFace className="size-4 text-acento" /> Entrada 08:00 · tolerancia 10 minutos</li>
            <li className="flex items-center gap-2"><ScanFace className="size-4 text-acento" /> Lunes a sábado, 08:00 a 19:00</li>
          </ul>
        </div>
        <p className="font-mono text-[11px] text-lateral-tenue">Sistema de tesis · Aplicación web + app móvil sincronizadas</p>
      </section>

      <section className="flex items-center justify-center px-4 py-10 sm:px-8">
        <form onSubmit={ingresar} className="flex w-full max-w-sm flex-col gap-5" noValidate>
          <div className="lg:hidden">
            <p className="font-mono text-[11px] tracking-[0.12em] text-tenue uppercase">Motorrepuestos</p>
            <p className="titulo-display text-5xl tracking-wider">
              CHA<span className="text-acento">HUA</span>
            </p>
          </div>
          <div>
            <h2 className="titulo-display text-3xl">Iniciar sesión</h2>
            <p className="mt-1 text-[13px] text-tenue">Usuario y contraseña inicial: tu DNI.</p>
          </div>

          <Campo etiqueta="DNI">
            <input
              id="dni"
              className={claseInput}
              inputMode="numeric"
              autoComplete="username"
              maxLength={8}
              placeholder="72345678"
              value={dni}
              onChange={(e) => setDni(e.target.value.replace(/\D/g, ''))}
              autoFocus
            />
          </Campo>
          <Campo etiqueta="Contraseña">
            <div className="relative">
              <input
                id="clave"
                className={`${claseInput} pr-10`}
                type={verClave ? 'text' : 'password'}
                autoComplete="current-password"
                value={clave}
                onChange={(e) => setClave(e.target.value)}
              />
              <button
                type="button"
                onClick={() => setVerClave((v) => !v)}
                aria-label={verClave ? 'Ocultar contraseña' : 'Mostrar contraseña'}
                className="absolute inset-y-0 right-2 grid place-items-center text-tenue"
              >
                {verClave ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
              </button>
            </div>
          </Campo>

          {error && <p role="alert" className="rounded-lg bg-peligro-suave px-3 py-2 text-[13px] text-peligro">{error}</p>}

          <Boton type="submit" cargando={cargando} icono={<LogIn className="size-4" />} className="py-2.5">
            Ingresar
          </Boton>
        </form>
      </section>
    </main>
  );
}
