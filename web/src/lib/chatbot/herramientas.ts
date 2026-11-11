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
      '(con las fechas exactas), sus pagos (montos y si ya se pagaron), el pago estimado del mes en curso y el estado de sus solicitudes de permiso. ' +
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
type Trabajador = { id: string; dni: string; nombres: string; apellidos: string; cargo: string; area: string; pago_por_dia: number; rol: string };

const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

async function resolverTrabajador(ctx: Contexto, dni?: string, nombre?: string): Promise<{ trabajador?: Trabajador; error?: string; opciones?: string[] }> {
  const sb = supabaseAdmin();
  const campos = 'id, dni, nombres, apellidos, cargo, area, pago_por_dia, rol';
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
    sb.from('pagos').select('periodo_mes, dias_asistidos, dias_permiso, dias_permiso_pagado, dias_falta, tardanzas_acumuladas, pago_por_dia, monto_base, descuentos, bonos, total_pagar, estado_pago, fecha_pago')
      .eq('personal_id', trabajador.id).order('periodo_mes', { ascending: false }).limit(3),
    sb.from('permisos').select('tipo_permiso, fecha_inicio, fecha_fin, motivo, estado, con_goce, origen, created_at')
      .eq('personal_id', trabajador.id).order('created_at', { ascending: false }).limit(6),
  ]);
  if (detalleR.error) return { encontrado: true, error: `No se pudo leer la asistencia: ${detalleR.error.message}` };

  const dias = (detalleR.data || []) as Dia[];
  const transcurridos = dias.filter((d) => d.estado !== 'futuro');
  const fechas = (estado: string) => transcurridos.filter((d) => d.estado === estado).map((d) => d.fecha);
  const asistidos = transcurridos.filter((d) => d.estado === 'asistio' || d.estado === 'tardanza').length;
  const permisoPagado = transcurridos.filter((d) => d.estado === 'permiso' && d.permiso_con_goce).length;
  const pagoPorDia = Number(trabajador.pago_por_dia);
  const hoyDia = dias.find((d) => d.fecha === hoy);

  const guardado = (pagosR.data || []).find((p) => p.periodo_mes === periodo);
  // Mes en curso sin pagar: se calcula en vivo con la asistencia de hoy (la planilla guardada puede estar desactualizada).
  const enVivo = periodo === periodoDe(hoy) && guardado?.estado_pago !== 'pagado';
  const pagoRegistrado = enVivo ? undefined : guardado;
  const descuentos = Number(guardado?.descuentos || 0);
  const bonos = Number(guardado?.bonos || 0);
  const estimado = Math.max(0, (asistidos + permisoPagado) * pagoPorDia - descuentos + bonos);

  return {
    encontrado: true,
    trabajador: {
      nombre: `${trabajador.nombres} ${trabajador.apellidos}`,
      dni: trabajador.dni,
      cargo: trabajador.cargo,
      area: trabajador.area,
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
    pago_del_periodo: pagoRegistrado
      ? {
          total: soles(Number(pagoRegistrado.total_pagar)),
          estado: pagoRegistrado.estado_pago,
          fecha_pago: pagoRegistrado.fecha_pago ? fechaLarga(pagoRegistrado.fecha_pago) : null,
          detalle: `(${pagoRegistrado.dias_asistidos} días asistidos + ${pagoRegistrado.dias_permiso_pagado} de permiso con goce) × ${soles(Number(pagoRegistrado.pago_por_dia))} − descuentos ${soles(Number(pagoRegistrado.descuentos))} + bonos ${soles(Number(pagoRegistrado.bonos))}`,
          nota: periodo === periodoDe(hoy) ? 'El mes aún no termina: el monto crece con cada día trabajado.' : undefined,
        }
      : {
          total_acumulado_a_la_fecha: soles(estimado),
          estado: enVivo ? 'mes en curso, pendiente de pago' : 'planilla aún no generada',
          detalle: `(${asistidos} días asistidos + ${permisoPagado} de permiso con goce) × ${soles(pagoPorDia)}${descuentos ? ` − descuentos ${soles(descuentos)}` : ''}${bonos ? ` + bonos ${soles(bonos)}` : ''}`,
          nota: enVivo ? 'El mes aún no termina: el monto crece con cada día trabajado.' : undefined,
        },
    ultimos_pagos: (pagosR.data || []).map((p) => ({
      mes: nombrePeriodo(p.periodo_mes),
      total: soles(Number(p.total_pagar)),
      estado: p.estado_pago,
      fecha_pago: p.fecha_pago,
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
