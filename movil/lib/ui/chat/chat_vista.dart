import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../sesion_vm.dart';
import 'chat_vm.dart';

/// Chat nativo con el asistente (Gemini + Function Calling) vía /api/ia/chatbot.
class ChatVista extends StatelessWidget {
  final bool conAtras;
  const ChatVista({super.key, this.conAtras = false});

  @override
  Widget build(BuildContext context) {
    final yo = context.read<SesionVm>().yo!;
    return ChangeNotifierProvider(
      create: (ctx) => ChatVm(ctx.read<IaRepositorio>(), yo),
      child: _Chat(conAtras: conAtras),
    );
  }
}

class _Chat extends StatefulWidget {
  final bool conAtras;
  const _Chat({required this.conAtras});
  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  final _texto = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _texto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _bajar() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _enviar(ChatVm vm, String texto) async {
    _texto.clear();
    _bajar();
    await vm.enviar(texto);
    _bajar();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ChatVm>();
    final c = Colores.de(context);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: widget.conAtras, title: const Text('ASISTENTE IA')),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(14),
            itemCount: vm.mensajes.length + (vm.enviando ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == vm.mensajes.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    _Icono(c: c),
                    const SizedBox(width: 8),
                    Text('Consultando…', style: TextStyle(color: c.tenue)),
                  ]),
                );
              }
              return _Burbuja(m: vm.mensajes[i]);
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final s in vm.sugerencias)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 6),
                  child: ActionChip(label: Text(s, style: const TextStyle(fontSize: 12)), onPressed: vm.enviando ? null : () => _enviar(vm, s)),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _texto,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1500,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (t) => _enviar(vm, t),
                  decoration: InputDecoration(
                    hintText: vm.yo.esAdmin ? 'Pregunta por un trabajador (DNI o nombre)…' : 'Escribe tu consulta…',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Enviar',
                onPressed: vm.enviando ? null : () => _enviar(vm, _texto.text),
                icon: const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Icono extends StatelessWidget {
  final Colores c;
  const _Icono({required this.c});
  @override
  Widget build(BuildContext context) =>
      CircleAvatar(radius: 14, backgroundColor: c.lateral, child: Icon(Icons.smart_toy_outlined, size: 16, color: c.acento));
}

class _Burbuja extends StatelessWidget {
  final MensajeChat m;
  const _Burbuja({required this.m});

  /// Texto con **negritas** y viñetas simples.
  List<InlineSpan> _formatear(String texto, TextStyle base) {
    final spans = <InlineSpan>[];
    final lineas = texto.split('\n');
    for (var i = 0; i < lineas.length; i++) {
      var linea = lineas[i];
      if (RegExp(r'^\s*[*-]\s+').hasMatch(linea)) linea = '• ${linea.replaceFirst(RegExp(r'^\s*[*-]\s+'), '')}';
      final partes = linea.split(RegExp(r'(\*\*[^*]+\*\*)'));
      final negritas = RegExp(r'\*\*([^*]+)\*\*').allMatches(linea).map((x) => x.group(1)!).toList();
      for (var j = 0; j < partes.length; j++) {
        spans.add(TextSpan(text: partes[j], style: base));
        if (j < negritas.length) spans.add(TextSpan(text: negritas[j], style: base.copyWith(fontWeight: FontWeight.w800)));
      }
      if (i < lineas.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final mio = m.rol == 'usuario';
    final ancho = MediaQuery.sizeOf(context).width * 0.8;
    if (mio) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: ancho),
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: c.acento, borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4))),
          child: Text(m.texto, style: TextStyle(color: c.acentoTinta)),
        ),
      );
    }
    final base = TextStyle(color: m.error ? c.peligro : c.tinta, fontSize: 14, height: 1.4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Icono(c: c),
        const SizedBox(width: 8),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (m.etiquetas.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final e in m.etiquetas)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: e.startsWith('Permiso registrado') ? c.okSuave : e.startsWith('Permiso no') ? c.alertaSuave : c.infoSuave,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(e,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: e.startsWith('Permiso registrado') ? c.ok : e.startsWith('Permiso no') ? c.alerta : c.info,
                          )),
                    ),
                ]),
              ),
            Container(
              constraints: BoxConstraints(maxWidth: ancho),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: m.error ? c.peligroSuave : c.superficie,
                border: Border.all(color: c.linea),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
              ),
              child: Text.rich(TextSpan(children: _formatear(m.texto, base))),
            ),
          ]),
        ),
      ]),
    );
  }
}
