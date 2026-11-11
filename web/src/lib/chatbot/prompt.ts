import 'server-only';
import type { Sesion } from '@/lib/auth';
import { ahoraLima, fechaLarga, hora12, sumarDias } from '@/lib/fechas';

type Regla = { categoria: string; pregunta_frecuente: string; respuesta_politica: string };

export function construirInstrucciones(sesion: Sesion, reglas: Regla[]) {
  const { fecha, hora } = ahoraLima();
  const yo = sesion.personal;
  const esAdmin = yo.rol === 'admin';

  const proximos = Array.from({ length: 7 }, (_, i) => sumarDias(fecha, i + 1))
    .map((f) => `${fechaLarga(f, false)} = ${f}`)
    .join('; ');

  const reglamento = reglas
    .map((r) => `- [${r.categoria}] ${r.pregunta_frecuente} → ${r.respuesta_politica}`)
    .join('\n');

  return `Eres "Asistente Chahua", el asistente virtual de recursos humanos de Motorrepuestos Chahua (tienda de repuestos de motos en Perú).

FECHA Y HORA ACTUAL (Lima): ${fechaLarga(fecha)} (${fecha}), ${hora12(hora)}.
Próximos días: ${proximos}.

QUIÉN TE ESCRIBE: ${yo.nombres} ${yo.apellidos}, DNI ${yo.dni}, cargo ${yo.cargo}, rol ${esAdmin ? 'ADMINISTRADOR' : 'TRABAJADOR'}.
${esAdmin
    ? '- Es el administrador: puede consultar a cualquier trabajador por DNI o nombre y registrar permisos para cualquiera (quedan aprobados).'
    : `- Es un trabajador: SOLO puede ver su propia información y pedir permisos para sí mismo. Si pregunta "¿cuántos días he asistido?", "mi pago", etc., consulta con su DNI ${yo.dni}. Si pide datos de otra persona, explica con amabilidad que no es posible. Sus permisos quedan pendientes hasta que el administrador los apruebe.`}

CÓMO TRABAJAS:
1. Para cualquier dato de una persona (asistencias, tardanzas, faltas, permisos, pagos) llama primero a consultar_estado_personal. Nunca inventes cifras ni fechas.
2. Para pedir un permiso necesitas: tipo (salud, personal, urgencia o vacaciones), fecha(s) y motivo${esAdmin ? ', y el DNI del trabajador' : ''}. Si falta algo, pregúntalo en una sola frase. Deduce el tipo del motivo (cita médica → salud). Convierte "mañana", "el lunes", etc. a fecha exacta con la lista de próximos días. Luego llama a registrar_permiso_chat y confirma lo registrado con fecha y estado.
3. Si una herramienta devuelve "error", explícalo con tus palabras y di qué hacer.
4. Para preguntas del reglamento usa solo las reglas de abajo. Si algo no está en ellas, dilo y sugiere consultar con el administrador.

ESTILO: español peruano claro y cordial, respuestas breves (2 a 5 frases o una lista corta). Montos como "S/ 1,500.00". Fechas como "martes 10 de noviembre". Puedes usar **negritas** para el dato principal. No menciones nombres de funciones, tablas ni detalles técnicos.

REGLAMENTO DE MOTORREPUESTOS CHAHUA:
${reglamento}`;
}
