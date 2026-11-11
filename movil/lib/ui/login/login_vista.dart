import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../sesion_vm.dart';

class LoginVista extends StatefulWidget {
  const LoginVista({super.key});
  @override
  State<LoginVista> createState() => _LoginVistaState();
}

class _LoginVistaState extends State<LoginVista> {
  final _dni = TextEditingController();
  final _clave = TextEditingController();
  bool _ver = false, _cargando = false;
  String? _error;

  @override
  void dispose() {
    _dni.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _cargando = true;
      _error = null;
    });
    final error = await context.read<SesionVm>().ingresar(
      _dni.text.trim(),
      _clave.text,
    );
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    return Scaffold(
      backgroundColor: c.lateral,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, caja) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: caja.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Center(
                            child: Image.asset(
                              'assets/logo_chahua.png',
                              height: 150,
                              semanticLabel: 'Motorrepuestos Chahua',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Asistencia con reconocimiento facial, permisos y pagos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: c.lateralTinta.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        decoration: BoxDecoration(
                          color: c.fondo,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'INICIAR SESIÓN',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Usuario y contraseña inicial: tu DNI.',
                              style: TextStyle(color: c.tenue),
                            ),
                            const SizedBox(height: 22),
                            TextField(
                              controller: _dni,
                              keyboardType: TextInputType.number,
                              maxLength: 8,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              decoration: const InputDecoration(
                                labelText: 'DNI',
                                counterText: '',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _clave,
                              obscureText: !_ver,
                              autofillHints: const [AutofillHints.password],
                              onSubmitted: (_) => _ingresar(),
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _ver
                                      ? 'Ocultar contraseña'
                                      : 'Mostrar contraseña',
                                  icon: Icon(
                                    _ver
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () => setState(() => _ver = !_ver),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: c.peligroSuave,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: c.peligro,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _cargando ? null : _ingresar,
                              icon: _cargando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.login),
                              label: const Text('Ingresar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
