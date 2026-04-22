"use client";

import * as React from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { AdminParcel, fetchParcels } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { DateRangeFilter, type DateRange } from "@/components/date-range-filter";
import { Badge } from "@/components/ui/badge";
import { formatDate } from "@/lib/utils";
import { Loader2 } from "lucide-react";

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

type ParcelFilter = {
  value: string;
  label: string;
  params: {
    status?: string;
    scope?: string;
    created_today?: boolean;
    payment_blocked?: boolean;
  };
};

const FILTERS: ParcelFilter[] = [
  { value: "all", label: "Tous", params: {} },
  { value: "today", label: "Aujourd'hui", params: { created_today: true } },
  { value: "active", label: "Actifs", params: { scope: "active" } },
  {
    value: "payment_blocked",
    label: "Paiement bloqué",
    params: { payment_blocked: true },
  },
  { value: "created", label: "Créés", params: { status: "created" } },
  { value: "in_transit", label: "En transit", params: { status: "in_transit" } },
  {
    value: "available_at_relay",
    label: "Dispo relais",
    params: { status: "available_at_relay" },
  },
  {
    value: "out_for_delivery",
    label: "En livraison",
    params: { status: "out_for_delivery" },
  },
  { value: "delivered", label: "Livrés", params: { status: "delivered" } },
  {
    value: "delivery_failed",
    label: "Échecs",
    params: { status: "delivery_failed" },
  },
  { value: "disputed", label: "Litiges", params: { status: "disputed" } },
  { value: "cancelled", label: "Annulés", params: { status: "cancelled" } },
];

const xof = new Intl.NumberFormat("fr-FR");

function filterFromSearchParams(searchParams: URLSearchParams) {
  if (searchParams.get("created_today") === "true") return "today";
  if (searchParams.get("payment_blocked") === "true") return "payment_blocked";
  if (searchParams.get("scope") === "active") return "active";
  return searchParams.get("status") ?? "all";
}

export default function ParcelsPage() {
  const searchParams = useSearchParams();
  const [selectedFilter, setSelectedFilter] = React.useState(() =>
    filterFromSearchParams(searchParams)
  );
  const [dateRange, setDateRange] = React.useState<DateRange>({});

  React.useEffect(() => {
    setSelectedFilter(filterFromSearchParams(searchParams));
  }, [searchParams]);

  const activeFilter =
    FILTERS.find((filter) => filter.value === selectedFilter) ?? FILTERS[0];

  const { data, isLoading, isError } = useQuery({
    queryKey: ["parcels", activeFilter.value, dateRange.from ?? "", dateRange.to ?? ""],
    queryFn: () =>
      fetchParcels({
        limit: 500,
        ...activeFilter.params,
        ...(dateRange.from ? { from_date: dateRange.from } : {}),
        ...(dateRange.to ? { to_date: dateRange.to } : {}),
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
          const status = getValue() as string;
          return (
            <Badge tone={STATUS_TONE[status] ?? "default"}>
              {STATUS_LABELS[status] ?? status}
            </Badge>
          );
        },
      },
      {
        id: "mode",
        header: "Mode",
        accessorKey: "delivery_mode",
        cell: ({ getValue }) => {
          const mode = getValue() as string;
          return <span className="text-xs">{MODE_LABELS[mode] ?? mode ?? "—"}</span>;
        },
      },
      {
        id: "sender",
        header: "Expéditeur",
        accessorFn: (parcel) => parcel.sender_name ?? "—",
        cell: ({ getValue }) => (
          <span className="text-sm">{(getValue() as string) ?? "—"}</span>
        ),
      },
      {
        id: "recipient",
        header: "Destinataire",
        accessorFn: (parcel) => parcel.recipient_name ?? parcel.recipient_phone ?? "—",
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
        accessorFn: (parcel) => parcel.paid_price ?? parcel.quoted_price ?? 0,
        cell: ({ row }) => {
          const parcel = row.original;
          const paid = parcel.paid_price ?? null;
          const quoted = parcel.quoted_price ?? 0;
          return (
            <div className="flex flex-col">
              <span className="font-medium">{xof.format(paid ?? quoted)} XOF</span>
              <span className="text-[11px] text-muted-foreground">
                {parcel.payment_status ?? "—"}
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
            Suivre l'ensemble des colis avec des filtres alignés sur les cartes du
            tableau de bord.
          </p>
        </div>
        <div className="text-sm text-muted-foreground">
          {data ? `${data.total} colis` : null}
        </div>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap gap-2">
          {FILTERS.map((filter) => (
            <button
              key={filter.value}
              onClick={() => setSelectedFilter(filter.value)}
              className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
                activeFilter.value === filter.value
                  ? "border-primary bg-primary text-primary-foreground"
                  : "border-input bg-background hover:bg-accent"
              }`}
            >
              {filter.label}
            </button>
          ))}
        </div>
        <DateRangeFilter value={dateRange} onChange={setDateRange} />
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
          globalFilterFn={(parcel, query) =>
            (parcel.tracking_code ?? "").toLowerCase().includes(query) ||
            (parcel.sender_name ?? "").toLowerCase().includes(query) ||
            (parcel.recipient_name ?? "").toLowerCase().includes(query) ||
            (parcel.recipient_phone ?? "").toLowerCase().includes(query) ||
            (parcel.parcel_id ?? "").toLowerCase().includes(query)
          }
        />
      )}
    </div>
  );
}
