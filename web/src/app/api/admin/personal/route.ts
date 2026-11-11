import { exigirSesion } from '@/lib/auth';
import { ahoraLima } from '@/lib/fechas';
import { ErrorHttp, json, leerImagen, manejar } from '@/lib/http';
import { guardarRostroOficial, verificarRostroNoDuplicado } from '@/lib/personal-rostro';
import { analizarRostro, normalizarFoto } from '@/lib/rostro';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { asegurarUsuario } from '@/lib/usuarios';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const maxDuration = 30;

const AREAS = ['Administración', 'Ventas', 'Taller', 'Almacén', 'Caja', 'Logística'];
const DIAS_LABORABLES_MES = 26;

/**
 * POST /api/admin/personal
 * Solo el administrador (desde la web o la app). Registra un trabajador nuevo en un solo paso:
 *   1. valida datos y la foto del rostro (un único rostro, que no pertenezca a otra persona)
 *   2. inserta la fila en personal
 *   3. guarda la foto en rostros_personal y su descriptor facial
 *   4. crea su acceso: usuario = DNI, contraseña = DNI
 * Si algo falla después de insertar, deshace lo creado.
 *
 * multipart/form-data: dni, nombres, apellidos, cargo, area, telefono?, correo?, pago_por_dia, tipo_pago? (fijo|variable),
 *                      hora_entrada? (08:00), tolerancia_min? (10), rol? (trabajador), imagen
 */
export const POST = manejar(async (req) => {
  await exigirSesion(req, 'admin');
  const recibido = await leerImagen(req);
  const c = recibido!.campos;

  const dni = (c.dni || '').trim();
  const nombres = (c.nombres || '').trim();
  const apellidos = (c.apellidos || '').trim();
  const cargo = (c.cargo || '').trim();
  const area = (c.area || '').trim();
  const pagoPorDia = Number(c.pago_por_dia);
  const horaEntrada = (c.hora_entrada || '08:00').trim();
  const tolerancia = c.tolerancia_min ? Number(c.tolerancia_min) : 10;
  const rol = c.rol === 'admin' ? 'admin' : 'trabajador';
  const tipoPago = c.tipo_pago === 'variable' ? 'variable' : 'fijo';

  if (!/^\d{8}$/.test(dni)) throw new ErrorHttp(400, 'El DNI debe tener 8 dígitos.');
  if (!nombres || !apellidos) throw new ErrorHttp(400, 'Completa nombres y apellidos.');
  if (!cargo) throw new ErrorHttp(400, 'Indica el cargo.');
  if (!AREAS.includes(area)) throw new ErrorHttp(400, `El área debe ser una de: ${AREAS.join(', ')}.`);
  if (!Number.isFinite(pagoPorDia) || pagoPorDia <= 0) throw new ErrorHttp(400, 'El pago por día debe ser mayor que 0.');
  if (!/^\d{2}:\d{2}(:\d{2})?$/.test(horaEntrada)) throw new ErrorHttp(400, 'La hora de entrada debe tener el formato HH:MM.');
  if (!Number.isInteger(tolerancia) || tolerancia < 0 || tolerancia > 60) throw new ErrorHttp(400, 'La tolerancia debe estar entre 0 y 60 minutos.');
  if (c.correo && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(c.correo)) throw new ErrorHttp(400, 'El correo no es válido.');

  const sb = supabaseAdmin();
  const { data: existe } = await sb.from('personal').select('id').eq('dni', dni).maybeSingle();
  if (existe) throw new ErrorHttp(409, `Ya existe un trabajador con DNI ${dni}.`);

  // La foto se valida antes de crear nada.
  const jpeg = await normalizarFoto(recibido!.buffer);
  const rostro = await analizarRostro(jpeg, true);
  await verificarRostroNoDuplicado(rostro.descriptor);

  const { data: nuevo, error } = await sb
    .from('personal')
    .insert({
      dni, nombres, apellidos, cargo, area,
      telefono: c.telefono?.trim() || null,
      correo: c.correo?.trim() || null,
      pago_por_dia: pagoPorDia,
      tipo_pago: tipoPago,
      sueldo_base: Math.round(pagoPorDia * DIAS_LABORABLES_MES * 100) / 100,
      hora_entrada: horaEntrada.length === 5 ? `${horaEntrada}:00` : horaEntrada,
      tolerancia_min: tolerancia,
      rol,
      estado: 'activo',
      fecha_ingreso: ahoraLima().fecha,
    })
    .select('id, dni, nombres, apellidos, cargo, area, rol')
    .single();
  if (error || !nuevo) throw new ErrorHttp(400, `No se pudo registrar: ${error?.message}`);

  let usuarioId: string | null = null;
  try {
    const { ruta } = await guardarRostroOficial(nuevo.id, jpeg);
    const usuario = await asegurarUsuario(nuevo);
    usuarioId = usuario.id;

    return json(
      {
        ok: true,
        mensaje: `${nombres} ${apellidos} fue registrado. Su usuario y contraseña inicial son su DNI (${dni}).`,
        personal: { ...nuevo, foto_rostro_url: ruta },
        acceso: { usuario: dni, clave_inicial: dni },
      },
      201,
    );
  } catch (e) {
    await sb.storage.from('rostros_personal').remove([`${nuevo.id}/rostro.jpg`]);
    if (usuarioId) await sb.auth.admin.deleteUser(usuarioId);
    await sb.from('personal').delete().eq('id', nuevo.id);
    throw e;
  }
});
