"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { AdminParcel, fetchParcels } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { formatDate } from "@/lib/utils";
import { Loader2 } from "lucide-react";
import Link from "next/link";

const STATUS_LABELS: Record<string, string> = {
  created: "Créé",
  dropped_at_origin_relay: "Déposé relais origine",
  in_transit: "En transit",
  at_destination_relay: "Au relais destination",
  available_at_relay: "Dispo relais",
  out_for_delivery: "En livraison",
  redirected_to_relay: "Redirigé relais",
  delivery_failed: "Échec livraison",
  delivered: "Livré",
  cancelled: "Annulé",
  returned: "Retourné",
  disputed: "Litige",
  expired: "Expiré",
  incident_reported: "Incident",
};

const STATUS_TONE: Record<
  string,
  "default" | "info" | "warning" | "success" | "danger"
> = {
  delivered: "success",
  out_for_delivery: "info",
  in_transit: "info",
  available_at_relay: "info",
  at_destination_relay: "info",
  dropped_at_origin_relay: "info",
  redirected_to_relay: "warning",
  delivery_failed: "danger",
  cancelled: "default",
  returned: "default",
  disputed: "danger",
  expired: "default",
  incident_reported: "danger",
  created: "default",
};

const MODE_LABELS: Record<string, string> = {
  relay_to_relay: "Relais → Relais",
  relay_to_home: "Relais → Domicile",
  home_to_relay: "Domicile → Relais",
  home_to_home: "Domicile → Domicile",
};

const FILTERS: { value: string; label: string }[] = [
  { value: "all", label: "Tous" },
  { value: "created", label: "Créés" },
  { value: "in_transit", label: "En transit" },
  { value: "available_at_relay", label: "Dispo relais" },
  { value: "out_for_delivery", label: "En livraison" },
  { value: "delivered", label: "Livrés" },
  { value: "delivery_failed", label: "Échecs" },
  { value: "disputed", label: "Litiges" },
  { value: "cancelled", label: "Annulés" },
];

const xof = new Intl.NumberFormat("fr-FR");

export default function ParcelsPage() {
  const [status, setStatus] = React.useState("all");

  const { data, isLoading, isError } = useQuery({
    queryKey: ["parcels", status],
    queryFn: () =>
      fetchParcels({
        limit: 500,
        status: status === "all" ? undefined : status,
      }),
  });

  const columns = React.useMemo<ColumnDef<AdminParcel, any>[]>(
    () => [
      {
        id: "tracking",
        header: "Tracking",
        accessorKey: "tracking_code",
        cell: ({ row }) => (
          <Link
            href={`/dashboard/parcels/${row.original.parcel_id}`}
            className="group flex flex-col"
          >
            <span className="font-mono text-xs font-semibold group-hover:text-primary group-hover:underline">
              {row.original.tracking_code}
            </span>
            <span className="text-[11px] text-muted-foreground">
              {row.original.parcel_id}
            </span>
          </Link>
        ),
      },
      {
        id: "status",
        header: "Statut",
        accessorKey: "status",
        cell: ({ getValue }) => {
          const s = getValue() as string;
          return (
            <Badge tone={STATUS_TONE[s] ?? "default"}>
              {STATUS_LABELS[s] ?? s}
            </Badge>
          );
        },
      },
      {
        id: "mode",
        header: "Mode",
        accessorKey: "delivery_mode",
        cell: ({ getValue }) => {
          const m = getValue() as string;
          return (
            <span className="text-xs">{MODE_LABELS[m] ?? m ?? "—"}</span>
          );
        },
      },
      {
        id: "sender",
        header: "Expéditeur",
        accessorFn: (p) => p.sender_name ?? "—",
        cell: ({ getValue }) => (
          <span className="text-sm">{(getValue() as string) ?? "—"}</span>
        ),
      },
      {
        id: "recipient",
        header: "Destinataire",
        accessorFn: (p) => p.recipient_name ?? p.recipient_phone ?? "—",
        cell: ({ row }) => (
          <div className="flex flex-col">
            <span className="text-sm">{row.original.recipient_name ?? "—"}</span>
            {row.original.recipient_phone && (
              <span className="text-[11px] text-muted-foreground">
                {row.original.recipient_phone}
              </span>
            )}
          </div>
        ),
      },
      {
        id: "price",
        header: "Prix",
        accessorFn: (p) => p.paid_price ?? p.quoted_price ?? 0,
        cell: ({ row }) => {
          const p = row.original;
          const paid = p.paid_price ?? null;
          const quoted = p.quoted_price ?? 0;
          return (
            <div className="flex flex-col">
              <span className="font-medium">
                {xof.format(paid ?? quoted)} XOF
              </span>
              <span className="text-[11px] text-muted-foreground">
                {p.payment_status ?? "—"}
              </span>
            </div>
          );
        },
      },
      {
        id: "created_at",
        header: "Créé le",
        accessorKey: "created_at",
        cell: ({ getValue }) => (
          <span className="text-xs text-muted-foreground">
            {formatDate(getValue() as string | undefined)}
          </span>
        ),
      },
    ],
    []
  );

  return (
    <div className="space-y-5 p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Colis</h1>
          <p className="text-sm text-muted-foreground">
            Suivre l'ensemble des colis avec filtres par statut.
          </p>
        </div>
        <div className="text-sm text-muted-foreground">
          {data ? `${data.total} colis` : null}
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        {FILTERS.map((f) => (
          <button
            key={f.value}
            onClick={() => setStatus(f.value)}
            className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
              status === f.value
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
          Erreur de chargement des colis.
        </div>
      )}
      {data && (
        <DataTable
          columns={columns}
          data={data.parcels}
          searchPlaceholder="Code suivi, expéditeur, destinataire, téléphone…"
          globalFilterFn={(p, q) =>
            (p.tracking_code ?? "").toLowerCase().includes(q) ||
            (p.sender_name ?? "").toLowerCase().includes(q) ||
            (p.recipient_name ?? "").toLowerCase().includes(q) ||
            (p.recipient_phone ?? "").toLowerCase().includes(q) ||
            (p.parcel_id ?? "").toLowerCase().includes(q)
          }
        />
      )}
    </div>
  );
}
