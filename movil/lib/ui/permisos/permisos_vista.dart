import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/fechas.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../comunes/widgets.dart';
import '../comunes/perfil_boton.dart';
import '../sesion_vm.dart';
import 'permisos_vm.dart';

class PermisosVista extends StatelessWidget {
  const PermisosVista({super.key});

  @override
  Widget build(BuildContext context) {
    final yo = context.read<SesionVm>().yo!;
    return ChangeNotifierProvider(
      create: (ctx) => PermisosVm(ctx.read<DatosRepositorio>(), yo)..iniciar(),
      child: Consumer<PermisosVm>(builder: (context, vm, _) {
        return Scaffold(
          appBar: AppBar(title: Text(yo.esAdmin ? 'PERMISOS' : 'MIS PERMISOS'), actions: const [BotonPerfil()]),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _abrirFormulario(context, vm),
            icon: const Icon(Icons.add),
            label: Text(yo.esAdmin ? 'Registrar' : 'Solicitar'),
          ),
          body: RefreshIndicator(
            onRefresh: vm.cargar,
            child: ListView(padding: rellenoLista(context, abajo: 96), children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (valor, texto) in [
                    ('todos', 'Todos'),
                    ('pendiente', 'Pendientes (${vm.contar('pendiente')})'),
                    ('aprobado', 'Aprobados'),
                    ('rechazado', 'Rechazados'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(texto), selected: vm.filtro == valor, onSelected: (_) => vm.filtrar(valor)),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              if (vm.error != null) ...[MensajeError(vm.error!, reintentar: vm.cargar), const SizedBox(height: 10)],
              if (vm.cargando && vm.todos.isEmpty)
                const Cargando()
              else if (vm.lista.isEmpty)
                Vacio(
                  vm.filtro == 'todos' ? 'Todavía no hay permisos' : 'No hay permisos en este filtro',
                  texto: yo.esAdmin ? 'Aparecerán aquí los pedidos desde la app, la web o el chatbot.' : 'Usa “Solicitar” o pídeselo al asistente.',
                  icono: Icons.description_outlined,
                )
              else
                for (final p in vm.lista) ...[_TarjetaPermiso(permiso: p, vm: vm), const SizedBox(height: 10)],
            ]),
          ),
        );
      }),
    );
  }

  void _abrirFormulario(BuildContext context, PermisosVm vm) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(value: vm, child: const _FormularioPermiso()),
    );
  }
}

class _TarjetaPermiso extends StatelessWidget {
  final Permiso permiso;
  final PermisosVm vm;
  const _TarjetaPermiso({required this.permiso, required this.vm});

  Future<void> _ejecutar(BuildContext context, Future<(String, bool)> Function() accion) async {
    final (mensaje, error) = await accion();
    if (context.mounted) mostrarAviso(context, mensaje, error: error);
  }

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final p = permiso;
    final rango = p.fechaInicio == p.fechaFin ? Fechas.corta(p.fechaInicio) : '${Fechas.corta(p.fechaInicio)} al ${Fechas.corta(p.fechaFin)}';
    final ocupado = vm.ocupado?.startsWith(p.id) ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (vm.yo.esAdmin) ...[
              AvatarPersona(iniciales: '${p.nombres?[0] ?? ''}${p.apellidos?[0] ?? ''}', url: p.fotoRostroUrl == null ? null : vm.fotos[p.fotoRostroUrl], tam: 34),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (vm.yo.esAdmin) Text(p.nombreCorto, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${tiposPermiso[p.tipo]} · $rango', style: TextStyle(fontWeight: vm.yo.esAdmin ? FontWeight.w500 : FontWeight.w700)),
              ]),
            ),
            if (!(vm.yo.esAdmin && p.estado == 'pendiente')) ChipPermiso(p.estado),
          ]),
          const SizedBox(height: 6),
          Text(p.motivo),
          const SizedBox(height: 4),
          Text('Solicitado desde: ${origenesPermiso[p.origen]}', style: TextStyle(fontSize: 12, color: c.tenue)),
          if (vm.yo.esAdmin && p.estado == 'pendiente') ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: c.ok, foregroundColor: c.superficie),
                  onPressed: ocupado ? null : () => _ejecutar(context, () => vm.aprobar(p)),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Aprobar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ocupado ? null : () => _ejecutar(context, () => vm.rechazar(p)),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Rechazar'),
                ),
              ),
            ]),
          ],
          if (vm.yo.esAdmin && p.estado == 'aprobado')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Pagar estos días (con goce)'),
              subtitle: const Text('Por defecto los permisos no se pagan'),
              value: p.conGoce,
              onChanged: ocupado ? null : (v) => _ejecutar(context, () => vm.cambiarGoce(p, v)),
            )
          else if (p.estado == 'aprobado')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(p.conGoce ? 'Con goce: estos días se pagan' : 'Sin goce: estos días no se pagan', style: TextStyle(fontSize: 12, color: c.tenue)),
            ),
        ]),
      ),
    );
  }
}

class _FormularioPermiso extends StatefulWidget {
  const _FormularioPermiso();
  @override
  State<_FormularioPermiso> createState() => _FormularioPermisoState();
}

class _FormularioPermisoState extends State<_FormularioPermiso> {
  final _motivo = TextEditingController();
  late String _inicio = Fechas.sumarDias(Fechas.hoy(), 1);
  late String _fin = _inicio;
  String _tipo = 'salud';
  String? _trabajador;
  bool _conGoce = false, _guardando = false;
  String? _error;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha(bool inicio) async {
    final actual = Fechas.aFecha(inicio ? _inicio : _fin);
    final elegida = await showDatePicker(
      context: context,
      initialDate: DateTime(actual.year, actual.month, actual.day),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: inicio ? 'Desde' : 'Hasta',
    );
    if (elegida == null) return;
    final iso = Fechas.iso(elegida);
    setState(() {
      if (inicio) {
        _inicio = iso;
        if (_fin.compareTo(iso) < 0) _fin = iso;
      } else {
        _fin = iso;
      }
    });
  }

  Future<void> _guardar() async {
    final vm = context.read<PermisosVm>();
    if (vm.yo.esAdmin && _trabajador == null) return setState(() => _error = 'Elige al trabajador.');
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await vm.crear(personalId: _trabajador ?? vm.yo.id, tipo: _tipo, inicio: _inicio, fin: _fin, motivo: _motivo.text, conGoce: _conGoce);
    if (!mounted) return;
    if (error != null) {
      return setState(() {
        _guardando = false;
        _error = error;
      });
    }
    Navigator.of(context).pop();
    mostrarAviso(context, vm.yo.esAdmin ? 'Permiso registrado y aprobado.' : 'Solicitud enviada. El administrador la revisará.');
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PermisosVm>();
    final c = Colores.de(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(vm.yo.esAdmin ? 'Registrar permiso' : 'Solicitar permiso', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          if (vm.yo.esAdmin) ...[
            DropdownButtonFormField<String>(
              initialValue: _trabajador,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Trabajador'),
              items: [for (final p in vm.personal) DropdownMenuItem(value: p.id, child: Text('${p.nombreCompleto} · ${p.dni}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _trabajador = v),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            initialValue: _tipo,
            decoration: const InputDecoration(labelText: 'Tipo de permiso'),
            items: [for (final e in tiposPermiso.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _tipo = v ?? 'salud'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _elegirFecha(true), icon: const Icon(Icons.event), label: Text('Desde ${Fechas.diaMes(_inicio)}'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _elegirFecha(false), icon: const Icon(Icons.event), label: Text('Hasta ${Fechas.diaMes(_fin)}'))),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _motivo,
            maxLength: 300,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(labelText: 'Motivo', hintText: 'Ej.: cita médica en EsSalud'),
          ),
          if (vm.yo.esAdmin)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pagar estos días (con goce)'),
              value: _conGoce,
              onChanged: (v) => setState(() => _conGoce = v),
            )
          else
            Text('Quedará pendiente hasta que el administrador la apruebe. Por defecto los permisos no se pagan.', style: TextStyle(fontSize: 12, color: c.tenue)),
          if (_error != null) ...[const SizedBox(height: 10), MensajeError(_error!)],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(vm.yo.esAdmin ? 'Registrar permiso' : 'Enviar solicitud'),
          ),
        ]),
      ),
    );
  }
}
