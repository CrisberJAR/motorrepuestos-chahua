import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/fechas.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../comunes/widgets.dart';
import '../comunes/perfil_boton.dart';
import '../comunes/reportes.dart';
import '../sesion_vm.dart';
import 'asistencia_vm.dart';

/// Monitoreo semanal y mensual: el admin ve a todos; el trabajador, solo lo suyo.
class AsistenciaVista extends StatelessWidget {
  const AsistenciaVista({super.key});

  @override
  Widget build(BuildContext context) {
    final yo = context.read<SesionVm>().yo!;
    return ChangeNotifierProvider(
      create: (ctx) => AsistenciaVm(ctx.read<DatosRepositorio>(), yo)..iniciar(),
      child: Consumer<AsistenciaVm>(builder: (context, vm, _) {
        final r = vm.totales;
        final c = Colores.de(context);
        return Scaffold(
          appBar: AppBar(title: Text(yo.esAdmin ? 'ASISTENCIA' : 'MI ASISTENCIA'), actions: const [BotonReportes(tipo: 'asistencia'), BotonPerfil()]),
          body: RefreshIndicator(
            onRefresh: vm.cargar,
            child: ListView(padding: rellenoLista(context, abajo: 24), children: [
              SegmentedButton<ModoPeriodo>(
                segments: const [
                  ButtonSegment(value: ModoPeriodo.semana, label: Text('Semana'), icon: Icon(Icons.view_week_outlined)),
                  ButtonSegment(value: ModoPeriodo.mes, label: Text('Mes'), icon: Icon(Icons.calendar_month_outlined)),
                ],
                selected: {vm.modo},
                onSelectionChanged: (s) => vm.cambiarModo(s.first),
              ),
              const SizedBox(height: 10),
              Row(children: [
                IconButton.outlined(tooltip: 'Anterior', onPressed: () => vm.mover(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(child: Text(vm.etiqueta, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton.outlined(tooltip: 'Siguiente', onPressed: () => vm.mover(1), icon: const Icon(Icons.chevron_right)),
                TextButton(onPressed: vm.irAHoy, child: const Text('Hoy')),
              ]),
              const SizedBox(height: 10),
              if (vm.error != null) ...[MensajeError(vm.error!, reintentar: vm.cargar), const SizedBox(height: 10)],
              if (vm.cargando && vm.filas.isEmpty)
                const Cargando()
              else ...[
                GrillaKpis([
                  Kpi('Días asistidos', '${r.asistidos}'),
                  Kpi('Tardanzas', '${r.tardanzas}', color: r.tardanzas > 0 ? c.alerta : null),
                  Kpi('Permisos', '${r.permisos}'),
                  Kpi('Faltas', '${r.faltas}', color: r.faltas > 0 ? c.peligro : null),
                ]),
                const SizedBox(height: 12),
                if (!yo.esAdmin && vm.filas.isNotEmpty)
                  DetalleTrabajador(fila: vm.filas.first, modo: vm.modo)
                else
                  for (final f in vm.filas) ...[
                    _TarjetaTrabajador(fila: f, foto: vm.foto(f.persona.personalId), modo: vm.modo),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 6),
                const Leyenda(),
              ],
            ]),
          ),
        );
      }),
    );
  }
}

class _TarjetaTrabajador extends StatelessWidget {
  final FilaTrabajador fila;
  final String? foto;
  final ModoPeriodo modo;
  const _TarjetaTrabajador({required this.fila, required this.foto, required this.modo});

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final r = fila.resumen;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(fila.persona.nombreCorto.toUpperCase())),
            body: ListView(padding: rellenoLista(context, arriba: 16), children: [
              Text('${fila.persona.cargo} · DNI ${fila.persona.dni}', style: TextStyle(color: c.tenue)),
              const SizedBox(height: 12),
              DetalleTrabajador(fila: fila, modo: modo),
              const SizedBox(height: 10),
              const Leyenda(),
            ]),
          ),
        )),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AvatarPersona(iniciales: fila.persona.iniciales, url: foto, tam: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fila.persona.nombreCorto, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(fila.persona.cargo, style: TextStyle(fontSize: 12, color: c.tenue)),
                ]),
              ),
              Text('A${r.asistidos} T${r.tardanzas} P${r.permisos} F${r.faltas}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const Icon(Icons.chevron_right, size: 18),
            ]),
            const SizedBox(height: 10),
            TiraDias(fila.dias),
          ]),
        ),
      ),
    );
  }
}

/// Lista de la semana o calendario del mes de un trabajador.
class DetalleTrabajador extends StatelessWidget {
  final FilaTrabajador fila;
  final ModoPeriodo modo;
  const DetalleTrabajador({super.key, required this.fila, required this.modo});

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    if (modo == ModoPeriodo.semana) {
      return Card(
        child: Column(children: [
          for (final d in fila.dias)
            ListTile(
              title: Text(Fechas.capitalizar(Fechas.larga(d.fecha)), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                d.horaEntrada != null
                    ? 'Entrada ${Fechas.horaCorta(d.horaEntrada)}${d.horaSalida != null ? ' · salida ${Fechas.horaCorta(d.horaSalida)}' : ''}'
                    : switch (d.estado) {
                        EstadoDia.permiso => 'Permiso aprobado${d.permisoConGoce ? ' (con goce)' : ''}',
                        EstadoDia.futuro => 'Día por venir',
                        EstadoDia.pendiente => 'Esperando marcación',
                        _ => 'Sin entrada registrada',
                      },
              ),
              trailing: d.estado == EstadoDia.futuro ? null : ChipDia(d.estado),
            ),
        ]),
      );
    }
    final desfase = fila.dias.isEmpty ? 0 : Fechas.diaSemana(fila.dias.first.fecha) - 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
          childAspectRatio: 0.95,
          children: [
            for (final d in ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'])
              Center(child: Text(d, style: TextStyle(fontSize: 11, color: c.tenue, fontWeight: FontWeight.w600))),
            for (var i = 0; i < desfase; i++) const SizedBox(),
            for (final d in fila.dias)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colorDia(context, d.estado, suave: true),
                  borderRadius: BorderRadius.circular(8),
                  border: d.estado == EstadoDia.pendiente ? Border.all(color: c.linea) : null,
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${Fechas.aFecha(d.fecha).day}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: d.estado == EstadoDia.futuro ? c.tenue : colorDia(context, d.estado))),
                  if (d.horaEntrada != null)
                    FittedBox(child: Text(Fechas.horaCorta(d.horaEntrada), style: TextStyle(fontSize: 10, color: colorDia(context, d.estado)))),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
