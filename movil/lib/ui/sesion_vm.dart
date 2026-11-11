import '../data/modelos.dart';
import '../data/repositorios.dart';
import 'vm_base.dart';

enum EstadoSesion { revisando, sinSesion, noHabilitada, activa }

/// Estado global de la sesión: quién ingresó y con qué rol.
class SesionVm extends VmBase {
  final AuthRepositorio _auth;
  SesionVm(this._auth);

  EstadoSesion estado = EstadoSesion.revisando;
  Yo? yo;

  Future<void> iniciar() async {
    if (!_auth.haySesion) {
      estado = EstadoSesion.sinSesion;
      return avisar();
    }
    await _cargarYo();
  }

  Future<void> _cargarYo() async {
    try {
      yo = await _auth.cargarYo();
      estado = yo == null ? EstadoSesion.noHabilitada : EstadoSesion.activa;
    } catch (e) {
      error = mensajeDeError(e);
      estado = EstadoSesion.sinSesion;
    }
    avisar();
  }

  /// Vuelve a leer los datos propios (tras cambiar la foto o los datos de contacto).
  Future<void> recargarYo() async {
    try {
      final nuevo = await _auth.cargarYo();
      if (nuevo != null) {
        yo = nuevo;
        avisar();
      }
    } catch (_) {}
  }

  /// Devuelve un mensaje de error o null si ingresó.
  Future<String?> ingresar(String dni, String clave) async {
    if (!RegExp(r'^\d{8}$').hasMatch(dni)) return 'Tu usuario es tu DNI: 8 dígitos.';
    if (clave.isEmpty) return 'Escribe tu contraseña.';
    try {
      await _auth.ingresar(dni, clave);
      await _cargarYo();
      return estado == EstadoSesion.activa ? null : 'Tu cuenta no está habilitada. Comunícate con el administrador.';
    } catch (e) {
      return mensajeDeError(e);
    }
  }

  Future<void> salir() async {
    await _auth.salir();
    yo = null;
    estado = EstadoSesion.sinSesion;
    avisar();
  }
}
