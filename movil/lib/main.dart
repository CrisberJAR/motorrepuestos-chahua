import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/tema.dart';
import 'data/api_cliente.dart';
import 'data/repositorios.dart';
import 'ui/comunes/widgets.dart';
import 'ui/login/login_vista.dart';
import 'ui/principal/principal_vista.dart';
import 'ui/sesion_vm.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseAnonKey);
  final sb = Supabase.instance.client;

  runApp(MultiProvider(
    providers: [
      Provider(create: (_) => AuthRepositorio(sb)),
      Provider(create: (_) => DatosRepositorio(sb)),
      Provider(create: (_) => IaRepositorio(ApiCliente(sb))),
      ChangeNotifierProvider(create: (ctx) => SesionVm(ctx.read<AuthRepositorio>())..iniciar()),
    ],
    child: const AppChahua(),
  ));
}

class AppChahua extends StatelessWidget {
  const AppChahua({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chahua Personal',
      debugShowCheckedModeBanner: false,
      theme: construirTema(Brightness.light),
      darkTheme: construirTema(Brightness.dark),
      home: Consumer<SesionVm>(
        builder: (context, sesion, _) => switch (sesion.estado) {
          EstadoSesion.revisando => const Scaffold(body: Cargando()),
          EstadoSesion.sinSesion => const LoginVista(),
          EstadoSesion.noHabilitada => const _NoHabilitada(),
          EstadoSesion.activa => PrincipalVista(key: ValueKey(sesion.yo!.id)),
        },
      ),
    );
  }
}

class _NoHabilitada extends StatelessWidget {
  const _NoHabilitada();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Cuenta no habilitada', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Tu cuenta está inactiva o no está vinculada a un trabajador. Comunícate con el administrador.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: () => context.read<SesionVm>().salir(), child: const Text('Cerrar sesión')),
              ]),
            ),
          ),
        ),
      );
}
