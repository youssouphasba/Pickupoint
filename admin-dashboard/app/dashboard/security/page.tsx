"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { AlertTriangle, Loader2 } from "lucide-react";
import { fetchAuditLog } from "@/lib/api";
import { DataTable, ServerPagination } from "@/components/data-table";
import { DateRangeFilter, type DateRange } from "@/components/date-range-filter";
import { Badge } from "@/components/ui/badge";

type SecurityEvent = {
  event_type: string;
  actor_id?: string;
  actor_name?: string;
  actor_role?: string;
  parcel_id?: string;
  tracking_code?: string;
  notes?: string;
  created_at?: string;
};

function fmtDate(iso?: string) {
  if (!iso) return "—";
  const date = new Date(iso);
  return `${date.toLocaleDateString("fr-FR")} ${date.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })}`;
}

export default function DriverSecurityPage() {
  const [dateRange, setDateRange] = React.useState<DateRange>({});
  const [page, setPage] = React.useState(0);
  const { data, isLoading, isError } = useQuery({
    queryKey: ["driver-security", dateRange.from ?? "", dateRange.to ?? "", page],
    queryFn: () => fetchAuditLog({
      limit: 100,
      offset: page * 100,
      search: "SECURITY_GPS_BLOCKED",
      ...(dateRange.from ? { from_date: dateRange.from } : {}),
      ...(dateRange.to ? { to_date: dateRange.to } : {}),
    }),
    refetchInterval: 60_000,
  });

  React.useEffect(() => setPage(0), [dateRange.from, dateRange.to]);

  const columns = React.useMemo<ColumnDef<SecurityEvent, any>[]>(
    () => [
      {
        id: "date",
        header: "Date",
        accessorKey: "created_at",
        cell: ({ getValue }) => <span className="whitespace-nowrap text-xs text-muted-foreground">{fmtDate(getValue() as string)}</span>,
      },
      {
        id: "event",
        header: "Événement",
        accessorKey: "event_type",
        cell: () => <Badge tone="danger">Blocage sécurité GPS</Badge>,
      },
      {
        id: "driver",
        header: "Livreur",
        accessorFn: (event) => event.actor_name ?? event.actor_id ?? "—",
        cell: ({ row }) => <div><div className="text-sm font-medium">{row.original.actor_name ?? row.original.actor_id ?? "—"}</div>{row.original.actor_role ? <div className="text-[11px] text-muted-foreground">{row.original.actor_role}</div> : null}</div>,
      },
      {
        id: "parcel",
        header: "Colis",
        accessorKey: "tracking_code",
        cell: ({ row }) => row.original.tracking_code ? <span className="font-mono text-xs">{row.original.tracking_code}</span> : <span className="text-xs text-muted-foreground">—</span>,
      },
      {
        id: "notes",
        header: "Détail",
        accessorKey: "notes",
        enableSorting: false,
        cell: ({ getValue }) => <span className="line-clamp-2 max-w-lg text-xs text-muted-foreground">{(getValue() as string) ?? "—"}</span>,
      },
    ],
    []
  );

  const events: SecurityEvent[] = data?.events ?? [];

  return (
    <div className="space-y-5 p-4 sm:p-6 lg:p-8">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="flex items-start gap-3">
          <div className="rounded-lg bg-red-100 p-2 text-red-700"><AlertTriangle className="h-5 w-5" /></div>
          <div>
            <h1 className="text-2xl font-bold">Sécurité livreurs</h1>
            <p className="text-sm text-muted-foreground">Blocages GPS et événements de protection liés aux missions des livreurs.</p>
          </div>
        </div>
        <DateRangeFilter value={dateRange} onChange={setDateRange} />
      </div>

      {isLoading ? <div className="flex h-40 items-center justify-center"><Loader2 className="h-5 w-5 animate-spin text-muted-foreground" /></div> : null}
      {isError ? <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">Erreur de chargement des événements de sécurité.</div> : null}
      {data ? <><DataTable columns={columns} data={events} searchPlaceholder="Filtrer les alertes…" /><ServerPagination page={page} total={data.total} pageSize={100} onPageChange={setPage} /></> : null}
    </div>
  );
}
