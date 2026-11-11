double _num(dynamic v) => v == null ? 0 : (v as num).toDouble();
int _int(dynamic v) => v == null ? 0 : (v as num).toInt();

enum EstadoDia { asistio, tardanza, falta, permiso, pendiente, futuro }

EstadoDia estadoDiaDe(String s) => EstadoDia.values.firstWhere((e) => e.name == s, orElse: () => EstadoDia.futuro);

const etiquetaDia = {
  EstadoDia.asistio: 'Asistió',
  EstadoDia.tardanza: 'Tardanza',
  EstadoDia.falta: 'Falta',
  EstadoDia.permiso: 'Permiso',
  EstadoDia.pendiente: 'Sin marcar',
  EstadoDia.futuro: '—',
};

const tiposPermiso = {'salud': 'Salud', 'personal': 'Personal', 'urgencia': 'Urgencia', 'vacaciones': 'Vacaciones'};
const origenesPermiso = {'movil': 'App móvil', 'web': 'Web', 'chatbot_movil': 'Chatbot móvil', 'chatbot_web': 'Chatbot web'};
const areas = ['Administración', 'Ventas', 'Taller', 'Almacén', 'Caja', 'Logística'];

/// Persona que inició sesión.
class Yo {
  final String id, dni, nombres, apellidos, cargo, area, rol;
  final double pagoPorDia;
  final String? fotoRostroUrl;

  Yo({
    required this.id,
    required this.dni,
    required this.nombres,
    required this.apellidos,
    required this.cargo,
    required this.area,
    required this.rol,
    required this.pagoPorDia,
    this.fotoRostroUrl,
  });

  bool get esAdmin => rol == 'admin';
  String get nombreCorto => '${nombres.split(' ').first} ${apellidos.split(' ').first}';

  factory Yo.desdeJson(Map<String, dynamic> j) => Yo(
        id: j['id'],
        dni: j['dni'],
        nombres: j['nombres'],
        apellidos: j['apellidos'],
        cargo: j['cargo'],
        area: j['area'],
        rol: j['rol'],
        pagoPorDia: _num(j['pago_por_dia']),
        fotoRostroUrl: j['foto_rostro_url'],
      );
}

class Personal {
  final String id, dni, nombres, apellidos, cargo, area, rol, estado, horaEntrada;
  final String? telefono, correo, fotoRostroUrl;
  final double pagoPorDia;
  final int toleranciaMin;

  Personal({
    required this.id,
    required this.dni,
    required this.nombres,
    required this.apellidos,
    required this.cargo,
    required this.area,
    required this.rol,
    required this.estado,
    required this.horaEntrada,
    required this.pagoPorDia,
    required this.toleranciaMin,
    this.telefono,
    this.correo,
    this.fotoRostroUrl,
  });

  bool get activo => estado == 'activo';
  String get nombreCompleto => '$nombres $apellidos';
  String get nombreCorto => '${nombres.split(' ').first} ${apellidos.split(' ').first}';
  String get iniciales => '${nombres.isNotEmpty ? nombres[0] : ''}${apellidos.isNotEmpty ? apellidos[0] : ''}'.toUpperCase();

  factory Personal.desdeJson(Map<String, dynamic> j) => Personal(
        id: j['id'],
        dni: j['dni'],
        nombres: j['nombres'],
        apellidos: j['apellidos'],
        cargo: j['cargo'],
        area: j['area'],
        rol: j['rol'],
        estado: j['estado'],
        horaEntrada: j['hora_entrada'] ?? '08:00:00',
        pagoPorDia: _num(j['pago_por_dia']),
        toleranciaMin: _int(j['tolerancia_min']),
        telefono: j['telefono'],
        correo: j['correo'],
        fotoRostroUrl: j['foto_rostro_url'],
      );
}

/// Un día de un trabajador (función SQL detalle_asistencia).
class DiaAsistencia {
  final String personalId, dni, nombres, apellidos, cargo, fecha;
  final EstadoDia estado;
  final String? horaEntrada, horaSalida, permisoTipo;
  final double? confianza;
  final bool permisoConGoce;

  DiaAsistencia({
    required this.personalId,
    required this.dni,
    required this.nombres,
    required this.apellidos,
    required this.cargo,
    required this.fecha,
    required this.estado,
    this.horaEntrada,
    this.horaSalida,
    this.permisoTipo,
    this.confianza,
    this.permisoConGoce = false,
  });

  String get nombreCorto => '${nombres.split(' ').first} ${apellidos.split(' ').first}';
  String get iniciales => '${nombres[0]}${apellidos[0]}'.toUpperCase();
  bool get presente => estado == EstadoDia.asistio || estado == EstadoDia.tardanza;

  factory DiaAsistencia.desdeJson(Map<String, dynamic> j) => DiaAsistencia(
        personalId: j['personal_id'],
        dni: j['dni'],
        nombres: j['nombres'],
        apellidos: j['apellidos'],
        cargo: j['cargo'],
        fecha: j['fecha'],
        estado: estadoDiaDe(j['estado']),
        horaEntrada: j['hora_entrada'],
        horaSalida: j['hora_salida'],
        permisoTipo: j['permiso_tipo'],
        confianza: j['confianza_facial'] == null ? null : _num(j['confianza_facial']),
        permisoConGoce: j['permiso_con_goce'] == true,
      );
}

class Resumen {
  final int asistidos, tardanzas, permisos, faltas, permisosPagados;
  Resumen(this.asistidos, this.tardanzas, this.permisos, this.faltas, this.permisosPagados);

  factory Resumen.de(Iterable<DiaAsistencia> dias) {
    int c(EstadoDia e) => dias.where((d) => d.estado == e).length;
    return Resumen(
      c(EstadoDia.asistio) + c(EstadoDia.tardanza),
      c(EstadoDia.tardanza),
      c(EstadoDia.permiso),
      c(EstadoDia.falta),
      dias.where((d) => d.estado == EstadoDia.permiso && d.permisoConGoce).length,
    );
  }
}

class Permiso {
  final String id, personalId, tipo, fechaInicio, fechaFin, motivo, estado, origen, creado;
  final bool conGoce;
  final String? nombres, apellidos, dni, fotoRostroUrl;

  Permiso({
    required this.id,
    required this.personalId,
    required this.tipo,
    required this.fechaInicio,
    required this.fechaFin,
    required this.motivo,
    required this.estado,
    required this.origen,
    required this.creado,
    required this.conGoce,
    this.nombres,
    this.apellidos,
    this.dni,
    this.fotoRostroUrl,
  });

  String get nombreCorto => nombres == null ? '' : '${nombres!.split(' ').first} ${apellidos!.split(' ').first}';

  factory Permiso.desdeJson(Map<String, dynamic> j) {
    final p = j['personal'] as Map<String, dynamic>?;
    return Permiso(
      id: j['id'],
      personalId: j['personal_id'],
      tipo: j['tipo_permiso'],
      fechaInicio: j['fecha_inicio'],
      fechaFin: j['fecha_fin'],
      motivo: j['motivo'],
      estado: j['estado'],
      origen: j['origen'],
      creado: j['created_at'],
      conGoce: j['con_goce'] == true,
      nombres: p?['nombres'],
      apellidos: p?['apellidos'],
      dni: p?['dni'],
      fotoRostroUrl: p?['foto_rostro_url'],
    );
  }
}

class Pago {
  final String id, personalId, periodo, estadoPago;
  final int diasAsistidos, diasPermiso, diasPermisoPagado, diasFalta, tardanzas;
  final double pagoPorDia, montoBase, descuentos, bonos, total;
  final String? fechaPago, nombres, apellidos, dni, fotoRostroUrl;

  Pago({
    required this.id,
    required this.personalId,
    required this.periodo,
    required this.estadoPago,
    required this.diasAsistidos,
    required this.diasPermiso,
    required this.diasPermisoPagado,
    required this.diasFalta,
    required this.tardanzas,
    required this.pagoPorDia,
    required this.montoBase,
    required this.descuentos,
    required this.bonos,
    required this.total,
    this.fechaPago,
    this.nombres,
    this.apellidos,
    this.dni,
    this.fotoRostroUrl,
  });

  bool get pagado => estadoPago == 'pagado';
  String get nombreCorto => nombres == null ? '' : '${nombres!.split(' ').first} ${apellidos!.split(' ').first}';

  factory Pago.desdeJson(Map<String, dynamic> j) {
    final p = j['personal'] as Map<String, dynamic>?;
    return Pago(
      id: j['id'],
      personalId: j['personal_id'],
      periodo: j['periodo_mes'],
      estadoPago: j['estado_pago'],
      diasAsistidos: _int(j['dias_asistidos']),
      diasPermiso: _int(j['dias_permiso']),
      diasPermisoPagado: _int(j['dias_permiso_pagado']),
      diasFalta: _int(j['dias_falta']),
      tardanzas: _int(j['tardanzas_acumuladas']),
      pagoPorDia: _num(j['pago_por_dia']),
      montoBase: _num(j['monto_base']),
      descuentos: _num(j['descuentos']),
      bonos: _num(j['bonos']),
      total: _num(j['total_pagar']),
      fechaPago: j['fecha_pago'],
      nombres: p?['nombres'],
      apellidos: p?['apellidos'],
      dni: p?['dni'],
      fotoRostroUrl: p?['foto_rostro_url'],
    );
  }
}

/// Resultado de /api/ia/identificar-rostro
class ResultadoEscaneo {
  final bool reconocido, registrado;
  final String mensaje;
  final String? tipo, codigo, nombre, cargo, dni, estado, horaEntrada, horaSalida;
  final double? confianza;

  ResultadoEscaneo({
    required this.reconocido,
    required this.registrado,
    required this.mensaje,
    this.tipo,
    this.codigo,
    this.nombre,
    this.cargo,
    this.dni,
    this.estado,
    this.horaEntrada,
    this.horaSalida,
    this.confianza,
  });

  factory ResultadoEscaneo.desdeJson(Map<String, dynamic> j) {
    final t = j['trabajador'] as Map<String, dynamic>?;
    final a = j['asistencia'] as Map<String, dynamic>?;
    return ResultadoEscaneo(
      reconocido: j['reconocido'] == true,
      registrado: j['registrado'] == true,
      mensaje: (j['mensaje'] ?? j['error'] ?? '') as String,
      tipo: j['tipo'],
      codigo: j['codigo'],
      nombre: t?['nombre_corto'],
      cargo: t?['cargo'],
      dni: t?['dni'],
      estado: a?['estado'],
      horaEntrada: a?['hora_entrada'],
      horaSalida: a?['hora_salida'],
      confianza: j['confianza'] == null ? null : _num(j['confianza']),
    );
  }
}

class MensajeChat {
  final String rol; // usuario | asistente
  final String texto;
  final bool error;
  final List<String> etiquetas;
  MensajeChat(this.rol, this.texto, {this.error = false, this.etiquetas = const []});
}
