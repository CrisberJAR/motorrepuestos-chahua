'use client';
import { Bot, CalendarDays, FileText, LayoutDashboard, Settings, Users, Wallet } from 'lucide-react';
import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { BotonSalir } from '@/components/boton-salir';
import { useYo } from '@/components/sesion';
import { Avatar } from '@/components/ui';
import { useFotos } from '@/lib/hooks';
import { nombreCorto } from '@/lib/tipos';

const MENU_ADMIN = [
  { href: '/panel', texto: 'Panel del día', icono: LayoutDashboard },
  { href: '/asistencia', texto: 'Asistencia', icono: CalendarDays },
  { href: '/permisos', texto: 'Permisos', icono: FileText },
  { href: '/pagos', texto: 'Pagos', icono: Wallet },
  { href: '/personal', texto: 'Personal', icono: Users },
  { href: '/asistente', texto: 'Asistente IA', icono: Bot },
  { href: '/configuracion', texto: 'Configuración', icono: Settings },
];

const MENU_TRABAJADOR = [
  { href: '/panel', texto: 'Mi resumen', icono: LayoutDashboard },
  { href: '/asistencia', texto: 'Mi asistencia', icono: CalendarDays },
  { href: '/permisos', texto: 'Mis permisos', icono: FileText },
  { href: '/pagos', texto: 'Mis pagos', icono: Wallet },
  { href: '/asistente', texto: 'Asistente IA', icono: Bot },
  { href: '/configuracion', texto: 'Configuración', icono: Settings },
];

export function Estructura({ children }: { children: React.ReactNode }) {
  const yo = useYo();
  const ruta = usePathname();
  const menu = yo.esAdmin ? MENU_ADMIN : MENU_TRABAJADOR;
  const fotosPerfil = useFotos([yo.foto_perfil_url], 'fotos_perfil');
  const fotosRostro = useFotos([yo.foto_perfil_url ? null : yo.foto_rostro_url]);
  const miFoto = yo.foto_perfil_url ? fotosPerfil[yo.foto_perfil_url] : yo.foto_rostro_url ? fotosRostro[yo.foto_rostro_url] : null;
  const activo = (href: string) => ruta === href || ruta.startsWith(href + '/');

  return (
    <div className="min-h-dvh lg:grid lg:grid-cols-[224px_minmax(0,1fr)]">
      {/* Barra lateral (escritorio) */}
      <aside className="sticky top-0 hidden h-dvh flex-col gap-6 bg-lateral px-3 py-5 text-lateral-tinta lg:flex">
        <div className="flex flex-col items-center gap-1 px-2">
          <Image src="/logo-chahua.png" alt="Motorrepuestos Chahua" width={128} height={126} priority />
        </div>
        <nav className="flex flex-col gap-0.5" aria-label="Menú principal">
          {menu.map(({ href, texto, icono: Icono }) => (
            <Link
              key={href}
              href={href}
              aria-current={activo(href) ? 'page' : undefined}
              className={`flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-[13px] font-medium transition ${
                activo(href) ? 'bg-white/10 text-lateral-tinta' : 'text-lateral-tenue hover:text-lateral-tinta'
              }`}
            >
              <Icono className={`size-[17px] ${activo(href) ? 'text-acento' : ''}`} />
              {texto}
            </Link>
          ))}
        </nav>
        <div className="mt-auto flex flex-col gap-2 border-t border-white/10 pt-4">
          <Link href="/configuracion" className="flex items-center gap-2.5 rounded-lg px-2 py-1 hover:bg-white/5" title="Mi perfil y configuración">
            <Avatar persona={yo} url={miFoto} />
            <div className="min-w-0">
              <p className="truncate text-[13px] font-semibold">{nombreCorto(yo)}</p>
              <p className="truncate text-[11px] text-lateral-tenue">{yo.esAdmin ? 'Administrador · acceso total' : yo.cargo}</p>
            </div>
          </Link>
          <BotonSalir className="text-lateral-tenue hover:bg-white/10 hover:text-lateral-tinta" />
        </div>
      </aside>

      {/* Barra superior (móvil y tablet) */}
      <header className="sticky top-0 z-30 bg-lateral text-lateral-tinta lg:hidden">
        <div className="flex items-center justify-between px-4 pt-3">
          <div className="flex items-center gap-2">
            <Image src="/logo-chahua.png" alt="" width={36} height={36} priority />
            <p className="titulo-display text-2xl tracking-wider">
              CHA<span className="text-acento">HUA</span>
            </p>
          </div>
          <div className="flex items-center gap-2">
            <span className="rounded-md bg-acento-suave px-2 py-1 font-mono text-[10px] text-acento uppercase">{yo.esAdmin ? 'Admin' : 'Personal'}</span>
            <Link href="/configuracion" aria-label="Mi perfil y configuración">
              <Avatar persona={yo} url={miFoto} tam={30} />
            </Link>
            <BotonSalir compacto className="text-lateral-tenue" />
          </div>
        </div>
        <nav className="flex gap-1 overflow-x-auto px-3 pt-2 pb-2" aria-label="Menú principal">
          {menu.map(({ href, texto, icono: Icono }) => (
            <Link
              key={href}
              href={href}
              aria-current={activo(href) ? 'page' : undefined}
              className={`flex shrink-0 items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-medium ${
                activo(href) ? 'bg-white/10 text-lateral-tinta' : 'text-lateral-tenue'
              }`}
            >
              <Icono className={`size-4 ${activo(href) ? 'text-acento' : ''}`} />
              {texto}
            </Link>
          ))}
        </nav>
      </header>

      <main className="mx-auto flex w-full max-w-6xl min-w-0 flex-col gap-5 px-4 py-6 sm:px-6 lg:px-8">{children}</main>
    </div>
  );
}
