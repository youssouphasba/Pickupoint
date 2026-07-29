"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchMe } from "@/lib/api";
import { Sidebar } from "@/components/sidebar";
import { NotificationBell } from "@/components/notification-bell";
import { Loader2, Menu } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const router = useRouter();
  const [mobileNavigationOpen, setMobileNavigationOpen] = useState(false);
  const { data, isLoading, isError } = useQuery({
    queryKey: ["me"],
    queryFn: fetchMe,
    retry: false,
  });

  useEffect(() => {
    if (isError) router.replace("/login");
  }, [isError, router]);

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (!data) return null;

  return (
    <div className="flex min-h-screen bg-muted/10">
      <Sidebar
        admin={data}
        mobileOpen={mobileNavigationOpen}
        onMobileClose={() => setMobileNavigationOpen(false)}
      />
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 flex h-14 shrink-0 items-center justify-between gap-3 border-b bg-background/95 px-3 backdrop-blur sm:px-6 lg:justify-end">
          <div className="flex min-w-0 items-center gap-3 lg:hidden">
            <button
              type="button"
              onClick={() => setMobileNavigationOpen(true)}
              className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-md border bg-background text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
              aria-label="Ouvrir la navigation"
            >
              <Menu className="h-5 w-5" />
            </button>
            <span className="truncate text-sm font-semibold">Denkma Admin</span>
          </div>
          <NotificationBell />
        </header>
        <main className="min-w-0 flex-1 overflow-x-hidden">{children}</main>
      </div>
    </div>
  );
}
