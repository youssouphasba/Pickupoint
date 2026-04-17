"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import {
  AdminUser,
  banUser,
  changeUserRole,
  fetchUsers,
  unbanUser,
} from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ActionModal } from "@/components/action-modal";
import { useToast } from "@/components/ui/toaster";
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

const FILTERS: { value: string; label: string }[] = [
  { value: "all", label: "Tous" },
  { value: "client", label: "Clients" },
  { value: "driver", label: "Livreurs" },
  { value: "relay_agent", label: "Agents relais" },
  { value: "admin", label: "Admins" },
];

export default function UsersPage() {
  const qc = useQueryClient();
  const { toast } = useToast();
  const [role, setRole] = React.useState("all");

  // Modal state
  const [banTarget, setBanTarget] = React.useState<AdminUser | null>(null);
  const [unbanTarget, setUnbanTarget] = React.useState<AdminUser | null>(null);

  const { data, isLoading, isError } = useQuery({
    queryKey: ["users", role],
    queryFn: () =>
      fetchUsers({ limit: 500, role: role === "all" ? undefined : role }),
  });

  const invalidate = () =>
    qc.invalidateQueries({ queryKey: ["users"], exact: false });

  const banMut = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) =>
      banUser(id, reason),
    onSuccess: () => { invalidate(); toast("Utilisateur banni."); },
  });

  const unbanMut = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) =>
      unbanUser(id, reason),
    onSuccess: () => { invalidate(); toast("Utilisateur débanni."); },
  });

  const columns = React.useMemo<ColumnDef<AdminUser, any>[]>(
    () => [
      {
        id: "name",
        header: "Utilisateur",
        accessorFn: (u) => u.full_name ?? "—",
        cell: ({ row }) => {
          const u = row.original;
          return (
            <Link
              href={`/dashboard/users/${u.user_id}`}
              className="group flex flex-col"
            >
              <span className="font-medium group-hover:text-primary group-hover:underline">
                {u.full_name ?? "—"}
              </span>
              <span className="text-xs text-muted-foreground">{u.phone}</span>
              {u.email && (
                <span className="text-xs text-muted-foreground">{u.email}</span>
              )}
            </Link>
          );
        },
      },
      {
        id: "role",
        header: "Rôle",
        accessorKey: "role",
        cell: ({ getValue }) => {
          const r = (getValue() as string) ?? "client";
          return (
            <Badge tone={ROLE_TONES[r] ?? "default"}>
              {ROLE_LABELS[r] ?? r}
            </Badge>
          );
        },
      },
      {
        id: "status",
        header: "Statut",
        accessorFn: (u) =>
          u.is_banned ? "banned" : u.is_active ? "active" : "inactive",
        cell: ({ row }) => {
          const u = row.original;
          if (u.is_banned) return <Badge tone="danger">Suspendu</Badge>;
          if (!u.is_active) return <Badge tone="default">Inactif</Badge>;
          return <Badge tone="success">Actif</Badge>;
        },
      },
      {
        id: "kyc",
        header: "KYC",
        accessorFn: (u) => u.kyc_status ?? "unknown",
        cell: ({ getValue }) => {
          const s = getValue() as string;
          if (s === "verified") return <Badge tone="success">Vérifié</Badge>;
          if (s === "pending") return <Badge tone="warning">En attente</Badge>;
          if (s === "rejected") return <Badge tone="danger">Rejeté</Badge>;
          return <Badge tone="default">—</Badge>;
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
          const u = row.original;
          return (
            <div className="flex flex-wrap gap-2">
              <Link href={`/dashboard/users/${u.user_id}`}>
                <Button size="sm" variant="outline">
                  <Eye className="h-3.5 w-3.5" />
                  Fiche
                </Button>
              </Link>
              {u.is_banned ? (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => setUnbanTarget(u)}
                >
                  <ShieldCheck className="h-3.5 w-3.5" />
                  Débannir
                </Button>
              ) : (
                <Button
                  size="sm"
                  variant="destructive"
                  onClick={() => setBanTarget(u)}
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
            Gérer les rôles, suspensions et KYC des comptes Denkma.
          </p>
        </div>
        <div className="text-sm text-muted-foreground">
          {data ? `${data.total} comptes au total` : null}
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        {FILTERS.map((f) => (
          <button
            key={f.value}
            onClick={() => setRole(f.value)}
            className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
              role === f.value
                ? "border-primary bg-primary text-primary-foreground"
                : "border-input bg-background hover:bg-accent"
            }`}
          >
            {f.label}
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
          data={data.users}
          searchPlaceholder="Nom, téléphone, e-mail, ID…"
          globalFilterFn={(u, q) =>
            (u.full_name ?? "").toLowerCase().includes(q) ||
            (u.phone ?? "").toLowerCase().includes(q) ||
            (u.email ?? "").toLowerCase().includes(q) ||
            (u.user_id ?? "").toLowerCase().includes(q)
          }
        />
      )}

      {/* Ban modal */}
      <ActionModal
        open={!!banTarget}
        onOpenChange={(open) => !open && setBanTarget(null)}
        title={`Bannir ${banTarget?.full_name ?? banTarget?.phone ?? ""}`}
        description="L'utilisateur ne pourra plus se connecter."
        inputLabel="Motif du bannissement"
        inputPlaceholder="Ex: fraude, documents invalides…"
        inputType="textarea"
        confirmLabel="Bannir"
        confirmVariant="destructive"
        onConfirm={async (reason) => {
          if (!banTarget) return;
          await banMut.mutateAsync({ id: banTarget.user_id, reason });
          setBanTarget(null);
        }}
      />

      {/* Unban modal */}
      <ActionModal
        open={!!unbanTarget}
        onOpenChange={(open) => !open && setUnbanTarget(null)}
        title={`Débannir ${unbanTarget?.full_name ?? unbanTarget?.phone ?? ""}`}
        description="L'utilisateur pourra de nouveau se connecter."
        inputLabel="Motif du débannissement"
        inputPlaceholder="Ex: erreur, correction…"
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
