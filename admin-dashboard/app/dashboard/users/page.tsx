"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import {
  AdminUser,
  banUser,
  fetchUsers,
  unbanUser,
} from "@/lib/api";
import { ActionModal } from "@/components/action-modal";
import { DataTable } from "@/components/data-table";
import { SecureProfileImage } from "@/components/secure-profile-image";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
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

export default function UsersPage() {
  const qc = useQueryClient();
  const { toast } = useToast();
  const [role, setRole] = React.useState("all");
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
                  Débannir
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
        <div className="text-sm text-muted-foreground">
          {data ? `${data.total} comptes au total` : null}
        </div>
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
          data={data.users}
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
