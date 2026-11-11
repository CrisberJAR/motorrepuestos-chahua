import 'dart:typed_data';

import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../vm_base.dart';

class PersonalVm extends VmBase {
  final DatosRepositorio _repo;
  final IaRepositorio _ia;
  PersonalVm(this._repo, this._ia);

  List<Personal> lista = [];
  Map<String, String> fotos = {};
  bool verInactivos = false;
  String busqueda = '';

  static String _normal(String s) => s.toLowerCase().replaceAll(RegExp('[áà]'), 'a').replaceAll(RegExp('[éè]'), 'e').replaceAll('í', 'i').replaceAll('ó', 'o').replaceAll('ú', 'u');

  List<Personal> get visibles => lista
      .where((p) => verInactivos || p.activo)
      .where((p) => busqueda.isEmpty || _normal('${p.nombreCompleto} ${p.dni} ${p.cargo}').contains(_normal(busqueda)))
      .toList();

  int get sinRostro => lista.where((p) => p.activo && p.fotoRostroUrl == null).length;

  Future<void> iniciar() async {
    await cargar();
    escucharCambios(_repo, ['personal'], () => cargar(silencioso: true));
  }

  Future<void> cargar({bool silencioso = false}) => cargarCon(() async {
        lista = await _repo.personal(soloActivos: false);
        fotos = await _repo.urlsFotos(lista.map((p) => p.fotoRostroUrl));
      }, silencioso: silencioso);

  void buscar(String t) {
    busqueda = t;
    avisar();
  }

  void alternarInactivos(bool v) {
    verInactivos = v;
    avisar();
  }

  Future<(String, bool)> _resultado(Future<String> Function() f) async {
    try {
      final m = await f();
      await cargar(silencioso: true);
      return (m, false);
    } catch (e) {
      return (mensajeDeError(e), true);
    }
  }

  Future<(String, bool)> crear(Map<String, String> datos, Uint8List foto) => _resultado(() => _ia.crearTrabajador(datos, foto));
  Future<(String, bool)> cambiarFoto(Personal p, Uint8List foto) => _resultado(() => _ia.registrarRostro(p.id, foto));
  Future<(String, bool)> cambiarClave(Personal p, String clave) => _resultado(() => _ia.cambiarClave(p.id, clave));

  Future<(String, bool)> cambiarEstado(Personal p) => _resultado(() async {
        final nuevo = p.activo ? 'inactivo' : 'activo';
        await _repo.actualizarPersonal(p.id, {'estado': nuevo});
        return nuevo == 'activo' ? '${p.nombres} fue reactivado.' : '${p.nombres} quedó inactivo: ya no podrá ingresar ni marcar.';
      });
}
