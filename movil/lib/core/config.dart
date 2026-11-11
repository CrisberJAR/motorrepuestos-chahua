/// Configuración de la app. Se puede cambiar al compilar con --dart-define, por ejemplo:
///   flutter build apk --dart-define=API_URL=https://chahua-personal.vercel.app
class Config {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://keicfpvtuhmhvfkpqsre.supabase.co',
  );

  /// Clave pública (anon). Es segura en la app: los datos están protegidos por RLS.
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtlaWNmcHZ0dWhtaHZma3Bxc3JlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQyNDc5NzEsImV4cCI6MjEwOTgyMzk3MX0.wdPplNY2osUyY5WsVjPMKNAokA6zVDo1NuASW_eGfnU',
  );

  /// Servidor Next.js con los endpoints de IA (Vercel).
  /// En desarrollo con el celular por USB: `adb reverse tcp:3000 tcp:3000` y se usa localhost.
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  /// El usuario escribe su DNI; en Supabase Auth el correo interno es `<dni>@chahua.pe`
  static const dominioLogin = 'chahua.pe';
  static String correoDesdeDni(String dni) => '${dni.trim()}@$dominioLogin';
}
