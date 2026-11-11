import '../../core/fechas.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../vm_base.dart';

class PagosVm extends VmBase {
  final DatosRepositorio _repo;
  final Yo yo;
  PagosVm(this._repo, this.yo);

  final String mesActual = Fechas.periodoDe(Fechas.hoy());
  late String periodo = mesActual;
  List<Pago> pagos = [];
  Map<String, String> fotos = {};
  String? ocupado;
  String? _recalculado;

  // Trabajador: mes en curso calculado en vivo.
  Resumen? resumenVivo;

  double get total => pagos.fold(0, (s, p) => s + p.total);
  double get pagado => pagos.where((p) => p.pagado).fold(0, (s, p) => s + p.total);

  Future<void> iniciar() async {
    await cargar();
    escucharCambios(_repo, yo.esAdmin ? ['pagos'] : ['pagos', 'asistencias', 'permisos'], () => cargar(silencioso: true));
  }

  Future<void> cargar({bool silencioso = false}) => cargarCon(() async {
        if (yo.esAdmin) {
          // El mes en curso se recalcula una vez al abrirlo (no en cada aviso de tiempo real).
          if (periodo == mesActual && _recalculado != periodo) {
            _recalculado = periodo;
            await _repo.generarPlanilla(periodo);
          }
          pagos = await _repo.pagosDelPeriodo(periodo);
          fotos = await _repo.urlsFotos(pagos.map((p) => p.fotoRostroUrl));
        } else {
          final mes = Fechas.rangoMes(mesActual);
          final resultados = await Future.wait([_repo.pagosDe(yo.id), _repo.detalle(mes.desde, mes.hasta, personalId: yo.id)]);
          pagos = resultados[0] as List<Pago>;
          resumenVivo = Resumen.de(resultados[1] as List<DiaAsistencia>);
        }
      }, silencioso: silencioso);

  void mover(int paso) {
    periodo = Fechas.sumarMeses(periodo, paso);
    pagos = [];
    cargar();
  }

  Future<String?> generar() async {
    ocupado = 'generar';
    avisar();
    try {
      await _repo.generarPlanilla(periodo);
      await cargar(silencioso: true);
      return null;
    } catch (e) {
      return mensajeDeError(e);
    } finally {
      ocupado = null;
      avisar();
    }
  }

  Future<String?> actualizar(Pago p, Map<String, dynamic> cambios) async {
    ocupado = p.id;
    avisar();
    try {
      await _repo.actualizarPago(p.id, cambios);
      await cargar(silencioso: true);
      return null;
    } catch (e) {
      return mensajeDeError(e);
    } finally {
      ocupado = null;
      avisar();
    }
  }

  /// Lista para el trabajador: mes en curso en vivo + meses anteriores guardados.
  List<Pago> get pagosTrabajador {
    final r = resumenVivo;
    if (r == null) return pagos;
    final guardado = pagos.where((p) => p.periodo == mesActual).firstOrNull;
    final base = (r.asistidos + r.permisosPagados) * yo.pagoPorDia;
    final descuentos = guardado?.descuentos ?? 0;
    final bonos = guardado?.bonos ?? 0;
    final vivo = Pago(
      id: 'vivo',
      personalId: yo.id,
      periodo: mesActual,
      estadoPago: guardado?.estadoPago ?? 'pendiente',
      diasAsistidos: r.asistidos,
      diasPermiso: r.permisos,
      diasPermisoPagado: r.permisosPagados,
      diasFalta: r.faltas,
      tardanzas: r.tardanzas,
      pagoPorDia: yo.pagoPorDia,
      montoBase: base,
      descuentos: descuentos,
      bonos: bonos,
      total: (base - descuentos + bonos).clamp(0, double.infinity).toDouble(),
      fechaPago: guardado?.fechaPago,
    );
    return [vivo, ...pagos.where((p) => p.periodo != mesActual)];
  }
}
