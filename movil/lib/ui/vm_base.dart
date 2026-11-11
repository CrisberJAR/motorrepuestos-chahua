import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositorios.dart';

/// Base de los ViewModels (MVVM): estado de carga/error, recarga por tiempo real y limpieza.
abstract class VmBase extends ChangeNotifier {
  bool cargando = false;
  String? error;
  bool _vivo = true;
  final List<void Function()> _alCerrar = [];
  Timer? _espera;

  void avisar() {
    if (_vivo) notifyListeners();
  }

  /// Ejecuta una carga mostrando el indicador solo la primera vez (las recargas son silenciosas).
  Future<void> cargarCon(Future<void> Function() tarea, {bool silencioso = false}) async {
    if (!silencioso) {
      cargando = true;
      avisar();
    }
    try {
      await tarea();
      error = null;
    } catch (e) {
      error = mensajeDeError(e);
    } finally {
      cargando = false;
      avisar();
    }
  }

  /// Recarga cuando Supabase Realtime informa cambios (agrupa avisos seguidos).
  void escucharCambios(DatosRepositorio repo, List<String> tablas, Future<void> Function() recargar) {
    _alCerrar.add(repo.escuchar(tablas, () {
      _espera?.cancel();
      _espera = Timer(const Duration(milliseconds: 500), () {
        if (_vivo) recargar();
      });
    }));
  }

  @override
  void dispose() {
    _vivo = false;
    _espera?.cancel();
    for (final f in _alCerrar) {
      f();
    }
    super.dispose();
  }
}
