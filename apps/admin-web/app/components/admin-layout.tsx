'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { supabaseAdmin } from '../lib/supabase';

interface AdminLayoutProps {
  children: React.ReactNode;
}

const NAV_ITEMS = [
  { name: 'Dashboard', href: '/dashboard', icon: '📊' },
  { name: 'Live Rides', href: '/rides', icon: '🚗' },
  { name: 'Service Areas', href: '/areas', icon: '🗺️' },
  { name: 'Fare Config', href: '/fares', icon: '💰' },
  { name: 'Plans', href: '/plans', icon: '💳' },
  { name: 'Coupons', href: '/coupons', icon: '🎫' },
  { name: 'Users & Drivers', href: '/users', icon: '👥' },
  { name: 'Driver KYC', href: '/kyc', icon: '🪪' },
  { name: 'Disputes', href: '/disputes', icon: '🚨' },
];

export default function AdminLayout({ children }: AdminLayoutProps) {
  const [isCollapsed, setIsCollapsed] = useState(false);
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const pathname = usePathname();

  return (
    <div className="relative flex flex-col h-screen overflow-hidden">
      {/* Sidebar */}
      <aside
        className={`fixed left-0 top-0 h-full border-r border-slate-200 bg-white z-50 ${isCollapsed ? 'w-20' : 'w-64'} transition-all duration-300 ease-in-out`}
      >
        <div className="flex h-14 items-center justify-between px-4 bg-white border-b border-slate-200">
          <div className="flex items-center gap-2">
            <div className="h-8 w-8 rounded-lg bg-blue-600 flex items-center justify-center">
              <span className="text-white font-bold text-lg">DT</span>
            </div>
            <span className={isCollapsed ? 'hidden' : 'text-xl font-bold tracking-tight text-slate-900'}>DT Ride</span>
          </div>
          <button onClick={() => setIsSidebarOpen(false)} className="md:hidden p-2 text-slate-500 hover:text-slate-700">
            <span className="material-symbols-rounded">close</span>
          </button>
        </div>
        <nav className="flex-1 overflow-y-auto py-4 space-y-1">
          {NAV_ITEMS.map((item) => {
            const isActive = pathname === item.href || pathname.startsWith(item.href + '/');
            return (
              <Link key={item.name} href={item.href} className={`flex items-center gap-3 px-4 py-3 text-sm font-medium rounded-lg transition-colors duration-200 ${isActive ? 'bg-blue-50 text-blue-700' : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900'}`}>
                <span className="text-lg w-6 text-center">{item.icon}</span>
                <span className={isCollapsed ? 'hidden' : 'block'}>{item.name}</span>
              </Link>
            );
          })}
        </nav>
        <div className="p-4 border-t border-slate-200 bg-slate-50">
          <button onClick={() => setIsCollapsed(!isCollapsed)} className="flex w-full items-center gap-2 px-3 py-2 text-sm text-slate-600 rounded-lg hover:bg-slate-200">
            <span className={`material-symbols-rounded ${isCollapsed ? 'chevron_right' : 'chevron_left'}`} />
            <span className={isCollapsed ? 'hidden' : 'block'}>Collapse</span>
          </button>
        </div>
      </aside>

      {/* Overlay for mobile sidebar */}
      {isSidebarOpen && (
        <div className="fixed inset-0 z-40 bg-black/50" onClick={() => setIsSidebarOpen(false)} />
      )}

      {/* Main Content */}
      <main className={`flex flex-col h-full overflow-hidden ${isCollapsed ? 'ml-20' : 'ml-64'}`}>
        <header className="sticky top-0 z-40 flex h-16 items-center justify-between px-6 bg-white border-b border-slate-200 shadow-sm">
          <div className="flex items-center gap-2">
            <button
              onClick={() => setIsSidebarOpen(true)}
              className="md:hidden p-2 text-slate-500 hover:text-slate-700"
            >
              <span className="material-symbols-rounded">menu</span>
            </button>
            <h1 className="text-lg font-semibold text-slate-900">DT Ride Admin</h1>
          </div>
          <div className="flex items-center gap-3">
            <button className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-600 rounded-lg border border-slate-200 hover:bg-slate-100">
              <span className="material-symbols-rounded text-sm">notifications</span>
              <span className="hidden sm:block">Notifications</span>
            </button>
            <div className="flex items-center gap-2 pl-4 border-l border-slate-200">
              <div className="h-8 w-8 rounded-full bg-blue-600 flex items-center justify-center text-xs font-bold text-white">AD</div>
              <div className="text-sm font-medium text-slate-700">Admin User</div>
              <button className="ml-2 p-1 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded">
                <span className="material-symbols-rounded text-sm">logout</span>
              </button>
            </div>
          </div>
        </header>
        <main className="flex-1 overflow-y-auto p-6">
          {children}
        </main>
      </main>
    </div>
  );
}
