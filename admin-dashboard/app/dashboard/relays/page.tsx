"use client";

import * as React from "react";
import { useSearchParams } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { AdminRelay, fetchRelays, fetchRelayStats, verifyRelay } from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { CheckCircle2, Eye, Loader2 } from "lucide-react";
import Link from "next/link";

type RelayRow = AdminRelay & {
  rank?: number | null;
  parcels_processed?: number;
  parcels_delivered?: number;
  projected_bonus_xof?: number;
  next_bonus_threshold?: number | null;
};

const xof = new Intl.NumberFormat("fr-FR");

function currentPeriod() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

export default function RelaysPage() {
  const qc = useQueryClient();
  const searchParams = useSearchParams();
  const activeOnly = searchParams.get("active") === "true";
  const [period, setPeriod] = React.useState(currentPeriod);
  const { data, isLoading, isError } = useQuery({
    queryKey: ["relays", activeOnly],
    queryFn: () => fetchRelays(activeOnly ? { active: true } : undefined),
  });
  const { data: relayStatsData } = useQuery({
    queryKey: ["relays-performance", period],
    queryFn: () => fetchRelayStats(period),
  });

  const relays = React.useMemo<RelayRow[]>(() => {
    const stats = relayStatsData?.stats ?? [];
    const statsByRelay = new Map(stats.map((stat: any) => [stat.relay_id, stat]));
    return (data?.relay_points ?? []).map((relay) => ({
      ...relay,
      ...(statsByRelay.get(relay.relay_id) ?? {}),
    }));
  }, [data, relayStatsData]);

  const verifyMut = useMutation({
    mutationFn: (id: string) => verifyRelay(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["relays"] }),
  });

  const columns = React.useMemo<ColumnDef<RelayRow, any>[]>(
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
        id: "rank",
        header: "Rang mois",
        accessorFn: (relay) => relay.rank ?? 999999,
        cell: ({ row }) => (
          <span className="font-medium">#{row.original.rank ?? "-"}</span>
        ),
      },
      {
        id: "processed",
        header: "Traites",
        accessorFn: (relay) => relay.parcels_processed ?? 0,
        cell: ({ row }) => (
          <div className="flex flex-col">
            <span className="font-medium">
              {row.original.parcels_processed ?? 0} colis
            </span>
            <span className="text-xs text-muted-foreground">
              {row.original.parcels_delivered ?? 0} livres
            </span>
          </div>
        ),
      },
      {
        id: "bonus",
        header: "Bonus",
        accessorFn: (relay) => relay.projected_bonus_xof ?? 0,
        cell: ({ row }) => (
          <div className="flex flex-col">
            <span className="font-medium">
              {xof.format(row.original.projected_bonus_xof ?? 0)} XOF
            </span>
            <span className="text-xs text-muted-foreground">
              Palier {row.original.next_bonus_threshold ?? "-"}
            </span>
          </div>
        ),
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

      <div className="w-40">
        <label className="mb-1.5 block text-sm font-medium">Periode</label>
        <Input value={period} onChange={(e) => setPeriod(e.target.value)} />
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
          data={relays}
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
