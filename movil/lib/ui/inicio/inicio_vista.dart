import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/fechas.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../comunes/widgets.dart';
import '../sesion_vm.dart';
import 'inicio_vm.dart';

class InicioVista extends StatelessWidget {
  final VoidCallback? alEscanear, alVerPermisos, alVerPagos;
  const InicioVista({super.key, this.alEscanear, this.alVerPermisos, this.alVerPagos});

  @override
  Widget build(BuildContext context) {
    final yo = context.read<SesionVm>().yo!;
    return ChangeNotifierProvider(
      create: (ctx) => InicioVm(ctx.read<DatosRepositorio>(), yo)..iniciar(),
      child: Consumer<InicioVm>(builder: (context, vm, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(yo.esAdmin ? 'HOY' : 'HOLA, ${yo.nombres.split(' ').first.toUpperCase()}'),
            actions: [
              if (!yo.esAdmin)
                IconButton(tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout), onPressed: () => context.read<SesionVm>().salir()),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: vm.cargar,
            child: vm.cargando && vm.deHoy.isEmpty && vm.delMes.isEmpty
                ? ListView(children: const [Cargando()])
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      Text(Fechas.capitalizar(Fechas.larga(vm.hoy, anio: true)), style: TextStyle(color: Colores.de(context).tenue)),
                      const SizedBox(height: 12),
                      if (vm.error != null) ...[MensajeError(vm.error!, reintentar: vm.cargar), const SizedBox(height: 12)],
                      if (yo.esAdmin) ..._admin(context, vm) else ..._trabajador(context, vm, yo),
                    ],
                  ),
          ),
        );
      }),
    );
  }

  List<Widget> _admin(BuildContext context, InicioVm vm) {
    final c = Colores.de(context);
    final presentes = vm.contarHoy((d) => d.presente);
    final tardanzas = vm.contarHoy((d) => d.estado == EstadoDia.tardanza);
    final sinMarcar = vm.contarHoy((d) => d.estado == EstadoDia.pendiente);
    return [
      GrillaKpis([
        Kpi('Presentes', '$presentes/${vm.deHoy.length}'),
        Kpi('Tardanzas', '$tardanzas', color: tardanzas > 0 ? c.alerta : null),
        Kpi('Sin marcar', '$sinMarcar'),
        InkWell(
          onTap: alVerPermisos,
          borderRadius: BorderRadius.circular(12),
          child: Kpi('Permisos por revisar', '${vm.pendientes}', color: vm.pendientes > 0 ? c.acento : null),
        ),
      ]),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: vm.esDomingo ? null : alEscanear,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        icon: const Icon(Icons.face_retouching_natural, size: 26),
        label: Text(vm.esDomingo ? 'Domingo: no se marca asistencia' : 'Escanear rostro', style: const TextStyle(fontSize: 16)),
      ),
      const SizedBox(height: 14),
      Tarjeta(
        titulo: 'Marcaciones de hoy',
        extra: Text('Entrada 08:00 · tol. 10 min', style: TextStyle(fontSize: 11, color: c.tenue)),
        child: vm.deHoy.isEmpty
            ? const Vacio('Sin registros para hoy')
            : Column(children: [
                for (final d in vm.deHoy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      AvatarPersona(iniciales: d.iniciales, url: vm.foto(d.personalId)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.nombreCorto, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(d.cargo, style: TextStyle(fontSize: 12, color: c.tenue)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('${Fechas.horaCorta(d.horaEntrada)}${d.horaSalida != null ? ' – ${Fechas.horaCorta(d.horaSalida)}' : ''}',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        const SizedBox(height: 3),
                        ChipDia(d.estado),
                      ]),
                    ]),
                  ),
              ]),
      ),
    ];
  }

  List<Widget> _trabajador(BuildContext context, InicioVm vm, Yo yo) {
    final c = Colores.de(context);
    final hoy = vm.deHoy.isEmpty ? null : vm.deHoy.first;
    final r = vm.resumenMes;
    final texto = hoy == null
        ? 'Hoy es domingo: no es día laborable.'
        : hoy.estado == EstadoDia.pendiente
            ? 'Aún no tienes entrada registrada. El administrador la marca con tu rostro al llegar.'
            : hoy.estado == EstadoDia.permiso
                ? 'Hoy tienes permiso aprobado.'
                : 'Entrada ${Fechas.horaCorta(hoy.horaEntrada)}${hoy.horaSalida != null ? ' · salida ${Fechas.horaCorta(hoy.horaSalida)}' : ''}'
                    '${hoy.confianza != null ? ' · ${hoy.confianza!.toStringAsFixed(1)} % rostro' : ''}';
    return [
      Tarjeta(titulo: 'Hoy', extra: hoy == null ? null : ChipDia(hoy.estado), child: Text(texto)),
      const SizedBox(height: 14),
      Text(Fechas.nombrePeriodo(Fechas.periodoDe(vm.hoy)), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      GrillaKpis([
        Kpi('Días asistidos', '${r.asistidos}'),
        Kpi('Tardanzas', '${r.tardanzas}', color: r.tardanzas > 0 ? c.alerta : null, detalle: 'No descuentan'),
        Kpi('Permisos', '${r.permisos}'),
        Kpi('Faltas', '${r.faltas}', color: r.faltas > 0 ? c.peligro : null),
      ]),
      const SizedBox(height: 14),
      InkWell(
        onTap: alVerPagos,
        borderRadius: BorderRadius.circular(12),
        child: Tarjeta(
          titulo: 'Pago acumulado del mes',
          extra: const Icon(Icons.chevron_right),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Fechas.soles(vm.pagoAcumulado), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
            Text('(${r.asistidos} días${r.permisosPagados > 0 ? ' + ${r.permisosPagados} de permiso pagado' : ''}) × ${Fechas.soles(yo.pagoPorDia)}',
                style: TextStyle(fontSize: 12, color: c.tenue)),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Tarjeta(
        titulo: 'Mis permisos recientes',
        extra: TextButton(onPressed: alVerPermisos, child: const Text('Ver todos')),
        child: vm.permisos.isEmpty
            ? Text('Aún no tienes permisos registrados.', style: TextStyle(color: c.tenue))
            : Column(children: [
                for (final p in vm.permisos)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${tiposPermiso[p.tipo]} · ${Fechas.corta(p.fechaInicio)}${p.fechaFin != p.fechaInicio ? ' al ${Fechas.corta(p.fechaFin)}' : ''}'),
                    subtitle: Text(p.motivo, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: ChipPermiso(p.estado),
                  ),
              ]),
      ),
    ];
  }
}
