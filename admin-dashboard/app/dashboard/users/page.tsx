"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import {
  AdminUser,
  banUser,
  fetchClientStats,
  fetchUsers,
  unbanUser,
} from "@/lib/api";
import { ActionModal } from "@/components/action-modal";
import { DataTable } from "@/components/data-table";
import { DateRangeFilter, type DateRange } from "@/components/date-range-filter";
import { SecureProfileImage } from "@/components/secure-profile-image";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/toaster";
import { driverLevelTitle } from "@/lib/driver-levels";
import { formatDate } from "@/lib/utils";
import { Eye, Loader2, ShieldBan, ShieldCheck } from "lucide-react";
import Link from "next/link";

const ROLE_LABELS: Record<string, string> = {
  client: "Client",
  driver: "Livreur",
  relay_agent: "Agent relais",
  admin: "Admin",
  superadmin: "Super admin",
};

const ROLE_TONES: Record<string, "default" | "info" | "warning" | "success" | "danger"> = {
  client: "default",
  driver: "info",
  relay_agent: "warning",
  admin: "success",
  superadmin: "danger",
};

const PROFILE_PHOTO_TONES: Record<string, "default" | "info" | "warning" | "success" | "danger"> = {
  approved: "success",
  pending: "warning",
  rejected: "danger",
  missing: "default",
};

const PROFILE_PHOTO_LABELS: Record<string, string> = {
  approved: "Photo approuvée",
  pending: "Photo à vérifier",
  rejected: "Photo refusée",
  missing: "Photo absente",
};

const FILTERS: { value: string; label: string }[] = [
  { value: "all", label: "Tous" },
  { value: "client", label: "Clients" },
  { value: "driver", label: "Livreurs" },
  { value: "relay_agent", label: "Agents relais" },
  { value: "admin", label: "Admins" },
];

function userDisplayName(user: AdminUser) {
  return user.name ?? user.full_name ?? "—";
}

function StatCard({
  title,
  value,
  hint,
  tone = "default",
  onClick,
}: {
  title: string;
  value: string | number;
  hint?: string;
  tone?: "default" | "blue" | "green" | "orange" | "purple" | "teal";
  onClick?: () => void;
}) {
  const toneClass = {
    default: "border-border",
    blue: "border-blue-200 bg-blue-50/50",
    green: "border-green-200 bg-green-50/50",
    orange: "border-orange-200 bg-orange-50/50",
    purple: "border-purple-200 bg-purple-50/50",
    teal: "border-teal-200 bg-teal-50/50",
  }[tone];

  return (
    <Card
      className={`rounded-lg ${toneClass} ${onClick ? "cursor-pointer transition hover:shadow-md" : ""}`}
      onClick={onClick}
      role={onClick ? "button" : undefined}
    >
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold">{value}</div>
        {hint ? <p className="mt-1 text-xs text-muted-foreground">{hint}</p> : null}
      </CardContent>
    </Card>
  );
}

function currentPeriod() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

export default function UsersPage() {
  const qc = useQueryClient();
  const { toast } = useToast();
  const [role, setRole] = React.useState("all");
  const [dateRange, setDateRange] = React.useState<DateRange>({});
  const [banTarget, setBanTarget] = React.useState<AdminUser | null>(null);
  const [unbanTarget, setUnbanTarget] = React.useState<AdminUser | null>(null);

  const { data, isLoading, isError } = useQuery({
    queryKey: ["users", role, dateRange.from ?? "", dateRange.to ?? ""],
    queryFn: () =>
      fetchUsers({
        limit: 500,
        role: role === "all" ? undefined : role,
        ...(dateRange.from ? { from_date: dateRange.from } : {}),
        ...(dateRange.to ? { to_date: dateRange.to } : {}),
      }),
  });
  const period = React.useMemo(currentPeriod, []);
  const { data: clientStatsData } = useQuery({
    queryKey: ["users-client-performance", period],
    queryFn: () => fetchClientStats(period),
    enabled: role === "all" || role === "client",
  });


  const usersSummary = React.useMemo(() => {
    const allUsers = data?.users ?? [];
    return {
      total: data?.total ?? allUsers.length,
      clients: allUsers.filter((user) => user.role === "client").length,
      drivers: allUsers.filter((user) => user.role === "driver").length,
      relays: allUsers.filter((user) => user.role === "relay_agent").length,
      admins: allUsers.filter((user) => user.role === "admin" || user.role === "superadmin").length,
    };
  }, [data]);

  const users = React.useMemo(() => {
    const stats = clientStatsData?.stats ?? [];
    const statsByClient = new Map(stats.map((stat: any) => [stat.user_id, stat]));
    return (data?.users ?? []).map((user) => {
      if (user.role !== "client") return user;
      const stat = statsByClient.get(user.user_id) as any;
      if (!stat) return user;
      return {
        ...user,
        client_monthly_rank: stat.rank,
        client_sent_parcels: stat.sent_parcels,
        client_delivered_parcels: stat.delivered_parcels,
        client_success_rate: stat.success_rate,
        client_spent_xof: stat.spent_xof,
        client_monthly_goal: stat.monthly_goal,
        client_goal_progress: stat.goal_progress,
        client_total_ranked: stats.length,
        loyalty_points: stat.loyalty_points ?? user.loyalty_points,
      };
    });
  }, [clientStatsData, data]);

  const invalidate = () =>
    qc.invalidateQueries({ queryKey: ["users"], exact: false });

  const banMut = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) =>
      banUser(id, reason),
    onSuccess: () => {
      invalidate();
      toast("Utilisateur banni.");
    },
  });

  const unbanMut = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) =>
      unbanUser(id, reason),
    onSuccess: () => {
      invalidate();
      toast("Utilisateur débanni.");
    },
  });

  const columns = React.useMemo<ColumnDef<AdminUser, any>[]>(
    () => [
      {
        id: "name",
        header: "Utilisateur",
        accessorFn: userDisplayName,
        cell: ({ row }) => {
          const user = row.original;
          const displayName = userDisplayName(user);
          return (
            <Link
              href={`/dashboard/users/${user.user_id}`}
              className="group flex items-center gap-3"
            >
              <SecureProfileImage
                src={user.profile_picture_url}
                alt={`Photo de ${displayName}`}
                className="h-10 w-10 shrink-0"
              />
              <span className="flex min-w-0 flex-col">
                <span className="font-medium group-hover:text-primary group-hover:underline">
                  {displayName}
                </span>
                <span className="text-xs text-muted-foreground">{user.phone}</span>
                {user.email && (
                  <span className="truncate text-xs text-muted-foreground">
                    {user.email}
                  </span>
                )}
              </span>
            </Link>
          );
        },
      },
      {
        id: "role",
        header: "Rôle",
        accessorKey: "role",
        cell: ({ getValue }) => {
          const roleValue = (getValue() as string) ?? "client";
          return (
            <Badge tone={ROLE_TONES[roleValue] ?? "default"}>
              {ROLE_LABELS[roleValue] ?? roleValue}
            </Badge>
          );
        },
      },
      {
        id: "status",
        header: "Statut",
        accessorFn: (user) =>
          user.is_banned ? "banned" : user.is_active ? "active" : "inactive",
        cell: ({ row }) => {
          const user = row.original;
          if (user.is_banned) return <Badge tone="danger">Suspendu</Badge>;
          if (!user.is_active) return <Badge tone="default">Inactif</Badge>;
          return <Badge tone="success">Actif</Badge>;
        },
      },
      {
        id: "kyc",
        header: "KYC",
        accessorFn: (user) => user.kyc_status ?? "unknown",
        cell: ({ getValue }) => {
          const status = getValue() as string;
          if (status === "verified") return <Badge tone="success">Vérifié</Badge>;
          if (status === "pending") return <Badge tone="warning">En attente</Badge>;
          if (status === "rejected") return <Badge tone="danger">Rejeté</Badge>;
          return <Badge tone="default">—</Badge>;
        },
      },
      {
        id: "profile_picture_status",
        header: "Photo",
        accessorFn: (user) => user.profile_picture_status ?? "missing",
        cell: ({ getValue }) => {
          const status = (getValue() as string) || "missing";
          return (
            <Badge tone={PROFILE_PHOTO_TONES[status] ?? "default"}>
              {PROFILE_PHOTO_LABELS[status] ?? status}
            </Badge>
          );
        },
      },
      {
        id: "performance",
        header: "Performance",
        accessorFn: (user) =>
          user.role === "driver"
            ? user.monthly_rank ?? 999999
            : user.role === "client"
              ? user.client_monthly_rank ?? 999999
              : 999999,
        cell: ({ row }) => {
          const user = row.original;
          if (user.role === "client") {
            const rank = user.client_monthly_rank
              ? `#${user.client_monthly_rank} / ${user.client_total_ranked ?? "-"}`
              : "Non classe";
            return (
              <div className="flex flex-col gap-1">
                <span className="font-medium">{rank}</span>
                <span className="text-xs text-muted-foreground">
                  {user.client_sent_parcels ?? 0} colis ce mois
                </span>
              </div>
            );
          }
          if (user.role !== "driver") {
            return <span className="text-xs text-muted-foreground">—</span>;
          }
          const rank = user.monthly_rank
            ? `#${user.monthly_rank} / ${user.total_ranked_drivers ?? "-"}`
            : "Non classé";
          return (
            <div className="flex flex-col gap-1">
              <span className="font-medium">{rank}</span>
              <span className="text-xs text-muted-foreground">
                {user.monthly_deliveries_success ?? 0} courses ce mois
              </span>
            </div>
          );
        },
      },
      {
        id: "level",
        header: "Progression",
        accessorFn: (user) => user.level ?? 0,
        cell: ({ row }) => {
          const user = row.original;
          if (user.role === "client") {
            const progress = Math.round((user.client_goal_progress ?? 0) * 100);
            return (
              <div className="flex flex-col gap-1">
                <span className="font-medium">{user.loyalty_points ?? 0} pts</span>
                <span className="text-xs text-muted-foreground">
                  Objectif {progress}%
                </span>
              </div>
            );
          }
          if (user.role !== "driver") {
            return <span className="text-xs text-muted-foreground">—</span>;
          }
          const level = user.level ?? 1;
          return (
            <div className="flex flex-col gap-1">
              <span className="font-medium">
                Niv. {level} · {driverLevelTitle(level)}
              </span>
              <span className="text-xs text-muted-foreground">
                {user.xp ?? 0} XP
              </span>
            </div>
          );
        },
      },
      {
        id: "rating",
        header: "Qualite",
        accessorFn: (user) => user.average_rating ?? 0,
        cell: ({ row }) => {
          const user = row.original;
          if (user.role === "client") {
            return (
              <div className="flex flex-col gap-1">
                <span className="font-medium">
                  {user.client_success_rate ?? 0}% livraison
                </span>
                <span className="text-xs text-muted-foreground">
                  {user.client_delivered_parcels ?? 0} colis livres
                </span>
              </div>
            );
          }
          const rating = row.original.average_rating ?? 0;
          const count = row.original.total_ratings_count ?? 0;
          if (row.original.role !== "driver") {
            return <span className="text-xs text-muted-foreground">—</span>;
          }
          return (
            <div className="flex flex-col gap-1">
              <span className={rating >= 4 ? "font-medium text-green-600" : ""}>
                {rating > 0 ? rating.toFixed(1) : "—"}
              </span>
              <span className="text-xs text-muted-foreground">{count} avis</span>
            </div>
          );
        },
      },
      {
        id: "created_at",
        header: "Inscrit le",
        accessorKey: "created_at",
        cell: ({ getValue }) => (
          <span className="text-xs text-muted-foreground">
            {formatDate(getValue() as string | undefined)}
          </span>
        ),
      },
      {
        id: "actions",
        header: "Actions",
        enableSorting: false,
        cell: ({ row }) => {
          const user = row.original;
          return (
            <div className="flex flex-wrap gap-2">
              <Link href={`/dashboard/users/${user.user_id}`}>
                <Button size="sm" variant="outline">
                  <Eye className="h-3.5 w-3.5" />
                  Fiche
                </Button>
              </Link>
              {user.is_banned ? (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => setUnbanTarget(user)}
                >
                  <ShieldCheck className="h-3.5 w-3.5" />
                  Debannir
                </Button>
              ) : (
                <Button
                  size="sm"
                  variant="destructive"
                  onClick={() => setBanTarget(user)}
                >
                  <ShieldBan className="h-3.5 w-3.5" />
                  Bannir
                </Button>
              )}
            </div>
          );
        },
      },
    ],
    []
  );

  return (
    <div className="space-y-5 p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Utilisateurs</h1>
          <p className="text-sm text-muted-foreground">
            Gérer les rôles, suspensions, KYC et photos de profil des comptes Denkma.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <DateRangeFilter value={dateRange} onChange={setDateRange} />
          <div className="text-sm text-muted-foreground">
            {data ? `${data.total} comptes au total` : null}
          </div>
        </div>
      </div>


      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-5">
        <StatCard title="Utilisateurs" value={usersSummary.total} hint="Tous les comptes" tone="default" onClick={() => setRole("all")} />
        <StatCard title="Clients" value={usersSummary.clients} hint="Comptes clients" tone="blue" onClick={() => setRole("client")} />
        <StatCard title="Livreurs" value={usersSummary.drivers} hint="Comptes livreurs" tone="green" onClick={() => setRole("driver")} />
        <StatCard title="Relais" value={usersSummary.relays} hint="Agents relais" tone="orange" onClick={() => setRole("relay_agent")} />
        <StatCard title="Admins" value={usersSummary.admins} hint="Comptes administration" tone="purple" onClick={() => setRole("admin")} />
      </div>

      <div className="flex flex-wrap gap-2">
        {FILTERS.map((filter) => (
          <button
            key={filter.value}
            onClick={() => setRole(filter.value)}
            className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
              role === filter.value
                ? "border-primary bg-primary text-primary-foreground"
                : "border-input bg-background hover:bg-accent"
            }`}
          >
            {filter.label}
          </button>
        ))}
      </div>

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement des utilisateurs.
        </div>
      )}
      {data && (
        <DataTable
          columns={columns}
          data={users}
          searchPlaceholder="Nom, téléphone, e-mail, ID..."
          globalFilterFn={(user, query) =>
            userDisplayName(user).toLowerCase().includes(query) ||
            (user.phone ?? "").toLowerCase().includes(query) ||
            (user.email ?? "").toLowerCase().includes(query) ||
            (user.user_id ?? "").toLowerCase().includes(query)
          }
        />
      )}

      <ActionModal
        open={!!banTarget}
        onOpenChange={(open) => !open && setBanTarget(null)}
        title={`Bannir ${banTarget ? userDisplayName(banTarget) : ""}`}
        description="L'utilisateur ne pourra plus se connecter."
        inputLabel="Motif du bannissement"
        inputPlaceholder="Ex: fraude, documents invalides..."
        inputType="textarea"
        confirmLabel="Bannir"
        confirmVariant="destructive"
        onConfirm={async (reason) => {
          if (!banTarget) return;
          await banMut.mutateAsync({ id: banTarget.user_id, reason });
          setBanTarget(null);
        }}
      />

      <ActionModal
        open={!!unbanTarget}
        onOpenChange={(open) => !open && setUnbanTarget(null)}
        title={`Débannir ${unbanTarget ? userDisplayName(unbanTarget) : ""}`}
        description="L'utilisateur pourra de nouveau se connecter."
        inputLabel="Motif du débannissement"
        inputPlaceholder="Ex: erreur, correction..."
        inputType="textarea"
        confirmLabel="Débannir"
        onConfirm={async (reason) => {
          if (!unbanTarget) return;
          await unbanMut.mutateAsync({ id: unbanTarget.user_id, reason });
          setUnbanTarget(null);
        }}
      />
    </div>
  );
}
