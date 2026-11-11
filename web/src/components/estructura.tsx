'use client';
import { Bot, CalendarDays, FileText, LayoutDashboard, Users, Wallet } from 'lucide-react';
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
  { href: '/pagos', texto: 'Pagos y planilla', icono: Wallet },
  { href: '/personal', texto: 'Personal', icono: Users },
  { href: '/asistente', texto: 'Asistente IA', icono: Bot },
];

const MENU_TRABAJADOR = [
  { href: '/panel', texto: 'Mi resumen', icono: LayoutDashboard },
  { href: '/asistencia', texto: 'Mi asistencia', icono: CalendarDays },
  { href: '/permisos', texto: 'Mis permisos', icono: FileText },
  { href: '/pagos', texto: 'Mis pagos', icono: Wallet },
  { href: '/asistente', texto: 'Asistente IA', icono: Bot },
];

export function Estructura({ children }: { children: React.ReactNode }) {
  const yo = useYo();
  const ruta = usePathname();
  const menu = yo.esAdmin ? MENU_ADMIN : MENU_TRABAJADOR;
  const fotos = useFotos([yo.foto_rostro_url]);
  const activo = (href: string) => ruta === href || ruta.startsWith(href + '/');

  return (
    <div className="min-h-dvh lg:grid lg:grid-cols-[224px_minmax(0,1fr)]">
      {/* Barra lateral (escritorio) */}
      <aside className="sticky top-0 hidden h-dvh flex-col gap-6 bg-lateral px-3 py-5 text-lateral-tinta lg:flex">
        <div className="px-2">
          <p className="font-mono text-[10px] tracking-[0.12em] text-lateral-tenue uppercase">Motorrepuestos</p>
          <p className="titulo-display text-3xl tracking-wider">
            CHA<span className="text-acento">HUA</span>
          </p>
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
          <div className="flex items-center gap-2.5 px-2">
            <Avatar persona={yo} url={yo.foto_rostro_url ? fotos[yo.foto_rostro_url] : null} />
            <div className="min-w-0">
              <p className="truncate text-[13px] font-semibold">{nombreCorto(yo)}</p>
              <p className="truncate text-[11px] text-lateral-tenue">{yo.esAdmin ? 'Administrador · acceso total' : yo.cargo}</p>
            </div>
          </div>
          <BotonSalir className="text-lateral-tenue hover:bg-white/10 hover:text-lateral-tinta" />
        </div>
      </aside>

      {/* Barra superior (móvil y tablet) */}
      <header className="sticky top-0 z-30 bg-lateral text-lateral-tinta lg:hidden">
        <div className="flex items-center justify-between px-4 pt-3">
          <p className="titulo-display text-2xl tracking-wider">
            CHA<span className="text-acento">HUA</span>
          </p>
          <div className="flex items-center gap-2">
            <span className="rounded-md bg-acento-suave px-2 py-1 font-mono text-[10px] text-acento uppercase">{yo.esAdmin ? 'Admin' : 'Personal'}</span>
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
