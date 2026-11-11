import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/fechas.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../comunes/widgets.dart';
import '../sesion_vm.dart';
import 'pagos_vm.dart';

const _regla = 'Cálculo: (días asistidos + días de permiso con goce) × pago por día − descuentos + bonos. '
    'Las tardanzas cuentan como asistidas y no descuentan. Faltas y permisos sin goce no se pagan.';

class PagosVista extends StatelessWidget {
  final bool conAtras;
  const PagosVista({super.key, this.conAtras = false});

  @override
  Widget build(BuildContext context) {
    final yo = context.read<SesionVm>().yo!;
    return ChangeNotifierProvider(
      create: (ctx) => PagosVm(ctx.read<DatosRepositorio>(), yo)..iniciar(),
      child: Consumer<PagosVm>(builder: (context, vm, _) {
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: conAtras,
            title: Text(yo.esAdmin ? 'PAGOS' : 'MI PAGO'),
            actions: [
              if (yo.esAdmin && vm.periodo.compareTo(vm.mesActual) <= 0)
                IconButton(
                  tooltip: 'Recalcular planilla',
                  icon: vm.ocupado == 'generar' ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                  onPressed: vm.ocupado != null
                      ? null
                      : () async {
                          final e = await vm.generar();
                          if (context.mounted) mostrarAviso(context, e ?? 'Planilla recalculada. Los pagos ya realizados no cambian.', error: e != null);
                        },
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: vm.cargar,
            child: yo.esAdmin ? _admin(context, vm) : _trabajador(context, vm),
          ),
        );
      }),
    );
  }

  Widget _admin(BuildContext context, PagosVm vm) {
    final c = Colores.de(context);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Row(children: [
        IconButton.outlined(tooltip: 'Mes anterior', onPressed: () => vm.mover(-1), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text('${Fechas.nombrePeriodo(vm.periodo)}${vm.periodo == vm.mesActual ? ' · en curso' : ''}',
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        IconButton.outlined(tooltip: 'Mes siguiente', onPressed: () => vm.mover(1), icon: const Icon(Icons.chevron_right)),
      ]),
      const SizedBox(height: 10),
      if (vm.error != null) ...[MensajeError(vm.error!, reintentar: vm.cargar), const SizedBox(height: 10)],
      if (vm.cargando && vm.pagos.isEmpty)
        const Cargando()
      else if (vm.pagos.isEmpty) ...[
        Vacio(vm.periodo.compareTo(vm.mesActual) > 0 ? 'Este mes aún no empieza' : 'No hay planilla para este mes', icono: Icons.receipt_long_outlined),
        if (vm.periodo.compareTo(vm.mesActual) <= 0)
          FilledButton(
            onPressed: vm.ocupado != null ? null : () => vm.generar(),
            child: const Text('Generar planilla'),
          ),
      ] else ...[
        GrillaKpis([
          Kpi('Total planilla', Fechas.soles(vm.total)),
          Kpi('Pagado', Fechas.soles(vm.pagado), color: c.ok),
          Kpi('Por pagar', Fechas.soles(vm.total - vm.pagado), color: vm.total > vm.pagado && vm.periodo != vm.mesActual ? c.acento : null),
          Kpi('Trabajadores', '${vm.pagos.length}'),
        ]),
        const SizedBox(height: 12),
        for (final p in vm.pagos) ...[_TarjetaPagoAdmin(pago: p, vm: vm), const SizedBox(height: 10)],
        Text(_regla, style: TextStyle(fontSize: 12, color: c.tenue)),
      ],
    ]);
  }

  Widget _trabajador(BuildContext context, PagosVm vm) {
    final c = Colores.de(context);
    final lista = vm.pagosTrabajador;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      if (vm.error != null) ...[MensajeError(vm.error!, reintentar: vm.cargar), const SizedBox(height: 10)],
      if (vm.cargando && lista.isEmpty) const Cargando(),
      for (final p in lista) ...[
        Tarjeta(
          titulo: '${Fechas.nombrePeriodo(p.periodo)}${p.periodo == vm.mesActual ? ' (hasta hoy)' : ''}',
          extra: _ChipPago(pago: p, mesActual: p.periodo == vm.mesActual),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(Fechas.soles(p.total), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            _fila(context, 'Días asistidos (${p.diasAsistidos} × ${Fechas.soles(p.pagoPorDia)})', Fechas.soles(p.diasAsistidos * p.pagoPorDia)),
            _fila(context, 'Permisos con goce (${p.diasPermisoPagado} de ${p.diasPermiso})', Fechas.soles(p.diasPermisoPagado * p.pagoPorDia)),
            _fila(context, 'Descuentos', '− ${Fechas.soles(p.descuentos)}'),
            _fila(context, 'Bonos', Fechas.soles(p.bonos)),
            _fila(context, 'Faltas · tardanzas', '${p.diasFalta} · ${p.tardanzas}', tenue: true),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      Text(_regla, style: TextStyle(fontSize: 12, color: c.tenue)),
    ]);
  }

  Widget _fila(BuildContext context, String a, String b, {bool tenue = false}) {
    final c = Colores.de(context);
    final estilo = TextStyle(fontSize: 13, color: tenue ? c.tenue : c.tinta);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.linea))),
      child: Row(children: [Expanded(child: Text(a, style: estilo)), Text(b, style: estilo)]),
    );
  }
}

class _ChipPago extends StatelessWidget {
  final Pago pago;
  final bool mesActual;
  const _ChipPago({required this.pago, required this.mesActual});
  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    if (pago.pagado) return Etiqueta('Pagado${pago.fechaPago != null ? ' ${Fechas.diaMes(pago.fechaPago!)}' : ''}', fondo: c.okSuave, color: c.ok);
    return mesActual ? Etiqueta('En curso', fondo: c.hundido, color: c.tenue) : Etiqueta('Por pagar', fondo: c.alertaSuave, color: c.alerta);
  }
}

class _TarjetaPagoAdmin extends StatelessWidget {
  final Pago pago;
  final PagosVm vm;
  const _TarjetaPagoAdmin({required this.pago, required this.vm});

  Future<void> _ajustar(BuildContext context) async {
    final desc = TextEditingController(text: pago.descuentos.toStringAsFixed(2));
    final bono = TextEditingController(text: pago.bonos.toStringAsFixed(2));
    final formato = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ajustes · ${pago.nombreCorto}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: desc, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: formato, decoration: const InputDecoration(labelText: 'Descuentos (S/)')),
          const SizedBox(height: 12),
          TextField(controller: bono, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: formato, decoration: const InputDecoration(labelText: 'Bonos (S/)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (guardar != true) return;
    final d = double.tryParse(desc.text), b = double.tryParse(bono.text);
    if (d == null || b == null || d < 0 || b < 0) {
      if (context.mounted) mostrarAviso(context, 'Ingresa montos válidos (0 o más).', error: true);
      return;
    }
    final e = await vm.actualizar(pago, {'descuentos': d, 'bonos': b});
    if (context.mounted) mostrarAviso(context, e ?? 'Ajustes guardados.', error: e != null);
  }

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final p = pago;
    final mesActual = p.periodo == vm.mesActual;
    final ocupado = vm.ocupado == p.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AvatarPersona(iniciales: '${p.nombres?[0] ?? ''}${p.apellidos?[0] ?? ''}', url: p.fotoRostroUrl == null ? null : vm.fotos[p.fotoRostroUrl], tam: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.nombreCorto, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('A${p.diasAsistidos} · P${p.diasPermisoPagado}/${p.diasPermiso} · F${p.diasFalta} · T${p.tardanzas} · ${Fechas.soles(p.pagoPorDia)}/día',
                    style: TextStyle(fontSize: 12, color: c.tenue)),
              ]),
            ),
            _ChipPago(pago: p, mesActual: mesActual),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Fechas.soles(p.total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                if (p.descuentos > 0 || p.bonos > 0)
                  Text('Base ${Fechas.soles(p.montoBase)} − ${Fechas.soles(p.descuentos)} + ${Fechas.soles(p.bonos)}', style: TextStyle(fontSize: 11, color: c.tenue)),
              ]),
            ),
            if (!p.pagado) IconButton(tooltip: 'Descuentos y bonos', onPressed: ocupado ? null : () => _ajustar(context), icon: const Icon(Icons.tune)),
            if (p.pagado)
              TextButton.icon(
                onPressed: ocupado
                    ? null
                    : () async {
                        final e = await vm.actualizar(p, {'estado_pago': 'pendiente'});
                        if (context.mounted) mostrarAviso(context, e ?? 'Pago revertido a pendiente.', error: e != null);
                      },
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Revertir'),
              )
            else if (!mesActual)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: c.ok, foregroundColor: c.superficie, minimumSize: const Size(0, 38)),
                onPressed: ocupado
                    ? null
                    : () async {
                        final e = await vm.actualizar(p, {'estado_pago': 'pagado'});
                        if (context.mounted) mostrarAviso(context, e ?? 'Pago de ${p.nombreCorto} marcado como pagado.', error: e != null);
                      },
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Pagado'),
              ),
          ]),
        ]),
      ),
    );
  }
}
