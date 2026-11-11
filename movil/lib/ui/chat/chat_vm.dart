import '../../data/modelos.dart';
import '../../data/repositorios.dart';
import '../vm_base.dart';

class ChatVm extends VmBase {
  final IaRepositorio _ia;
  final Yo yo;
  ChatVm(this._ia, this.yo)
      : mensajes = [
          MensajeChat(
            'asistente',
            yo.esAdmin
                ? 'Hola. Puedo consultar la asistencia, los pagos y los permisos de cualquier trabajador por DNI o nombre, explicar el reglamento y registrar permisos.'
                : 'Hola, ${yo.nombres.split(' ').first}. Puedo decirte tus asistencias, faltas y tardanzas, cuánto te toca cobrar, cómo va tu permiso, y registrar una solicitud de permiso.',
          ),
        ];

  final List<MensajeChat> mensajes;
  bool enviando = false;

  List<String> get sugerencias => yo.esAdmin
      ? const [
          '¿Cuántos días asistió Carlos Gómez este mes?',
          '¿Qué días faltó José Ramos en octubre?',
          'Registra un permiso de salud para mañana al DNI 73561249 por cita médica',
          '¿Cuántos minutos de tolerancia hay?',
        ]
      : const [
          '¿Cuántos días he asistido este mes?',
          '¿Qué días tengo falta?',
          '¿Cuánto me toca cobrar en mi pago de este mes?',
          '¿Ya aprobaron mi permiso?',
          'Necesito pedir permiso para mañana por cita médica',
        ];

  Future<void> enviar(String texto) async {
    final limpio = texto.trim();
    if (limpio.isEmpty || enviando) return;
    mensajes.add(MensajeChat('usuario', limpio));
    enviando = true;
    avisar();
    try {
      // Se omite el saludo inicial: la conversación enviada empieza con el usuario.
      final r = await _ia.chat(mensajes.skip(1).toList());
      mensajes.add(MensajeChat('asistente', r.respuesta, etiquetas: r.etiquetas));
    } catch (e) {
      mensajes.add(MensajeChat('asistente', mensajeDeError(e), error: true));
    } finally {
      enviando = false;
      avisar();
    }
  }
}
