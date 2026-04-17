"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { fetchStaleParcels } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { formatDate } from "@/lib/utils";
import { Loader2 } from "lucide-react";

type StaleParcel = {
  parcel_id: string;
  tracking_code: string;
  status: string;
  relay_name?: string;
  updated_at?: string;
  days_stale?: number;
  sender_name?: string;
  recipient_name?: string;
};

export default function StaleParcelsPage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["stale-parcels"],
    queryFn: fetchStaleParcels,
    refetchInterval: 60_000,
  });

  const parcels: StaleParcel[] = data?.parcels ?? [];

  const columns = React.useMemo<ColumnDef<StaleParcel, any>[]>(
    () => [
      {
        id: "tracking",
        header: "Tracking",
        accessorKey: "tracking_code",
        cell: ({ getValue }) => (
          <span className="font-mono text-xs font-semibold">
            {getValue() as string}
          </span>
        ),
      },
      {
        id: "status",
        header: "Statut",
        accessorKey: "status",
        cell: ({ getValue }) => (
          <Badge tone="warning">{(getValue() as string).replace(/_/g, " ")}</Badge>
        ),
      },
      {
        id: "relay",
        header: "Relais",
        accessorKey: "relay_name",
        cell: ({ getValue }) => (
          <span className="text-sm">{(getValue() as string) ?? "—"}</span>
        ),
      },
      {
        id: "days",
        header: "Jours",
        accessorKey: "days_stale",
        cell: ({ getValue }) => {
          const d = (getValue() as number) ?? 0;
          return (
            <Badge tone={d > 14 ? "danger" : "warning"}>
              {d}j
            </Badge>
          );
        },
      },
      {
        id: "sender",
        header: "Expéditeur",
        accessorKey: "sender_name",
        cell: ({ getValue }) => (
          <span className="text-sm">{(getValue() as string) ?? "—"}</span>
        ),
      },
      {
        id: "updated",
        header: "Dernière MAJ",
        accessorKey: "updated_at",
        cell: ({ getValue }) => (
          <span className="text-xs text-muted-foreground">
            {formatDate(getValue() as string)}
          </span>
        ),
      },
    ],
    []
  );

  return (
    <div className="space-y-5 p-8">
      <div>
        <h1 className="text-2xl font-bold">Colis stagnants</h1>
        <p className="text-sm text-muted-foreground">
          Colis immobilisés en relais depuis plus de 7 jours.
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
          data={parcels}
          searchPlaceholder="Code suivi, relais, expéditeur…"
          globalFilterFn={(p, q) =>
            (p.tracking_code ?? "").toLowerCase().includes(q) ||
            (p.relay_name ?? "").toLowerCase().includes(q) ||
            (p.sender_name ?? "").toLowerCase().includes(q)
          }
          emptyLabel="Aucun colis stagnant. Tout est fluide."
        />
      )}
    </div>
  );
}
