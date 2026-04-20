"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  LayoutDashboard,
  Package,
  Users,
  FileText,
  Wallet,
  Store,
  Map,
  Truck,
  Tag,
  Banknote,
  AlertTriangle,
  Clock,
  Flame,
  History,
  Scale,
  LogOut,
  MessageCircle,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { logout } from "@/lib/api";

const items = [
  { href: "/dashboard", label: "Dashboard", Icon: LayoutDashboard },
  { href: "/dashboard/parcels", label: "Colis", Icon: Package },
  { href: "/dashboard/users", label: "Utilisateurs", Icon: Users },
  { href: "/dashboard/applications", label: "Candidatures", Icon: FileText },
  { href: "/dashboard/payouts", label: "Retraits", Icon: Wallet },
  { href: "/dashboard/relays", label: "Relais", Icon: Store },
  { href: "/dashboard/drivers", label: "Livreurs", Icon: Truck },
  { href: "/dashboard/fleet", label: "Flotte live", Icon: Map },
  { href: "/dashboard/promotions", label: "Promotions", Icon: Tag },
  { href: "/dashboard/finance", label: "Finance", Icon: Banknote },
  { href: "/dashboard/anomalies", label: "Anomalies", Icon: AlertTriangle },
  { href: "/dashboard/support", label: "Support WhatsApp", Icon: MessageCircle },
  { href: "/dashboard/stale", label: "Colis stagnants", Icon: Clock },
  { href: "/dashboard/heatmap", label: "Heatmap", Icon: Flame },
  { href: "/dashboard/audit-log", label: "Audit log", Icon: History },
  { href: "/dashboard/legal", label: "Juridique", Icon: Scale },
];

export function Sidebar({ admin }: { admin: { email?: string | null; full_name?: string | null } }) {
  const pathname = usePathname();
  const router = useRouter();

  async function handleLogout() {
    await logout();
    router.replace("/login");
  }

  return (
    <aside className="flex w-64 shrink-0 flex-col border-r bg-muted/30">
      <div className="flex h-16 items-center gap-2 border-b px-5">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary text-primary-foreground">
          <Package className="h-5 w-5" />
        </div>
        <div>
          <div className="text-sm font-bold leading-tight">Denkma</div>
          <div className="text-[11px] text-muted-foreground">Admin console</div>
        </div>
      </div>

      <nav className="flex-1 overflow-y-auto px-3 py-4">
        <ul className="space-y-1">
          {items.map(({ href, label, Icon }) => {
            const active =
              href === "/dashboard"
                ? pathname === "/dashboard"
                : pathname === href || pathname.startsWith(`${href}/`);
            return (
              <li key={href}>
                <Link
                  href={href}
                  className={cn(
                    "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                    active
                      ? "bg-primary/10 text-primary"
                      : "text-muted-foreground hover:bg-accent hover:text-foreground"
                  )}
                >
                  <Icon className="h-4 w-4" />
                  {label}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>

      <div className="border-t p-3">
        <div className="mb-2 px-2">
          <div className="truncate text-sm font-medium">
            {admin.full_name ?? admin.email ?? "Admin"}
          </div>
          <div className="truncate text-xs text-muted-foreground">
            {admin.email}
          </div>
        </div>
        <button
          onClick={handleLogout}
          className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm text-muted-foreground hover:bg-accent hover:text-foreground"
        >
          <LogOut className="h-4 w-4" />
          Déconnexion
        </button>
      </div>
    </aside>
  );
}
