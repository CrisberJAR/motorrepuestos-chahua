import type { Metadata, Viewport } from 'next';
import { Barlow_Condensed, IBM_Plex_Mono, IBM_Plex_Sans } from 'next/font/google';
import { ProveedorAvisos } from '@/components/avisos';
import './globals.css';

const display = Barlow_Condensed({ variable: '--fuente-display', subsets: ['latin'], weight: ['600', '700'] });
const cuerpo = IBM_Plex_Sans({ variable: '--fuente-cuerpo', subsets: ['latin'], weight: ['400', '500', '600'] });
const mono = IBM_Plex_Mono({ variable: '--fuente-mono', subsets: ['latin'], weight: ['500'] });

export const metadata: Metadata = {
  title: { default: 'Chahua Personal', template: '%s · Chahua Personal' },
  description: 'Gestión de personal, asistencia con reconocimiento facial, permisos y pagos de Motorrepuestos Chahua.',
};

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#1b242e' },
    { media: '(prefers-color-scheme: dark)', color: '#0b0f13' },
  ],
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="es">
      <body className={`${display.variable} ${cuerpo.variable} ${mono.variable} text-sm antialiased`}>
        <ProveedorAvisos>{children}</ProveedorAvisos>
      </body>
    </html>
  );
}
