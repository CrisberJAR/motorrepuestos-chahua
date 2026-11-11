import '../../core/fechas.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../vm_base.dart';

/// Pagos con rango libre: el administrador paga cuando el trabajador lo pide
/// (semana, mes o días). Lo pendiente se calcula en vivo con la asistencia.
class PagosVm extends VmBase {
  final DatosRepositorio _repo;
  final Yo yo;
  PagosVm(this._repo, this.yo);

  // Admin
  bool verHistorial = false;
  List<PagoPendiente> pendientes = [];
  List<Pago> realizados = [];
  final String _hoy = Fechas.hoy();
  late String histDesde = '${Fechas.sumarDias('${_hoy.substring(0, 7)}-01', -1).substring(0, 7)}-01';
  late String histHasta = _hoy;
  double pagadoMes = 0;
  Map<String, String> fotos = {};

  // Trabajador
  PagoPendiente? miPendiente;
  List<DiaPago> misDias = [];
  List<Pago> misPagos = [];

  double get totalPendiente => pendientes.fold(0, (s, p) => s + p.monto);
  int get conSaldo => pendientes.where((p) => p.monto > 0).length;
  double get totalRealizados => realizados.fold(0, (s, p) => s + p.total);

  Future<void> iniciar() async {
    await cargar();
    escucharCambios(_repo, ['pagos', 'asistencias', 'permisos'], () => cargar(silencioso: true));
  }

  Future<void> cargar({bool silencioso = false}) => cargarCon(() async {
        if (yo.esAdmin) {
          final mesDesde = '${_hoy.substring(0, 7)}-01';
          final r = await Future.wait([_repo.pagosPendientes(), _repo.pagosRealizados(histDesde, histHasta), _repo.pagosRealizados(mesDesde, _hoy)]);
          pendientes = r[0] as List<PagoPendiente>;
          realizados = r[1] as List<Pago>;
          pagadoMes = (r[2] as List<Pago>).fold(0, (s, p) => s + p.total);
          fotos = await _repo.urlsFotos([...pendientes.map((p) => p.fotoRostroUrl), ...realizados.map((p) => p.fotoRostroUrl)]);
        } else {
          final r = await Future.wait([_repo.pagosPendientes(personalId: yo.id), _repo.pagosDe(yo.id)]);
          final lista = r[0] as List<PagoPendiente>;
          miPendiente = lista.isEmpty ? null : lista.first;
          misPagos = r[1] as List<Pago>;
          final p = miPendiente;
          misDias = p == null || p.alDia ? [] : await _repo.detallePago(yo.id, p.desde, p.hasta);
        }
      }, silencioso: silencioso);

  void cambiarVista(bool historial) {
    verHistorial = historial;
    avisar();
  }

  void rangoHistorial(String desde, String hasta) {
    histDesde = desde;
    histHasta = hasta;
    cargar();
  }

  Future<String?> anular(Pago p) async {
    try {
      await _repo.anularPago(p.id);
      await cargar(silencioso: true);
      return null;
    } catch (e) {
      return mensajeDeError(e);
    }
  }
}

/// Estado de la hoja "Registrar pago" (un trabajador, un rango).
class RegistrarPagoVm extends VmBase {
  final DatosRepositorio _repo;
  final PagoPendiente pendiente;
  RegistrarPagoVm(this._repo, this.pendiente) : desde = pendiente.desde;

  final String hoy = Fechas.hoy();
  String desde;
  late String hasta = hoy;
  List<DiaPago> dias = [];
  final Map<String, String> montos = {};
  String bonos = '0', descuentos = '0', metodo = 'efectivo', operacion = '', observacion = '';
  bool guardando = false;

  double get tarifa => pendiente.pagoPorDia;

  static double? numero(String t) {
    final v = double.tryParse(t.trim().replaceAll(',', '.'));
    return v == null ? null : (v * 100).roundToDouble() / 100;
  }

  double montoDe(DiaPago d) {
    if (!d.pagable) return 0;
    if (d.estado == EstadoDia.permiso) return tarifa;
    final t = montos[d.fecha];
    return (t == null || t.trim().isEmpty) ? tarifa : (numero(t) ?? tarifa);
  }

  double get base => dias.fold(0, (s, d) => s + montoDe(d));
  int get pagables => dias.where((d) => d.pagable).length;
  int get yaPagados => dias.where((d) => d.pagado).length;
  double get total => (base + (numero(bonos) ?? 0) - (numero(descuentos) ?? 0)).clamp(0, double.infinity).toDouble();

  Future<void> cargarDias() => cargarCon(() async {
        dias = hasta.compareTo(desde) < 0 ? [] : await _repo.detallePago(pendiente.personalId, desde, hasta);
        montos
          ..clear()
          ..addAll({for (final d in dias.where((d) => d.montoDia != null)) d.fecha: d.montoDia!.toStringAsFixed(2)});
      });

  void cambiarRango({String? nuevoDesde, String? nuevoHasta}) {
    if (nuevoDesde != null) desde = nuevoDesde;
    if (nuevoHasta != null) hasta = nuevoHasta;
    if (hasta.compareTo(desde) < 0) hasta = desde;
    cargarDias();
  }

  void cambiar(void Function() f) {
    f();
    avisar();
  }

  /// Guarda los montos por día que cambiaron y registra el pago. Devuelve un error o null.
  Future<String?> pagar() async {
    if (yaPagados > 0) return 'El periodo incluye días ya pagados. Empieza desde el día siguiente al último pago.';
    if (pagables == 0) return 'No hay días por pagar en ese periodo.';
    final b = numero(bonos.isEmpty ? '0' : bonos), d = numero(descuentos.isEmpty ? '0' : descuentos);
    if (b == null || d == null || b < 0 || d < 0) return 'Bonos y descuentos deben ser 0 o más.';
    final cambios = <Map<String, dynamic>>[];
    for (final dia in dias.where((x) => x.editable)) {
      final t = (montos[dia.fecha] ?? '').trim();
      if (t.isEmpty) {
        if (dia.montoDia != null) cambios.add({'fecha': dia.fecha, 'monto': null});
      } else {
        final v = numero(t);
        if (v == null || v < 0) return 'El monto del ${Fechas.diaMes(dia.fecha)} no es válido.';
        if (v != dia.montoDia) cambios.add({'fecha': dia.fecha, 'monto': v});
      }
    }
    guardando = true;
    avisar();
    try {
      if (cambios.isNotEmpty) await _repo.fijarMontos(pendiente.personalId, cambios);
      await _repo.registrarPago(
        personalId: pendiente.personalId,
        desde: desde,
        hasta: hasta,
        metodo: metodo,
        bonos: b,
        descuentos: d,
        operacion: metodo == 'efectivo' || operacion.trim().isEmpty ? null : operacion.trim(),
        observacion: observacion.trim().isEmpty ? null : observacion.trim(),
      );
      return null;
    } catch (e) {
      return mensajeDeError(e);
    } finally {
      guardando = false;
      avisar();
    }
  }
}
