import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/painting.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../vm_base.dart';

enum EstadoEscaner { iniciando, buscando, rostroListo, enviando, resultado, errorCamara }

/// Cámara del administrador con detección facial EN VIVO (ML Kit, en el celular).
/// Cuando hay un rostro de frente, cerca y estable durante varios cuadros, toma la foto
/// y la envía a /api/ia/identificar-rostro, que identifica al trabajador (1:N) y registra
/// su entrada o salida en Supabase.
class EscanerVm extends VmBase {
  final IaRepositorio _ia;
  EscanerVm(this._ia);

  static const _framesNecesarios = 3;
  static const _intervalo = Duration(milliseconds: 250);
  static const _tamanoMinimo = 0.28; // ancho del rostro / ancho de la imagen

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast, minFaceSize: 0.15),
  );

  CameraController? camara;
  List<CameraDescription> _camaras = [];
  int _indiceCamara = 0;
  bool _procesando = false;
  DateTime _ultimoFrame = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _continuar;
  bool _cerrado = false;

  EstadoEscaner estado = EstadoEscaner.iniciando;
  String guia = 'Iniciando cámara…';
  int framesEstables = 0;
  bool autoEscaneo = true;

  /// Caja del rostro detectado, normalizada (0..1) respecto a la vista previa vertical.
  Rect? cajaRostro;
  ResultadoEscaneo? resultado;
  String? errorEnvio;
  int marcadosEnSesion = 0;

  bool get camaraFrontal => _camaras.isNotEmpty && _camaras[_indiceCamara].lensDirection == CameraLensDirection.front;
  bool get puedeCambiarCamara => _camaras.length > 1;
  double get progreso => math.min(1, framesEstables / _framesNecesarios);

  Future<void> iniciarCamara() async {
    if (_cerrado) return;
    estado = EstadoEscaner.iniciando;
    guia = 'Iniciando cámara…';
    avisar();
    try {
      if (_camaras.isEmpty) {
        _camaras = await availableCameras();
        final trasera = _camaras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        _indiceCamara = trasera >= 0 ? trasera : 0;
      }
      if (_camaras.isEmpty) throw CameraException('sin_camara', 'Este celular no tiene cámara disponible.');
      final controlador = CameraController(
        _camaras[_indiceCamara],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controlador.initialize();
      if (_cerrado) {
        await controlador.dispose();
        return;
      }
      camara = controlador;
      await _empezarDeteccion();
    } on CameraException catch (e) {
      estado = EstadoEscaner.errorCamara;
      guia = e.code.contains('AccessDenied') || e.code.contains('Permission')
          ? 'Se necesita permiso de cámara. Actívalo en Ajustes > Aplicaciones > Chahua Personal > Permisos.'
          : (e.description ?? 'No se pudo abrir la cámara.');
      avisar();
    }
  }

  Future<void> _empezarDeteccion() async {
    final c = camara;
    if (c == null || !c.value.isInitialized) return;
    framesEstables = 0;
    cajaRostro = null;
    estado = EstadoEscaner.buscando;
    guia = 'Enfoca el rostro del trabajador';
    avisar();
    if (!c.value.isStreamingImages) await c.startImageStream(_alRecibirFrame);
  }

  Future<void> detenerCamara() async {
    _continuar?.cancel();
    final c = camara;
    camara = null;
    if (c != null) {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      await c.dispose();
    }
    avisar();
  }

  Future<void> cambiarCamara() async {
    if (!puedeCambiarCamara || estado == EstadoEscaner.enviando) return;
    await detenerCamara();
    _indiceCamara = (_indiceCamara + 1) % _camaras.length;
    await iniciarCamara();
  }

  void alternarAuto(bool valor) {
    autoEscaneo = valor;
    avisar();
  }

  Future<void> _alRecibirFrame(CameraImage imagen) async {
    if (_procesando || estado != EstadoEscaner.buscando && estado != EstadoEscaner.rostroListo) return;
    final ahora = DateTime.now();
    if (ahora.difference(_ultimoFrame) < _intervalo) return;
    _ultimoFrame = ahora;
    _procesando = true;
    try {
      final entrada = _aInputImage(imagen);
      if (entrada == null) return;
      final rostros = await _detector.processImage(entrada);
      _evaluar(rostros, imagen);
    } catch (_) {
      // Un cuadro dañado no detiene el escáner.
    } finally {
      _procesando = false;
    }
  }

  InputImage? _aInputImage(CameraImage imagen) {
    final rotacion = InputImageRotationValue.fromRawValue(_camaras[_indiceCamara].sensorOrientation);
    final formato = InputImageFormatValue.fromRawValue(imagen.format.raw as int);
    if (rotacion == null || formato == null || imagen.planes.isEmpty) return null;
    final plano = imagen.planes.first;
    return InputImage.fromBytes(
      bytes: plano.bytes,
      metadata: InputImageMetadata(
        size: Size(imagen.width.toDouble(), imagen.height.toDouble()),
        rotation: rotacion,
        format: formato,
        bytesPerRow: plano.bytesPerRow,
      ),
    );
  }

  void _evaluar(List<Face> rostros, CameraImage imagen) {
    if (estado != EstadoEscaner.buscando && estado != EstadoEscaner.rostroListo) return;
    // La cámara entrega la imagen acostada: en vertical el ancho real es el lado menor.
    final ancho = math.min(imagen.width, imagen.height).toDouble();
    final alto = math.max(imagen.width, imagen.height).toDouble();

    if (rostros.isEmpty) {
      framesEstables = 0;
      cajaRostro = null;
      estado = EstadoEscaner.buscando;
      guia = 'Enfoca el rostro del trabajador';
      return avisar();
    }

    final rostro = rostros.reduce((a, b) => a.boundingBox.width * a.boundingBox.height >= b.boundingBox.width * b.boundingBox.height ? a : b);
    final caja = rostro.boundingBox;
    var izquierda = caja.left / ancho;
    var derecha = caja.right / ancho;
    if (camaraFrontal) {
      final i = 1 - derecha;
      derecha = 1 - izquierda;
      izquierda = i;
    }
    cajaRostro = Rect.fromLTRB(izquierda.clamp(0, 1), (caja.top / alto).clamp(0, 1), derecha.clamp(0, 1), (caja.bottom / alto).clamp(0, 1));

    final tamano = caja.width / ancho;
    final giro = (rostro.headEulerAngleY ?? 0).abs();
    final inclinacion = (rostro.headEulerAngleZ ?? 0).abs();

    if (tamano < _tamanoMinimo) {
      framesEstables = 0;
      estado = EstadoEscaner.buscando;
      guia = 'Acércate un poco más al rostro';
    } else if (giro > 18 || inclinacion > 15) {
      framesEstables = 0;
      estado = EstadoEscaner.buscando;
      guia = 'Pide que mire de frente a la cámara';
    } else {
      framesEstables++;
      estado = EstadoEscaner.rostroListo;
      guia = rostros.length > 1 ? 'Varios rostros: se tomará el más cercano' : 'Rostro detectado · mantén la cámara quieta';
      if (autoEscaneo && framesEstables >= _framesNecesarios) {
        avisar();
        capturar();
        return;
      }
    }
    avisar();
  }

  /// Toma la foto y la envía al servidor de IA.
  Future<void> capturar() async {
    final c = camara;
    if (c == null || !c.value.isInitialized || estado == EstadoEscaner.enviando) return;
    estado = EstadoEscaner.enviando;
    guia = 'Identificando…';
    resultado = null;
    errorEnvio = null;
    avisar();
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final foto = await c.takePicture();
      final bytes = await foto.readAsBytes();
      resultado = await _ia.identificarRostro(bytes);
      if (resultado!.registrado) marcadosEnSesion++;
    } catch (e) {
      errorEnvio = mensajeDeError(e);
    }
    estado = EstadoEscaner.resultado;
    guia = resultado?.registrado == true ? 'Marcación registrada' : 'Revisa el resultado y vuelve a escanear';
    avisar();
    // En modo automático, tras una marcación correcta sigue con el siguiente trabajador.
    if (autoEscaneo && resultado?.registrado == true) {
      _continuar = Timer(const Duration(seconds: 5), siguiente);
    }
  }

  Future<void> siguiente() async {
    _continuar?.cancel();
    resultado = null;
    errorEnvio = null;
    await _empezarDeteccion();
  }

  @override
  void dispose() {
    _cerrado = true;
    _continuar?.cancel();
    final c = camara;
    camara = null;
    if (c != null) {
      if (c.value.isStreamingImages) c.stopImageStream().catchError((_) {});
      c.dispose();
    }
    _detector.close();
    super.dispose();
  }
}
