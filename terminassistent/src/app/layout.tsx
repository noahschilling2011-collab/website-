import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Terminassistent',
  description: 'Erledigt Terminabsprachen und Fristen per Mail.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="de">
      <body>{children}</body>
    </html>
  );
}
