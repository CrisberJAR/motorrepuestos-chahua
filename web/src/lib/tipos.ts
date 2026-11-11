export type Rol = 'admin' | 'trabajador';
export type EstadoDia = 'asistio' | 'tardanza' | 'falta' | 'permiso' | 'pendiente' | 'futuro';
export type TipoPermiso = 'salud' | 'personal' | 'urgencia' | 'vacaciones';
export type EstadoPermiso = 'pendiente' | 'aprobado' | 'rechazado';
export type OrigenPermiso = 'movil' | 'web' | 'chatbot_movil' | 'chatbot_web';

export type Yo = {
  id: string;
  dni: string;
  nombres: string;
  apellidos: string;
  cargo: string;
  area: string;
  rol: Rol;
  pago_por_dia: number;
  foto_rostro_url: string | null;
};

export type Personal = {
  id: string;
  user_id: string | null;
  dni: string;
  nombres: string;
  apellidos: string;
  cargo: string;
  area: string;
  telefono: string | null;
  correo: string | null;
  sueldo_base: number;
  pago_por_dia: number;
  hora_entrada: string;
  hora_salida: string;
  tolerancia_min: number;
  foto_rostro_url: string | null;
  tiene_rostro?: boolean;
  rol: Rol;
  estado: 'activo' | 'inactivo';
  fecha_ingreso: string;
};

export type DiaAsistencia = {
  personal_id: string;
  dni: string;
  nombres: string;
  apellidos: string;
  cargo: string;
  area: string;
  fecha: string;
  dia_semana: number;
  estado: EstadoDia;
  hora_entrada: string | null;
  hora_salida: string | null;
  confianza_facial: number | null;
  permiso_id: string | null;
  permiso_tipo: TipoPermiso | null;
  permiso_con_goce: boolean;
};

export type Permiso = {
  id: string;
  personal_id: string;
  tipo_permiso: TipoPermiso;
  fecha_inicio: string;
  fecha_fin: string;
  motivo: string;
  estado: EstadoPermiso;
  origen: OrigenPermiso;
  con_goce: boolean;
  fecha_revision: string | null;
  observacion: string | null;
  created_at: string;
  personal?: { id: string; dni: string; nombres: string; apellidos: string; foto_rostro_url: string | null } | null;
};

export type Pago = {
  id: string;
  personal_id: string;
  periodo_mes: string;
  dias_asistidos: number;
  dias_permiso: number;
  dias_permiso_pagado: number;
  dias_falta: number;
  tardanzas_acumuladas: number;
  pago_por_dia: number;
  monto_base: number;
  descuentos: number;
  bonos: number;
  total_pagar: number;
  estado_pago: 'pendiente' | 'pagado';
  fecha_pago: string | null;
  observacion: string | null;
  personal?: { id: string; dni: string; nombres: string; apellidos: string; cargo: string; foto_rostro_url: string | null } | null;
};

export const ETIQUETA_DIA: Record<EstadoDia, string> = {
  asistio: 'Asistió',
  tardanza: 'Tardanza',
  falta: 'Falta',
  permiso: 'Permiso',
  pendiente: 'Sin marcar',
  futuro: '—',
};

export const ETIQUETA_TIPO: Record<TipoPermiso, string> = {
  salud: 'Salud',
  personal: 'Personal',
  urgencia: 'Urgencia',
  vacaciones: 'Vacaciones',
};

export const ETIQUETA_ORIGEN: Record<OrigenPermiso, string> = {
  movil: 'App móvil',
  web: 'Web',
  chatbot_movil: 'Chatbot móvil',
  chatbot_web: 'Chatbot web',
};

export const AREAS = ['Administración', 'Ventas', 'Taller', 'Almacén', 'Caja', 'Logística'];

export const nombreCorto = (p: { nombres: string; apellidos: string }) => `${p.nombres.split(' ')[0]} ${p.apellidos.split(' ')[0]}`;
export const iniciales = (p: { nombres: string; apellidos: string }) => `${p.nombres[0] || ''}${p.apellidos[0] || ''}`.toUpperCase();
