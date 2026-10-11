import './globals.css';
import { supabaseAdmin } from './lib/supabase';
import AdminGate from './lib/AdminGate';

export const dynamic = 'force-dynamic';

// Shared search state across admin pages
const AdminSearch = ({ anons }: { anons: string[] }) => {
  const [query, setQuery] = React.useState('');
  const handleSearch = (e: React.ChangeEvent<HTMLInputElement>) => {
    setQuery(e.target.value);
  };
  return (
    <div className="border-b border-slate-200 pb-4 mb-4">
      <div className="flex items-center gap-2">
        <svg className="h-5 w-5 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path className="stroke-current" d="M21 21l-5.3-5.3a.75.75 0 0 0-1.06 0L8 21M21 21l-5.3-5.3a.75.75 0 0 0-1.06 0L8 21M21 21l-5.3-5.3a.75.75 0 0 0-1.06 0L8 21M21 21l-5.3-5.3a.75.75 0 0 0-1.06 0L8 21M4 8.75a2.25 2.25 0 1 1 0-4.5 2.25 2.25 0 0 1 0 4.5m8.25 0a2.25 2.25 0 1 1 0-4.5 2.25 2.25 0 0 1 0 4.5m-8.25 0a2.25 2.25 0 1 1 0-4.5 2.25 2.25 0 0 1 0 4.5m14.375-3.125a.375.375 0 1 0 0-.75.375.375 0 0 0 0 .75m0 0a.375.375 0 1 0 0-.75.375.375 0 0 0 0 .75m-5.5 0a.375.375 0 1 0 0-.75.375.375 0 0 0 0 .75m0 8.25a.375.375 0 1 0 0-.75.375.375 0 0 0 0 .75m-5.5 0a.375.375 0 1 0 0-.75.375.375 0 0 0 0 .75m0-8.25a.375.375 0 1 0 0-.75.375.375 0 0 0 0 .75"/>
        </svg>
        <input
          type="text"
          placeholder="Search rides, drivers, KYC, riders..."
          className="border border-slate-300 rounded-l-lg padding-2 focus outline-none bg-slate-50"
          onChange={handleSearch}
          value={query}
        />
        <button
          onClick={() => {
            // Global search - filter based on current page context
            // Will be handled by each page
          }
          className="bg-indigo-600 text-white rounded-r-lg px-3 py-1 text-sm hidden sm:block"
        >
          Search
        </button>
      </div>
    </div>
  );
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  // Fetch recent announcements for header display
  const [announcements, setAnnouncements] = React.useState<string[]>([]);
  React.useEffect(() => {
    const init = async () => {
      try {
        const supa = supabaseAdmin();
        const { data } = await supa.from('platform_announcements').select('title').order('is_pinned', { ascending: false }).limit(3);
        if (data) setAnnouncements(data.map((d: any) => d.title));
      } catch (_) {}
    };
    init();
  }, []);

  return (
    <html lang="en">
      <body className="min-h-screen bg-slate-50 text-slate-900">
        <AdminGate>
          {/* Header with announcements and search */}
          <header className="border-b border-slate-200 bg-white sticky top-0 z-10">
            <div className="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
              <h1 className="text-xl font-bold">DT Ride Admin</h1>
              <div className="flex items-center gap-2">
                <AnnouncementsBanner announcements={announcements} />
                <AdminSearch anons={announcements} />
              </div>
            </div>
          </header>

          <main className="max-w-7xl mx-auto p-4">
            {children}
          </main>
        </AdminGate>
      </body>
    </html>
  );
}

function AnnouncementsBanner({ announcements }: { announcements: string[] }) {
  return (
    <div className="flex items-center gap-2 text-sm text-slate-500">
      {announcements.length > 0 && (
        <div>
          {announcements.slice(0, 3).map((a, i) => (
            <span key={i} className="bg-amber-50 text-amber-700 rounded px-2 py-0.5 mr-1">
              {a}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}