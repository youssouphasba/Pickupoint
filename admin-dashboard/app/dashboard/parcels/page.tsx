"use client";

import * as React from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { Loader2 } from "lucide-react";

import { AdminParcel, AdminParcelsOverview, fetchParcels, fetchParcelsOverview } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { DateRangeFilter, type DateRange } from "@/components/date-range-filter";
import { Badge } from "@/components/ui/badge";
import { formatDate } from "@/lib/utils";

const STATUS_LABELS: Record<string, string> = {
  created: "Créé",
  dropped_at_origin_relay: "Déposé relais origine",
  in_transit: "En transit",
  at_destination_relay: "Au relais destination",
  available_at_relay: "Disponible en relais",
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
    finance_filter?: string;
    created_today?: boolean;
    payment_blocked?: boolean;
  };
};

const FILTERS: ParcelFilter[] = [
  { value: "all", label: "Tous", params: {} },
  { value: "today", label: "Aujourd’hui", params: { created_today: true } },
  { value: "active", label: "Actifs", params: { scope: "active" } },
  {
    value: "payment_blocked",
    label: "Paiement bloqué",
    params: { payment_blocked: true },
  },
  { value: "delivered", label: "Livrés", params: { status: "delivered" } },
  {
    value: "delivered_unpaid",
    label: "À régulariser",
    params: { finance_filter: "delivered_unpaid" },
  },
  { value: "cancelled", label: "Annulés", params: { status: "cancelled" } },
  {
    value: "commission_received",
    label: "Commission reçue",
    params: { finance_filter: "commission_received" },
  },
  {
    value: "commission_debt",
    label: "Commission dette",
    params: { finance_filter: "commission_debt" },
  },
  {
    value: "commission_offered",
    label: "Commission offerte",
    params: { finance_filter: "commission_offered" },
  },
  { value: "disputed", label: "Litiges", params: { status: "disputed" } },
];

const xof = new Intl.NumberFormat("fr-FR");

function filterFromSearchParams(searchParams: URLSearchParams) {
  const financeFilter = searchParams.get("finance_filter");
  if (financeFilter === "delivered_paid") return "delivered";
  if (financeFilter) return financeFilter;
  if (searchParams.get("created_today") === "true") return "today";
  if (searchParams.get("payment_blocked") === "true") return "payment_blocked";
  if (searchParams.get("scope") === "active") return "active";
  return searchParams.get("status") ?? "all";
}

function ParcelStatCard({
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
    <div
      className={`rounded-xl border p-5 shadow-sm ${toneClass} ${onClick ? "cursor-pointer transition hover:shadow-md" : ""}`}
      onClick={onClick}
      role={onClick ? "button" : undefined}
    >
      <div className="text-sm font-medium text-muted-foreground">{title}</div>
      <div className="mt-2 text-2xl font-semibold">{value}</div>
      {hint ? <div className="mt-1 text-xs text-muted-foreground">{hint}</div> : null}
    </div>
  );
}

function modeCount(overview: AdminParcelsOverview | undefined, mode: string) {
  return overview?.by_mode?.[mode] ?? 0;
}

function dateRangeFromSearchParams(searchParams: URLSearchParams): DateRange {
  const from = searchParams.get("from_date") ?? undefined;
  const to = searchParams.get("to_date") ?? undefined;
  return { from, to };
}

export default function ParcelsPage() {
  const searchParams = useSearchParams();
  const [selectedFilter, setSelectedFilter] = React.useState(() =>
    filterFromSearchParams(searchParams)
  );
  const [dateRange, setDateRange] = React.useState<DateRange>(() =>
    dateRangeFromSearchParams(searchParams)
  );

  React.useEffect(() => {
    setSelectedFilter(filterFromSearchParams(searchParams));
    setDateRange(dateRangeFromSearchParams(searchParams));
  }, [searchParams]);

  const activeFilter =
    FILTERS.find((filter) => filter.value === selectedFilter) ?? FILTERS[0];

  const { data: overviewData } = useQuery({
    queryKey: ["parcels-overview", dateRange.from ?? "", dateRange.to ?? ""],
    queryFn: () =>
      fetchParcelsOverview({
        ...(dateRange.from ? { from_date: dateRange.from } : {}),
        ...(dateRange.to ? { to_date: dateRange.to } : {}),
      }),
  });

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
            {row.original.recipient_phone ? (
              <span className="text-[11px] text-muted-foreground">
                {row.original.recipient_phone}
              </span>
            ) : null}
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
                {parcel.payment_override
                  ? "override admin"
                  : parcel.payment_status ?? "—"}
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
            Suivre l’ensemble des colis avec des filtres alignés sur les cartes finance.
          </p>
        </div>
        <div className="text-sm text-muted-foreground">
          {data ? `${data.total} colis` : null}
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-5">
        <ParcelStatCard title="Colis" value={overviewData?.total ?? 0} hint="Tous les colis" tone="teal" onClick={() => setSelectedFilter("all")} />
        <ParcelStatCard title="Actifs" value={overviewData?.active ?? 0} hint="Colis en cours" tone="blue" onClick={() => setSelectedFilter("active")} />
        <ParcelStatCard title="Colis livres" value={overviewData?.delivered ?? 0} hint="Livraisons terminees" tone="green" onClick={() => setSelectedFilter("delivered")} />
        <ParcelStatCard title="Colis annules" value={overviewData?.cancelled ?? 0} hint="Annules sur la periode" tone="orange" onClick={() => setSelectedFilter("cancelled")} />
        <ParcelStatCard title="Paiement bloque" value={overviewData?.payment_blocked ?? 0} hint="Blocage paiement" tone="purple" onClick={() => setSelectedFilter("payment_blocked")} />
      </div>

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        {Object.entries(MODE_LABELS).map(([mode, label]) => (
          <ParcelStatCard
            key={mode}
            title={label}
            value={modeCount(overviewData, mode)}
            hint="Crees sur la periode"
            tone="teal"
          />
        ))}
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

      {isLoading ? (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      ) : null}

      {isError ? (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement des colis.
        </div>
      ) : null}

      {data ? (
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
      ) : null}
    </div>
  );
}
