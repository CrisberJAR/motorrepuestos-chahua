import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';

class ApiExcepcion implements Exception {
  final String mensaje;
  final int status;
  final Map<String, dynamic> cuerpo;
  ApiExcepcion(this.mensaje, this.status, [this.cuerpo = const {}]);
  String? get codigo => cuerpo['codigo'] as String?;
  @override
  String toString() => mensaje;
}

/// Cliente de los endpoints de IA en Vercel (Next.js). Envía el token de la sesión de Supabase.
class ApiCliente {
  final SupabaseClient _sb;
  ApiCliente(this._sb);

  Future<String> _token() async {
    var sesion = _sb.auth.currentSession;
    if (sesion == null) throw ApiExcepcion('Tu sesión expiró. Vuelve a iniciar sesión.', 401);
    if (sesion.isExpired) {
      sesion = (await _sb.auth.refreshSession()).session;
      if (sesion == null) throw ApiExcepcion('Tu sesión expiró. Vuelve a iniciar sesión.', 401);
    }
    return sesion.accessToken;
  }

  Uri _url(String ruta) => Uri.parse('${Config.apiUrl}$ruta');

  Map<String, dynamic> _leer(http.Response r, {bool aceptarErrores = false}) {
    Map<String, dynamic> cuerpo;
    try {
      cuerpo = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiExcepcion('El servidor respondió algo inesperado (${r.statusCode}).', r.statusCode);
    }
    if ((r.statusCode >= 400 || cuerpo['ok'] == false) && !aceptarErrores) {
      throw ApiExcepcion((cuerpo['error'] ?? 'Error ${r.statusCode}') as String, r.statusCode, cuerpo);
    }
    return cuerpo;
  }

  Future<T> _conRed<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on SocketException {
      throw ApiExcepcion('No hay conexión con el servidor (${Config.apiUrl}). Revisa tu internet.', 0);
    } on TimeoutException {
      throw ApiExcepcion('El servidor tardó demasiado en responder. Intenta de nuevo.', 0);
    } on http.ClientException {
      throw ApiExcepcion('No hay conexión con el servidor (${Config.apiUrl}).', 0);
    }
  }

  Future<Map<String, dynamic>> postJson(String ruta, Map<String, dynamic> datos, {Duration limite = const Duration(seconds: 70)}) async {
    final token = await _token();
    return _conRed(() async {
      final r = await http
          .post(_url(ruta), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: jsonEncode(datos))
          .timeout(limite);
      return _leer(r);
    });
  }

  /// Descarga un archivo (PDF o Excel). Devuelve los bytes y el nombre sugerido por el servidor.
  Future<({Uint8List bytes, String nombre})> getArchivo(String ruta, Map<String, String> params) async {
    final token = await _token();
    return _conRed(() async {
      final r = await http.get(_url(ruta).replace(queryParameters: params), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 60));
      final tipo = r.headers['content-type'] ?? '';
      if (r.statusCode >= 400 || tipo.contains('application/json')) {
        _leer(r); // lanza ApiExcepcion con el mensaje del servidor
        throw ApiExcepcion('No se pudo descargar el archivo (${r.statusCode}).', r.statusCode);
      }
      final nombre = RegExp(r'filename="([^"]+)"').firstMatch(r.headers['content-disposition'] ?? '')?.group(1) ?? 'reporte.${params['formato'] ?? 'pdf'}';
      return (bytes: r.bodyBytes, nombre: nombre);
    });
  }

  /// multipart/form-data con el campo "imagen" (JPEG).
  Future<Map<String, dynamic>> postImagen(
    String ruta,
    Uint8List imagen, {
    Map<String, String> campos = const {},
    bool aceptarErrores = false,
  }) async {
    final token = await _token();
    return _conRed(() async {
      final req = http.MultipartRequest('POST', _url(ruta))
        ..headers['Authorization'] = 'Bearer $token'
        ..fields.addAll(campos)
        ..files.add(http.MultipartFile.fromBytes('imagen', imagen, filename: 'foto.jpg', contentType: MediaType('image', 'jpeg')));
      final r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 45)));
      return _leer(r, aceptarErrores: aceptarErrores);
    });
  }
}
