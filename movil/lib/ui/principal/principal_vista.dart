import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../asistencia/asistencia_vista.dart';
import '../chat/chat_vista.dart';
import '../escaner/escaner_vista.dart';
import '../inicio/inicio_vista.dart';
import '../pagos/pagos_vista.dart';
import '../permisos/permisos_vista.dart';
import '../personal/personal_vista.dart';
import '../comunes/perfil_boton.dart';
import '../comunes/widgets.dart';
import '../comunes/reportes.dart';
import '../configuracion/configuracion_vista.dart';
import '../sesion_vm.dart';

/// Navegación inferior según el rol.
/// Admin: Hoy · Asistencia · Marcar (cámara) · Permisos · Más (Pagos, Personal, Asistente).
/// Trabajador: Inicio · Asistencia · Permisos · Pagos · Chat. (Sin cámara: solo el admin registra asistencia.)
class PrincipalVista extends StatefulWidget {
  const PrincipalVista({super.key});
  @override
  State<PrincipalVista> createState() => _PrincipalVistaState();
}

class _PrincipalVistaState extends State<PrincipalVista> {
  int _indice = 0;

  void irA(int i) => setState(() => _indice = i);

  @override
  Widget build(BuildContext context) {
    final yo = context.watch<SesionVm>().yo!;
    final destinos = yo.esAdmin
        ? const [
            NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Hoy'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Asistencia'),
            NavigationDestination(icon: Icon(Icons.face_retouching_natural_outlined), selectedIcon: Icon(Icons.face_retouching_natural), label: 'Marcar'),
            NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Permisos'),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Más'),
          ]
        : const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Asistencia'),
            NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Permisos'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Mi pago'),
            NavigationDestination(icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'Chat'),
          ];

    // Solo se construye la pestaña visible: así la cámara se apaga al salir de "Marcar".
    final Widget pagina = yo.esAdmin
        ? switch (_indice) {
            0 => InicioVista(alEscanear: () => irA(2), alVerPermisos: () => irA(3)),
            1 => const AsistenciaVista(),
            2 => const EscanerVista(),
            3 => const PermisosVista(),
            _ => const _MasVista(),
          }
        : switch (_indice) {
            0 => InicioVista(alVerPermisos: () => irA(2), alVerPagos: () => irA(3)),
            1 => const AsistenciaVista(),
            2 => const PermisosVista(),
            3 => const PagosVista(),
            _ => const ChatVista(),
          };

    return Scaffold(
      body: pagina,
      bottomNavigationBar: NavigationBar(selectedIndex: _indice, onDestinationSelected: irA, destinations: destinos),
    );
  }
}

class _MasVista extends StatelessWidget {
  const _MasVista();

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final yo = context.read<SesionVm>().yo!;
    void abrir(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    Widget opcion(IconData icono, String titulo, String sub, VoidCallback onTap) => ListTile(
          leading: CircleAvatar(backgroundColor: c.acentoSuave, child: Icon(icono, color: c.acento)),
          title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('MÁS'), actions: const [BotonPerfil()]),
      body: ListView(padding: rellenoLista(context, arriba: 16), children: [
        Card(
          child: Column(children: [
            opcion(Icons.account_balance_wallet_outlined, 'Pagos', 'Por pagar, registrar pagos y comprobantes', () => abrir(const PagosVista(conAtras: true))),
            const Divider(height: 1),
            opcion(Icons.groups_outlined, 'Personal', 'Registrar trabajador con foto, contraseñas', () => abrir(const PersonalVista())),
            const Divider(height: 1),
            opcion(Icons.smart_toy_outlined, 'Asistente IA', 'Consultas y permisos por chat', () => abrir(const ChatVista(conAtras: true))),
            const Divider(height: 1),
            opcion(Icons.download_outlined, 'Reportes', 'Asistencia y pagos en PDF o Excel', () => abrirHojaReportes(context)),
            const Divider(height: 1),
            opcion(Icons.settings_outlined, 'Configuración', 'Mi perfil, contraseña, términos y ayuda', () => abrir(const ConfiguracionVista())),
          ]),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Cerrar sesión'),
            subtitle: Text('${yo.nombreCorto} · Administrador'),
            onTap: () => context.read<SesionVm>().salir(),
          ),
        ),
      ]),
    );
  }
}
