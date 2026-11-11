'use client';
import { LogOut } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { supabaseNavegador } from '@/lib/supabase/navegador';

export function BotonSalir({ compacto = false, className = '' }: { compacto?: boolean; className?: string }) {
  const router = useRouter();
  const [saliendo, setSaliendo] = useState(false);

  async function salir() {
    setSaliendo(true);
    await supabaseNavegador().auth.signOut();
    router.replace('/login');
    router.refresh();
  }

  return (
    <button
      type="button"
      onClick={salir}
      disabled={saliendo}
      aria-label="Cerrar sesión"
      className={`inline-flex items-center gap-2 rounded-lg px-2.5 py-2 text-[13px] font-medium disabled:opacity-60 ${className}`}
    >
      <LogOut className="size-4" />
      {!compacto && (saliendo ? 'Saliendo…' : 'Cerrar sesión')}
    </button>
  );
}
