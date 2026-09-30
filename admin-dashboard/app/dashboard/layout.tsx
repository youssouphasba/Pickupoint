"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchMe } from "@/lib/api";
import { Sidebar } from "@/components/sidebar";
import { NotificationBell } from "@/components/notification-bell";
import { AdminBreadcrumbs, AdminPageContext } from "@/components/admin-page-context";
import { Button } from "@/components/ui/button";
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
  const { data, isLoading, isError, error, refetch } = useQuery({
    queryKey: ["me"],
    queryFn: fetchMe,
    retry: false,
  });

  useEffect(() => {
    const status = (error as { response?: { status?: number } } | null)?.response?.status;
    if (isError && (status === 401 || status === 403)) router.replace("/login");
  }, [isError, error, router]);

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (isError) {
    return (
      <div className="flex min-h-screen items-center justify-center p-6">
        <div className="max-w-md space-y-4 rounded-xl border bg-background p-6" role="alert">
          <h1 className="text-lg font-semibold">Connexion à l’admin indisponible</h1>
          <p className="text-sm text-muted-foreground">La vérification de votre session a échoué. Réessayez lorsque la connexion est rétablie.</p>
          <Button onClick={() => refetch()}>Réessayer</Button>
        </div>
      </div>
    );
  }

  if (!data) return null;

  return (
    <div className="flex min-h-screen bg-muted/10">
      <a href="#admin-content" className="sr-only z-[60] rounded-md bg-primary px-4 py-3 text-primary-foreground focus:not-sr-only focus:fixed focus:left-4 focus:top-4">Aller au contenu</a>
      <Sidebar
        admin={data}
        mobileOpen={mobileNavigationOpen}
        onMobileClose={() => setMobileNavigationOpen(false)}
      />
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 flex h-16 shrink-0 items-center justify-between gap-3 border-b bg-background/95 px-3 backdrop-blur sm:px-6">
          <div className="flex min-w-0 items-center gap-3">
            <button
              id="admin-navigation-toggle"
              type="button"
              onClick={() => setMobileNavigationOpen(true)}
              className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-md border bg-background text-muted-foreground transition-colors hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring lg:hidden"
              aria-label="Ouvrir la navigation"
              aria-expanded={mobileNavigationOpen}
              aria-haspopup="dialog"
            >
              <Menu className="h-5 w-5" />
            </button>
            <AdminBreadcrumbs />
          </div>
          <NotificationBell />
        </header>
        <main id="admin-content" tabIndex={-1} className="dashboard-main min-w-0 max-w-full flex-1 outline-none">
          <AdminPageContext />
          {children}
        </main>
      </div>
    </div>
  );
}
