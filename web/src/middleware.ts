import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

/**
 * Refresca la sesión de Supabase en cada visita y protege las páginas:
 * sin sesión → /login ; con sesión en /login → /panel.
 * Las rutas /api hacen su propia verificación (aceptan también Bearer token de la app móvil).
 */
export async function middleware(req: NextRequest) {
  let respuesta = NextResponse.next({ request: req });

  const sb = createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    cookies: {
      getAll: () => req.cookies.getAll(),
      setAll: (lista) => {
        lista.forEach(({ name, value }) => req.cookies.set(name, value));
        respuesta = NextResponse.next({ request: req });
        lista.forEach(({ name, value, options }) => respuesta.cookies.set(name, value, options));
      },
    },
  });

  const {
    data: { user },
  } = await sb.auth.getUser();

  const ruta = req.nextUrl.pathname;
  if (ruta.startsWith('/api')) return respuesta;

  if (!user && ruta !== '/login') {
    const destino = req.nextUrl.clone();
    destino.pathname = '/login';
    destino.search = '';
    return NextResponse.redirect(destino);
  }
  if (user && ruta === '/login') {
    const destino = req.nextUrl.clone();
    destino.pathname = '/panel';
    return NextResponse.redirect(destino);
  }
  return respuesta;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)'],
};
