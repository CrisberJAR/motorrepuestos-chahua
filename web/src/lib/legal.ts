// Textos legales y de ayuda (la app móvil tiene la misma copia en lib/core/legal.dart).

export const VERSION_APP = '1.1.0';
export const ACTUALIZADO = '10 de noviembre de 2026';
export const EMPRESA = {
  nombre: 'Motorrepuestos Chahua',
  whatsapp: '928033056',
  horario: 'Lunes a sábado, de 08:00 a 19:00',
};

export type SeccionLegal = { titulo: string; parrafos: string[] };

export const TERMINOS: SeccionLegal[] = [
  {
    titulo: '1. Objeto',
    parrafos: [
      'Estos términos regulan el uso de la aplicación móvil y web "Chahua Personal" de Motorrepuestos Chahua, que sirve para registrar la asistencia, gestionar permisos, consultar pagos y comunicarse con el asistente virtual.',
      'Al iniciar sesión, el usuario declara haber leído y aceptado estos términos.',
    ],
  },
  {
    titulo: '2. Cuentas de acceso',
    parrafos: [
      'Cada trabajador recibe una cuenta personal: el usuario es su DNI y la contraseña inicial también. Se recomienda cambiarla en Configuración en el primer ingreso.',
      'La cuenta es personal e intransferible. El usuario es responsable de no compartir su contraseña. Si la olvida, el administrador puede restablecerla.',
    ],
  },
  {
    titulo: '3. Roles',
    parrafos: [
      'El administrador registra la asistencia mediante reconocimiento facial desde su celular, gestiona al personal, aprueba o rechaza permisos y registra los pagos.',
      'El trabajador puede consultar su asistencia, solicitar permisos, ver lo que tiene por cobrar y su historial de pagos, y descargar sus reportes. No puede ver información de otras personas.',
    ],
  },
  {
    titulo: '4. Asistencia y pagos',
    parrafos: [
      'El horario es de lunes a sábado de 08:00 a 19:00, con refrigerio de 13:00 a 14:00 y 10 minutos de tolerancia. Las tardanzas se registran pero no generan descuento.',
      'Un día laborable sin marcación ni permiso aprobado se considera falta y no se paga. Los permisos no se pagan, salvo que el administrador los apruebe con goce.',
      'El pago puede ser fijo por día o por rendimiento diario. El trabajador puede solicitar su pago en cualquier momento; el administrador lo registra indicando el periodo, el método (efectivo, Yape, Plin o transferencia) y, si corresponde, bonos o descuentos.',
      'Los montos mostrados en la aplicación son informativos y se basan en los registros del sistema. Ante cualquier diferencia, el trabajador debe comunicarlo al administrador.',
    ],
  },
  {
    titulo: '5. Asistente virtual',
    parrafos: [
      'El asistente usa inteligencia artificial (Google Gemini) para responder consultas y registrar solicitudes de permiso. Puede cometer errores: la información oficial es la que figura en los módulos de la aplicación.',
    ],
  },
  {
    titulo: '6. Uso adecuado',
    parrafos: [
      'Está prohibido suplantar a otra persona, intentar marcar asistencia con fotos de terceros, acceder a cuentas ajenas o alterar la información del sistema. Estas conductas pueden dar lugar a medidas disciplinarias.',
    ],
  },
  {
    titulo: '7. Cambios',
    parrafos: ['Motorrepuestos Chahua puede actualizar estos términos. La versión vigente estará siempre disponible en Configuración.'],
  },
];

export const PRIVACIDAD: SeccionLegal[] = [
  {
    titulo: '1. Responsable',
    parrafos: [
      'Motorrepuestos Chahua es responsable del tratamiento de los datos personales registrados en esta aplicación, conforme a la Ley N.° 29733, Ley de Protección de Datos Personales, y su reglamento.',
    ],
  },
  {
    titulo: '2. Datos que se tratan',
    parrafos: [
      'Datos de identificación y contacto: nombres, apellidos, DNI, cargo, área, teléfono, correo y foto de perfil.',
      'Datos laborales: horarios, marcaciones de entrada y salida, permisos, faltas, montos por día y pagos.',
      'Datos biométricos: una foto oficial del rostro y un vector numérico de 128 valores que la representa, usado solo para identificar a la persona al marcar asistencia. También se guarda la foto tomada en cada marcación como evidencia.',
    ],
  },
  {
    titulo: '3. Finalidad',
    parrafos: [
      'Controlar la asistencia, calcular y registrar los pagos, gestionar permisos y atender consultas del personal. Los datos no se usan con fines comerciales ni se venden a terceros.',
    ],
  },
  {
    titulo: '4. Datos biométricos',
    parrafos: [
      'El registro del rostro requiere el consentimiento del trabajador, que lo otorga al momento de su registro. El rostro se procesa únicamente en el servidor de la empresa para comparar el vector facial; las fotos se guardan en almacenamiento privado al que solo accede el administrador y el propio trabajador.',
      'El trabajador puede solicitar al administrador la eliminación de su registro facial; en ese caso su asistencia se registrará de forma manual.',
    ],
  },
  {
    titulo: '5. Almacenamiento y seguridad',
    parrafos: [
      'La información se almacena en servicios en la nube (Supabase y Vercel) con conexión cifrada, contraseñas protegidas y reglas de acceso por usuario: cada trabajador solo puede ver su propia información.',
    ],
  },
  {
    titulo: '6. Conservación',
    parrafos: ['Los datos se conservan mientras dure la relación laboral y luego durante el plazo que exijan las normas laborales y tributarias.'],
  },
  {
    titulo: '7. Derechos del titular',
    parrafos: [
      'El trabajador puede ejercer sus derechos de acceso, rectificación, cancelación y oposición (ARCO) comunicándose con el administrador o por WhatsApp al 928033056. Puede actualizar su teléfono, correo y foto de perfil directamente en Configuración.',
    ],
  },
];

export const PREGUNTAS: { p: string; r: string }[] = [
  { p: '¿Cómo marco mi asistencia?', r: 'Al llegar y al salir, el administrador escanea tu rostro con su celular. No necesitas hacer nada en tu app.' },
  { p: '¿Qué pasa si llego tarde?', r: 'Desde las 08:11 se registra como tardanza. Las tardanzas no descuentan, pero quedan en tu historial.' },
  { p: '¿Cómo pido un permiso?', r: 'En Permisos → Solicitar, o escribiéndole al Asistente IA. Queda pendiente hasta que el administrador lo apruebe.' },
  { p: '¿Cuándo me pagan?', r: 'Cuando lo solicites: por semana, quincena, mes o días. En Pagos ves lo que tienes por cobrar y los pagos recibidos.' },
  { p: 'Olvidé mi contraseña', r: 'Pide al administrador que la restablezca. Luego cámbiala en Configuración → Seguridad.' },
];
