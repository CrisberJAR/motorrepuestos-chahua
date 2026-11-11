import 'package:intl/intl.dart';

/// Fechas en hora de Lima (UTC−5, Perú no usa horario de verano), en formato AAAA-MM-DD.
class Fechas {
  static const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  static const _diasCortos = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  static const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'setiembre', 'octubre', 'noviembre', 'diciembre'];
  static const _mesesCortos = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];

  static String _p2(int n) => n.toString().padLeft(2, '0');

  static DateTime ahoraLima() => DateTime.now().toUtc().subtract(const Duration(hours: 5));
  static String iso(DateTime d) => '${d.year}-${_p2(d.month)}-${_p2(d.day)}';
  static String hoy() => iso(ahoraLima());

  static DateTime aFecha(String iso) {
    final p = iso.split('-').map(int.parse).toList();
    return DateTime.utc(p[0], p[1], p[2]);
  }

  static String sumarDias(String fecha, int dias) => iso(aFecha(fecha).add(Duration(days: dias)));

  /// 1 = lunes … 7 = domingo
  static int diaSemana(String fecha) => aFecha(fecha).weekday;
  static String inicioSemana(String fecha) => sumarDias(fecha, -(diaSemana(fecha) - 1));

  static String periodoDe(String fecha) => fecha.substring(0, 7);

  static String sumarMeses(String periodo, int meses) {
    final p = periodo.split('-').map(int.parse).toList();
    final d = DateTime.utc(p[0], p[1] + meses, 1);
    return '${d.year}-${_p2(d.month)}';
  }

  static ({String desde, String hasta}) rangoMes(String periodo) {
    final p = periodo.split('-').map(int.parse).toList();
    final fin = DateTime.utc(p[0], p[1] + 1, 0);
    return (desde: '$periodo-01', hasta: iso(fin));
  }

  static List<String> ultimosLaborables(String hasta, int n) {
    final dias = <String>[];
    for (var d = hasta; dias.length < n; d = sumarDias(d, -1)) {
      if (diaSemana(d) != 7) dias.insert(0, d);
    }
    return dias;
  }

  /// "lunes 9 de noviembre"
  static String larga(String fecha, {bool anio = false}) {
    final d = aFecha(fecha);
    return '${_dias[d.weekday - 1]} ${d.day} de ${_meses[d.month - 1]}${anio ? ' de ${d.year}' : ''}';
  }

  /// "lun 9 nov"
  static String corta(String fecha) {
    final d = aFecha(fecha);
    return '${_diasCortos[d.weekday - 1]} ${d.day} ${_mesesCortos[d.month - 1]}';
  }

  /// "9 nov"
  static String diaMes(String fecha) {
    final d = aFecha(fecha);
    return '${d.day} ${_mesesCortos[d.month - 1]}';
  }

  /// "Noviembre 2026"
  static String nombrePeriodo(String periodo) {
    final p = periodo.split('-').map(int.parse).toList();
    final m = _meses[p[1] - 1];
    return '${m[0].toUpperCase()}${m.substring(1)} ${p[0]}';
  }

  /// '1 nov – 7 nov' (o '3 nov' si es un solo día)
  static String rango(String desde, String hasta) => desde == hasta ? diaMes(desde) : '${diaMes(desde)} – ${diaMes(hasta)}';

  static String horaCorta(String? hora) => hora == null ? '--:--' : hora.substring(0, 5);

  static String capitalizar(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static final _moneda = NumberFormat('#,##0.00', 'en_US');
  static String soles(num n) => 'S/ ${_moneda.format(n)}';
}
