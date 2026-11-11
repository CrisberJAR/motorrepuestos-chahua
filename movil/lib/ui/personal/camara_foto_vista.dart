import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Toma la foto oficial del rostro y la devuelve como JPEG (Navigator.pop con Uint8List).
class CamaraFotoVista extends StatefulWidget {
  const CamaraFotoVista({super.key});
  @override
  State<CamaraFotoVista> createState() => _CamaraFotoVistaState();
}

class _CamaraFotoVistaState extends State<CamaraFotoVista> {
  List<CameraDescription> _camaras = [];
  int _indice = 0;
  CameraController? _camara;
  Uint8List? _foto;
  String? _error;
  bool _tomando = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      if (_camaras.isEmpty) {
        _camaras = await availableCameras();
        final trasera = _camaras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        _indice = trasera >= 0 ? trasera : 0;
      }
      final c = CameraController(_camaras[_indice], ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _camara = c;
        _error = null;
      });
    } on CameraException catch (e) {
      setState(() => _error = e.code.contains('AccessDenied') ? 'Se necesita permiso de cámara.' : (e.description ?? 'No se pudo abrir la cámara.'));
    }
  }

  Future<void> _cambiar() async {
    final c = _camara;
    setState(() => _camara = null);
    await c?.dispose();
    _indice = (_indice + 1) % _camaras.length;
    await _iniciar();
  }

  Future<void> _tomar() async {
    final c = _camara;
    if (c == null || _tomando) return;
    setState(() => _tomando = true);
    try {
      final archivo = await c.takePicture();
      final bytes = await archivo.readAsBytes();
      setState(() => _foto = bytes);
    } catch (_) {
      setState(() => _error = 'No se pudo tomar la foto. Intenta de nuevo.');
    } finally {
      setState(() => _tomando = false);
    }
  }

  @override
  void dispose() {
    _camara?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _camara;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('FOTO DEL ROSTRO', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        actions: [
          if (_camaras.length > 1 && _foto == null) IconButton(tooltip: 'Cambiar cámara', onPressed: _cambiar, icon: const Icon(Icons.cameraswitch_outlined)),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: _error != null
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center))
                  : _foto != null
                      ? Image.memory(_foto!, fit: BoxFit.contain)
                      : c == null
                          ? const CircularProgressIndicator(color: Colors.white)
                          : AspectRatio(aspectRatio: 1 / c.value.aspectRatio, child: CameraPreview(c)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Text('De frente, con buena luz, sin gorra ni lentes oscuros. Solo una persona.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              if (_foto == null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: c == null || _tomando ? null : _tomar,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Tomar foto'),
                )
              else
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                      onPressed: () => setState(() => _foto = null),
                      child: const Text('Tomar otra'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(onPressed: () => Navigator.of(context).pop(_foto), child: const Text('Usar esta foto'))),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
