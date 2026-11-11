import '../../core/fechas.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../vm_base.dart';

class InicioVm extends VmBase {
  final DatosRepositorio _repo;
  final Yo yo;
  InicioVm(this._repo, this.yo);

  final String hoy = Fechas.hoy();
  List<DiaAsistencia> deHoy = [];
  List<DiaAsistencia> delMes = [];
  List<Permiso> permisos = [];
  int pendientes = 0;
  Map<String, String> fotos = {};
  Map<String, String?> rutas = {};
  PagoPendiente? porCobrar;

  bool get esDomingo => Fechas.diaSemana(hoy) == 7;

  Future<void> iniciar() async {
    await cargar();
    escucharCambios(_repo, ['asistencias', 'permisos', 'personal', 'pagos'], () => cargar(silencioso: true));
  }

  Future<void> cargar({bool silencioso = false}) => cargarCon(() async {
        if (yo.esAdmin) {
          final resultados = await Future.wait([
            _repo.detalle(hoy, hoy),
            _repo.permisos(estado: 'pendiente', limite: 50),
            _repo.personal(),
          ]);
          deHoy = resultados[0] as List<DiaAsistencia>;
          pendientes = (resultados[1] as List<Permiso>).length;
          rutas = {for (final p in resultados[2] as List<Personal>) p.id: p.fotoRostroUrl};
          fotos = await _repo.urlsFotos(rutas.values);
        } else {
          final mes = Fechas.rangoMes(Fechas.periodoDe(hoy));
          final resultados = await Future.wait([
            _repo.detalle(mes.desde, mes.hasta, personalId: yo.id),
            _repo.permisos(personalId: yo.id, limite: 3),
            _repo.pagosPendientes(personalId: yo.id),
          ]);
          delMes = resultados[0] as List<DiaAsistencia>;
          permisos = resultados[1] as List<Permiso>;
          final saldo = resultados[2] as List<PagoPendiente>;
          porCobrar = saldo.isEmpty ? null : saldo.first;
          deHoy = delMes.where((d) => d.fecha == hoy).toList();
        }
      }, silencioso: silencioso);

  String? foto(String personalId) => rutas[personalId] == null ? null : fotos[rutas[personalId]];

  int contarHoy(bool Function(DiaAsistencia) f) => deHoy.where(f).length;
  Resumen get resumenMes => Resumen.de(delMes);
}
