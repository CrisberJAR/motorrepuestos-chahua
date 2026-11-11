import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/fechas.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../sesion_vm.dart';

/// Descarga un reporte (PDF o Excel) desde el servidor, lo guarda en el celular y lo abre.
/// Si no hay una app para abrirlo, ofrece compartirlo (WhatsApp, Drive, correo…).
Future<void> descargarReporte(BuildContext context, Map<String, String> params) async {
  final ia = context.read<IaRepositorio>();
  final mensajero = ScaffoldMessenger.of(context);
  final c = Colores.de(context);
  mensajero
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Generando reporte…'), duration: Duration(seconds: 30)));
  try {
    final archivo = await ia.descargarReporte(params);
    final carpeta = await getApplicationDocumentsDirectory();
    final dir = Directory('${carpeta.path}/reportes');
    if (!await dir.exists()) await dir.create(recursive: true);
    final ruta = '${dir.path}/${archivo.nombre}';
    await File(ruta).writeAsBytes(archivo.bytes, flush: true);
    mensajero.hideCurrentSnackBar();
    final abierto = await OpenFilex.open(ruta);
    Future<void> compartir() => SharePlus.instance.share(ShareParams(files: [XFile(ruta)], subject: archivo.nombre)).then((_) {});
    if (abierto.type != ResultType.done) {
      await compartir();
      return;
    }
    mensajero.showSnackBar(SnackBar(
      content: Text('Reporte guardado: ${archivo.nombre}', style: TextStyle(color: c.fondo)),
      backgroundColor: c.tinta,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'Compartir', onPressed: compartir),
    ));
  } catch (e) {
    mensajero
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensajeDeError(e), style: const TextStyle(color: Colors.white)), backgroundColor: c.peligro));
  }
}

/// Botón que abre la hoja para elegir el reporte.
class BotonReportes extends StatelessWidget {
  final String tipo;
  const BotonReportes({super.key, this.tipo = 'asistencia'});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Descargar reporte',
        icon: const Icon(Icons.download_outlined),
        onPressed: () => abrirHojaReportes(context, tipo: tipo),
      );
}

void abrirHojaReportes(BuildContext context, {String tipo = 'asistencia'}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _HojaReportes(tipoInicial: tipo),
  );
}

class _HojaReportes extends StatefulWidget {
  final String tipoInicial;
  const _HojaReportes({required this.tipoInicial});
  @override
  State<_HojaReportes> createState() => _HojaReportesState();
}

class _HojaReportesState extends State<_HojaReportes> {
  late String _tipo = widget.tipoInicial;
  String _formato = 'pdf';
  String _rango = 'mes';
  final _hoy = Fechas.hoy();
  late String _desde = '${_hoy.substring(0, 7)}-01';
  late String _hasta = _hoy;
  String? _persona;
  List<Personal> _personal = [];

  @override
  void initState() {
    super.initState();
    if (context.read<SesionVm>().yo!.esAdmin) {
      context.read<DatosRepositorio>().personal().then((l) {
        if (mounted) setState(() => _personal = l);
      }).catchError((_) {});
    }
  }

  void _elegirRango(String r) {
    setState(() {
      _rango = r;
      if (r == 'semana') {
        _desde = Fechas.inicioSemana(_hoy);
        _hasta = _hoy;
      } else if (r == 'mes') {
        _desde = '${_hoy.substring(0, 7)}-01';
        _hasta = _hoy;
      } else if (r == 'anterior') {
        final fin = Fechas.sumarDias('${_hoy.substring(0, 7)}-01', -1);
        _desde = '${fin.substring(0, 7)}-01';
        _hasta = fin;
      }
    });
  }

  Future<void> _elegirFecha(bool inicio) async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: Fechas.aFecha(inicio ? _desde : _hasta),
      firstDate: DateTime(2024),
      lastDate: Fechas.aFecha(_hoy).add(const Duration(days: 366)),
      helpText: inicio ? 'Desde' : 'Hasta',
    );
    if (elegida == null) return;
    setState(() {
      _rango = 'libre';
      if (inicio) {
        _desde = Fechas.iso(elegida);
        if (_hasta.compareTo(_desde) < 0) _hasta = _desde;
      } else {
        _hasta = Fechas.iso(elegida);
        if (_desde.compareTo(_hasta) > 0) _desde = _hasta;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final yo = context.read<SesionVm>().yo!;
    Widget titulo(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(t.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.5, color: c.tenue)));

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('DESCARGAR REPORTE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          titulo('Reporte'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'asistencia', label: Text('Asistencia'), icon: Icon(Icons.calendar_month_outlined)),
              ButtonSegment(value: 'pagos', label: Text('Pagos'), icon: Icon(Icons.payments_outlined)),
            ],
            selected: {_tipo},
            onSelectionChanged: (v) => setState(() => _tipo = v.first),
          ),
          titulo('Periodo'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (v, t) in const [('semana', 'Esta semana'), ('mes', 'Este mes'), ('anterior', 'Mes anterior')])
              ChoiceChip(label: Text(t), selected: _rango == v, onSelected: (_) => _elegirRango(v)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(onPressed: () => _elegirFecha(true), icon: const Icon(Icons.event, size: 18), label: Text('Desde ${Fechas.diaMes(_desde)}')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(onPressed: () => _elegirFecha(false), icon: const Icon(Icons.event, size: 18), label: Text('Hasta ${Fechas.diaMes(_hasta)}')),
            ),
          ]),
          if (yo.esAdmin) ...[
            titulo('Trabajador'),
            DropdownButtonFormField<String?>(
              initialValue: _persona,
              isExpanded: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.groups_outlined)),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todo el personal')),
                for (final p in _personal) DropdownMenuItem(value: p.id, child: Text(p.nombreCorto)),
              ],
              onChanged: (v) => setState(() => _persona = v),
            ),
          ],
          titulo('Formato'),
          Row(children: [
            for (final (v, t, d, i) in const [
              ('pdf', 'PDF', 'Para imprimir o enviar', Icons.picture_as_pdf_outlined),
              ('xlsx', 'Excel', 'Para editar y filtrar', Icons.grid_on_outlined),
            ]) ...[
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _formato = v),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _formato == v ? c.acentoSuave : null,
                      border: Border.all(color: _formato == v ? c.acento : c.linea),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Icon(i, color: _formato == v ? c.acento : c.tenue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(d, style: TextStyle(fontSize: 11, color: c.tenue)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              if (v == 'pdf') const SizedBox(width: 8),
            ],
          ]),
          if (!yo.esAdmin) Padding(padding: const EdgeInsets.only(top: 10), child: Text('El reporte incluye solo tu información.', style: TextStyle(fontSize: 12, color: c.tenue))),
          const SizedBox(height: 18),
          FilledButton.icon(
            icon: const Icon(Icons.download),
            label: Text('Descargar ${_formato == 'pdf' ? 'PDF' : 'Excel'}'),
            onPressed: () {
              final params = {'tipo': _tipo, 'formato': _formato, 'desde': _desde, 'hasta': _hasta, 'personal_id': ?_persona};
              final raiz = Navigator.of(context);
              final ctx = raiz.context;
              raiz.pop();
              descargarReporte(ctx, params);
            },
          ),
        ]),
      ),
    );
  }
}

/// Comprobante PDF de un pago.
void descargarComprobante(BuildContext context, Pago pago) => descargarReporte(context, {'tipo': 'comprobante', 'formato': 'pdf', 'id': pago.id});
