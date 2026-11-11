# API · Motorrepuestos Chahua

Base: `https://<tu-proyecto>.vercel.app` (local: `http://localhost:3000`).

**Autenticación**
- App Flutter: `Authorization: Bearer <access_token>` obtenido con `supabase.auth.signInWithPassword(email: '<dni>@chahua.pe', password: ...)`.
- Web: cookies de sesión de `@supabase/ssr`, que se envían solas.

Todas las respuestas son JSON. Si hay un error, la respuesta es `{ ok: false, error: "mensaje para mostrar", codigo?: "..." }`.

| Endpoint | Quién | Para qué |
|---|---|---|
| `POST /api/ia/identificar-rostro` | Admin | Escanea un rostro (1:N) y registra la entrada o la salida |
| `POST /api/ia/registrar-rostro` | Admin | Registra o reemplaza la foto oficial de un trabajador existente |
| `POST /api/ia/chatbot` | Todos | Asistente con Gemini: consultas y registro de permisos |
| `POST /api/admin/personal` | Admin | Alta de trabajador con foto y acceso DNI/DNI |
| `POST /api/admin/cambiar-clave` | Admin | Cambia la contraseña de cualquiera, incluida la suya |

---

## POST /api/ia/identificar-rostro
`multipart/form-data`: `imagen` (JPG/PNG/WEBP, ≤ 5 MB) · `solo_identificar` opcional (`"true"` solo identifica, sin registrar).
También se puede enviar JSON: `{ "imagen_base64": "data:image/jpeg;base64,..." }`.

**200**:
```json
{
  "ok": true, "reconocido": true, "registrado": true, "tipo": "entrada",
  "mensaje": "Rostro identificado: Carlos Gómez - 96.9% coincidencia - Entrada registrada 07:56 a. m.",
  "trabajador": { "id": "uuid", "dni": "72345678", "nombre_corto": "Carlos Gómez", "cargo": "...", "foto_rostro_url": "uuid/rostro.jpg" },
  "confianza": 96.9,
  "asistencia": { "fecha": "2026-11-09", "hora_entrada": "07:56:12", "hora_salida": null, "estado": "asistio" },
  "foto_evidencia_url": "uuid/2026-11-09_075612.jpg"
}
```
Valores de `tipo`:
- `entrada`: primer escaneo del día.
- `salida`: escaneo hecho 30 minutos o más después de la entrada.
- `duplicado`: escaneo hecho antes de esos 30 minutos.
- `completo`: el trabajador ya tiene entrada y salida registradas.
- `no_laborable`: domingo.

Errores:
- **404** `no_reconocido` o `sin_registros`.
- **409** `ambiguo`.
- **422** `sin_rostro` o `rostro_pequeno`.
- **403** si quien llama no es administrador.

## POST /api/ia/registrar-rostro
`multipart`: `personal_id` e `imagen` (un solo rostro).
- **200** `{ ok, mensaje, foto_rostro_url }`.
- **409** `rostro_duplicado`: ese rostro ya pertenece a otra persona.
- **422** `varios_rostros` o `sin_rostro`.

## POST /api/ia/chatbot
```json
{ "origen": "movil", "mensajes": [ { "rol": "usuario", "texto": "Necesito pedir permiso para mañana por cita médica, mi DNI es 72345678" } ] }
```
Envía el historial completo; el servidor usa como máximo los últimos 20 mensajes. `rol` puede ser `usuario` o `asistente`.

**200**:
```json
{ "ok": true, "respuesta": "¡Listo, Carlos! ...", "modelo": "gemini-3.5-flash",
  "acciones": [ { "herramienta": "registrar_permiso_chat", "argumentos": {...}, "ok": true, "resultado": { "registrado": true, "estado": "pendiente" } } ] }
```
Las herramientas de Gemini son `consultar_estado_personal` y `registrar_permiso_chat`.
- Un trabajador solo puede consultar sus propios datos y sus permisos quedan **pendientes**.
- Los permisos que registra el admin quedan **aprobados**.

Errores: **429**, cuando se alcanza el límite por minuto del plan gratuito de Gemini, y **502**, cuando el modelo no está disponible.

## POST /api/admin/personal
`multipart` con estos campos:
- `dni`, `nombres`, `apellidos`, `cargo`, `pago_por_dia`, `imagen`.
- `area`: Administración, Ventas, Taller, Almacén, Caja o Logística.
- Opcionales: `telefono`, `correo`, `hora_entrada` (`08:00`), `tolerancia_min` (`10`), `rol` (`trabajador` o `admin`).

**201** `{ ok, mensaje, personal, acceso: { usuario, clave_inicial } }`. Primero valida la foto; si algo falla después, deshace todo lo creado.

## POST /api/admin/cambiar-clave
```json
{ "dni": "72345678", "nueva_clave": "nueva2026" }
```
También acepta `personal_id` en lugar de `dni`. La clave debe tener entre 6 y 72 caracteres.

---

## Lecturas directas a Supabase (sin endpoint; las protege RLS)
- Tablas `personal`, `asistencias`, `permisos`, `pagos` y `conocimiento_empresa`.
- RPC `resumen_asistencia(p_desde, p_hasta, p_personal_id?)` y `detalle_asistencia(...)`.
- Vistas `v_asistencia_semana_actual` y `v_asistencia_mes_actual`.
- RPC `generar_planilla('AAAA-MM')`, solo para el admin.
- Aprobar o rechazar un permiso: `update permisos set estado, con_goce`, solo el admin.
- Marcar un pago: `update pagos set estado_pago = 'pagado', descuentos, bonos`, solo el admin.
- Fotos: `storage.from('rostros_personal' | 'capturas_asistencia').createSignedUrl(ruta, 3600)`.
- Tiempo real: suscribirse a `postgres_changes` de `asistencias`, `permisos`, `pagos` y `personal`.
