'use client';
import { Chat } from '@/components/chat';
import { useYo } from '@/components/sesion';
import { Encabezado } from '@/components/ui';

export default function PaginaAsistente() {
  const yo = useYo();
  return (
    <>
      <Encabezado
        titulo="Asistente IA"
        subtitulo={
          yo.esAdmin
            ? 'Consulta a cualquier trabajador por DNI o nombre, revisa el reglamento o registra permisos. Usa los datos en tiempo real.'
            : 'Pregunta por tus asistencias, faltas, pagos o permisos, o pide un permiso. Solo ve tu propia información.'
        }
      />
      <Chat />
    </>
  );
}
