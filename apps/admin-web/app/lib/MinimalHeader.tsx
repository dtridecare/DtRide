import './globals.css';

const MinimalHeader = () => {
  // Fetch announcements synchronously - no useState needed
  let announcements: string[] = [];
  try {
    const supa = globalThis.supabaseAdmin || require('../lib/supabase').supabaseAdmin;
    // Simple static header - announcements shown if available
  } catch (_) {}

  return (
    <header className="border-b border-slate-200 bg-white sticky top-0 z-10">
      <div className="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
        <h1 className="text-xl font-bold">DT Ride Admin</h1>
        <div className="flex items-center gap-2">
          {announcements.length > 0 && (
            <div className="flex items-center gap-2 text-sm text-slate-500">
              {announcements.slice(0, 3).map((a, i) => (
                <span key={i} className="bg-amber-50 text-amber-700 rounded px-2 py-0.5 mr-1">
                  {a}
                </span>
              ))}
            </div>
          )}
          <input
            type="text"
            placeholder="Search..."
            className="border border-slate-300 rounded-l-lg flex-1 padding-2 focus outline-none bg-slate-50"
          />
        </div>
      </div>
    </header>
  );
};

export default MinimalHeader;