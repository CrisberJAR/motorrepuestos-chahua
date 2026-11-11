import '../../core/fechas.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../vm_base.dart';

class PermisosVm extends VmBase {
  final DatosRepositorio _repo;
  final Yo yo;
  PermisosVm(this._repo, this.yo);

  String filtro = 'todos';
  List<Permiso> todos = [];
  List<Personal> personal = [];
  Map<String, String> fotos = {};
  String? ocupado;

  List<Permiso> get lista => filtro == 'todos' ? todos : todos.where((p) => p.estado == filtro).toList();
  int contar(String estado) => todos.where((p) => p.estado == estado).length;

  Future<void> iniciar() async {
    await cargar();
    escucharCambios(_repo, ['permisos'], () => cargar(silencioso: true));
  }

  Future<void> cargar({bool silencioso = false}) => cargarCon(() async {
        todos = await _repo.permisos(personalId: yo.esAdmin ? null : yo.id);
        if (yo.esAdmin && personal.isEmpty) personal = await _repo.personal();
        fotos = await _repo.urlsFotos(todos.map((p) => p.fotoRostroUrl));
      }, silencioso: silencioso);

  void filtrar(String f) {
    filtro = f;
    avisar();
  }

  /// Devuelve un mensaje para mostrar (éxito o error) y si fue error.
  Future<(String, bool)> _accion(Permiso p, String clave, Map<String, dynamic> cambios, String ok) async {
    ocupado = '${p.id}-$clave';
    avisar();
    try {
      await _repo.actualizarPermiso(p, cambios);
      await cargar(silencioso: true);
      return (ok, false);
    } catch (e) {
      return (mensajeDeError(e), true);
    } finally {
      ocupado = null;
      avisar();
    }
  }

  Future<(String, bool)> aprobar(Permiso p) => _accion(p, 'ok', {'estado': 'aprobado'}, 'Permiso aprobado.');
  Future<(String, bool)> rechazar(Permiso p) => _accion(p, 'no', {'estado': 'rechazado'}, 'Permiso rechazado.');
  Future<(String, bool)> cambiarGoce(Permiso p, bool valor) =>
      _accion(p, 'goce', {'con_goce': valor}, valor ? 'Estos días se pagarán.' : 'Estos días ya no se pagarán.');

  /// Admin: registra aprobado. Trabajador: solicita (queda pendiente). Devuelve error o null.
  Future<String?> crear({
    required String personalId,
    required String tipo,
    required String inicio,
    required String fin,
    required String motivo,
    required bool conGoce,
  }) async {
    if (fin.compareTo(inicio) < 0) return 'La fecha final no puede ser anterior a la inicial.';
    if (inicio == fin && Fechas.diaSemana(inicio) == 7) return 'Ese día es domingo y no es laborable.';
    if (motivo.trim().isEmpty) return 'Escribe el motivo.';
    try {
      await _repo.crearPermiso({
        'personal_id': yo.esAdmin ? personalId : yo.id,
        'tipo_permiso': tipo,
        'fecha_inicio': inicio,
        'fecha_fin': fin,
        'motivo': motivo.trim(),
        'estado': yo.esAdmin ? 'aprobado' : 'pendiente',
        'origen': 'movil',
        'con_goce': yo.esAdmin && conGoce,
      });
      await cargar(silencioso: true);
      return null;
    } catch (e) {
      return mensajeDeError(e);
    }
  }
}
