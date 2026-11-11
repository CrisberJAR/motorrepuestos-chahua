'use client';
import { Camera, KeyRound, Pencil, Plus, Search, UserCheck, UserX } from 'lucide-react';
import { useState } from 'react';
import { useAvisos } from '@/components/avisos';
import { CapturaFoto } from '@/components/captura-foto';
import { useYo } from '@/components/sesion';
import { Avatar, Boton, Campo, Cargando, Chip, claseInput, Encabezado, MensajeError, Modal, Tarjeta, Vacio } from '@/components/ui';
import { soles } from '@/lib/fechas';
import { llamarApi, useConsulta, useFotos } from '@/lib/hooks';
import { supabaseNavegador } from '@/lib/supabase/navegador';
import { AREAS, type Personal } from '@/lib/tipos';

type Dialogo = { tipo: 'nuevo' } | { tipo: 'editar' | 'foto' | 'clave'; persona: Personal } | null;

export default function PaginaPersonal() {
  const yo = useYo();
  const { avisar } = useAvisos();
  const [busqueda, setBusqueda] = useState('');
  const [verInactivos, setVerInactivos] = useState(false);
  const [dialogo, setDialogo] = useState<Dialogo>(null);
  const [cambiando, setCambiando] = useState<string | null>(null);

  const { datos, error, cargando, recargar } = useConsulta(
    async () => {
      const { data, error: e } = await supabaseNavegador()
        .from('personal')
        .select('id, user_id, dni, nombres, apellidos, cargo, area, telefono, correo, sueldo_base, pago_por_dia, tipo_pago, hora_entrada, hora_salida, tolerancia_min, foto_rostro_url, rol, estado, fecha_ingreso')
        .order('rol')
        .order('apellidos');
      if (e) throw new Error(e.message);
      return (data || []) as Personal[];
    },
    [],
    ['personal'],
  );
  const fotos = useFotos(datos?.map((p) => p.foto_rostro_url) || []);

  if (!yo.esAdmin) {
    return <Vacio titulo="Solo el administrador puede ver esta sección" />;
  }

  const texto = busqueda.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const lista = (datos || []).filter(
    (p) =>
      (verInactivos || p.estado === 'activo') &&
      (!texto || `${p.nombres} ${p.apellidos} ${p.dni} ${p.cargo}`.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().includes(texto)),
  );
  const activos = datos?.filter((p) => p.estado === 'activo').length || 0;
  const sinRostro = datos?.filter((p) => p.estado === 'activo' && !p.foto_rostro_url).length || 0;

  async function cambiarEstado(p: Personal) {
    const nuevo = p.estado === 'activo' ? 'inactivo' : 'activo';
    setCambiando(p.id);
    const { error: e } = await supabaseNavegador().from('personal').update({ estado: nuevo }).eq('id', p.id);
    setCambiando(null);
    if (e) return avisar(`No se pudo cambiar el estado: ${e.message}`, 'error');
    avisar(nuevo === 'activo' ? `${p.nombres} fue reactivado.` : `${p.nombres} quedó inactivo: ya no podrá ingresar ni marcar asistencia.`);
    recargar();
  }

  return (
    <>
      <Encabezado
        titulo="Personal"
        subtitulo={`${activos} trabajadores activos${sinRostro ? ` · ${sinRostro} sin rostro registrado (no podrán marcar asistencia)` : ''}`}
        acciones={
          <Boton icono={<Plus className="size-4" />} onClick={() => setDialogo({ tipo: 'nuevo' })}>
            Nuevo trabajador
          </Boton>
        }
      />

      <div className="flex flex-wrap items-center gap-3">
        <label className="relative min-w-0 flex-1 sm:max-w-xs">
          <Search className="pointer-events-none absolute top-2.5 left-3 size-4 text-tenue" />
          <input
            id="buscar-personal"
            className={`${claseInput} pl-9`}
            placeholder="Buscar por nombre, DNI o cargo"
            value={busqueda}
            onChange={(e) => setBusqueda(e.target.value)}
            aria-label="Buscar trabajador"
          />
        </label>
        <label className="inline-flex items-center gap-2 text-[13px] text-tenue">
          <input type="checkbox" className="size-4" checked={verInactivos} onChange={(e) => setVerInactivos(e.target.checked)} />
          Mostrar inactivos
        </label>
      </div>

      {cargando && !datos ? (
        <Cargando />
      ) : error && !datos ? (
        <MensajeError texto={error} onReintentar={recargar} />
      ) : !lista.length ? (
        <Vacio titulo="No hay trabajadores que coincidan" />
      ) : (
        <Tarjeta>
          <ul>
            {lista.map((p) => (
              <li key={p.id} className="flex flex-wrap items-center gap-3 border-t border-linea py-3 first:border-t-0 first:pt-0 last:pb-0">
                <Avatar persona={p} url={p.foto_rostro_url ? fotos[p.foto_rostro_url] : undefined} tam={44} />
                <div className="min-w-[200px] flex-1">
                  <p className="font-semibold">
                    {p.nombres} {p.apellidos}
                    {p.rol === 'admin' && <Chip clase="ml-2 bg-acento-suave text-acento">Administrador</Chip>}
                    {p.estado === 'inactivo' && <Chip clase="ml-2 bg-hundido text-tenue">Inactivo</Chip>}
                  </p>
                  <p className="text-xs text-tenue">
                    DNI {p.dni} · {p.cargo} · {p.area} · entrada {p.hora_entrada.slice(0, 5)} (+{p.tolerancia_min} min)
                  </p>
                </div>
                <span className="cifras font-mono text-xs">{p.tipo_pago === 'variable' ? `Rendimiento · ref. ${soles(Number(p.pago_por_dia))}` : `${soles(Number(p.pago_por_dia))}/día`}</span>
                {p.foto_rostro_url ? <Chip clase="bg-ok-suave text-ok">Rostro registrado</Chip> : <Chip clase="bg-alerta-suave text-alerta">Sin rostro</Chip>}
                <div className="flex flex-wrap gap-1">
                  <Boton variante="fantasma" tam="sm" icono={<Pencil className="size-3.5" />} onClick={() => setDialogo({ tipo: 'editar', persona: p })}>
                    Editar
                  </Boton>
                  <Boton variante="fantasma" tam="sm" icono={<Camera className="size-3.5" />} onClick={() => setDialogo({ tipo: 'foto', persona: p })}>
                    Foto
                  </Boton>
                  <Boton variante="fantasma" tam="sm" icono={<KeyRound className="size-3.5" />} onClick={() => setDialogo({ tipo: 'clave', persona: p })}>
                    Contraseña
                  </Boton>
                  {p.id !== yo.id && (
                    <Boton
                      variante="fantasma"
                      tam="sm"
                      cargando={cambiando === p.id}
                      icono={p.estado === 'activo' ? <UserX className="size-3.5" /> : <UserCheck className="size-3.5" />}
                      onClick={() => cambiarEstado(p)}
                    >
                      {p.estado === 'activo' ? 'Desactivar' : 'Activar'}
                    </Boton>
                  )}
                </div>
              </li>
            ))}
          </ul>
        </Tarjeta>
      )}

      <Modal abierto={dialogo?.tipo === 'nuevo'} titulo="Nuevo trabajador" onCerrar={() => setDialogo(null)} ancho="max-w-2xl">
        <FormularioNuevo onListo={() => { setDialogo(null); recargar(); }} />
      </Modal>
      {dialogo && dialogo.tipo !== 'nuevo' && (
        <>
          <Modal abierto={dialogo.tipo === 'editar'} titulo={`Editar · ${dialogo.persona.nombres}`} onCerrar={() => setDialogo(null)} ancho="max-w-2xl">
            <FormularioEditar persona={dialogo.persona} onListo={() => { setDialogo(null); recargar(); }} />
          </Modal>
          <Modal abierto={dialogo.tipo === 'foto'} titulo={`Rostro · ${dialogo.persona.nombres}`} onCerrar={() => setDialogo(null)}>
            <FormularioFoto persona={dialogo.persona} onListo={() => { setDialogo(null); recargar(); }} />
          </Modal>
          <Modal abierto={dialogo.tipo === 'clave'} titulo="Cambiar contraseña" onCerrar={() => setDialogo(null)} ancho="max-w-md">
            <FormularioClave persona={dialogo.persona} propia={dialogo.persona.id === yo.id} onListo={() => setDialogo(null)} />
          </Modal>
        </>
      )}
    </>
  );
}

/* ---------- Nuevo trabajador ---------- */
function FormularioNuevo({ onListo }: { onListo: () => void }) {
  const { avisar } = useAvisos();
  const [d, setD] = useState({ dni: '', nombres: '', apellidos: '', cargo: '', area: 'Ventas', telefono: '', correo: '', pago_por_dia: '55', tipo_pago: 'fijo', hora_entrada: '08:00', tolerancia_min: '10' });
  const [foto, setFoto] = useState<Blob | null>(null);
  const [error, setError] = useState('');
  const [guardando, setGuardando] = useState(false);
  const cambiar = (k: keyof typeof d) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setD({ ...d, [k]: e.target.value });

  async function guardar(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (!/^\d{8}$/.test(d.dni)) return setError('El DNI debe tener 8 dígitos.');
    if (!d.nombres.trim() || !d.apellidos.trim()) return setError('Completa nombres y apellidos.');
    if (!d.cargo.trim()) return setError('Indica el cargo.');
    if (!(Number(d.pago_por_dia) > 0)) return setError('El pago por día debe ser mayor que 0.');
    if (!foto) return setError('Falta la foto del rostro: sin ella no se le puede reconocer al marcar asistencia.');

    const form = new FormData();
    Object.entries(d).forEach(([k, v]) => form.append(k, v.trim()));
    form.append('imagen', foto, 'rostro.jpg');
    setGuardando(true);
    try {
      const r = await llamarApi<{ mensaje: string }>('/api/admin/personal', form);
      avisar(r.mensaje);
      onListo();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo registrar.');
    } finally {
      setGuardando(false);
    }
  }

  return (
    <form onSubmit={guardar} className="grid gap-5 md:grid-cols-[minmax(0,1fr)_260px]" noValidate>
      <div className="grid content-start gap-3 sm:grid-cols-2">
        <Campo etiqueta="DNI">
          <input id="nuevo-dni" className={claseInput} inputMode="numeric" maxLength={8} value={d.dni} onChange={(e) => setD({ ...d, dni: e.target.value.replace(/\D/g, '') })} />
        </Campo>
        <Campo etiqueta="Teléfono">
          <input id="nuevo-telefono" className={claseInput} inputMode="tel" maxLength={15} value={d.telefono} onChange={cambiar('telefono')} />
        </Campo>
        <Campo etiqueta="Nombres">
          <input id="nuevo-nombres" className={claseInput} value={d.nombres} onChange={cambiar('nombres')} />
        </Campo>
        <Campo etiqueta="Apellidos">
          <input id="nuevo-apellidos" className={claseInput} value={d.apellidos} onChange={cambiar('apellidos')} />
        </Campo>
        <Campo etiqueta="Cargo">
          <input id="nuevo-cargo" className={claseInput} placeholder="Vendedor de Repuestos" value={d.cargo} onChange={cambiar('cargo')} />
        </Campo>
        <Campo etiqueta="Área">
          <select id="nuevo-area" className={claseInput} value={d.area} onChange={cambiar('area')}>
            {AREAS.map((a) => (
              <option key={a}>{a}</option>
            ))}
          </select>
        </Campo>
        <Campo etiqueta="Tipo de pago" ayuda={d.tipo_pago === 'variable' ? 'El monto de cada día se registra al pagar, según su rendimiento. El pago por día sirve de referencia.' : 'Gana el mismo monto cada día asistido.'}>
          <select id="nuevo-tipo-pago" className={claseInput} value={d.tipo_pago} onChange={cambiar('tipo_pago')}>
            <option value="fijo">Fijo por día</option>
            <option value="variable">Por rendimiento (variable)</option>
          </select>
        </Campo>
        <Campo etiqueta={d.tipo_pago === 'variable' ? 'Pago de referencia por día (S/)' : 'Pago por día (S/)'}>
          <input id="nuevo-pago" className={claseInput} type="number" min="1" step="0.5" value={d.pago_por_dia} onChange={cambiar('pago_por_dia')} />
        </Campo>
        <Campo etiqueta="Correo (opcional)">
          <input id="nuevo-correo" className={claseInput} type="email" value={d.correo} onChange={cambiar('correo')} />
        </Campo>
        <Campo etiqueta="Hora de entrada">
          <input id="nuevo-entrada" className={claseInput} type="time" value={d.hora_entrada} onChange={cambiar('hora_entrada')} />
        </Campo>
        <Campo etiqueta="Tolerancia (min)">
          <input id="nuevo-tolerancia" className={claseInput} type="number" min="0" max="60" value={d.tolerancia_min} onChange={cambiar('tolerancia_min')} />
        </Campo>
        <p className="text-xs text-tenue sm:col-span-2">Su usuario y contraseña inicial serán su DNI.</p>
      </div>
      <div className="flex flex-col gap-2">
        <span className="text-[11px] tracking-wide text-tenue uppercase">Foto oficial del rostro</span>
        <CapturaFoto foto={foto} onCambio={setFoto} />
      </div>
      {error && <p role="alert" className="rounded-lg bg-peligro-suave px-3 py-2 text-[13px] text-peligro md:col-span-2">{error}</p>}
      <div className="flex justify-end md:col-span-2">
        <Boton type="submit" cargando={guardando}>
          {guardando ? 'Analizando rostro…' : 'Registrar trabajador'}
        </Boton>
      </div>
    </form>
  );
}

/* ---------- Editar datos ---------- */
function FormularioEditar({ persona, onListo }: { persona: Personal; onListo: () => void }) {
  const { avisar } = useAvisos();
  const [d, setD] = useState({
    nombres: persona.nombres,
    apellidos: persona.apellidos,
    cargo: persona.cargo,
    area: persona.area,
    telefono: persona.telefono || '',
    correo: persona.correo || '',
    pago_por_dia: String(persona.pago_por_dia),
    tipo_pago: persona.tipo_pago || 'fijo',
    hora_entrada: persona.hora_entrada.slice(0, 5),
    tolerancia_min: String(persona.tolerancia_min),
  });
  const [error, setError] = useState('');
  const [guardando, setGuardando] = useState(false);
  const cambiar = (k: keyof typeof d) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setD({ ...d, [k]: e.target.value });

  async function guardar(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    const pago = Number(d.pago_por_dia);
    const tolerancia = Number(d.tolerancia_min);
    if (!d.nombres.trim() || !d.apellidos.trim() || !d.cargo.trim()) return setError('Nombres, apellidos y cargo son obligatorios.');
    if (!(pago > 0)) return setError('El pago por día debe ser mayor que 0.');
    if (!Number.isInteger(tolerancia) || tolerancia < 0 || tolerancia > 60) return setError('La tolerancia debe estar entre 0 y 60 minutos.');
    setGuardando(true);
    const { error: err } = await supabaseNavegador()
      .from('personal')
      .update({
        nombres: d.nombres.trim(),
        apellidos: d.apellidos.trim(),
        cargo: d.cargo.trim(),
        area: d.area,
        telefono: d.telefono.trim() || null,
        correo: d.correo.trim() || null,
        pago_por_dia: pago,
        tipo_pago: d.tipo_pago,
        sueldo_base: Math.round(pago * 26 * 100) / 100,
        hora_entrada: `${d.hora_entrada}:00`,
        tolerancia_min: tolerancia,
      })
      .eq('id', persona.id);
    setGuardando(false);
    if (err) return setError(`No se pudo guardar: ${err.message}`);
    avisar('Datos actualizados. Lo pendiente de pago ya usa los nuevos valores.');
    onListo();
  }

  return (
    <form onSubmit={guardar} className="grid gap-3 sm:grid-cols-2" noValidate>
      <Campo etiqueta="Nombres"><input id="editar-nombres" className={claseInput} value={d.nombres} onChange={cambiar('nombres')} /></Campo>
      <Campo etiqueta="Apellidos"><input id="editar-apellidos" className={claseInput} value={d.apellidos} onChange={cambiar('apellidos')} /></Campo>
      <Campo etiqueta="Cargo"><input id="editar-cargo" className={claseInput} value={d.cargo} onChange={cambiar('cargo')} /></Campo>
      <Campo etiqueta="Área">
        <select id="editar-area" className={claseInput} value={d.area} onChange={cambiar('area')}>
          {AREAS.map((a) => <option key={a}>{a}</option>)}
        </select>
      </Campo>
      <Campo etiqueta="Teléfono"><input id="editar-telefono" className={claseInput} value={d.telefono} onChange={cambiar('telefono')} /></Campo>
      <Campo etiqueta="Correo"><input id="editar-correo" className={claseInput} type="email" value={d.correo} onChange={cambiar('correo')} /></Campo>
      <Campo etiqueta="Tipo de pago" ayuda={d.tipo_pago === 'variable' ? 'El monto de cada día se registra al pagar, según su rendimiento. El pago por día sirve de referencia.' : 'Gana el mismo monto cada día asistido.'}>
        <select id="editar-tipo-pago" className={claseInput} value={d.tipo_pago} onChange={cambiar('tipo_pago')}>
          <option value="fijo">Fijo por día</option>
          <option value="variable">Por rendimiento (variable)</option>
        </select>
      </Campo>
      <Campo etiqueta={d.tipo_pago === 'variable' ? 'Pago de referencia por día (S/)' : 'Pago por día (S/)'}><input id="editar-pago" className={claseInput} type="number" min="1" step="0.5" value={d.pago_por_dia} onChange={cambiar('pago_por_dia')} /></Campo>
      <Campo etiqueta="Hora de entrada"><input id="editar-entrada" className={claseInput} type="time" value={d.hora_entrada} onChange={cambiar('hora_entrada')} /></Campo>
      <Campo etiqueta="Tolerancia (min)"><input id="editar-tolerancia" className={claseInput} type="number" min="0" max="60" value={d.tolerancia_min} onChange={cambiar('tolerancia_min')} /></Campo>
      <Campo etiqueta="DNI"><input id="editar-dni" className={claseInput} value={persona.dni} disabled /></Campo>
      {error && <p role="alert" className="rounded-lg bg-peligro-suave px-3 py-2 text-[13px] text-peligro sm:col-span-2">{error}</p>}
      <div className="flex justify-end sm:col-span-2">
        <Boton type="submit" cargando={guardando}>Guardar cambios</Boton>
      </div>
    </form>
  );
}

/* ---------- Foto del rostro ---------- */
function FormularioFoto({ persona, onListo }: { persona: Personal; onListo: () => void }) {
  const { avisar } = useAvisos();
  const [foto, setFoto] = useState<Blob | null>(null);
  const [error, setError] = useState('');
  const [guardando, setGuardando] = useState(false);

  async function guardar() {
    if (!foto) return setError('Toma o sube una foto primero.');
    setError('');
    const form = new FormData();
    form.append('personal_id', persona.id);
    form.append('imagen', foto, 'rostro.jpg');
    setGuardando(true);
    try {
      const r = await llamarApi<{ mensaje: string }>('/api/ia/registrar-rostro', form);
      avisar(r.mensaje);
      onListo();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo guardar la foto.');
    } finally {
      setGuardando(false);
    }
  }

  return (
    <div className="flex flex-col gap-3">
      <p className="text-[13px] text-tenue">
        {persona.foto_rostro_url ? 'La nueva foto reemplazará a la actual como base del reconocimiento facial.' : 'Sin esta foto no podrá marcar asistencia con su rostro.'}
      </p>
      <CapturaFoto foto={foto} onCambio={setFoto} />
      {error && <p role="alert" className="rounded-lg bg-peligro-suave px-3 py-2 text-[13px] text-peligro">{error}</p>}
      <div className="flex justify-end">
        <Boton cargando={guardando} disabled={!foto} onClick={guardar}>
          {guardando ? 'Analizando rostro…' : 'Guardar foto'}
        </Boton>
      </div>
    </div>
  );
}

/* ---------- Contraseña ---------- */
function FormularioClave({ persona, propia, onListo }: { persona: Personal; propia: boolean; onListo: () => void }) {
  const { avisar } = useAvisos();
  const [clave, setClave] = useState('');
  const [confirmar, setConfirmar] = useState('');
  const [error, setError] = useState('');
  const [guardando, setGuardando] = useState(false);

  async function guardar(nueva: string) {
    setError('');
    if (nueva.length < 6) return setError('La contraseña debe tener al menos 6 caracteres.');
    if (nueva !== persona.dni && nueva !== confirmar) return setError('Las contraseñas no coinciden.');
    setGuardando(true);
    try {
      const r = await llamarApi<{ mensaje: string }>('/api/admin/cambiar-clave', { personal_id: persona.id, nueva_clave: nueva });
      avisar(r.mensaje);
      onListo();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo cambiar la contraseña.');
    } finally {
      setGuardando(false);
    }
  }

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        guardar(clave);
      }}
      className="flex flex-col gap-3"
      noValidate
    >
      <p className="text-[13px]">
        {propia ? 'Tu cuenta' : `${persona.nombres} ${persona.apellidos}`} · usuario <span className="font-mono">{persona.dni}</span>
      </p>
      <Campo etiqueta="Nueva contraseña">
        <input id="clave-nueva" className={claseInput} type="password" autoComplete="new-password" value={clave} onChange={(e) => setClave(e.target.value)} />
      </Campo>
      <Campo etiqueta="Repite la contraseña">
        <input id="clave-confirmar" className={claseInput} type="password" autoComplete="new-password" value={confirmar} onChange={(e) => setConfirmar(e.target.value)} />
      </Campo>
      {error && <p role="alert" className="rounded-lg bg-peligro-suave px-3 py-2 text-[13px] text-peligro">{error}</p>}
      <div className="flex flex-wrap justify-between gap-2">
        <Boton variante="secundario" disabled={guardando} onClick={() => guardar(persona.dni)}>
          Restablecer al DNI
        </Boton>
        <Boton type="submit" cargando={guardando}>Cambiar contraseña</Boton>
      </div>
    </form>
  );
}
