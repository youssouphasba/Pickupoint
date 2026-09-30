"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import * as DialogPrimitive from "@radix-ui/react-dialog";
import { ChevronDown, LogOut, Package, Search, X } from "lucide-react";
import { cn } from "@/lib/utils";
import { logout, type ActionCategory } from "@/lib/api";
import { useActionCenter } from "@/lib/use-action-center";
import { adminPageForPath, searchAdminNavigation, type AdminPage } from "@/lib/admin-navigation";
import { Input } from "@/components/ui/input";

function SidebarBadge({ category }: { category?: ActionCategory }) {
  if (!category || category.count === 0) return null;
  const tone = category.urgent_count > 0
    ? "bg-red-600 text-white"
    : category.warning_count > 0 ? "bg-amber-100 text-amber-900" : "bg-muted text-foreground";
  return (
    <span className={cn("ml-auto inline-flex min-w-5 items-center justify-center rounded-full px-1.5 text-[11px] font-semibold", tone)}
      aria-label={`${category.count} à traiter`}>
      {category.count > 99 ? "99+" : category.count}
    </span>
  );
}

export function Sidebar({
  admin, mobileOpen = false, onMobileClose,
}: {
  admin: { email?: string | null; full_name?: string | null };
  mobileOpen?: boolean;
  onMobileClose?: () => void;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const { data: actionCenter } = useActionCenter();
  const [query, setQuery] = React.useState("");
  const [collapsed, setCollapsed] = React.useState<string[]>([]);
  const activePage = adminPageForPath(pathname);
  const groups = searchAdminNavigation(query);

  React.useEffect(() => {
    const activeGroup = searchAdminNavigation("").find((group) => group.pages.some((page) => page.href === adminPageForPath(pathname)?.href));
    if (activeGroup) setCollapsed((current) => current.filter((id) => id !== activeGroup.id));
    setQuery("");
  }, [pathname]);

  React.useEffect(() => {
    const media = window.matchMedia("(min-width: 1024px)");
    const closeOnDesktop = () => { if (media.matches) onMobileClose?.(); };
    media.addEventListener("change", closeOnDesktop);
    return () => media.removeEventListener("change", closeOnDesktop);
  }, [onMobileClose]);

  function resolveBadge(page: AdminPage) {
    if (!actionCenter || !page.badge) return null;
    if (page.badge !== "incidents_payment") {
      return <SidebarBadge category={actionCenter.categories[page.badge]} />;
    }
    const incidents = actionCenter.categories.incidents;
    const payment = actionCenter.categories.payment_blocked;
    return <SidebarBadge category={{
      ...incidents,
      count: incidents.count + payment.count,
      urgent_count: incidents.urgent_count + payment.urgent_count,
      warning_count: incidents.warning_count + payment.warning_count,
    }} />;
  }

  function toggleGroup(id: string) {
    setCollapsed((current) => current.includes(id) ? current.filter((value) => value !== id) : [...current, id]);
  }

  function navigation(mobile: boolean) {
    const prefix = mobile ? "mobile" : "desktop";
    return (
      <>
        <div className="flex h-16 shrink-0 items-center gap-3 border-b px-5">
          <Link href="/dashboard" onClick={onMobileClose} className="flex min-w-0 items-center gap-3 rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" aria-label="Denkma, tableau de bord">
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-foreground"><Package className="h-5 w-5" aria-hidden="true" /></span>
            <span><span className="block text-sm font-bold">Denkma</span><span className="block text-xs text-muted-foreground">Administration</span></span>
          </Link>
          {mobile && <DialogPrimitive.Close className="ml-auto rounded-md p-2 hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" aria-label="Fermer la navigation"><X className="h-5 w-5" /></DialogPrimitive.Close>}
        </div>
        <div className="px-3 pt-4">
          <label htmlFor={`${prefix}-navigation-search`} className="sr-only">Rechercher un écran</label>
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-3 h-4 w-4 text-muted-foreground" aria-hidden="true" />
            <Input id={`${prefix}-navigation-search`} type="search" placeholder="Rechercher un écran…" value={query} onChange={(event) => setQuery(event.target.value)} className="pl-9" />
          </div>
          {query.trim() && <p className="mt-2 text-xs text-muted-foreground" role="status">{groups.reduce((count, group) => count + group.pages.length, 0)} écran(s) trouvé(s)</p>}
        </div>
        <nav aria-label="Navigation principale" className="min-h-0 flex-1 space-y-4 overflow-y-auto px-3 py-4">
          {groups.length === 0 && <p className="rounded-lg bg-muted p-3 text-sm text-muted-foreground">Aucun écran trouvé. Essayez « colis », « horaires » ou « commissions ».</p>}
          {groups.map((group) => {
            const expanded = query.trim() !== "" || !collapsed.includes(group.id);
            return (
              <div key={group.id}>
                {group.id !== "home" && <button type="button" onClick={() => toggleGroup(group.id)}
                  aria-expanded={expanded} aria-controls={`${prefix}-group-${group.id}`}
                  className="mb-1 flex w-full items-center justify-between gap-2 rounded px-3 py-1 text-left text-[11px] font-semibold uppercase tracking-wider text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                  {group.label}<ChevronDown className={cn("h-3.5 w-3.5 shrink-0 transition-transform", !expanded && "-rotate-90")} aria-hidden="true" />
                </button>}
                <ul hidden={!expanded} id={`${prefix}-group-${group.id}`} className="space-y-1">
                  {group.pages.map((page) => {
                    const active = page.href === activePage?.href;
                    return <li key={page.href}>
                      <Link href={page.href} onClick={onMobileClose} title={page.description} aria-current={active ? "page" : undefined}
                        className={cn("flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                          active ? "bg-primary/10 text-primary" : "text-muted-foreground hover:bg-accent hover:text-foreground")}>
                        <page.Icon className="h-4 w-4 shrink-0" aria-hidden="true" />
                        <span className="min-w-0 flex-1">{page.label}</span>
                        {resolveBadge(page)}
                      </Link>
                    </li>;
                  })}
                </ul>
              </div>
            );
          })}
        </nav>
        <div className="shrink-0 border-t p-3">
          <div className="mb-2 px-2"><div className="truncate text-sm font-medium">{admin.full_name || admin.email || "Administrateur"}</div><div className="truncate text-xs text-muted-foreground">{admin.email}</div></div>
          <button type="button" onClick={async () => { await logout(); router.replace("/login"); }} className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm text-muted-foreground hover:bg-accent hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"><LogOut className="h-4 w-4" aria-hidden="true" />Déconnexion</button>
        </div>
      </>
    );
  }

  return (
    <>
      <aside className="sticky top-0 hidden h-screen w-72 shrink-0 flex-col border-r bg-background lg:flex">{navigation(false)}</aside>
      <DialogPrimitive.Root open={mobileOpen} onOpenChange={(open) => { if (!open) onMobileClose?.(); }}>
        <DialogPrimitive.Portal>
          <DialogPrimitive.Overlay className="fixed inset-0 z-40 bg-black/45" />
          <DialogPrimitive.Content className="fixed inset-y-0 left-0 z-50 flex w-[min(21rem,90vw)] flex-col border-r bg-background shadow-xl"
            onCloseAutoFocus={(event) => { event.preventDefault(); document.getElementById("admin-navigation-toggle")?.focus(); }}>
            <DialogPrimitive.Title className="sr-only">Navigation Denkma</DialogPrimitive.Title>
            <DialogPrimitive.Description className="sr-only">Recherchez un écran ou choisissez une rubrique.</DialogPrimitive.Description>
            {navigation(true)}
          </DialogPrimitive.Content>
        </DialogPrimitive.Portal>
      </DialogPrimitive.Root>
    </>
  );
}
