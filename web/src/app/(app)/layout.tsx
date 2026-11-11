import { redirect } from 'next/navigation';
import { Estructura } from '@/components/estructura';
import { ProveedorSesion } from '@/components/sesion';
import { BotonSalir } from '@/components/boton-salir';
import { supabaseServidor } from '@/lib/supabase/server';
import type { Yo } from '@/lib/tipos';

export const dynamic = 'force-dynamic';

export default async function LayoutApp({ children }: { children: React.ReactNode }) {
  const sb = await supabaseServidor();
  const {
    data: { user },
  } = await sb.auth.getUser();
  if (!user) redirect('/login');

  const { data: yo } = await sb
    .from('personal')
    .select('id, dni, nombres, apellidos, cargo, area, rol, estado, pago_por_dia, foto_rostro_url')
    .eq('user_id', user.id)
    .maybeSingle();

  if (!yo || yo.estado !== 'activo') {
    return (
      <main className="grid min-h-dvh place-items-center px-4">
        <div className="max-w-sm space-y-3 text-center">
          <h1 className="titulo-display text-3xl">Cuenta no habilitada</h1>
          <p className="text-tenue">
            {yo ? 'Tu cuenta está inactiva.' : 'Tu usuario no está vinculado a ningún trabajador.'} Comunícate con el administrador de Motorrepuestos Chahua.
          </p>
          <BotonSalir />
        </div>
      </main>
    );
  }

  const { estado: _estado, ...datos } = yo;
  void _estado;
  return (
    <ProveedorSesion yo={{ ...datos, pago_por_dia: Number(datos.pago_por_dia) } as Yo}>
      <Estructura>{children}</Estructura>
    </ProveedorSesion>
  );
}
