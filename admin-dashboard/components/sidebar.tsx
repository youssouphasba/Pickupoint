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
  Settings,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { logout, type ActionCategory } from "@/lib/api";
import { useActionCenter } from "@/lib/use-action-center";

type BadgeSource = keyof ReturnType<typeof useActionCenter>["data"] extends never
  ? never
  : "payouts" | "applications" | "anomalies" | "stale_parcels" | "support";

type Item = {
  href: string;
  label: string;
  Icon: React.ComponentType<{ className?: string }>;
  badge?:
    | "payouts"
    | "applications"
    | "anomalies"
    | "stale_parcels"
    | "support"
    | "incidents_payment"; // combo : incidents + paiements bloqués sous "Colis"
};

const items: Item[] = [
  { href: "/dashboard", label: "Dashboard", Icon: LayoutDashboard },
  { href: "/dashboard/parcels", label: "Colis", Icon: Package, badge: "incidents_payment" },
  { href: "/dashboard/users", label: "Utilisateurs", Icon: Users },
  { href: "/dashboard/applications", label: "Candidatures", Icon: FileText, badge: "applications" },
  { href: "/dashboard/payouts", label: "Retraits", Icon: Wallet, badge: "payouts" },
  { href: "/dashboard/relays", label: "Relais", Icon: Store },
  { href: "/dashboard/drivers", label: "Livreurs", Icon: Truck },
  { href: "/dashboard/fleet", label: "Flotte live", Icon: Map },
  { href: "/dashboard/promotions", label: "Promotions", Icon: Tag },
  { href: "/dashboard/configuration", label: "Configuration", Icon: Settings },
  { href: "/dashboard/finance", label: "Finance", Icon: Banknote },
  { href: "/dashboard/anomalies", label: "Anomalies", Icon: AlertTriangle, badge: "anomalies" },
  { href: "/dashboard/support", label: "Support WhatsApp", Icon: MessageCircle, badge: "support" },
  { href: "/dashboard/stale", label: "Colis stagnants", Icon: Clock, badge: "stale_parcels" },
  { href: "/dashboard/heatmap", label: "Heatmap", Icon: Flame },
  { href: "/dashboard/audit-log", label: "Audit log", Icon: History },
  { href: "/dashboard/legal", label: "Juridique", Icon: Scale },
];

function SidebarBadge({ category }: { category?: ActionCategory }) {
  if (!category || category.count === 0) return null;
  const tone =
    category.urgent_count > 0
      ? "bg-red-600 text-white"
      : category.warning_count > 0
        ? "bg-amber-500 text-white"
        : "bg-muted text-foreground";
  return (
    <span
      className={cn(
        "ml-auto inline-flex min-w-[1.25rem] items-center justify-center rounded-full px-1.5 text-[11px] font-semibold",
        tone
      )}
      aria-label={`${category.count} à traiter`}
    >
      {category.count > 99 ? "99+" : category.count}
    </span>
  );
}

function ComboBadge({
  incidents,
  payment,
}: {
  incidents?: ActionCategory;
  payment?: ActionCategory;
}) {
  const total = (incidents?.count ?? 0) + (payment?.count ?? 0);
  if (total === 0) return null;
  const urgent = (incidents?.urgent_count ?? 0) + (payment?.urgent_count ?? 0);
  const warning = (incidents?.warning_count ?? 0) + (payment?.warning_count ?? 0);
  const tone =
    urgent > 0
      ? "bg-red-600 text-white"
      : warning > 0
        ? "bg-amber-500 text-white"
        : "bg-muted text-foreground";
  return (
    <span
      className={cn(
        "ml-auto inline-flex min-w-[1.25rem] items-center justify-center rounded-full px-1.5 text-[11px] font-semibold",
        tone
      )}
      aria-label={`${total} colis à traiter`}
    >
      {total > 99 ? "99+" : total}
    </span>
  );
}

export function Sidebar({
  admin,
}: {
  admin: { email?: string | null; full_name?: string | null };
}) {
  const pathname = usePathname();
  const router = useRouter();
  const { data: ac } = useActionCenter();

  async function handleLogout() {
    await logout();
    router.replace("/login");
  }

  function resolveBadge(item: Item) {
    if (!ac || !item.badge) return null;
    if (item.badge === "incidents_payment") {
      return (
        <ComboBadge
          incidents={ac.categories.incidents}
          payment={ac.categories.payment_blocked}
        />
      );
    }
    return <SidebarBadge category={ac.categories[item.badge]} />;
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
          {items.map((item) => {
            const { href, label, Icon } = item;
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
                  <span className="flex-1 truncate">{label}</span>
                  {resolveBadge(item)}
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
