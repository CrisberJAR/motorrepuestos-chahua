// Generado desde web/src/lib/legal.ts: mismos textos en la web y en la app.

class SeccionLegal {
  final String titulo;
  final List<String> parrafos;
  const SeccionLegal(this.titulo, this.parrafos);
}

const versionApp = '1.1.0';
const actualizado = '10 de noviembre de 2026';
const empresaNombre = 'Motorrepuestos Chahua';
const empresaWhatsapp = '928033056';
const empresaHorario = 'Lunes a sábado, de 08:00 a 19:00';

const terminos = [
  SeccionLegal('1. Objeto', [
    'Estos términos regulan el uso de la aplicación móvil y web "Chahua Personal" de Motorrepuestos Chahua, que sirve para registrar la asistencia, gestionar permisos, consultar pagos y comunicarse con el asistente virtual.',
    'Al iniciar sesión, el usuario declara haber leído y aceptado estos términos.',
  ]),
  SeccionLegal('2. Cuentas de acceso', [
    'Cada trabajador recibe una cuenta personal: el usuario es su DNI y la contraseña inicial también. Se recomienda cambiarla en Configuración en el primer ingreso.',
    'La cuenta es personal e intransferible. El usuario es responsable de no compartir su contraseña. Si la olvida, el administrador puede restablecerla.',
  ]),
  SeccionLegal('3. Roles', [
    'El administrador registra la asistencia mediante reconocimiento facial desde su celular, gestiona al personal, aprueba o rechaza permisos y registra los pagos.',
    'El trabajador puede consultar su asistencia, solicitar permisos, ver lo que tiene por cobrar y su historial de pagos, y descargar sus reportes. No puede ver información de otras personas.',
  ]),
  SeccionLegal('4. Asistencia y pagos', [
    'El horario es de lunes a sábado de 08:00 a 19:00, con refrigerio de 13:00 a 14:00 y 10 minutos de tolerancia. Las tardanzas se registran pero no generan descuento.',
    'Un día laborable sin marcación ni permiso aprobado se considera falta y no se paga. Los permisos no se pagan, salvo que el administrador los apruebe con goce.',
    'El pago puede ser fijo por día o por rendimiento diario. El trabajador puede solicitar su pago en cualquier momento; el administrador lo registra indicando el periodo, el método (efectivo, Yape, Plin o transferencia) y, si corresponde, bonos o descuentos.',
    'Los montos mostrados en la aplicación son informativos y se basan en los registros del sistema. Ante cualquier diferencia, el trabajador debe comunicarlo al administrador.',
  ]),
  SeccionLegal('5. Asistente virtual', [
    'El asistente usa inteligencia artificial (Google Gemini) para responder consultas y registrar solicitudes de permiso. Puede cometer errores: la información oficial es la que figura en los módulos de la aplicación.',
  ]),
  SeccionLegal('6. Uso adecuado', [
    'Está prohibido suplantar a otra persona, intentar marcar asistencia con fotos de terceros, acceder a cuentas ajenas o alterar la información del sistema. Estas conductas pueden dar lugar a medidas disciplinarias.',
  ]),
  SeccionLegal('7. Cambios', [
    'Motorrepuestos Chahua puede actualizar estos términos. La versión vigente estará siempre disponible en Configuración.',
  ]),
];

const privacidad = [
  SeccionLegal('1. Responsable', [
    'Motorrepuestos Chahua es responsable del tratamiento de los datos personales registrados en esta aplicación, conforme a la Ley N.° 29733, Ley de Protección de Datos Personales, y su reglamento.',
  ]),
  SeccionLegal('2. Datos que se tratan', [
    'Datos de identificación y contacto: nombres, apellidos, DNI, cargo, área, teléfono, correo y foto de perfil.',
    'Datos laborales: horarios, marcaciones de entrada y salida, permisos, faltas, montos por día y pagos.',
    'Datos biométricos: una foto oficial del rostro y un vector numérico de 128 valores que la representa, usado solo para identificar a la persona al marcar asistencia. También se guarda la foto tomada en cada marcación como evidencia.',
  ]),
  SeccionLegal('3. Finalidad', [
    'Controlar la asistencia, calcular y registrar los pagos, gestionar permisos y atender consultas del personal. Los datos no se usan con fines comerciales ni se venden a terceros.',
  ]),
  SeccionLegal('4. Datos biométricos', [
    'El registro del rostro requiere el consentimiento del trabajador, que lo otorga al momento de su registro. El rostro se procesa únicamente en el servidor de la empresa para comparar el vector facial; las fotos se guardan en almacenamiento privado al que solo accede el administrador y el propio trabajador.',
    'El trabajador puede solicitar al administrador la eliminación de su registro facial; en ese caso su asistencia se registrará de forma manual.',
  ]),
  SeccionLegal('5. Almacenamiento y seguridad', [
    'La información se almacena en servicios en la nube (Supabase y Vercel) con conexión cifrada, contraseñas protegidas y reglas de acceso por usuario: cada trabajador solo puede ver su propia información.',
  ]),
  SeccionLegal('6. Conservación', [
    'Los datos se conservan mientras dure la relación laboral y luego durante el plazo que exijan las normas laborales y tributarias.',
  ]),
  SeccionLegal('7. Derechos del titular', [
    'El trabajador puede ejercer sus derechos de acceso, rectificación, cancelación y oposición (ARCO) comunicándose con el administrador o por WhatsApp al 928033056. Puede actualizar su teléfono, correo y foto de perfil directamente en Configuración.',
  ]),
];

const preguntas = [
  ('¿Cómo marco mi asistencia?', 'Al llegar y al salir, el administrador escanea tu rostro con su celular. No necesitas hacer nada en tu app.'),
  ('¿Qué pasa si llego tarde?', 'Desde las 08:11 se registra como tardanza. Las tardanzas no descuentan, pero quedan en tu historial.'),
  ('¿Cómo pido un permiso?', 'En Permisos → Solicitar, o escribiéndole al Asistente IA. Queda pendiente hasta que el administrador lo apruebe.'),
  ('¿Cuándo me pagan?', 'Cuando lo solicites: por semana, quincena, mes o días. En Pagos ves lo que tienes por cobrar y los pagos recibidos.'),
  ('Olvidé mi contraseña', 'Pide al administrador que la restablezca. Luego cámbiala en Configuración → Seguridad.'),
];
