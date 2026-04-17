"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { fetchAuditLog } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { Loader2 } from "lucide-react";

type AuditEvent = {
  event_type: string;
  actor_id?: string;
  actor_name?: string;
  actor_role?: string;
  parcel_id?: string;
  tracking_code?: string;
  notes?: string;
  created_at?: string;
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
};

function fmtDate(iso?: string) {
  if (!iso) return "—";
  const d = new Date(iso);
  return `${d.getDate().toString().padStart(2, "0")}/${(d.getMonth() + 1).toString().padStart(2, "0")}/${d.getFullYear()} ${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
}

export default function AuditLogPage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["audit-log"],
    queryFn: () => fetchAuditLog({ limit: 500 }),
  });

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
          return (
            <Badge tone={EVENT_TONES[t] ?? "default"}>{t.replace(/_/g, " ")}</Badge>
          );
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
        cell: ({ getValue }) => (
          <span className="line-clamp-2 max-w-xs text-xs text-muted-foreground">
            {(getValue() as string) ?? "—"}
          </span>
        ),
      },
    ],
    []
  );

  return (
    <div className="space-y-5 p-8">
      <div>
        <h1 className="text-2xl font-bold">Audit log</h1>
        <p className="text-sm text-muted-foreground">
          Journal d'audit global — tous les événements système tracés.
        </p>
      </div>

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement de l'audit log.
        </div>
      )}
      {data && (
        <DataTable
          columns={columns}
          data={events}
          searchPlaceholder="Événement, acteur, tracking code, notes…"
          globalFilterFn={(e, q) =>
            (e.event_type ?? "").toLowerCase().includes(q) ||
            (e.actor_name ?? "").toLowerCase().includes(q) ||
            (e.actor_id ?? "").toLowerCase().includes(q) ||
            (e.tracking_code ?? "").toLowerCase().includes(q) ||
            (e.notes ?? "").toLowerCase().includes(q)
          }
        />
      )}
    </div>
  );
}
