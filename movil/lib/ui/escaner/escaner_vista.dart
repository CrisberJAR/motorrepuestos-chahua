import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/fechas.dart';
import '../../core/tema.dart';
import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../comunes/widgets.dart';
import 'escaner_vm.dart';

/// Pantalla "Marcar" (solo administrador).
class EscanerVista extends StatelessWidget {
  const EscanerVista({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (ctx) => EscanerVm(ctx.read<IaRepositorio>())..iniciarCamara(),
        child: const _Contenido(),
      );
}

class _Contenido extends StatefulWidget {
  const _Contenido();
  @override
  State<_Contenido> createState() => _ContenidoState();
}

class _ContenidoState extends State<_Contenido> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Libera la cámara si la app pasa a segundo plano y la vuelve a abrir al regresar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    final vm = context.read<EscanerVm>();
    if (estado == AppLifecycleState.inactive || estado == AppLifecycleState.paused) {
      vm.detenerCamara();
    } else if (estado == AppLifecycleState.resumed && vm.camara == null) {
      vm.iniciarCamara();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<EscanerVm>();
    final c = Colores.de(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('MARCAR ASISTENCIA', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        actions: [
          if (vm.marcadosEnSesion > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Etiqueta('${vm.marcadosEnSesion} marcados', fondo: c.okSuave, color: c.ok),
              ),
            ),
          if (vm.puedeCambiarCamara)
            IconButton(tooltip: 'Cambiar cámara', icon: const Icon(Icons.cameraswitch_outlined), onPressed: vm.cambiarCamara),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(child: _VistaCamara(vm: vm)),
          _PanelInferior(vm: vm),
        ]),
      ),
    );
  }
}

class _VistaCamara extends StatelessWidget {
  final EscanerVm vm;
  const _VistaCamara({required this.vm});

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    final camara = vm.camara;
    if (vm.estado == EstadoEscaner.errorCamara) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(vm.guia, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            FilledButton(onPressed: vm.iniciarCamara, child: const Text('Reintentar')),
          ]),
        ),
      );
    }
    if (camara == null || !camara.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    final listo = vm.estado == EstadoEscaner.rostroListo;
    final colorMarco = vm.resultado?.registrado == true
        ? c.ok
        : listo
            ? const Color(0xFF4ADE80)
            : Colors.white70;

    return LayoutBuilder(builder: (context, caja) {
      // Vista previa vertical: relación ancho/alto = 1 / aspectRatio de la cámara.
      final relacion = 1 / camara.value.aspectRatio;
      var ancho = caja.maxWidth;
      var alto = ancho / relacion;
      if (alto > caja.maxHeight) {
        alto = caja.maxHeight;
        ancho = alto * relacion;
      }
      final r = vm.cajaRostro;
      return Center(
        child: SizedBox(
          width: ancho,
          height: alto,
          child: Stack(fit: StackFit.expand, children: [
            ClipRRect(borderRadius: BorderRadius.circular(16), child: CameraPreview(camara)),
            // Guía ovalada
            IgnorePointer(
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: ancho * 0.62,
                  height: alto * 0.55,
                  decoration: BoxDecoration(
                    border: Border.all(color: colorMarco, width: listo ? 4 : 2),
                    borderRadius: BorderRadius.all(Radius.elliptical(ancho * 0.31, alto * 0.275)),
                  ),
                ),
              ),
            ),
            // Caja del rostro detectado en vivo
            if (r != null && vm.estado != EstadoEscaner.resultado)
              Positioned(
                left: r.left * ancho,
                top: r.top * alto,
                width: r.width * ancho,
                height: r.height * alto,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: listo ? const Color(0xFF4ADE80) : Colors.amber, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            if (vm.estado == EstadoEscaner.enviando)
              Container(
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16)),
                child: const Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(vm.guia, textAlign: TextAlign.center, style: TextStyle(color: listo ? const Color(0xFF4ADE80) : Colors.white, fontWeight: FontWeight.w600)),
                  if (listo && vm.autoEscaneo) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: vm.progreso, color: const Color(0xFF4ADE80), backgroundColor: Colors.white24),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

class _PanelInferior extends StatelessWidget {
  final EscanerVm vm;
  const _PanelInferior({required this.vm});

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: c.fondo, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (vm.estado == EstadoEscaner.resultado) ...[
          if (vm.errorEnvio != null) MensajeError(vm.errorEnvio!) else _TarjetaResultado(resultado: vm.resultado!),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: vm.siguiente,
            icon: const Icon(Icons.face_retouching_natural),
            label: Text(vm.autoEscaneo && vm.resultado?.registrado == true ? 'Escanear siguiente (automático en 5 s)' : 'Escanear siguiente'),
          ),
        ] else ...[
          Row(children: [
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Escaneo automático', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Marca al detectar un rostro de frente'),
                value: vm.autoEscaneo,
                onChanged: vm.alternarAuto,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: vm.estado == EstadoEscaner.rostroListo || vm.estado == EstadoEscaner.buscando ? vm.capturar : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: vm.estado == EstadoEscaner.enviando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.camera_alt),
            label: Text(vm.estado == EstadoEscaner.enviando ? 'Identificando…' : 'Escanear ahora'),
          ),
        ],
      ]),
    );
  }
}

class _TarjetaResultado extends StatelessWidget {
  final ResultadoEscaneo resultado;
  const _TarjetaResultado({required this.resultado});

  @override
  Widget build(BuildContext context) {
    final c = Colores.de(context);
    if (!resultado.reconocido) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.peligroSuave, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.person_off_outlined, color: c.peligro, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(resultado.codigo == 'ambiguo' ? 'No se pudo distinguir' : 'Rostro no reconocido',
                  style: TextStyle(color: c.peligro, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 2),
              Text(resultado.mensaje, style: TextStyle(color: c.peligro, fontSize: 13)),
            ]),
          ),
        ]),
      );
    }
    final estado = resultado.estado == null ? null : estadoDiaDe(resultado.estado!);
    final hora = resultado.tipo == 'salida' ? resultado.horaSalida : resultado.horaEntrada;
    final fondo = resultado.registrado ? c.okSuave : c.alertaSuave;
    final color = resultado.registrado ? c.ok : c.alerta;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(resultado.registrado ? Icons.verified_user : Icons.info_outline, color: color, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rostro identificado', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
              Text(resultado.nombre ?? '', style: TextStyle(color: c.tinta, fontSize: 20, fontWeight: FontWeight.w900)),
              Text('${resultado.cargo ?? ''} · DNI ${resultado.dni ?? ''}', style: TextStyle(color: c.tenue, fontSize: 12)),
            ]),
          ),
          Text('${resultado.confianza?.toStringAsFixed(1)}%', style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
              resultado.registrado
                  ? '${resultado.tipo == 'salida' ? 'Salida' : 'Entrada'} registrada a las ${Fechas.horaCorta(hora)}'
                  : resultado.mensaje.split(' - ').last,
              style: TextStyle(color: c.tinta, fontWeight: FontWeight.w600),
            ),
          ),
          if (resultado.registrado && resultado.tipo == 'entrada' && estado != null) ChipDia(estado),
        ]),
      ]),
    );
  }
}
