import 'server-only';
import { Type, type FunctionDeclaration } from '@google/genai';
import type { Sesion } from '@/lib/auth';
import { ahoraLima, diaSemana, esFechaIso, esPeriodo, fechaLarga, nombrePeriodo, periodoDe, rangoPeriodo, soles, sumarDias } from '@/lib/fechas';
import { supabaseAdmin } from '@/lib/supabase/admin';

export type Origen = 'web' | 'movil';
export type Contexto = { sesion: Sesion; origen: Origen };
type Resultado = Record<string, unknown>;

const TIPOS_PERMISO = ['salud', 'personal', 'urgencia', 'vacaciones'] as const;

/* ------------------------------------------------------------------ */
/* Declaraciones que recibe Gemini (Function Calling)                  */
/* ------------------------------------------------------------------ */
export const DECLARACIONES: FunctionDeclaration[] = [
  {
    name: 'consultar_estado_personal',
    description:
      'Consulta en tiempo real los datos de un trabajador de Motorrepuestos Chahua: asistencias, tardanzas, faltas y permisos del mes ' +
      '(con las fechas exactas), lo que se le debe desde su último pago (saldo por cobrar), los pagos que ya recibió (fecha, periodo, monto y método) ' +
      'y el estado de sus solicitudes de permiso. ' +
      'Úsala SIEMPRE antes de responder cualquier pregunta sobre datos de una persona. Busca por DNI o por nombre.',
    parameters: {
      type: Type.OBJECT,
      properties: {
        dni: { type: Type.STRING, description: 'DNI peruano de 8 dígitos del trabajador.' },
        nombre: { type: Type.STRING, description: 'Nombre y/o apellido del trabajador, si no se conoce el DNI.' },
        periodo: { type: Type.STRING, description: 'Mes a consultar en formato AAAA-MM. Si no se indica, el mes actual.' },
      },
    },
  },
  {
    name: 'registrar_permiso_chat',
    description:
      'Registra una solicitud de permiso en la tabla permisos. Úsala cuando la persona pida un permiso y ya tengas el tipo, la fecha y el motivo. ' +
      'Convierte fechas relativas ("mañana", "el viernes") a AAAA-MM-DD usando la fecha de hoy. Los domingos no son laborables.',
    parameters: {
      type: Type.OBJECT,
      properties: {
        dni: { type: Type.STRING, description: 'DNI de 8 dígitos del trabajador que pide el permiso.' },
        tipo_permiso: {
          type: Type.STRING,
          enum: [...TIPOS_PERMISO],
          description: 'salud (citas o descansos médicos), personal (trámites o asuntos personales), urgencia (imprevistos graves) o vacaciones.',
        },
        fecha_inicio: { type: Type.STRING, description: 'Primer día del permiso, AAAA-MM-DD.' },
        fecha_fin: { type: Type.STRING, description: 'Último día del permiso, AAAA-MM-DD. Si es un solo día, igual a fecha_inicio.' },
        motivo: { type: Type.STRING, description: 'Motivo breve, con las palabras de la persona. Ej.: "Cita médica en EsSalud".' },
      },
      required: ['tipo_permiso', 'fecha_inicio', 'motivo'],
    },
  },
];

/* ------------------------------------------------------------------ */
/* Resolución del trabajador respetando el rol de quien pregunta       */
/* ------------------------------------------------------------------ */
type Trabajador = { id: string; dni: string; nombres: string; apellidos: string; cargo: string; area: string; pago_por_dia: number; tipo_pago: string; rol: string };

const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

async function resolverTrabajador(ctx: Contexto, dni?: string, nombre?: string): Promise<{ trabajador?: Trabajador; error?: string; opciones?: string[] }> {
  const sb = supabaseAdmin();
  const campos = 'id, dni, nombres, apellidos, cargo, area, pago_por_dia, tipo_pago, rol';
  const yo = ctx.sesion.personal;

  if (yo.rol !== 'admin') {
    if (dni && dni.trim() !== yo.dni) {
      return { error: 'Por privacidad, solo puedes consultar o pedir permisos con tu propio DNI. Para otra persona, consulta con el administrador.' };
    }
    if (!dni && nombre) {
      const n = normalizar(nombre);
      const propio = normalizar(`${yo.nombres} ${yo.apellidos}`);
      if (!n.split(/\s+/).every((p) => propio.includes(p))) {
        return { error: 'Por privacidad, solo puedes consultar tu propia información.' };
      }
    }
    const { data } = await sb.from('personal').select(campos).eq('id', yo.id).single();
    return { trabajador: data as Trabajador };
  }

  if (dni) {
    const limpio = dni.replace(/\D/g, '');
    if (!/^\d{8}$/.test(limpio)) return { error: `"${dni}" no es un DNI válido: debe tener 8 dígitos.` };
    const { data } = await sb.from('personal').select(campos).eq('dni', limpio).maybeSingle();
    if (!data) return { error: `No hay ningún trabajador registrado con DNI ${limpio}.` };
    return { trabajador: data as Trabajador };
  }

  if (nombre) {
    const { data } = await sb.from('personal').select(campos).eq('estado', 'activo');
    const palabras = normalizar(nombre).split(/\s+/).filter(Boolean);
    const coincidencias = ((data || []) as Trabajador[]).filter((t) => {
      const completo = normalizar(`${t.nombres} ${t.apellidos}`);
      return palabras.every((p) => completo.includes(p));
    });
    if (coincidencias.length === 1) return { trabajador: coincidencias[0] };
    if (coincidencias.length > 1) {
      return {
        error: 'Hay varias personas con ese nombre. Pide el DNI o el apellido completo.',
        opciones: coincidencias.map((t) => `${t.nombres} ${t.apellidos} (DNI ${t.dni})`),
      };
    }
    return { error: `No encontré a ningún trabajador activo llamado "${nombre}".` };
  }

  return { error: 'Falta indicar de qué trabajador se trata: pide su DNI o su nombre.' };
}

/* ------------------------------------------------------------------ */
/* Herramienta 1: consultar_estado_personal                            */
/* ------------------------------------------------------------------ */
type Dia = { fecha: string; estado: string; hora_entrada: string | null; hora_salida: string | null; permiso_con_goce: boolean };

async function consultarEstadoPersonal(args: Record<string, unknown>, ctx: Contexto): Promise<Resultado> {
  const { trabajador, error, opciones } = await resolverTrabajador(ctx, args.dni as string, args.nombre as string);
  if (!trabajador) return { encontrado: false, error, opciones };

  const hoy = ahoraLima().fecha;
  const periodo = esPeriodo(args.periodo) ? args.periodo : periodoDe(hoy);
  const { desde, hasta } = rangoPeriodo(periodo);
  const sb = supabaseAdmin();

  const [detalleR, pagosR, permisosR] = await Promise.all([
    sb.rpc('detalle_asistencia', { p_desde: desde, p_hasta: hasta, p_personal_id: trabajador.id }),
    sb.from('pagos').select('fecha_desde, fecha_hasta, dias_asistidos, dias_permiso_pagado, monto_base, descuentos, bonos, total_pagar, fecha_pago, metodo_pago, numero_operacion')
      .eq('personal_id', trabajador.id).order('fecha_hasta', { ascending: false }).limit(4),
    sb.from('permisos').select('tipo_permiso, fecha_inicio, fecha_fin, motivo, estado, con_goce, origen, created_at')
      .eq('personal_id', trabajador.id).order('created_at', { ascending: false }).limit(6),
  ]);
  if (detalleR.error) return { encontrado: true, error: `No se pudo leer la asistencia: ${detalleR.error.message}` };

  const dias = (detalleR.data || []) as Dia[];
  const transcurridos = dias.filter((d) => d.estado !== 'futuro');
  const fechas = (estado: string) => transcurridos.filter((d) => d.estado === estado).map((d) => d.fecha);
  const asistidos = transcurridos.filter((d) => d.estado === 'asistio' || d.estado === 'tardanza').length;
  const pagoPorDia = Number(trabajador.pago_por_dia);
  const hoyDia = dias.find((d) => d.fecha === hoy);
  // Saldo por cobrar en vivo: desde el día siguiente al último pago hasta hoy.
  const pendR = await sb.rpc('pagos_pendientes', { p_personal_id: trabajador.id });
  const pend = (pendR.data || [])[0] as
    | { desde: string; hasta: string; ultimo_pago_hasta: string | null; dias_asistidos: number; dias_permiso_pagado: number; dias_falta: number; dias_sin_monto: number; monto_pendiente: number; tipo_pago: string }
    | undefined;
  const metodo: Record<string, string> = { efectivo: 'Efectivo', yape: 'Yape', plin: 'Plin', transferencia: 'Transferencia', otro: 'Otro' };

  return {
    encontrado: true,
    trabajador: {
      nombre: `${trabajador.nombres} ${trabajador.apellidos}`,
      dni: trabajador.dni,
      cargo: trabajador.cargo,
      area: trabajador.area,
      tipo_de_pago: trabajador.tipo_pago === 'variable' ? 'por rendimiento (el monto de cada día lo registra el administrador)' : 'fijo por día',
      pago_por_dia: soles(pagoPorDia),
    },
    periodo: { codigo: periodo, nombre: nombrePeriodo(periodo), es_mes_actual: periodo === periodoDe(hoy), datos_hasta: hoy < hasta ? hoy : hasta },
    hoy: hoyDia
      ? { fecha: fechaLarga(hoy), estado: hoyDia.estado === 'pendiente' ? 'aún sin marcar entrada' : hoyDia.estado, entrada: hoyDia.hora_entrada, salida: hoyDia.hora_salida }
      : undefined,
    resumen_asistencia: {
      dias_asistidos: asistidos,
      tardanzas: fechas('tardanza').length,
      dias_permiso: fechas('permiso').length,
      dias_falta: fechas('falta').length,
    },
    fechas_tardanza: transcurridos.filter((d) => d.estado === 'tardanza').map((d) => `${fechaLarga(d.fecha, false)} (entrada ${d.hora_entrada?.slice(0, 5)})`),
    fechas_falta: fechas('falta').map((f) => fechaLarga(f, false)),
    fechas_permiso: transcurridos.filter((d) => d.estado === 'permiso').map((d) => `${fechaLarga(d.fecha, false)}${d.permiso_con_goce ? ' (con goce, se paga)' : ' (sin goce, no se paga)'}`),
    saldo_por_cobrar: pend
      ? {
          monto: soles(Number(pend.monto_pendiente)),
          desde: pend.desde <= pend.hasta ? fechaLarga(pend.desde) : null,
          hasta: fechaLarga(pend.hasta),
          dias_a_pagar: pend.dias_asistidos + pend.dias_permiso_pagado,
          faltas_en_ese_rango: pend.dias_falta,
          ultimo_pago_cubrio_hasta: pend.ultimo_pago_hasta ? fechaLarga(pend.ultimo_pago_hasta) : 'sin pagos registrados',
          nota:
            'Se puede pagar en cualquier momento (por semana, mes o días): el administrador registra el pago cuando el trabajador lo solicita. ' +
            (pend.dias_sin_monto ? `${pend.dias_sin_monto} día(s) aún sin monto de rendimiento, calculados con ${soles(pagoPorDia)} de referencia.` : ''),
        }
      : undefined,
    pagos_recibidos: (pagosR.data || []).map((p) => ({
      periodo: `${fechaLarga(p.fecha_desde)} al ${fechaLarga(p.fecha_hasta)}`,
      total: soles(Number(p.total_pagar)),
      dias_pagados: p.dias_asistidos + p.dias_permiso_pagado,
      bonos: soles(Number(p.bonos)),
      descuentos: soles(Number(p.descuentos)),
      fecha_pago: p.fecha_pago ? fechaLarga(p.fecha_pago) : null,
      metodo: metodo[p.metodo_pago] || p.metodo_pago,
      operacion: p.numero_operacion,
    })),
    permisos_recientes: (permisosR.data || []).map((p) => ({
      tipo: p.tipo_permiso,
      fechas: p.fecha_inicio === p.fecha_fin ? fechaLarga(p.fecha_inicio) : `${fechaLarga(p.fecha_inicio)} al ${fechaLarga(p.fecha_fin)}`,
      motivo: p.motivo,
      estado: p.estado,
      pagado: p.con_goce,
    })),
  };
}

/* ------------------------------------------------------------------ */
/* Herramienta 2: registrar_permiso_chat                               */
/* ------------------------------------------------------------------ */
async function registrarPermisoChat(args: Record<string, unknown>, ctx: Contexto): Promise<Resultado> {
  const esAdmin = ctx.sesion.personal.rol === 'admin';
  if (esAdmin && !args.dni) {
    return { registrado: false, error: 'Indica el DNI del trabajador para quien es el permiso.' };
  }
  const { trabajador, error } = await resolverTrabajador(ctx, args.dni as string);
  if (!trabajador) return { registrado: false, error };

  const tipo = String(args.tipo_permiso || '');
  const inicio = String(args.fecha_inicio || '');
  const fin = args.fecha_fin ? String(args.fecha_fin) : inicio;
  const motivo = String(args.motivo || '').trim().slice(0, 300);
  const hoy = ahoraLima().fecha;

  if (!TIPOS_PERMISO.includes(tipo as (typeof TIPOS_PERMISO)[number])) return { registrado: false, error: 'Tipo de permiso inválido: salud, personal, urgencia o vacaciones.' };
  if (!esFechaIso(inicio) || !esFechaIso(fin)) return { registrado: false, error: 'Las fechas deben tener el formato AAAA-MM-DD.' };
  if (fin < inicio) return { registrado: false, error: 'La fecha final no puede ser anterior a la inicial.' };
  if (inicio < sumarDias(hoy, -7)) return { registrado: false, error: 'No se pueden registrar permisos de hace más de 7 días. Consulta con el administrador.' };
  if (inicio > sumarDias(hoy, 365)) return { registrado: false, error: 'La fecha está a más de un año de distancia.' };
  if (inicio === fin && diaSemana(inicio) === 0) return { registrado: false, error: `El ${fechaLarga(inicio)} es domingo y no es día laborable.` };
  if (!motivo) return { registrado: false, error: 'Falta el motivo del permiso.' };

  const sb = supabaseAdmin();
  const { data: cruce } = await sb
    .from('permisos')
    .select('fecha_inicio, fecha_fin, estado')
    .eq('personal_id', trabajador.id)
    .in('estado', ['pendiente', 'aprobado'])
    .lte('fecha_inicio', fin)
    .gte('fecha_fin', inicio)
    .limit(1);
  if (cruce?.length) {
    const c = cruce[0];
    return { registrado: false, error: `Ya existe un permiso ${c.estado} del ${fechaLarga(c.fecha_inicio)} al ${fechaLarga(c.fecha_fin)} que se cruza con esas fechas.` };
  }

  const estado = esAdmin ? 'aprobado' : 'pendiente';
  const { data, error: errInsertar } = await sb
    .from('permisos')
    .insert({
      personal_id: trabajador.id,
      tipo_permiso: tipo,
      fecha_inicio: inicio,
      fecha_fin: fin,
      motivo,
      estado,
      origen: ctx.origen === 'movil' ? 'chatbot_movil' : 'chatbot_web',
      con_goce: false,
      revisado_por: esAdmin ? ctx.sesion.personal.id : null,
      fecha_revision: esAdmin ? new Date().toISOString() : null,
    })
    .select('id')
    .single();
  if (errInsertar) return { registrado: false, error: `No se pudo guardar: ${errInsertar.message}` };

  return {
    registrado: true,
    permiso_id: data.id,
    trabajador: `${trabajador.nombres} ${trabajador.apellidos} (DNI ${trabajador.dni})`,
    tipo,
    fechas: inicio === fin ? fechaLarga(inicio) : `${fechaLarga(inicio)} al ${fechaLarga(fin)}`,
    motivo,
    estado,
    aviso: esAdmin
      ? 'Registrado por el administrador: queda aprobado. Por defecto no se paga (sin goce); se puede cambiar en el módulo de Permisos.'
      : 'Queda pendiente hasta que el administrador lo apruebe o rechace. Por defecto los días de permiso no se pagan.',
  };
}

/* ------------------------------------------------------------------ */
export async function ejecutarHerramienta(nombre: string, args: Record<string, unknown>, ctx: Contexto): Promise<Resultado> {
  try {
    if (nombre === 'consultar_estado_personal') return await consultarEstadoPersonal(args, ctx);
    if (nombre === 'registrar_permiso_chat') return await registrarPermisoChat(args, ctx);
    return { error: `Herramienta desconocida: ${nombre}` };
  } catch (e) {
    console.error(`[chatbot] ${nombre}`, e);
    return { error: 'No se pudo completar la consulta en la base de datos.' };
  }
}
