# Motorrepuestos Chahua · Sistema de gestión de personal

Tesis: *Desarrollo de una Aplicación Móvil Inteligente para la Gestión y Control Empresarial*.

| Carpeta | Qué es |
|---|---|
| `supabase/` | Base de datos PostgreSQL: tablas, RLS, Storage, Realtime y datos semilla. Incluye los scripts para ejecutarla. |
| `web/` | Aplicación web Next.js (Tailwind, Recharts) y endpoints de IA. Se publica en Vercel. |
| `movil/` | App Android en Flutter (MVVM): cámara con detección facial en vivo, módulos y chat. |
| `prototipo/` | Prototipo navegable inicial. |

## Arquitectura
```
App Flutter (admin / trabajador) ─┐                     ┌─ Supabase Auth (login con DNI)
                                   ├─ supabase_flutter ─┤  PostgreSQL + RLS + Realtime
Web Next.js (admin / trabajador) ──┘                     └─ Storage (rostros, capturas)
        │
        └─ /api/ia/* en Vercel ──► face-api (TensorFlow, WASM): descriptor de 128 valores → pgvector (1:N)
                               └─► Gemini Flash + Function Calling (consultar_estado_personal, registrar_permiso_chat)
```

## Enlaces
- Web: https://chahua-personal.vercel.app
- APK: `ChahuaPersonal.apk` (raíz del proyecto)

## Usuarios de prueba
Para todos, el usuario y la contraseña inicial son el DNI.

| Rol | DNI |
|---|---|
| Administrador (Ricardo Torres) | 45781236 |
| Vendedor (Carlos Gómez) | 72345678 |
| Mecánico (José Ramos) | 70984512 |
| Almacenero (Miguel Paredes) | 73561249 |
| Cajera (Lucía Mendoza) | 71239845 |

## 1. Base de datos
Para ejecutarla desde cero, usa `supabase/01_esquema_chahua.sql` (en el SQL Editor o con `node supabase/ejecutar-sql.mjs 01_esquema_chahua.sql`). Después aplica `02_ajuste_rostro.sql` y `03_planilla_sin_cambios.sql`, y crea los accesos con `node supabase/crear-usuarios.mjs`.

## 2. Web y API (Next.js)
```bash
cd web
npm install
npm run build && npm start      # http://localhost:3000
```
Las variables necesarias están en `web/.env.example`. Las mismas se cargan en Vercel, en Settings → Environment Variables.

## 3. App Android (Flutter)
```bash
cd movil
flutter pub get
# Prueba con el celular conectado por USB (depuración USB activada) y la web corriendo en la PC:
adb reverse tcp:3000 tcp:3000
flutter run --release

# APK para instalar, apuntando a la web publicada en Vercel:
flutter build apk --release --dart-define=API_URL=https://chahua-personal.vercel.app
# Resultado: movil/build/app/outputs/flutter-apk/app-release.apk
```

## Reglas de negocio
- Horario de lunes a sábado, de 08:00 a 19:00. Refrigerio de 13:00 a 14:00.
- Tolerancia de 10 minutos: hasta las 08:10 es puntual; desde las 08:11 es tardanza. **La tardanza no descuenta.**
- Un día laborable sin entrada y sin permiso aprobado cuenta como falta. Las faltas no se pagan.
- Los permisos **no se pagan** por defecto. El administrador puede marcarlos "con goce".
- Pago = (días asistidos + días de permiso con goce) × pago por día − descuentos + bonos.
- Solo el administrador registra asistencia, con el reconocimiento facial **desde su celular**. El personal solo consulta su información y solicita permisos.
