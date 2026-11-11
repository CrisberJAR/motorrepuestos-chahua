import 'package:flutter/material.dart';

/// Colores de Motorrepuestos Chahua (los mismos de la web).
class Colores {
  final Color fondo, superficie, hundido, tinta, tenue, linea, acento, acentoSuave, acentoTinta;
  final Color ok, okSuave, alerta, alertaSuave, peligro, peligroSuave, info, infoSuave, lateral, lateralTinta;

  const Colores({
    required this.fondo,
    required this.superficie,
    required this.hundido,
    required this.tinta,
    required this.tenue,
    required this.linea,
    required this.acento,
    required this.acentoSuave,
    required this.acentoTinta,
    required this.ok,
    required this.okSuave,
    required this.alerta,
    required this.alertaSuave,
    required this.peligro,
    required this.peligroSuave,
    required this.info,
    required this.infoSuave,
    required this.lateral,
    required this.lateralTinta,
  });

  static const claro = Colores(
    fondo: Color(0xFFECEEED),
    superficie: Color(0xFFFFFFFF),
    hundido: Color(0xFFF4F6F5),
    tinta: Color(0xFF17202A),
    tenue: Color(0xFF5A6572),
    linea: Color(0xFFD6DCDF),
    acento: Color(0xFFCF4510),
    acentoSuave: Color(0xFFFBE4D8),
    acentoTinta: Color(0xFFFFFFFF),
    ok: Color(0xFF2A7A4B),
    okSuave: Color(0xFFDCF0E3),
    alerta: Color(0xFF9A6200),
    alertaSuave: Color(0xFFFAEDD0),
    peligro: Color(0xFFBC2A2A),
    peligroSuave: Color(0xFFF8DCDC),
    info: Color(0xFF285FA6),
    infoSuave: Color(0xFFDCE7F6),
    lateral: Color(0xFF1B242E),
    lateralTinta: Color(0xFFD7DEE5),
  );

  static const oscuro = Colores(
    fondo: Color(0xFF101419),
    superficie: Color(0xFF191F27),
    hundido: Color(0xFF141A20),
    tinta: Color(0xFFE5E9EE),
    tenue: Color(0xFF97A1AE),
    linea: Color(0xFF2A323C),
    acento: Color(0xFFF06B30),
    acentoSuave: Color(0xFF3A2219),
    acentoTinta: Color(0xFF16110E),
    ok: Color(0xFF5CC38A),
    okSuave: Color(0xFF163023),
    alerta: Color(0xFFE3B04B),
    alertaSuave: Color(0xFF382C13),
    peligro: Color(0xFFF07474),
    peligroSuave: Color(0xFF3A1C1C),
    info: Color(0xFF73A9EE),
    infoSuave: Color(0xFF172739),
    lateral: Color(0xFF0B0F13),
    lateralTinta: Color(0xFFCDD5DE),
  );

  static Colores de(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? oscuro : claro;
}

ThemeData construirTema(Brightness brillo) {
  final c = brillo == Brightness.dark ? Colores.oscuro : Colores.claro;
  final esquema = ColorScheme.fromSeed(
    seedColor: c.acento,
    brightness: brillo,
    primary: c.acento,
    onPrimary: c.acentoTinta,
    surface: c.superficie,
    onSurface: c.tinta,
    error: c.peligro,
  );
  final borde = OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.linea));
  return ThemeData(
    useMaterial3: true,
    brightness: brillo,
    colorScheme: esquema,
    scaffoldBackgroundColor: c.fondo,
    dividerColor: c.linea,
    appBarTheme: AppBarTheme(
      backgroundColor: c.fondo,
      foregroundColor: c.tinta,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: c.tinta, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 0.2),
    ),
    cardTheme: CardThemeData(
      color: c.superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.linea)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.superficie,
      border: borde,
      enabledBorder: borde,
      focusedBorder: borde.copyWith(borderSide: BorderSide(color: c.acento, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: TextStyle(color: c.tenue),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.acento,
        foregroundColor: c.acentoTinta,
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.tinta,
        side: BorderSide(color: c.linea),
        minimumSize: const Size(0, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.superficie,
      indicatorColor: c.acentoSuave,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.acento : c.tenue)),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: s.contains(WidgetState.selected) ? c.acento : c.tenue),
      ),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: c.tinta, contentTextStyle: TextStyle(color: c.fondo)),
  );
}
