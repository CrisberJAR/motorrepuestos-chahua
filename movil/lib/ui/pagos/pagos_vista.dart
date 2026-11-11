import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/fechas.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../comunes/perfil_boton.dart';
import '../comunes/reportes.dart';
import '../comunes/widgets.dart';
import '../sesion_vm.dart';
import 'pagos_vm.dart';

const _regla = 'Se suma lo ganado cada día asistido (pago fijo o monto por rendimiento) más los permisos con goce, más bonos y menos descuentos. '
    'Se puede pagar en cualquier momento: por semana, mes o días. Las tardanzas no descuentan; faltas y permisos sin goce no se pagan.';

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
            actions: [const BotonReportes(tipo: 'pagos'), if (!conAtras) const BotonPerfil()],
          ),
          body: RefreshIndicator(
            onRefresh: vm.cargar,
            child: yo.esAdmin ? _admin(context, vm) : _trabajador(context, vm),
          ),
        );
      }),
    );
  }

  /* ============================== ADMIN ============================== */
  Widget _admin(BuildContext context, PagosVm vm) {
    final c = Colores.de(context);
    return ListView(padding: rellenoLista(context), children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Por pagar'), icon: Icon(Icons.pending_actions_outlined)),
          ButtonSegment(value: true, label: Text('Realizados'), icon: Icon(Icons.history)),
        ],
        selected: {vm.verHistorial},
        onSelectionChanged: (v) => vm.cambiarVista(v.first),
      ),
      const SizedBox(height: 12),
      if (vm.error != null) ...[MensajeError(vm.error!, reintentar: vm.cargar), const SizedBox(height: 10)],
      if (vm.cargando && vm.pendientes.isEmpty && vm.realizados.isEmpty)
        const Cargando()
      else if (!vm.verHistorial) ...[
        GrillaKpis([
          Kpi('Total por pagar', Fechas.soles(vm.totalPendiente), color: vm.totalPendiente > 0 ? c.acento : null),
          Kpi('Pagado este mes', Fechas.soles(vm.pagadoMes), color: c.ok),
        ]),
        const SizedBox(height: 12),
        if (vm.pendientes.isEmpty) const Vacio('No hay trabajadores activos', icono: Icons.groups_outlined),
        for (final p in vm.pendientes) ...[_TarjetaPendiente(p: p, vm: vm), const SizedBox(height: 10)],
        Text(_regla, style: TextStyle(fontSize: 12, color: c.tenue)),
      ] else
        ..._historial(context, vm),
    ]);
  }

  List<Widget> _historial(BuildContext context, PagosVm vm) {
    final c = Colores.de(context);
    Future<void> elegir(bool inicio) async {
      final f = await showDatePicker(
        context: context,
        initialDate: Fechas.aFecha(inicio ? vm.histDesde : vm.histHasta),
        firstDate: DateTime(2024),
        lastDate: Fechas.aFecha(Fechas.hoy()),
      );
      if (f == null) return;
      final v = Fechas.iso(f);
      inicio
          ? vm.rangoHistorial(v, v.compareTo(vm.histHasta) > 0 ? v : vm.histHasta)
          : vm.rangoHistorial(vm.histDesde.compareTo(v) > 0 ? v : vm.histDesde, v);
    }

    return [
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () => elegir(true), icon: const Icon(Icons.event, size: 18), label: Text('Desde ${Fechas.diaMes(vm.histDesde)}'))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: () => elegir(false), icon: const Icon(Icons.event, size: 18), label: Text('Hasta ${Fechas.diaMes(vm.histHasta)}'))),
      ]),
      const SizedBox(height: 8),
      Text('${vm.realizados.length} pago(s) · ${Fechas.soles(vm.totalRealizados)}', style: TextStyle(color: c.tenue, fontSize: 13)),
      const SizedBox(height: 8),
      if (vm.realizados.isEmpty) const Vacio('No hay pagos en esas fechas', texto: 'Cambia el rango o registra un pago en "Por pagar".', icono: Icons.receipt_long_outlined),
      for (final p in vm.realizados) ...[_TarjetaPago(pago: p, foto: p.fotoRostroUrl == null ? null : vm.fotos[p.fotoRostroUrl], vm: vm), const SizedBox(height: 10)],
    ];
  }

  /* ============================== TRABAJADOR ============================== */
  Widget _trabajador(BuildContext context, PagosVm vm) {
    final c = Colores.de(context);
    final p = vm.miPendiente;
    return ListView(padding: rellenoLista(context), children: [
      if (vm.error != null) ...[MensajeError(vm.error!, reintentar: vm.cargar), const SizedBox(height: 10)],
      if (vm.cargando && p == null) const Cargando(),
      if (p != null)
        Tarjeta(
          titulo: 'Por cobrar',
          extra: ChipTipoPago(tipo: p.tipoPago, tarifa: p.pagoPorDia),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(Fechas.soles(p.monto), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
            ),
            Text(
              p.alDia ? 'Estás al día con tus pagos.' : 'Desde el ${Fechas.larga(p.desde)} hasta hoy · ${p.diasAPagar} día(s) · ${p.diasFalta} falta(s)',
              style: TextStyle(fontSize: 13, color: c.tenue),
            ),
            if (p.variable && p.diasSinMonto > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${p.diasSinMonto} día(s) aún sin monto de rendimiento: se muestran con ${Fechas.soles(p.pagoPorDia)} de referencia.',
                    style: TextStyle(fontSize: 12, color: c.tenue)),
              ),
            if (vm.misDias.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Detalle por día', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  children: [for (final d in vm.misDias) _FilaDia(dia: d, monto: d.pagable ? Fechas.soles(d.monto) : '—')],
                ),
              ),
          ]),
        ),
      const SizedBox(height: 16),
      const Text('PAGOS RECIBIDOS', style: TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      if (!vm.cargando && vm.misPagos.isEmpty) const Vacio('Todavía no tienes pagos registrados', icono: Icons.receipt_long_outlined),
      for (final pg in vm.misPagos) ...[_TarjetaPago(pago: pg), const SizedBox(height: 10)],
      Text(_regla, style: TextStyle(fontSize: 12, color: c.tenue)),
    ]);
  }
}

class _FilaDia extends StatelessWidget {
  final DiaPago dia;
  final String monto;
  final Widget? derecha;
  const _FilaDia({required this.dia, required this.monto, this.derecha});
  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    return Opacity(
      opacity: dia.pagado ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.linea))),
        child: Row(children: [
          SizedBox(width: 74, child: Text(Fechas.corta(dia.fecha), style: const TextStyle(fontSize: 13))),
          Expanded(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
              ChipDia(dia.estado),
              if (dia.pagado) Text('ya pagado', style: TextStyle(fontSize: 11, color: c.tenue)),
            ]),
          ),
          derecha ?? Text(monto, style: const TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

class _TarjetaPendiente extends StatelessWidget {
  final PagoPendiente p;
  final PagosVm vm;
  const _TarjetaPendiente({required this.p, required this.vm});

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AvatarPersona(iniciales: p.iniciales, url: p.fotoRostroUrl == null ? null : vm.fotos[p.fotoRostroUrl], tam: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.nombreCorto, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(p.cargo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.tenue)),
                const SizedBox(height: 4),
                ChipTipoPago(tipo: p.tipoPago, tarifa: p.pagoPorDia),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Fechas.soles(p.monto), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text('por pagar', style: TextStyle(fontSize: 11, color: c.tenue)),
            ]),
          ]),
          const SizedBox(height: 8),
          Text(
            p.alDia
                ? 'Al día.'
                : '${p.diasAPagar} día(s) desde el ${Fechas.diaMes(p.desde)} · ${p.diasFalta} falta(s) · ${p.tardanzas} tardanza(s)',
            style: TextStyle(fontSize: 12, color: c.tenue),
          ),
          Text(p.ultimoPagoHasta == null ? 'Sin pagos anteriores.' : 'Último pago cubrió hasta el ${Fechas.diaMes(p.ultimoPagoHasta!)}.',
              style: TextStyle(fontSize: 12, color: c.tenue)),
          if (p.variable && p.diasSinMonto > 0)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: c.alertaSuave, borderRadius: BorderRadius.circular(8)),
              child: Text('${p.diasSinMonto} día(s) sin monto de rendimiento: se calculan con ${Fechas.soles(p.pagoPorDia)} hasta que los registres.',
                  style: TextStyle(fontSize: 12, color: c.alerta)),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: c.ok, foregroundColor: c.superficie),
              onPressed: p.alDia ? null : () => _abrirPago(context, vm, p),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Registrar pago'),
            ),
          ),
        ]),
      ),
    );
  }

  void _abrirPago(BuildContext context, PagosVm vm, PagoPendiente p) {
    final repo = context.read<DatosRepositorio>();
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider(
        create: (_) => RegistrarPagoVm(repo, p)..cargarDias(),
        child: const _HojaPago(),
      ),
    ).then((pagado) {
      if (pagado == true) vm.cargar(silencioso: true);
    });
  }
}

/// Hoja para registrar un pago: periodo, monto de cada día (rendimiento), bonos, descuentos y método.
class _HojaPago extends StatelessWidget {
  const _HojaPago();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RegistrarPagoVm>();
    final c = Colores.de(context);
    final p = vm.pendiente;
    final formato = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    final sabadoPasado = Fechas.sumarDias(Fechas.inicioSemana(vm.hoy), -2);
    final finMesPasado = Fechas.sumarDias('${vm.hoy.substring(0, 7)}-01', -1);

    Future<void> elegir(bool inicio) async {
      final f = await showDatePicker(
        context: context,
        initialDate: Fechas.aFecha(inicio ? vm.desde : vm.hasta),
        firstDate: Fechas.aFecha(p.desde),
        lastDate: Fechas.aFecha(vm.hoy),
      );
      if (f == null) return;
      inicio ? vm.cambiarRango(nuevoDesde: Fechas.iso(f)) : vm.cambiarRango(nuevoHasta: Fechas.iso(f));
    }

    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(t.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.5, color: c.tenue)),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('PAGAR A ${p.nombreCorto.toUpperCase()}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChipTipoPago(tipo: p.tipoPago, tarifa: p.pagoPorDia),
            Text(p.ultimoPagoHasta == null ? 'Sin pagos anteriores' : 'Último pago hasta el ${Fechas.diaMes(p.ultimoPagoHasta!)}',
                style: TextStyle(fontSize: 12, color: c.tenue)),
          ]),
          titulo('Periodo a pagar'),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => elegir(true), child: Text('Desde ${Fechas.diaMes(vm.desde)}'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => elegir(false), child: Text('Hasta ${Fechas.diaMes(vm.hasta)}'))),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ActionChip(label: const Text('Hasta hoy'), onPressed: () => vm.cambiarRango(nuevoHasta: vm.hoy)),
            if (sabadoPasado.compareTo(p.desde) >= 0)
              ActionChip(label: Text('Hasta el sáb ${Fechas.diaMes(sabadoPasado)}'), onPressed: () => vm.cambiarRango(nuevoHasta: sabadoPasado)),
            if (finMesPasado.compareTo(p.desde) >= 0)
              ActionChip(label: const Text('Hasta fin del mes pasado'), onPressed: () => vm.cambiarRango(nuevoHasta: finMesPasado)),
          ]),
          titulo(p.variable ? 'Monto de cada día (rendimiento)' : 'Días del periodo'),
          if (vm.cargando)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (vm.dias.isEmpty)
            Text('Sin días en ese rango.', style: TextStyle(color: c.tenue))
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(border: Border.all(color: c.linea), borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ListView(shrinkWrap: true, children: [
                for (final d in vm.dias)
                  _FilaDia(
                    dia: d,
                    monto: d.pagable ? Fechas.soles(vm.montoDe(d)) : '—',
                    derecha: d.editable
                        ? SizedBox(
                            width: 92,
                            child: TextFormField(
                              key: ValueKey('${vm.desde}-${vm.hasta}-${d.fecha}'),
                              initialValue: vm.montos[d.fecha] ?? '',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: formato,
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(isDense: true, hintText: vm.tarifa.toStringAsFixed(2), prefixText: 'S/ '),
                              onChanged: (t) => vm.cambiar(() => vm.montos[d.fecha] = t),
                            ),
                          )
                        : null,
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              p.variable
                  ? 'Escribe lo que ganó cada día. Si dejas un día vacío se usa el monto de referencia.'
                  : 'Puedes cambiar el monto de un día si ese día ganó distinto. Vacío = pago por día normal.',
              style: TextStyle(fontSize: 12, color: c.tenue),
            ),
          ),
          titulo('Bonos y descuentos'),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: vm.bonos,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: formato,
                decoration: const InputDecoration(labelText: 'Bonos (S/)'),
                onChanged: (t) => vm.cambiar(() => vm.bonos = t),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                initialValue: vm.descuentos,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: formato,
                decoration: const InputDecoration(labelText: 'Descuentos (S/)'),
                onChanged: (t) => vm.cambiar(() => vm.descuentos = t),
              ),
            ),
          ]),
          titulo('Método de pago'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in metodosPago.entries) ChoiceChip(label: Text(m.value), selected: vm.metodo == m.key, onSelected: (_) => vm.cambiar(() => vm.metodo = m.key)),
          ]),
          if (vm.metodo != 'efectivo') ...[
            const SizedBox(height: 10),
            TextFormField(
              initialValue: vm.operacion,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'N° de operación (opcional)', counterText: ''),
              onChanged: (t) => vm.operacion = t,
            ),
          ],
          const SizedBox(height: 10),
          TextFormField(
            initialValue: vm.observacion,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Observación (opcional)', counterText: ''),
            onChanged: (t) => vm.observacion = t,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.hundido, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              _linea('${vm.pagables} día(s) a pagar', Fechas.soles(vm.base)),
              _linea('Bonos', '+ ${Fechas.soles(RegistrarPagoVm.numero(vm.bonos) ?? 0)}'),
              _linea('Descuentos', '- ${Fechas.soles(RegistrarPagoVm.numero(vm.descuentos) ?? 0)}'),
              const Divider(),
              Row(children: [
                const Expanded(child: Text('Total a pagar', style: TextStyle(fontWeight: FontWeight.w700))),
                Text(Fechas.soles(vm.total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: c.ok, foregroundColor: c.superficie, minimumSize: const Size.fromHeight(48)),
            onPressed: vm.guardando || vm.cargando
                ? null
                : () async {
                    final error = await vm.pagar();
                    if (!context.mounted) return;
                    if (error != null) {
                      mostrarAviso(context, error, error: true);
                    } else {
                      mostrarAviso(context, 'Pago de ${Fechas.soles(vm.total)} a ${p.nombreCorto} registrado (${metodosPago[vm.metodo]}).');
                      Navigator.pop(context, true);
                    }
                  },
            icon: vm.guardando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
            label: const Text('Confirmar pago'),
          ),
        ]),
      ),
    );
  }

  Widget _linea(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(a, style: const TextStyle(fontSize: 13))), Text(b, style: const TextStyle(fontSize: 13))]),
      );
}

/// Pago ya realizado (admin y trabajador).
class _TarjetaPago extends StatelessWidget {
  final Pago pago;
  final String? foto;
  final PagosVm? vm;
  const _TarjetaPago({required this.pago, this.foto, this.vm});

  Future<void> _anular(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular pago'),
        content: Text('Se anulará el pago de ${Fechas.soles(pago.total)} a ${pago.nombreCorto} (${Fechas.rango(pago.fechaDesde, pago.fechaHasta)}). '
            'Esos días volverán a figurar como pendientes. Úsalo solo si se registró por error.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Anular')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final e = await vm!.anular(pago);
    if (context.mounted) mostrarAviso(context, e ?? 'Pago anulado.', error: e != null);
  }

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final admin = vm != null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (admin) ...[AvatarPersona(iniciales: pago.iniciales, url: foto, tam: 34), const SizedBox(width: 10)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(admin ? pago.nombreCorto : Fechas.rango(pago.fechaDesde, pago.fechaHasta), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${admin ? '${Fechas.rango(pago.fechaDesde, pago.fechaHasta)} · ' : ''}${pago.diasPagados} día(s) · pagado ${pago.fechaPago == null ? '' : Fechas.diaMes(pago.fechaPago!)}',
                  style: TextStyle(fontSize: 12, color: c.tenue),
                ),
              ]),
            ),
            Text(Fechas.soles(pago.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Etiqueta(pago.metodoTexto, fondo: c.okSuave, color: c.ok),
            if (pago.numeroOperacion != null) Text('Op. ${pago.numeroOperacion}', style: TextStyle(fontSize: 12, color: c.tenue)),
            if (pago.bonos > 0 || pago.descuentos > 0)
              Text('Bonos ${Fechas.soles(pago.bonos)} · Desc. ${Fechas.soles(pago.descuentos)}', style: TextStyle(fontSize: 12, color: c.tenue)),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(onPressed: () => descargarComprobante(context, pago), icon: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('Comprobante')),
            if (admin) IconButton(tooltip: 'Anular pago', onPressed: () => _anular(context), icon: Icon(Icons.delete_outline, color: c.tenue)),
          ]),
        ]),
      ),
    );
  }
}
