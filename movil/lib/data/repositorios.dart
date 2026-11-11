import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import 'api_cliente.dart';
import 'modelos.dart';

/// Convierte errores técnicos en mensajes para la persona.
String mensajeDeError(Object e) {
  if (e is ApiExcepcion) return e.mensaje;
  if (e is AuthException) {
    if (e.message.toLowerCase().contains('invalid login')) {
      return 'DNI o contraseña incorrectos. Si olvidaste tu contraseña, pide al administrador que la restablezca.';
    }
    return 'No se pudo completar: ${e.message}';
  }
  if (e is PostgrestException) return e.message;
  if (e is StorageException) return 'No se pudo subir el archivo: ${e.message}';
  final t = e.toString();
  if (t.contains('SocketException') || t.contains('Failed host lookup')) return 'Sin conexión a internet.';
  return t.replaceFirst('Exception: ', '');
}

/* ======================= Autenticación ======================= */
class AuthRepositorio {
  final SupabaseClient _sb;
  AuthRepositorio(this._sb);

  bool get haySesion => _sb.auth.currentSession != null;

  Future<void> ingresar(String dni, String clave) => _sb.auth.signInWithPassword(email: Config.correoDesdeDni(dni), password: clave);

  Future<void> salir() => _sb.auth.signOut();

  /// Fila de la tabla personal vinculada al usuario. Null si no existe o está inactiva.
  Future<Yo?> cargarYo() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final fila = await _sb
        .from('personal')
        .select('id, dni, nombres, apellidos, cargo, area, rol, estado, pago_por_dia, tipo_pago, foto_rostro_url, foto_perfil_url, telefono, correo')
        .eq('user_id', uid)
        .maybeSingle();
    if (fila == null || fila['estado'] != 'activo') return null;
    return Yo.desdeJson(fila);
  }

  /// Cambia la contraseña propia comprobando antes la actual.
  Future<void> cambiarMiClave(String dni, String actual, String nueva) async {
    try {
      await _sb.auth.signInWithPassword(email: Config.correoDesdeDni(dni), password: actual);
    } on AuthException {
      throw Exception('La contraseña actual no es correcta.');
    }
    await _sb.auth.updateUser(UserAttributes(password: nueva));
  }
}

/* ======================= Datos (Supabase + RLS) ======================= */
class DatosRepositorio {
  final SupabaseClient _sb;
  DatosRepositorio(this._sb);

  Future<List<DiaAsistencia>> detalle(String desde, String hasta, {String? personalId}) async {
    final filas = await _sb.rpc('detalle_asistencia', params: {'p_desde': desde, 'p_hasta': hasta, 'p_personal_id': personalId}) as List<dynamic>;
    return filas.map((f) => DiaAsistencia.desdeJson(f as Map<String, dynamic>)).toList();
  }

  Future<List<Personal>> personal({bool soloActivos = true}) async {
    var q = _sb.from('personal').select('id, dni, nombres, apellidos, cargo, area, telefono, correo, pago_por_dia, tipo_pago, hora_entrada, tolerancia_min, foto_rostro_url, rol, estado');
    if (soloActivos) q = q.eq('estado', 'activo');
    final filas = await q.order('rol').order('apellidos');
    return filas.map(Personal.desdeJson).toList();
  }

  Future<void> actualizarPersonal(String id, Map<String, dynamic> cambios) => _sb.from('personal').update(cambios).eq('id', id);

  Future<List<Permiso>> permisos({String? personalId, String? estado, int limite = 200}) async {
    var q = _sb.from('permisos').select('*, personal:personal_id(id, dni, nombres, apellidos, foto_rostro_url)');
    if (personalId != null) q = q.eq('personal_id', personalId);
    if (estado != null) q = q.eq('estado', estado);
    final filas = await q.order('created_at', ascending: false).limit(limite);
    return filas.map(Permiso.desdeJson).toList();
  }

  // Lo pendiente de pago se calcula en vivo: aprobar un permiso se refleja al instante.
  Future<void> crearPermiso(Map<String, dynamic> datos) => _sb.from('permisos').insert(datos);

  Future<void> actualizarPermiso(Permiso p, Map<String, dynamic> cambios) => _sb.from('permisos').update(cambios).eq('id', p.id);

  /* ---------- Pagos ---------- */

  /// Saldo de cada trabajador desde su último pago hasta hoy (el trabajador solo recibe el suyo).
  Future<List<PagoPendiente>> pagosPendientes({String? personalId}) async {
    final filas = await _sb.rpc('pagos_pendientes', params: {'p_personal_id': personalId}) as List<dynamic>;
    return filas.map((f) => PagoPendiente.desdeJson(f as Map<String, dynamic>)).toList();
  }

  Future<List<DiaPago>> detallePago(String personalId, String desde, String hasta) async {
    final filas = await _sb.rpc('detalle_pago', params: {'p_personal_id': personalId, 'p_desde': desde, 'p_hasta': hasta}) as List<dynamic>;
    return filas.map((f) => DiaPago.desdeJson(f as Map<String, dynamic>)).toList();
  }

  /// Montos por rendimiento: [{'fecha': '2026-11-03', 'monto': 65.0}], monto null = pago por día normal.
  Future<void> fijarMontos(String personalId, List<Map<String, dynamic>> montos) =>
      _sb.rpc('fijar_montos_dia', params: {'p_personal_id': personalId, 'p_montos': montos});

  Future<void> registrarPago({
    required String personalId,
    required String desde,
    required String hasta,
    required String metodo,
    double bonos = 0,
    double descuentos = 0,
    String? operacion,
    String? observacion,
  }) =>
      _sb.rpc('registrar_pago', params: {
        'p_personal_id': personalId,
        'p_desde': desde,
        'p_hasta': hasta,
        'p_metodo': metodo,
        'p_bonos': bonos,
        'p_descuentos': descuentos,
        'p_numero_operacion': operacion,
        'p_observacion': observacion,
      });

  Future<List<Pago>> pagosRealizados(String desde, String hasta) async {
    final filas = await _sb
        .from('pagos')
        .select('*, personal:personal_id(id, dni, nombres, apellidos, foto_rostro_url)')
        .gte('fecha_pago', desde)
        .lte('fecha_pago', hasta)
        .order('fecha_pago', ascending: false)
        .order('created_at', ascending: false);
    return filas.map(Pago.desdeJson).toList();
  }

  Future<List<Pago>> pagosDe(String personalId) async {
    final filas = await _sb.from('pagos').select().eq('personal_id', personalId).order('fecha_hasta', ascending: false);
    return filas.map(Pago.desdeJson).toList();
  }

  Future<void> anularPago(String id) => _sb.from('pagos').delete().eq('id', id);

  /* ---------- Perfil propio ---------- */

  Future<void> actualizarMiPerfil({String? telefono, String? correo, String? fotoPerfil, bool quitarFoto = false}) =>
      _sb.rpc('actualizar_mi_perfil', params: {
        'p_telefono': telefono,
        'p_correo': correo,
        'p_foto_perfil_url': fotoPerfil,
        'p_quitar_foto': quitarFoto,
      });

  Future<void> subirFotoPerfil(String personalId, Uint8List jpeg) async {
    final ruta = '$personalId/perfil.jpg';
    await _sb.storage.from('fotos_perfil').uploadBinary(ruta, jpeg, fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg', cacheControl: '60'));
    await actualizarMiPerfil(fotoPerfil: ruta);
  }

  Future<void> quitarFotoPerfil(String personalId) async {
    await _sb.storage.from('fotos_perfil').remove(['$personalId/perfil.jpg']);
    await actualizarMiPerfil(quitarFoto: true);
  }

  /* ---------- Fotos ---------- */

  /// URLs temporales (1 hora) de las fotos de un bucket privado.
  Future<Map<String, String>> urlsFotos(Iterable<String?> rutas, {String bucket = 'rostros_personal'}) async {
    final lista = rutas.whereType<String>().toSet().toList();
    if (lista.isEmpty) return {};
    try {
      final urls = await _sb.storage.from(bucket).createSignedUrlsResult(lista, 3600);
      return {for (final u in urls.whereType<SignedUrlSuccess>()) u.path: u.signedUrl};
    } catch (_) {
      return {};
    }
  }

  /// Foto que representa a la persona: la de perfil si tiene, si no la del rostro.
  Future<String?> urlMiFoto(Yo yo) async {
    if (yo.fotoPerfilUrl != null) {
      final m = await urlsFotos([yo.fotoPerfilUrl], bucket: 'fotos_perfil');
      // La marca de tiempo evita que se muestre la foto anterior guardada en caché.
      final u = m[yo.fotoPerfilUrl];
      if (u != null) return '$u&v=${DateTime.now().millisecondsSinceEpoch ~/ 60000}';
    }
    if (yo.fotoRostroUrl != null) return (await urlsFotos([yo.fotoRostroUrl]))[yo.fotoRostroUrl];
    return null;
  }

  /// Escucha cambios en las tablas (Supabase Realtime). Devuelve una función para dejar de escuchar.
  void Function() escuchar(List<String> tablas, void Function() alCambiar) {
    final canal = _sb.channel('movil-${tablas.join('-')}-${DateTime.now().microsecondsSinceEpoch}');
    for (final t in tablas) {
      canal.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: t, callback: (_) => alCambiar());
    }
    canal.subscribe();
    return () => _sb.removeChannel(canal);
  }
}

/* ======================= IA y reportes (endpoints en Vercel) ======================= */
class IaRepositorio {
  final ApiCliente _api;
  IaRepositorio(this._api);

  /// Identifica el rostro (1:N) y registra entrada o salida. Devuelve también los casos "no reconocido".
  Future<ResultadoEscaneo> identificarRostro(Uint8List jpeg) async {
    final r = await _api.postImagen('/api/ia/identificar-rostro', jpeg, aceptarErrores: true);
    if (r['ok'] == false && r['codigo'] == null && r['reconocido'] == null) {
      throw ApiExcepcion((r['error'] ?? 'No se pudo procesar la foto.') as String, 400, r);
    }
    return ResultadoEscaneo.desdeJson(r);
  }

  Future<String> registrarRostro(String personalId, Uint8List jpeg) async {
    final r = await _api.postImagen('/api/ia/registrar-rostro', jpeg, campos: {'personal_id': personalId});
    return r['mensaje'] as String;
  }

  Future<String> crearTrabajador(Map<String, String> datos, Uint8List jpeg) async {
    final r = await _api.postImagen('/api/admin/personal', jpeg, campos: datos);
    return r['mensaje'] as String;
  }

  Future<String> cambiarClave(String personalId, String nueva) async {
    final r = await _api.postJson('/api/admin/cambiar-clave', {'personal_id': personalId, 'nueva_clave': nueva});
    return r['mensaje'] as String;
  }

  /// Reporte en PDF o Excel: tipo = asistencia | pagos | comprobante.
  Future<({Uint8List bytes, String nombre})> descargarReporte(Map<String, String> params) => _api.getArchivo('/api/reportes', params);

  /// Chatbot con Gemini. Devuelve la respuesta y etiquetas de las acciones realizadas.
  Future<({String respuesta, List<String> etiquetas})> chat(List<MensajeChat> historial) async {
    final r = await _api.postJson('/api/ia/chatbot', {
      'origen': 'movil',
      'mensajes': historial.where((m) => !m.error).map((m) => {'rol': m.rol, 'texto': m.texto}).toList(),
    });
    final etiquetas = <String>[];
    for (final a in (r['acciones'] as List<dynamic>? ?? [])) {
      final accion = a as Map<String, dynamic>;
      if (accion['herramienta'] == 'registrar_permiso_chat') {
        final res = accion['resultado'] as Map<String, dynamic>? ?? {};
        etiquetas.add(res['registrado'] == true ? 'Permiso registrado · ${res['estado']}' : 'Permiso no registrado');
      } else {
        etiquetas.add('Consultó datos en tiempo real');
      }
    }
    return (respuesta: r['respuesta'] as String, etiquetas: etiquetas.toSet().toList());
  }
}
