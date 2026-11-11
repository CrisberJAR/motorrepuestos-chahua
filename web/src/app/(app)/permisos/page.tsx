'use client';
import { Plus } from 'lucide-react';
import { useState } from 'react';
import { useAvisos } from '@/components/avisos';
import { FilaPermiso } from '@/components/fila-permiso';
import { useYo } from '@/components/sesion';
import { Boton, Campo, Cargando, claseInput, Encabezado, MensajeError, Modal, Segmentado, Tarjeta, Vacio } from '@/components/ui';
import { crearPermiso } from '@/lib/acciones';
import { ahoraLima, diaSemana, sumarDias } from '@/lib/fechas';
import { useConsulta, useFotos } from '@/lib/hooks';
import { supabaseNavegador } from '@/lib/supabase/navegador';
import { ETIQUETA_TIPO, type EstadoPermiso, type Permiso, type TipoPermiso } from '@/lib/tipos';

type Filtro = 'todos' | EstadoPermiso;

export default function PaginaPermisos() {
  const yo = useYo();
  const [filtro, setFiltro] = useState<Filtro>('todos');
  const [formulario, setFormulario] = useState(false);

  const { datos, error, cargando, recargar } = useConsulta(
    async () => {
      const sb = supabaseNavegador();
      let consulta = sb
        .from('permisos')
        .select('*, personal:personal_id(id, dni, nombres, apellidos, foto_rostro_url)')
        .order('created_at', { ascending: false })
        .limit(300);
      if (!yo.esAdmin) consulta = consulta.eq('personal_id', yo.id);
      const [permisos, personal] = await Promise.all([
        consulta,
        yo.esAdmin ? sb.from('personal').select('id, dni, nombres, apellidos').eq('estado', 'activo').order('apellidos') : Promise.resolve({ data: [] }),
      ]);
      if (permisos.error) throw new Error(permisos.error.message);
      return { permisos: (permisos.data || []) as Permiso[], personal: (personal.data || []) as { id: string; dni: string; nombres: string; apellidos: string }[] };
    },
    [yo.id],
    ['permisos'],
  );

  const fotos = useFotos(datos?.permisos.map((p) => p.personal?.foto_rostro_url) || []);
  const lista = (datos?.permisos || []).filter((p) => filtro === 'todos' || p.estado === filtro);
  const cuenta = (e: EstadoPermiso) => datos?.permisos.filter((p) => p.estado === e).length || 0;

  return (
    <>
      <Encabezado
        titulo={yo.esAdmin ? 'Gestión de permisos' : 'Mis permisos'}
        subtitulo={
          yo.esAdmin
            ? 'Incluye las solicitudes hechas desde la app, la web y el chatbot. Por defecto los días de permiso no se pagan.'
            : 'Tus solicitudes y su estado. El administrador las aprueba o rechaza.'
        }
        acciones={
          <Boton icono={<Plus className="size-4" />} onClick={() => setFormulario(true)}>
            {yo.esAdmin ? 'Registrar permiso' : 'Solicitar permiso'}
          </Boton>
        }
      />

      <div className="overflow-x-auto">
        <Segmentado<Filtro>
          etiqueta="Filtrar por estado"
          valor={filtro}
          onCambio={setFiltro}
          opciones={[
            ['todos', 'Todos'],
            ['pendiente', `Pendientes (${cuenta('pendiente')})`],
            ['aprobado', `Aprobados (${cuenta('aprobado')})`],
            ['rechazado', `Rechazados (${cuenta('rechazado')})`],
          ]}
        />
      </div>

      {cargando && !datos ? (
        <Cargando />
      ) : error && !datos ? (
        <MensajeError texto={error} onReintentar={recargar} />
      ) : lista.length ? (
        <Tarjeta>
          {lista.map((p) => (
            <FilaPermiso
              key={p.id}
              permiso={p}
              admin={yo.esAdmin}
              foto={p.personal?.foto_rostro_url ? fotos[p.personal.foto_rostro_url] : undefined}
              onCambio={recargar}
            />
          ))}
        </Tarjeta>
      ) : (
        <Vacio
          titulo={filtro === 'todos' ? 'Todavía no hay permisos' : 'No hay permisos en este filtro'}
          texto={yo.esAdmin ? 'Cuando alguien pida un permiso desde la app, la web o el chatbot, aparecerá aquí.' : 'Usa “Solicitar permiso” o pídeselo al asistente.'}
        />
      )}

      <Modal abierto={formulario} titulo={yo.esAdmin ? 'Registrar permiso' : 'Solicitar permiso'} onCerrar={() => setFormulario(false)}>
        <FormularioPermiso
          personal={datos?.personal || []}
          onListo={() => {
            setFormulario(false);
            recargar();
          }}
        />
      </Modal>
    </>
  );
}

function FormularioPermiso({ personal, onListo }: { personal: { id: string; dni: string; nombres: string; apellidos: string }[]; onListo: () => void }) {
  const yo = useYo();
  const { avisar } = useAvisos();
  const manana = sumarDias(ahoraLima().fecha, 1);
  const [trabajador, setTrabajador] = useState(personal[0]?.id || '');
  const [tipo, setTipo] = useState<TipoPermiso>('salud');
  const [inicio, setInicio] = useState(manana);
  const [fin, setFin] = useState(manana);
  const [motivo, setMotivo] = useState('');
  const [conGoce, setConGoce] = useState(false);
  const [error, setError] = useState('');
  const [guardando, setGuardando] = useState(false);

  async function guardar(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (yo.esAdmin && !trabajador) return setError('Elige al trabajador.');
    if (!inicio) return setError('Elige la fecha de inicio.');
    const hasta = fin || inicio;
    if (hasta < inicio) return setError('La fecha final no puede ser anterior a la inicial.');
    if (inicio === hasta && diaSemana(inicio) === 0) return setError('Ese día es domingo y no es laborable.');
    if (!motivo.trim()) return setError('Escribe el motivo.');

    setGuardando(true);
    try {
      await crearPermiso({
        personal_id: yo.esAdmin ? trabajador : yo.id,
        tipo_permiso: tipo,
        fecha_inicio: inicio,
        fecha_fin: hasta,
        motivo: motivo.trim(),
        estado: yo.esAdmin ? 'aprobado' : 'pendiente',
        origen: 'web',
        con_goce: yo.esAdmin ? conGoce : false,
      });
      avisar(yo.esAdmin ? 'Permiso registrado y aprobado.' : 'Solicitud enviada. El administrador la revisará.');
      onListo();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar.');
    } finally {
      setGuardando(false);
    }
  }

  return (
    <form onSubmit={guardar} className="grid gap-4 sm:grid-cols-2" noValidate>
      {yo.esAdmin && (
        <Campo etiqueta="Trabajador" ancho>
          <select id="permiso-trabajador" className={claseInput} value={trabajador} onChange={(e) => setTrabajador(e.target.value)}>
            {personal.map((p) => (
              <option key={p.id} value={p.id}>
                {p.nombres} {p.apellidos} · DNI {p.dni}
              </option>
            ))}
          </select>
        </Campo>
      )}
      <Campo etiqueta="Tipo de permiso" ancho>
        <select id="permiso-tipo" className={claseInput} value={tipo} onChange={(e) => setTipo(e.target.value as TipoPermiso)}>
          {Object.entries(ETIQUETA_TIPO).map(([v, t]) => (
            <option key={v} value={v}>{t}</option>
          ))}
        </select>
      </Campo>
      <Campo etiqueta="Desde">
        <input id="permiso-inicio" type="date" className={claseInput} value={inicio} onChange={(e) => { setInicio(e.target.value); if (fin < e.target.value) setFin(e.target.value); }} />
      </Campo>
      <Campo etiqueta="Hasta">
        <input id="permiso-fin" type="date" className={claseInput} value={fin} min={inicio} onChange={(e) => setFin(e.target.value)} />
      </Campo>
      <Campo etiqueta="Motivo" ancho>
        <textarea id="permiso-motivo" className={`${claseInput} min-h-20`} maxLength={300} placeholder="Ej.: cita médica en EsSalud" value={motivo} onChange={(e) => setMotivo(e.target.value)} />
      </Campo>
      {yo.esAdmin ? (
        <label className="flex items-center gap-2 text-[13px] sm:col-span-2">
          <input type="checkbox" className="size-4 accent-[var(--ok)]" checked={conGoce} onChange={(e) => setConGoce(e.target.checked)} />
          Pagar estos días (con goce). Por defecto los permisos no se pagan.
        </label>
      ) : (
        <p className="text-xs text-tenue sm:col-span-2">Quedará pendiente hasta que el administrador la apruebe. Por defecto los días de permiso no se pagan.</p>
      )}
      {error && <p role="alert" className="rounded-lg bg-peligro-suave px-3 py-2 text-[13px] text-peligro sm:col-span-2">{error}</p>}
      <div className="flex justify-end gap-2 sm:col-span-2">
        <Boton type="submit" cargando={guardando}>
          {yo.esAdmin ? 'Registrar permiso' : 'Enviar solicitud'}
        </Boton>
      </div>
    </form>
  );
}
