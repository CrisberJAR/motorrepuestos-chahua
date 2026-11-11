import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/legal.dart';
import '../../core/tema.dart';
import '../../data/repositorios.dart';
import '../comunes/perfil_boton.dart';
import '../comunes/reportes.dart';
import '../comunes/widgets.dart';
import '../sesion_vm.dart';

/// Configuración de cada usuario (admin y trabajador): perfil con foto, datos de contacto,
/// contraseña, reportes, términos, privacidad, ayuda y cierre de sesión.
class ConfiguracionVista extends StatefulWidget {
  const ConfiguracionVista({super.key});
  @override
  State<ConfiguracionVista> createState() => _ConfiguracionVistaState();
}

class _ConfiguracionVistaState extends State<ConfiguracionVista> {
  bool _subiendo = false;

  Future<void> _cambiarFoto() async {
    final yo = context.read<SesionVm>().yo!;
    final opcion = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar foto'), onTap: () => Navigator.pop(ctx, 'camara')),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de la galería'), onTap: () => Navigator.pop(ctx, 'galeria')),
        if (yo.fotoPerfilUrl != null)
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Quitar foto'), onTap: () => Navigator.pop(ctx, 'quitar')),
        const SizedBox(height: 12),
      ]),
    );
    if (opcion == null || !mounted) return;
    final repo = context.read<DatosRepositorio>();
    final sesion = context.read<SesionVm>();
    try {
      if (opcion == 'quitar') {
        setState(() => _subiendo = true);
        await repo.quitarFotoPerfil(yo.id);
      } else {
        final foto = await ImagePicker().pickImage(
          source: opcion == 'camara' ? ImageSource.camera : ImageSource.gallery,
          preferredCameraDevice: CameraDevice.front,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 85,
        );
        if (foto == null) return;
        setState(() => _subiendo = true);
        await repo.subirFotoPerfil(yo.id, await foto.readAsBytes());
      }
      await sesion.recargarYo();
      if (mounted) mostrarAviso(context, opcion == 'quitar' ? 'Foto de perfil eliminada.' : 'Foto de perfil actualizada.');
    } catch (e) {
      if (mounted) mostrarAviso(context, mensajeDeError(e), error: true);
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  void _abrir(Widget pagina) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => pagina));

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final yo = context.watch<SesionVm>().yo!;
    Widget opcion(IconData icono, String titulo, String? sub, VoidCallback onTap, {Color? color}) => ListTile(
          leading: Icon(icono, color: color ?? c.tenue),
          title: Text(titulo, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          subtitle: sub == null ? null : Text(sub),
          trailing: color == null ? const Icon(Icons.chevron_right) : null,
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('CONFIGURACIÓN')),
      body: ListView(padding: rellenoLista(context, arriba: 8), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Stack(alignment: Alignment.bottomRight, children: [
                const MiAvatar(tam: 96),
                Material(
                  color: c.acento,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _subiendo ? null : _cambiarFoto,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _subiendo
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.acentoTinta))
                          : Icon(Icons.photo_camera, size: 18, color: c.acentoTinta),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Text('${yo.nombres} ${yo.apellidos}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('${yo.esAdmin ? 'Administrador' : yo.cargo} · ${yo.area}', textAlign: TextAlign.center, style: TextStyle(color: c.tenue)),
              Text('DNI ${yo.dni}', style: TextStyle(color: c.tenue, fontSize: 13)),
              const SizedBox(height: 6),
              Text('La foto de perfil es solo para mostrar. La del reconocimiento facial la registra el administrador.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: c.tenue)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        _Seccion('Cuenta', [
          opcion(Icons.contact_phone_outlined, 'Datos de contacto', [yo.telefono, yo.correo].whereType<String>().join(' · ').ifEmpty('Agrega tu teléfono y correo'),
              () => _abrir(const _DatosContactoVista())),
          opcion(Icons.lock_outline, 'Cambiar contraseña', 'Tu contraseña inicial es tu DNI', () => _abrir(const _CambiarClaveVista())),
          opcion(Icons.download_outlined, yo.esAdmin ? 'Reportes de asistencia y pagos' : 'Descargar mis reportes', 'PDF o Excel', () => abrirHojaReportes(context)),
        ]),
        _Seccion('Información y ayuda', [
          opcion(Icons.description_outlined, 'Términos y condiciones', null, () => _abrir(const _LegalVista('TÉRMINOS Y CONDICIONES', terminos))),
          opcion(Icons.privacy_tip_outlined, 'Política de privacidad', 'Incluye el uso de datos biométricos', () => _abrir(const _LegalVista('PRIVACIDAD', privacidad))),
          opcion(Icons.help_outline, 'Preguntas frecuentes', null, () => _abrir(const _PreguntasVista())),
          opcion(Icons.chat_outlined, 'Soporte por WhatsApp', empresaWhatsapp, () async {
            final ok = await launchUrl(Uri.parse('https://wa.me/51$empresaWhatsapp'), mode: LaunchMode.externalApplication);
            if (!ok && context.mounted) mostrarAviso(context, 'No se pudo abrir WhatsApp.', error: true);
          }),
          ListTile(
            leading: Icon(Icons.info_outline, color: c.tenue),
            title: const Text('Acerca de', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Chahua Personal $versionApp · $empresaNombre\n$empresaHorario'),
            isThreeLine: true,
          ),
        ]),
        _Seccion('Sesión', [
          opcion(Icons.logout, 'Cerrar sesión', '${yo.nombreCorto} · ${yo.esAdmin ? 'Administrador' : yo.cargo}', () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Cerrar sesión'),
                content: const Text('¿Quieres salir de tu cuenta en este celular?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salir')),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              Navigator.of(context).popUntil((r) => r.isFirst);
              await context.read<SesionVm>().salir();
            }
          }, color: c.peligro),
        ]),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String otro) => isEmpty ? otro : this;
}

class _Seccion extends StatelessWidget {
  final String titulo;
  final List<Widget> hijos;
  const _Seccion(this.titulo, this.hijos);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(titulo.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.6, color: Colores.de(context).tenue)),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < hijos.length; i++) ...[if (i > 0) const Divider(height: 1), hijos[i]],
            ]),
          ),
        ]),
      );
}

/* ---------- Datos de contacto ---------- */
class _DatosContactoVista extends StatefulWidget {
  const _DatosContactoVista();
  @override
  State<_DatosContactoVista> createState() => _DatosContactoVistaState();
}

class _DatosContactoVistaState extends State<_DatosContactoVista> {
  late final _telefono = TextEditingController(text: context.read<SesionVm>().yo!.telefono ?? '');
  late final _correo = TextEditingController(text: context.read<SesionVm>().yo!.correo ?? '');
  bool _guardando = false;

  @override
  void dispose() {
    _telefono.dispose();
    _correo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final correo = _correo.text.trim();
    if (correo.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(correo)) {
      return mostrarAviso(context, 'El correo no es válido.', error: true);
    }
    setState(() => _guardando = true);
    try {
      await context.read<DatosRepositorio>().actualizarMiPerfil(telefono: _telefono.text.trim(), correo: correo);
      if (!mounted) return;
      await context.read<SesionVm>().recargarYo();
      if (!mounted) return;
      mostrarAviso(context, 'Datos de contacto guardados.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) mostrarAviso(context, mensajeDeError(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('DATOS DE CONTACTO')),
        body: ListView(padding: rellenoLista(context, arriba: 16), children: [
          TextField(
            controller: _telefono,
            keyboardType: TextInputType.phone,
            maxLength: 15,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
            decoration: const InputDecoration(labelText: 'Teléfono', prefixIcon: Icon(Icons.phone_outlined), counterText: ''),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _correo,
            keyboardType: TextInputType.emailAddress,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline), counterText: ''),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: _guardando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar'),
          ),
        ]),
      );
}

/* ---------- Cambiar contraseña ---------- */
class _CambiarClaveVista extends StatefulWidget {
  const _CambiarClaveVista();
  @override
  State<_CambiarClaveVista> createState() => _CambiarClaveVistaState();
}

class _CambiarClaveVistaState extends State<_CambiarClaveVista> {
  final _actual = TextEditingController(), _nueva = TextEditingController(), _repetir = TextEditingController();
  bool _ver = false, _guardando = false;
  String? _error;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _repetir.dispose();
    super.dispose();
  }

  Future<void> _cambiar() async {
    final yo = context.read<SesionVm>().yo!;
    final actual = _actual.text, nueva = _nueva.text;
    String? error;
    if (actual.isEmpty) {
      error = 'Escribe tu contraseña actual.';
    } else if (nueva.length < 6) {
      error = 'La nueva contraseña debe tener al menos 6 caracteres.';
    } else if (nueva.length > 72) {
      error = 'La nueva contraseña no puede superar los 72 caracteres.';
    } else if (nueva != _repetir.text) {
      error = 'Las contraseñas nuevas no coinciden.';
    } else if (nueva == actual) {
      error = 'La nueva contraseña debe ser distinta de la actual.';
    } else if (nueva == yo.dni) {
      error = 'Por seguridad, no uses tu DNI como contraseña.';
    }
    setState(() => _error = error);
    if (error != null) return;
    setState(() => _guardando = true);
    try {
      await context.read<AuthRepositorio>().cambiarMiClave(yo.dni, actual, nueva);
      if (!mounted) return;
      mostrarAviso(context, 'Contraseña cambiada. Úsala la próxima vez que ingreses.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String t) => InputDecoration(
          labelText: t,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(icon: Icon(_ver ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _ver = !_ver)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('CAMBIAR CONTRASEÑA')),
      body: ListView(padding: rellenoLista(context, arriba: 16), children: [
        Text('Tu contraseña inicial es tu DNI. Cámbiala por una que solo tú conozcas (mínimo 6 caracteres).',
            style: TextStyle(color: Colores.de(context).tenue)),
        const SizedBox(height: 16),
        TextField(controller: _actual, obscureText: !_ver, autofillHints: const [AutofillHints.password], decoration: deco('Contraseña actual')),
        const SizedBox(height: 14),
        TextField(controller: _nueva, obscureText: !_ver, autofillHints: const [AutofillHints.newPassword], decoration: deco('Nueva contraseña')),
        const SizedBox(height: 14),
        TextField(controller: _repetir, obscureText: !_ver, onSubmitted: (_) => _cambiar(), decoration: deco('Repite la nueva contraseña')),
        if (_error != null) ...[const SizedBox(height: 14), MensajeError(_error!)],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _guardando ? null : _cambiar,
          icon: _guardando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.key),
          label: const Text('Cambiar contraseña'),
        ),
      ]),
    );
  }
}

/* ---------- Textos legales y ayuda ---------- */
class _LegalVista extends StatelessWidget {
  final String titulo;
  final List<SeccionLegal> secciones;
  const _LegalVista(this.titulo, this.secciones);
  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: ListView(padding: rellenoLista(context, arriba: 12), children: [
        Text('Última actualización: $actualizado', style: TextStyle(fontSize: 12, color: c.tenue)),
        for (final s in secciones) ...[
          const SizedBox(height: 14),
          Text(s.titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
          for (final p in s.parrafos) Padding(padding: const EdgeInsets.only(top: 6), child: Text(p, style: TextStyle(height: 1.4, color: c.tinta.withValues(alpha: 0.85)))),
        ],
      ]),
    );
  }
}

class _PreguntasVista extends StatelessWidget {
  const _PreguntasVista();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('PREGUNTAS FRECUENTES')),
        body: ListView(padding: rellenoLista(context, arriba: 8), children: [
          for (final (p, r) in preguntas)
            Card(
              child: ExpansionTile(
                title: Text(p, style: const TextStyle(fontWeight: FontWeight.w700)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                expandedAlignment: Alignment.centerLeft,
                children: [Text(r)],
              ),
            ),
        ]),
      );
}
