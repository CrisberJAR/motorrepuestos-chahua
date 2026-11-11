import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../data/modelos.dart';

Color colorDia(BuildContext context, EstadoDia e, {bool suave = false}) {
  final c = Colores.de(context);
  switch (e) {
    case EstadoDia.asistio:
      return suave ? c.okSuave : c.ok;
    case EstadoDia.tardanza:
      return suave ? c.alertaSuave : c.alerta;
    case EstadoDia.falta:
      return suave ? c.peligroSuave : c.peligro;
    case EstadoDia.permiso:
      return suave ? c.infoSuave : c.info;
    case EstadoDia.pendiente:
    case EstadoDia.futuro:
      return suave ? c.hundido : c.linea;
  }
}

class Etiqueta extends StatelessWidget {
  final String texto;
  final Color fondo, color;
  const Etiqueta(this.texto, {super.key, required this.fondo, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(99)),
        child: Text(texto, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class ChipDia extends StatelessWidget {
  final EstadoDia estado;
  const ChipDia(this.estado, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final color = estado == EstadoDia.pendiente || estado == EstadoDia.futuro ? c.tenue : colorDia(context, estado);
    return Etiqueta(etiquetaDia[estado]!, fondo: colorDia(context, estado, suave: true), color: color);
  }
}

class ChipPermiso extends StatelessWidget {
  final String estado;
  const ChipPermiso(this.estado, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final (fondo, color) = switch (estado) {
      'aprobado' => (c.okSuave, c.ok),
      'rechazado' => (c.peligroSuave, c.peligro),
      _ => (c.alertaSuave, c.alerta),
    };
    return Etiqueta('${estado[0].toUpperCase()}${estado.substring(1)}', fondo: fondo, color: color);
  }
}

class Tarjeta extends StatelessWidget {
  final Widget child;
  final String? titulo;
  final Widget? extra;
  final EdgeInsets padding;
  const Tarjeta({super.key, required this.child, this.titulo, this.extra, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (titulo != null || extra != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    if (titulo != null) Expanded(child: Text(titulo!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                    ?extra,
                  ]),
                ),
              child,
            ],
          ),
        ),
      );
}

class Kpi extends StatelessWidget {
  final String etiqueta, valor;
  final Color? color;
  final String? detalle;
  const Kpi(this.etiqueta, this.valor, {super.key, this.color, this.detalle});

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(etiqueta.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, letterSpacing: 0.5, color: c.tenue)),
          // El valor se achica si no entra (montos grandes o letra del celular aumentada) en vez de encimarse.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, maxLines: 1, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color ?? c.tinta, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          if (detalle != null) Text(detalle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.tenue)),
        ]),
      ),
    );
  }
}

/// Indicadores en dos columnas. Cada fila toma la altura de su contenido (no hay alto fijo que se desborde).
class GrillaKpis extends StatelessWidget {
  final List<Widget> hijos;
  const GrillaKpis(this.hijos, {super.key});
  @override
  Widget build(BuildContext context) {
    final filas = <Widget>[];
    for (var i = 0; i < hijos.length; i += 2) {
      if (filas.isNotEmpty) filas.add(const SizedBox(height: 10));
      filas.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: hijos[i]),
          const SizedBox(width: 10),
          Expanded(child: i + 1 < hijos.length ? hijos[i + 1] : const SizedBox()),
        ]),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: filas);
  }
}

/// Relleno de una lista que deja libre la barra de navegación del sistema (Android 15 dibuja la app detrás de ella).
EdgeInsets rellenoLista(BuildContext context, {double lados = 16, double arriba = 0, double abajo = 24}) =>
    EdgeInsets.fromLTRB(lados, arriba, lados, abajo + MediaQuery.paddingOf(context).bottom);

/// Etiqueta del tipo de pago de un trabajador.
class ChipTipoPago extends StatelessWidget {
  final String tipo;
  final double tarifa;
  const ChipTipoPago({super.key, required this.tipo, required this.tarifa});
  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    return tipo == 'variable'
        ? Etiqueta('Por rendimiento', fondo: c.infoSuave, color: c.info)
        : Etiqueta('Fijo S/ ${tarifa.toStringAsFixed(2)}/día', fondo: c.hundido, color: c.tenue);
  }
}


class AvatarPersona extends StatelessWidget {
  final String iniciales;
  final String? url;
  final double tam;
  const AvatarPersona({super.key, required this.iniciales, this.url, this.tam = 38});

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    return CircleAvatar(
      radius: tam / 2,
      backgroundColor: c.acentoSuave,
      foregroundImage: url != null ? NetworkImage(url!) : null,
      child: Text(iniciales, style: TextStyle(color: c.acento, fontWeight: FontWeight.w800, fontSize: tam * 0.32)),
    );
  }
}

class Cargando extends StatelessWidget {
  const Cargando({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
}

class Vacio extends StatelessWidget {
  final String titulo;
  final String? texto;
  final IconData icono;
  const Vacio(this.titulo, {super.key, this.texto, this.icono = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(children: [
        Icon(icono, size: 36, color: c.tenue),
        const SizedBox(height: 8),
        Text(titulo, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (texto != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(texto!, textAlign: TextAlign.center, style: TextStyle(color: c.tenue, fontSize: 13))),
      ]),
    );
  }
}

class MensajeError extends StatelessWidget {
  final String texto;
  final VoidCallback? reintentar;
  const MensajeError(this.texto, {super.key, this.reintentar});

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.peligroSuave, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(Icons.error_outline, color: c.peligro),
        const SizedBox(width: 10),
        Expanded(child: Text(texto, style: TextStyle(color: c.peligro, fontSize: 13))),
        if (reintentar != null) TextButton(onPressed: reintentar, child: const Text('Reintentar')),
      ]),
    );
  }
}

/// Fila de cuadritos de colores (un cuadro por día).
class TiraDias extends StatelessWidget {
  final List<DiaAsistencia> dias;
  const TiraDias(this.dias, {super.key});
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 3,
        runSpacing: 3,
        children: [
          for (final d in dias)
            Tooltip(
              message: '${d.fecha}: ${etiquetaDia[d.estado]}',
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: d.estado == EstadoDia.pendiente ? null : colorDia(context, d.estado),
                  border: d.estado == EstadoDia.pendiente ? Border.all(color: Colores.de(context).tenue) : null,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      );
}

class Leyenda extends StatelessWidget {
  const Leyenda({super.key});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 12, runSpacing: 4, children: [
        for (final e in [EstadoDia.asistio, EstadoDia.tardanza, EstadoDia.permiso, EstadoDia.falta])
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: colorDia(context, e), borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 5),
            Text(etiquetaDia[e]!, style: TextStyle(fontSize: 12, color: Colores.de(context).tenue)),
          ]),
      ]);
}

void mostrarAviso(BuildContext context, String texto, {bool error = false}) {
  final c = Colores.de(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(texto, style: TextStyle(color: error ? Colors.white : c.fondo)),
      backgroundColor: error ? c.peligro : c.tinta,
    ));
}
