import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../configuracion/configuracion_vista.dart';
import '../sesion_vm.dart';
import 'widgets.dart';

/// Foto de perfil de quien inició sesión (perfil, o rostro si no subió una). Se actualiza al cambiarla.
class MiAvatar extends StatefulWidget {
  final double tam;
  const MiAvatar({super.key, this.tam = 34});
  @override
  State<MiAvatar> createState() => _MiAvatarState();
}

class _MiAvatarState extends State<MiAvatar> {
  Yo? _de;
  Future<String?>? _url;

  @override
  Widget build(BuildContext context) {
    final yo = context.watch<SesionVm>().yo!;
    if (!identical(yo, _de)) {
      _de = yo;
      _url = context.read<DatosRepositorio>().urlMiFoto(yo);
    }
    return FutureBuilder<String?>(
      future: _url,
      builder: (_, s) => AvatarPersona(iniciales: yo.iniciales, url: s.data, tam: widget.tam),
    );
  }
}

/// Botón de la barra superior: abre Configuración (perfil, contraseña, términos…).
class BotonPerfil extends StatelessWidget {
  const BotonPerfil({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: IconButton(
          tooltip: 'Mi perfil y configuración',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConfiguracionVista())),
          icon: const MiAvatar(tam: 32),
        ),
      );
}
