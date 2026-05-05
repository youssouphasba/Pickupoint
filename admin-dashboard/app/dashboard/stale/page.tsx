"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import Link from "next/link";
import { fetchActionCenter } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { formatDate } from "@/lib/utils";
import { Loader2 } from "lucide-react";

type StaleParcel = {
  id: string;
  parcel_id: string;
  tracking_code: string;
  parcel_status?: string;
  status?: string;
  relay_name?: string;
  last_move_at?: string;
  age_days?: number;
  sender_name?: string;
  recipient_name?: string;
};

export default function StaleParcelsPage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["action-center", "stale-parcels"],
    queryFn: fetchActionCenter,
    refetchInterval: 60_000,
  });

  const parcels = (data?.categories.stale_parcels.items ??
    []) as unknown as StaleParcel[];

  const columns = React.useMemo<ColumnDef<StaleParcel, any>[]>(
    () => [
      {
        id: "tracking",
        header: "Tracking",
        accessorKey: "tracking_code",
        cell: ({ row, getValue }) => {
          const trackingCode = getValue() as string;
          return row.original.parcel_id ? (
            <Link
              href={`/dashboard/parcels/${row.original.parcel_id}`}
              className="font-mono text-xs font-semibold hover:text-primary hover:underline"
            >
              {trackingCode}
            </Link>
          ) : (
            <span className="font-mono text-xs font-semibold">
              {trackingCode}
            </span>
          );
        },
      },
      {
        id: "status",
        header: "Statut",
        accessorFn: (row) => row.parcel_status || row.status || "",
        cell: ({ getValue }) => {
          const status = (getValue() as string) || "inconnu";
          return <Badge tone="warning">{status.replace(/_/g, " ")}</Badge>;
        },
      },
      {
        id: "relay",
        header: "Relais",
        accessorKey: "relay_name",
        cell: ({ getValue }) => (
          <span className="text-sm">{(getValue() as string) ?? "-"}</span>
        ),
      },
      {
        id: "days",
        header: "Jours",
        accessorKey: "age_days",
        cell: ({ getValue }) => {
          const days = (getValue() as number) ?? 0;
          return <Badge tone={days > 14 ? "danger" : "warning"}>{days} j</Badge>;
        },
      },
      {
        id: "sender",
        header: "Expéditeur",
        accessorKey: "sender_name",
        cell: ({ getValue }) => (
          <span className="text-sm">{(getValue() as string) ?? "-"}</span>
        ),
      },
      {
        id: "updated",
        header: "Dernière mise à jour",
        accessorKey: "last_move_at",
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
          searchPlaceholder="Code suivi, relais, expéditeur..."
          globalFilterFn={(parcel, query) =>
            (parcel.tracking_code ?? "").toLowerCase().includes(query) ||
            (parcel.relay_name ?? "").toLowerCase().includes(query) ||
            (parcel.sender_name ?? "").toLowerCase().includes(query)
          }
          emptyLabel="Aucun colis stagnant. Tout est fluide."
        />
      )}
    </div>
  );
}
