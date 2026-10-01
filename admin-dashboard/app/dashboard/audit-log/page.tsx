"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { fetchAuditLog } from "@/lib/api";
import { DataTable, ServerPagination } from "@/components/data-table";
import { DateRangeFilter, type DateRange } from "@/components/date-range-filter";
import { Badge } from "@/components/ui/badge";
import { Loader2 } from "lucide-react";
import { Input } from "@/components/ui/input";
import Link from "next/link";

type AuditEvent = {
  event_type: string;
  actor_id?: string;
  actor_name?: string;
  actor_role?: string;
  parcel_id?: string;
  tracking_code?: string;
  notes?: string;
  created_at?: string;
  target_user_name?: string;
  metadata?: { target_user_id?: string; document_type?: string };
};

const EVENT_TONES: Record<string, "default" | "info" | "success" | "warning" | "danger"> = {
  PARCEL_CREATED: "info",
  STATUS_CHANGED: "info",
  DELIVERED: "success",
  DELIVERY_FAILED: "danger",
  PAYOUT_APPROVED: "success",
  PAYOUT_REJECTED: "danger",
  USER_BANNED: "danger",
  USER_UNBANNED: "success",
  USER_ROLE_CHANGED: "warning",
  SECURITY_GPS_BLOCKED: "danger",
  KYC_DOCUMENT_ACCESS_DENIED: "danger",
  KYC_DOCUMENT_VIEWED: "info",
  KYC_DOCUMENT_UPLOADED: "info",
  KYC_DOCUMENT_REPLACED: "warning",
  KYC_ACCESS_GRANTED: "warning",
  KYC_ACCESS_REVOKED: "warning",
};

const EVENT_LABELS: Record<string, string> = {
  SECURITY_GPS_BLOCKED: "BLOCAGE SÉCURITÉ GPS",
  KYC_DOCUMENT_ACCESS_DENIED: "Accès à une pièce refusé",
  KYC_DOCUMENT_VIEWED: "Pièce d’identité consultée",
  KYC_DOCUMENT_UPLOADED: "Pièce d’identité téléversée",
  KYC_DOCUMENT_REPLACED: "Pièce d’identité remplacée",
  KYC_ACCESS_GRANTED: "Accès aux pièces autorisé",
  KYC_ACCESS_REVOKED: "Accès aux pièces retiré",
};

function fmtDate(iso?: string) {
  if (!iso) return "—";
  const d = new Date(iso);
  return `${d.getDate().toString().padStart(2, "0")}/${(d.getMonth() + 1).toString().padStart(2, "0")}/${d.getFullYear()} ${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
}

export default function AuditLogPage() {
  const [dateRange, setDateRange] = React.useState<DateRange>({});
  const [serverSearch, setServerSearch] = React.useState("");
  const [page, setPage] = React.useState(0);
  const { data, isLoading, isError } = useQuery({
    queryKey: ["audit-log", dateRange.from ?? "", dateRange.to ?? "", serverSearch, page],
    queryFn: () =>
      fetchAuditLog({
        limit: 100,
        offset: page * 100,
        search: serverSearch.trim() || undefined,
        ...(dateRange.from ? { from_date: dateRange.from } : {}),
        ...(dateRange.to ? { to_date: dateRange.to } : {}),
      }),
    refetchInterval: 60_000,
  });
  React.useEffect(() => setPage(0), [serverSearch, dateRange.from, dateRange.to]);

  const events: AuditEvent[] = data?.events ?? [];

  const columns = React.useMemo<ColumnDef<AuditEvent, any>[]>(
    () => [
      {
        id: "date",
        header: "Date",
        accessorKey: "created_at",
        cell: ({ getValue }) => (
          <span className="whitespace-nowrap text-xs text-muted-foreground">
            {fmtDate(getValue() as string)}
          </span>
        ),
      },
      {
        id: "event",
        header: "Événement",
        accessorKey: "event_type",
        cell: ({ getValue }) => {
          const t = getValue() as string;
          return <Badge tone={EVENT_TONES[t] ?? "default"}>{EVENT_LABELS[t] ?? t.replace(/_/g, " ")}</Badge>;
        },
      },
      {
        id: "actor",
        header: "Acteur",
        accessorFn: (e) => e.actor_name ?? e.actor_id ?? "—",
        cell: ({ row }) => (
          <div className="flex flex-col">
            <span className="text-sm">{row.original.actor_name ?? row.original.actor_id ?? "—"}</span>
            {row.original.actor_role && (
              <span className="text-[11px] text-muted-foreground">{row.original.actor_role}</span>
            )}
          </div>
        ),
      },
      {
        id: "parcel",
        header: "Colis",
        accessorKey: "tracking_code",
        cell: ({ row }) =>
          row.original.tracking_code ? (
            <span className="font-mono text-xs">{row.original.tracking_code}</span>
          ) : (
            <span className="text-xs text-muted-foreground">—</span>
          ),
      },
      {
        id: "notes",
        header: "Notes",
        accessorKey: "notes",
        enableSorting: false,
        cell: ({ getValue, row }) => (
          <div className="space-y-1 text-xs text-muted-foreground">
            <span className="line-clamp-2 max-w-xs">{(getValue() as string) ?? "—"}</span>
            {row.original.metadata?.target_user_id && (
              <Link href={`/dashboard/users/${encodeURIComponent(row.original.metadata.target_user_id)}`} className="block text-primary underline">
                {row.original.target_user_name ?? row.original.metadata.target_user_id}
                {row.original.metadata.document_type === "license" ? " · Permis" : row.original.metadata.document_type === "id_card" ? " · Pièce d’identité" : ""}
              </Link>
            )}
          </div>
        ),
      },
    ],
    []
  );

  return (
    <div className="space-y-5 p-4 sm:p-6 lg:p-8">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Journal des actions</h1>
          <p className="text-sm text-muted-foreground">
            Retrouvez les interventions administratives et les événements enregistrés. Filtrez par date, puis ouvrez les détails utiles.
          </p>
        </div>
        <DateRangeFilter value={dateRange} onChange={setDateRange} />
      </div>

      <Input
        value={serverSearch}
        onChange={(event) => setServerSearch(event.target.value)}
        placeholder="Rechercher côté serveur : action, acteur, colis…"
        className="max-w-xl"
      />

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement du journal d’audit.
        </div>
      )}
      {data && (
        <>
          <DataTable
            columns={columns}
            data={events}
            searchPlaceholder="Filtrer la page…"
            globalFilterFn={(e, q) =>
              (e.event_type ?? "").toLowerCase().includes(q) ||
              (e.actor_name ?? "").toLowerCase().includes(q) ||
              (e.actor_id ?? "").toLowerCase().includes(q) ||
              (e.tracking_code ?? "").toLowerCase().includes(q) ||
              (e.notes ?? "").toLowerCase().includes(q)
            }
          />
          <ServerPagination page={page} total={data.total} pageSize={100} onPageChange={setPage} />
        </>
      )}
    </div>
  );
}
