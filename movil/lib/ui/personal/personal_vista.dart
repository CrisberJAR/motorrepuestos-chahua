import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/fechas.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../comunes/widgets.dart';
import '../sesion_vm.dart';
import 'camara_foto_vista.dart';
import 'personal_vm.dart';

/// Personal (solo administrador): alta con foto, cambio de foto, contraseñas y estado.
class PersonalVista extends StatelessWidget {
  const PersonalVista({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => PersonalVm(ctx.read<DatosRepositorio>(), ctx.read<IaRepositorio>())..iniciar(),
      child: Consumer<PersonalVm>(builder: (context, vm, _) {
        final c = Colores.de(context);
        return Scaffold(
          appBar: AppBar(title: const Text('PERSONAL')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(value: vm, child: const _NuevoTrabajador()),
            )),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Nuevo'),
          ),
          body: RefreshIndicator(
            onRefresh: vm.cargar,
            child: ListView(padding: rellenoLista(context, abajo: 96), children: [
              TextField(
                onChanged: vm.buscar,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre, DNI o cargo'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Mostrar inactivos'),
                value: vm.verInactivos,
                onChanged: vm.alternarInactivos,
              ),
              if (vm.sinRostro > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: c.alertaSuave, borderRadius: BorderRadius.circular(10)),
                    child: Text('${vm.sinRostro} trabajador(es) sin rostro registrado: no podrán marcar asistencia. Toca “Foto” para registrarlo.',
                        style: TextStyle(color: c.alerta, fontSize: 13)),
                  ),
                ),
              if (vm.error != null) ...[MensajeError(vm.error!, reintentar: vm.cargar), const SizedBox(height: 10)],
              if (vm.cargando && vm.lista.isEmpty)
                const Cargando()
              else
                for (final p in vm.visibles) ...[_TarjetaPersona(persona: p, vm: vm), const SizedBox(height: 10)],
            ]),
          ),
        );
      }),
    );
  }
}

class _TarjetaPersona extends StatelessWidget {
  final Personal persona;
  final PersonalVm vm;
  const _TarjetaPersona({required this.persona, required this.vm});

  Future<void> _ejecutar(BuildContext context, Future<(String, bool)> f) async {
    final (m, e) = await f;
    if (context.mounted) mostrarAviso(context, m, error: e);
  }

  Future<void> _foto(BuildContext context) async {
    final foto = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(builder: (_) => const CamaraFotoVista()));
    if (foto == null || !context.mounted) return;
    mostrarAviso(context, 'Analizando rostro…');
    await _ejecutar(context, vm.cambiarFoto(persona, foto));
  }

  Future<void> _rol(BuildContext context) async {
    final hacerAdmin = persona.rol != 'admin';
    final nombre = persona.nombres.split(' ').first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hacerAdmin ? '¿Hacer administrador a $nombre?' : '¿Quitar el rol de administrador a $nombre?'),
        content: Text(hacerAdmin
            ? 'Tendrá acceso total: marcar asistencia con el rostro desde su celular, registrar pagos, aprobar permisos y gestionar al personal.'
            : 'Pasará a ser trabajador: solo verá su información y podrá solicitar permisos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(hacerAdmin ? 'Hacer administrador' : 'Quitar rol')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _ejecutar(context, vm.cambiarRol(persona, hacerAdmin ? 'admin' : 'trabajador'));
  }

  Future<void> _pago(BuildContext context) async {
    final monto = TextEditingController(text: persona.pagoPorDia.toStringAsFixed(2));
    var tipo = persona.tipoPago;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refrescar) => AlertDialog(
          title: Text('Pago de ${persona.nombres.split(' ').first}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'fijo', label: Text('Fijo')), ButtonSegment(value: 'variable', label: Text('Rendimiento'))],
              selected: {tipo},
              onSelectionChanged: (v) => refrescar(() => tipo = v.first),
            ),
            const SizedBox(height: 8),
            Text(
              tipo == 'variable'
                  ? 'El monto de cada día se registra al pagar, según su rendimiento. El pago por día sirve de referencia.'
                  : 'Gana el mismo monto cada día asistido.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: monto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: tipo == 'variable' ? 'Pago de referencia por día (S/)' : 'Pago por día (S/)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final valor = double.tryParse(monto.text);
    if (valor == null || valor <= 0) return mostrarAviso(context, 'El pago por día debe ser mayor que 0.', error: true);
    await _ejecutar(context, vm.cambiarPago(persona, tipo, valor));
  }

  Future<void> _clave(BuildContext context) async {
    final control = TextEditingController();
    final propia = persona.id == context.read<SesionVm>().yo!.id;
    final nueva = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(propia ? 'Cambiar mi contraseña' : 'Contraseña de ${persona.nombres.split(' ').first}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Usuario: ${persona.dni}'),
          const SizedBox(height: 12),
          TextField(controller: control, obscureText: true, decoration: const InputDecoration(labelText: 'Nueva contraseña (mín. 6)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, persona.dni), child: const Text('Restablecer al DNI')),
          FilledButton(onPressed: () => Navigator.pop(ctx, control.text), child: const Text('Cambiar')),
        ],
      ),
    );
    if (nueva == null || !context.mounted) return;
    if (nueva.length < 6) return mostrarAviso(context, 'La contraseña debe tener al menos 6 caracteres.', error: true);
    await _ejecutar(context, vm.cambiarClave(persona, nueva));
  }

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final p = persona;
    final yo = context.read<SesionVm>().yo!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AvatarPersona(iniciales: p.iniciales, url: p.fotoRostroUrl == null ? null : vm.fotos[p.fotoRostroUrl], tam: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.nombreCompleto, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('DNI ${p.dni} · ${p.cargo}', style: TextStyle(fontSize: 12, color: c.tenue)),
                Text('${p.area} · ${p.tipoPago == 'variable' ? 'por rendimiento (ref. ${Fechas.soles(p.pagoPorDia)})' : '${Fechas.soles(p.pagoPorDia)}/día'} · entrada ${p.horaEntrada.substring(0, 5)}',
                    style: TextStyle(fontSize: 12, color: c.tenue)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, children: [
                  if (p.rol == 'admin') Etiqueta('Administrador', fondo: c.acentoSuave, color: c.acento),
                  if (!p.activo) Etiqueta('Inactivo', fondo: c.hundido, color: c.tenue),
                  p.fotoRostroUrl != null
                      ? Etiqueta('Rostro registrado', fondo: c.okSuave, color: c.ok)
                      : Etiqueta('Sin rostro', fondo: c.alertaSuave, color: c.alerta),
                ]),
              ]),
            ),
          ]),
          Wrap(alignment: WrapAlignment.end, children: [
            TextButton.icon(onPressed: () => _foto(context), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Foto')),
            TextButton.icon(onPressed: () => _pago(context), icon: const Icon(Icons.payments_outlined, size: 18), label: const Text('Pago')),
            TextButton.icon(onPressed: () => _clave(context), icon: const Icon(Icons.key_outlined, size: 18), label: const Text('Clave')),
            if (p.id != yo.id)
              TextButton.icon(
                onPressed: () => _rol(context),
                icon: Icon(p.rol == 'admin' ? Icons.remove_moderator_outlined : Icons.admin_panel_settings_outlined, size: 18),
                label: Text(p.rol == 'admin' ? 'Quitar admin' : 'Hacer admin'),
              ),
            if (p.id != yo.id)
              TextButton.icon(
                onPressed: () => _ejecutar(context, vm.cambiarEstado(p)),
                icon: Icon(p.activo ? Icons.person_off_outlined : Icons.person_outline, size: 18),
                label: Text(p.activo ? 'Desactivar' : 'Activar'),
              ),
          ]),
        ]),
      ),
    );
  }
}

/* ---------------- Nuevo trabajador ---------------- */
class _NuevoTrabajador extends StatefulWidget {
  const _NuevoTrabajador();
  @override
  State<_NuevoTrabajador> createState() => _NuevoTrabajadorState();
}

class _NuevoTrabajadorState extends State<_NuevoTrabajador> {
  final _dni = TextEditingController();
  final _nombres = TextEditingController();
  final _apellidos = TextEditingController();
  final _cargo = TextEditingController();
  final _telefono = TextEditingController();
  final _correo = TextEditingController();
  final _pago = TextEditingController(text: '55');
  String _area = 'Ventas';
  String _tipoPago = 'fijo';
  String _rol = 'trabajador';
  Uint8List? _foto;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_dni, _nombres, _apellidos, _cargo, _telefono, _correo, _pago]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _tomarFoto() async {
    final foto = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(builder: (_) => const CamaraFotoVista()));
    if (foto != null) setState(() => _foto = foto);
  }

  Future<void> _guardar() async {
    String? error;
    if (!RegExp(r'^\d{8}$').hasMatch(_dni.text)) {
      error = 'El DNI debe tener 8 dígitos.';
    } else if (_nombres.text.trim().isEmpty || _apellidos.text.trim().isEmpty) {
      error = 'Completa nombres y apellidos.';
    } else if (_cargo.text.trim().isEmpty) {
      error = 'Indica el cargo.';
    } else if ((double.tryParse(_pago.text) ?? 0) <= 0) {
      error = 'El pago por día debe ser mayor que 0.';
    } else if (_foto == null) {
      error = 'Falta la foto del rostro: sin ella no podrá marcar asistencia.';
    }
    if (error != null) return setState(() => _error = error);

    setState(() {
      _guardando = true;
      _error = null;
    });
    final (mensaje, fallo) = await context.read<PersonalVm>().crear({
      'dni': _dni.text,
      'nombres': _nombres.text.trim(),
      'apellidos': _apellidos.text.trim(),
      'cargo': _cargo.text.trim(),
      'area': _area,
      'telefono': _telefono.text.trim(),
      'correo': _correo.text.trim(),
      'pago_por_dia': _pago.text,
      'tipo_pago': _tipoPago,
      'rol': _rol,
      'hora_entrada': '08:00',
      'tolerancia_min': '10',
    }, _foto!);
    if (!mounted) return;
    if (fallo) {
      return setState(() {
        _guardando = false;
        _error = mensaje;
      });
    }
    Navigator.of(context).pop();
    mostrarAviso(context, mensaje);
  }

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    const espacio = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('NUEVO TRABAJADOR')),
      body: ListView(padding: rellenoLista(context, abajo: 32), children: [
        InkWell(
          onTap: _tomarFoto,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(border: Border.all(color: c.linea, width: 1.5), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: c.hundido,
                foregroundImage: _foto != null ? MemoryImage(_foto!) : null,
                child: Icon(Icons.photo_camera_outlined, color: c.tenue, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_foto == null ? 'Tomar foto del rostro' : 'Foto lista · tocar para repetir', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Base del reconocimiento facial. De frente y con buena luz.', style: TextStyle(fontSize: 12, color: c.tenue)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _dni,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'DNI', counterText: ''),
        ),
        espacio,
        TextField(controller: _nombres, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nombres')),
        espacio,
        TextField(controller: _apellidos, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Apellidos')),
        espacio,
        TextField(controller: _cargo, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Cargo', hintText: 'Vendedor de Repuestos')),
        espacio,
        DropdownButtonFormField<String>(
          initialValue: _area,
          decoration: const InputDecoration(labelText: 'Área'),
          items: [for (final a in areas) DropdownMenuItem(value: a, child: Text(a))],
          onChanged: (v) => setState(() => _area = v ?? 'Ventas'),
        ),
        espacio,
        Text('Rol', style: TextStyle(fontSize: 12, color: c.tenue)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'trabajador', label: Text('Trabajador'), icon: Icon(Icons.person_outline)),
            ButtonSegment(value: 'admin', label: Text('Administrador'), icon: Icon(Icons.admin_panel_settings_outlined)),
          ],
          selected: {_rol},
          onSelectionChanged: (v) => setState(() => _rol = v.first),
        ),
        if (_rol == 'admin')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Acceso total: marca asistencia con el rostro, registra pagos, aprueba permisos y gestiona al personal.',
                style: TextStyle(fontSize: 12, color: c.tenue)),
          ),
        espacio,
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'fijo', label: Text('Pago fijo')),
            ButtonSegment(value: 'variable', label: Text('Por rendimiento')),
          ],
          selected: {_tipoPago},
          onSelectionChanged: (v) => setState(() => _tipoPago = v.first),
        ),
        espacio,
        TextField(
          controller: _pago,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(
            labelText: _tipoPago == 'variable' ? 'Pago de referencia por día (S/)' : 'Pago por día (S/)',
            helperText: _tipoPago == 'variable' ? 'El monto de cada día se registra al pagar, según su rendimiento.' : null,
          ),
        ),
        espacio,
        TextField(controller: _telefono, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono (opcional)')),
        espacio,
        TextField(controller: _correo, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo (opcional)')),
        const SizedBox(height: 8),
        Text('Horario 08:00 con 10 min de tolerancia. Usuario y contraseña inicial: su DNI.', style: TextStyle(fontSize: 12, color: c.tenue)),
        if (_error != null) ...[const SizedBox(height: 12), MensajeError(_error!)],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Analizando rostro…'),
                ])
              : const Text('Registrar trabajador'),
        ),
      ]),
    );
  }
}
