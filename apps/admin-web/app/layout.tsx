import './globals.css';

const NAV = [
  { href: '/', label: 'Dashboard' },
  { href: '/kyc', label: 'KYC' },
  { href: '/plans', label: 'Plans' },
  { href: '/fares', label: 'Fares' },
  { href: '/rides', label: 'Live rides' },
  { href: '/disputes', label: 'Disputes' },
  { href: '/coupons', label: 'Coupons' },
];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-slate-100 text-slate-900 antialiased">
        <div className="flex min-h-screen">
          <aside className="w-60 shrink-0 bg-slate-900 text-slate-200 p-5 hidden md:block">
            <div className="text-xl font-bold text-white mb-1">DT Ride</div>
            <div className="text-xs text-slate-400 mb-6">Ops console</div>
            <nav className="flex flex-col gap-1">
              {NAV.map((n) => (
                <a key={n.href} href={n.href}
                  className="rounded-lg px-3 py-2 text-sm hover:bg-slate-800 hover:text-white">
                  {n.label}
                </a>
              ))}
              <a href="/login" className="rounded-lg px-3 py-2 text-sm text-slate-400 hover:bg-slate-800 hover:text-white mt-4">
                Login
              </a>
            </nav>
          </aside>
          <div className="flex-1 min-w-0">
            <header className="md:hidden bg-slate-900 text-slate-200 px-4 py-3 flex gap-4 overflow-x-auto text-sm">
              {NAV.map((n) => <a key={n.href} href={n.href} className="whitespace-nowrap">{n.label}</a>)}
            </header>
            <main className="p-6 max-w-6xl mx-auto">{children}</main>
          </div>
        </div>
      </body>
    </html>
  );
}
