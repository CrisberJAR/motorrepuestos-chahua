import '../../core/fechas.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../vm_base.dart';

enum ModoPeriodo { semana, mes }

class FilaTrabajador {
  final DiaAsistencia persona;
  final List<DiaAsistencia> dias;
  FilaTrabajador(this.persona, this.dias);
  Resumen get resumen => Resumen.de(dias);
}

class AsistenciaVm extends VmBase {
  final DatosRepositorio _repo;
  final Yo yo;
  AsistenciaVm(this._repo, this.yo);

  ModoPeriodo modo = ModoPeriodo.semana;
  String ancla = Fechas.hoy();
  List<FilaTrabajador> filas = [];
  Map<String, String> fotos = {};
  Map<String, String?> rutas = {};

  ({String desde, String hasta}) get rango => modo == ModoPeriodo.semana
      ? (desde: Fechas.inicioSemana(ancla), hasta: Fechas.sumarDias(Fechas.inicioSemana(ancla), 5))
      : Fechas.rangoMes(Fechas.periodoDe(ancla));

  String get etiqueta => modo == ModoPeriodo.semana
      ? '${Fechas.diaMes(rango.desde)} – ${Fechas.diaMes(rango.hasta)}'
      : Fechas.nombrePeriodo(Fechas.periodoDe(ancla));

  Resumen get totales => Resumen.de(filas.expand((f) => f.dias));

  Future<void> iniciar() async {
    await cargar();
    escucharCambios(_repo, ['asistencias', 'permisos'], () => cargar(silencioso: true));
  }

  Future<void> cargar({bool silencioso = false}) => cargarCon(() async {
        final r = rango;
        final dias = await _repo.detalle(r.desde, r.hasta, personalId: yo.esAdmin ? null : yo.id);
        final agrupado = <String, FilaTrabajador>{};
        for (final d in dias) {
          agrupado.putIfAbsent(d.personalId, () => FilaTrabajador(d, [])).dias.add(d);
        }
        filas = agrupado.values.toList();
        if (yo.esAdmin && rutas.isEmpty) {
          final personal = await _repo.personal(soloActivos: false);
          rutas = {for (final p in personal) p.id: p.fotoRostroUrl};
          fotos = await _repo.urlsFotos(rutas.values);
        }
      }, silencioso: silencioso);

  String? foto(String id) => rutas[id] == null ? null : fotos[rutas[id]];

  void cambiarModo(ModoPeriodo m) {
    modo = m;
    cargar();
  }

  void mover(int paso) {
    ancla = modo == ModoPeriodo.semana ? Fechas.sumarDias(ancla, paso * 7) : '${Fechas.sumarMeses(Fechas.periodoDe(ancla), paso)}-01';
    cargar();
  }

  void irAHoy() {
    ancla = Fechas.hoy();
    cargar();
  }
}
