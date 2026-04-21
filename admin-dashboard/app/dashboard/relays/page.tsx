"use client";

import * as React from "react";
import { useSearchParams } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { AdminRelay, fetchRelays, verifyRelay } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { CheckCircle2, Eye, Loader2 } from "lucide-react";
import Link from "next/link";

export default function RelaysPage() {
  const qc = useQueryClient();
  const searchParams = useSearchParams();
  const activeOnly = searchParams.get("active") === "true";
  const { data, isLoading, isError } = useQuery({
    queryKey: ["relays", activeOnly],
    queryFn: () => fetchRelays(activeOnly ? { active: true } : undefined),
  });

  const verifyMut = useMutation({
    mutationFn: (id: string) => verifyRelay(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["relays"] }),
  });

  const columns = React.useMemo<ColumnDef<AdminRelay, any>[]>(
    () => [
      {
        id: "name",
        header: "Nom",
        accessorKey: "name",
        cell: ({ row }) => (
          <Link
            href={`/dashboard/relays/${row.original.relay_id}`}
            className="group flex flex-col"
          >
            <span className="font-medium group-hover:text-primary group-hover:underline">
              {row.original.name}
            </span>
            <span className="text-xs text-muted-foreground">
              {row.original.city ?? "—"}
            </span>
          </Link>
        ),
      },
      {
        id: "address",
        header: "Adresse",
        cell: ({ row }) => {
          const addr = row.original.address;
          const label = typeof addr === "string" ? addr : addr?.label ?? "—";
          return <span className="text-xs">{label}</span>;
        },
      },
      {
        id: "active",
        header: "Actif",
        accessorKey: "is_active",
        cell: ({ getValue }) =>
          getValue() ? (
            <Badge tone="success">Actif</Badge>
          ) : (
            <Badge tone="default">Inactif</Badge>
          ),
      },
      {
        id: "verified",
        header: "Vérifié",
        accessorKey: "is_verified",
        cell: ({ getValue }) =>
          getValue() ? (
            <Badge tone="success">Vérifié</Badge>
          ) : (
            <Badge tone="warning">Non vérifié</Badge>
          ),
      },
      {
        id: "capacity",
        header: "Charge",
        cell: ({ row }) => {
          const r = row.original;
          const load = r.current_load ?? 0;
          const max = r.max_capacity ?? 0;
          return (
            <span className="text-xs">
              {load}/{max || "∞"}
            </span>
          );
        },
      },
      {
        id: "actions",
        header: "",
        enableSorting: false,
        cell: ({ row }) => {
          const r = row.original;
          return (
            <div className="flex gap-2">
              <Link href={`/dashboard/relays/${r.relay_id}`}>
                <Button size="sm" variant="outline">
                  <Eye className="h-3.5 w-3.5" />
                  Fiche
                </Button>
              </Link>
              {!r.is_verified && (
                <Button
                  size="sm"
                  variant="outline"
                  disabled={verifyMut.isPending}
                  onClick={() => verifyMut.mutate(r.relay_id)}
                >
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  Vérifier
                </Button>
              )}
            </div>
          );
        },
      },
    ],
    [verifyMut]
  );

  return (
    <div className="space-y-5 p-8">
      <div>
        <h1 className="text-2xl font-bold">Points relais</h1>
        <p className="text-sm text-muted-foreground">
          Réseau complet des relais Denkma. Vérifiez les nouveaux.
        </p>
      </div>

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement des relais.
        </div>
      )}
      {data && (
        <DataTable
          columns={columns}
          data={data.relay_points}
          searchPlaceholder="Nom, ville, adresse…"
          globalFilterFn={(r, q) =>
            (r.name ?? "").toLowerCase().includes(q) ||
            (r.city ?? "").toLowerCase().includes(q) ||
            (typeof r.address === "string" ? r.address : r.address?.label ?? "").toLowerCase().includes(q) ||
            (r.relay_id ?? "").toLowerCase().includes(q)
          }
        />
      )}
    </div>
  );
}
