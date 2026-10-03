import './globals.css';
import Nav from '../lib/Nav';

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-slate-100 text-slate-900 antialiased">
        <div className="flex min-h-screen">
          <Nav />
          <div className="flex-1 min-w-0">
            <main className="p-4 md:p-6 max-w-6xl mx-auto w-full">{children}</main>
          </div>
        </div>
      </body>
    </html>
  );
}
