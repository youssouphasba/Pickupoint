"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import {
  AdminUser,
  changeUserRole,
  fetchUsers,
} from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { formatDate } from "@/lib/utils";
import { CheckCircle2, Loader2, XCircle } from "lucide-react";

export default function ApplicationsPage() {
  const qc = useQueryClient();

  const { data, isLoading, isError } = useQuery({
    queryKey: ["users", "client"],
    queryFn: () => fetchUsers({ role: "client", limit: 500 }),
  });

  const promoteMut = useMutation({
    mutationFn: ({ id, role }: { id: string; role: string }) =>
      changeUserRole(id, role),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["users"], exact: false }),
  });

  const pendingUsers = React.useMemo(() => {
    if (!data) return [];
    return data.users.filter(
      (u) => u.kyc_status === "pending" || u.kyc_status === "verified"
    );
  }, [data]);

  const columns = React.useMemo<ColumnDef<AdminUser, any>[]>(
    () => [
      {
        id: "name",
        header: "Nom",
        accessorFn: (u) => u.full_name ?? "—",
        cell: ({ row }) => (
          <div className="flex flex-col">
            <span className="font-medium">
              {row.original.full_name ?? "—"}
            </span>
            <span className="text-xs text-muted-foreground">
              {row.original.phone}
            </span>
          </div>
        ),
      },
      {
        id: "kyc",
        header: "KYC",
        accessorKey: "kyc_status",
        cell: ({ getValue }) => {
          const s = (getValue() as string) ?? "unknown";
          return (
            <Badge
              tone={
                s === "verified"
                  ? "success"
                  : s === "pending"
                    ? "warning"
                    : "default"
              }
            >
              {s === "verified"
                ? "Vérifié"
                : s === "pending"
                  ? "En attente"
                  : s}
            </Badge>
          );
        },
      },
      {
        id: "created",
        header: "Inscrit le",
        accessorKey: "created_at",
        cell: ({ getValue }) => (
          <span className="text-xs text-muted-foreground">
            {formatDate(getValue() as string)}
          </span>
        ),
      },
      {
        id: "actions",
        header: "Promouvoir en",
        enableSorting: false,
        cell: ({ row }) => {
          const u = row.original;
          return (
            <div className="flex gap-2">
              <Button
                size="sm"
                variant="outline"
                disabled={promoteMut.isPending}
                onClick={() => {
                  if (!confirm(`Promouvoir ${u.full_name ?? u.phone} en livreur ?`)) return;
                  promoteMut.mutate({ id: u.user_id, role: "driver" });
                }}
              >
                Livreur
              </Button>
              <Button
                size="sm"
                variant="outline"
                disabled={promoteMut.isPending}
                onClick={() => {
                  if (!confirm(`Promouvoir ${u.full_name ?? u.phone} en agent relais ?`)) return;
                  promoteMut.mutate({ id: u.user_id, role: "relay_agent" });
                }}
              >
                Agent relais
              </Button>
            </div>
          );
        },
      },
    ],
    [promoteMut]
  );

  return (
    <div className="space-y-5 p-8">
      <div>
        <h1 className="text-2xl font-bold">Candidatures</h1>
        <p className="text-sm text-muted-foreground">
          Clients avec KYC en attente ou vérifié — à promouvoir en livreur ou
          agent relais.
        </p>
      </div>

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement.
        </div>
      )}
      {data && (
        <DataTable
          columns={columns}
          data={pendingUsers}
          searchPlaceholder="Nom, téléphone…"
          globalFilterFn={(u, q) =>
            (u.full_name ?? "").toLowerCase().includes(q) ||
            (u.phone ?? "").toLowerCase().includes(q)
          }
          emptyLabel="Aucune candidature en attente."
        />
      )}
    </div>
  );
}
