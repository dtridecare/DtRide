export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: 'system-ui', margin: 0 }}>
        <nav style={{ padding: 12, borderBottom: '1px solid #ddd', display: 'flex', gap: 16 }}>
          <a href="/">Dashboard</a>
          <a href="/kyc">KYC</a>
          <a href="/plans">Plans</a>
          <a href="/fares">Fares</a>
          <a href="/rides">Rides</a>
          <a href="/disputes">Disputes</a>
          <a href="/coupons">Coupons</a>
          <a href="/login">Login</a>
        </nav>
        <div style={{ padding: 24 }}>{children}</div>
      </body>
    </html>
  );
}
