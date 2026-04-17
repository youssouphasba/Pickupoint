"use client";

import * as React from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import {
  fetchDrivers,
  fetchDriverStats,
  triggerMonthlyRewards,
} from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/ui/toaster";
import { formatDate } from "@/lib/utils";
import { Award, Eye, Loader2, Trophy } from "lucide-react";
import Link from "next/link";

type Driver = {
  user_id: string;
  phone: string;
  full_name?: string | null;
  name?: string | null;
  is_active: boolean;
  is_banned?: boolean;
  average_rating?: number;
  deliveries_completed?: number;
  total_earned?: number;
  missions_count?: number;
  created_at?: string;
};

const xof = new Intl.NumberFormat("fr-FR");

export default function DriversPage() {
  const { toast } = useToast();

  const { data, isLoading, isError } = useQuery({
    queryKey: ["drivers-list"],
    queryFn: fetchDrivers,
  });

  // Monthly rewards
  const [period, setPeriod] = React.useState(() => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
  });
  const [rewardsOpen, setRewardsOpen] = React.useState(false);

  const triggerMut = useMutation({
    mutationFn: () => triggerMonthlyRewards(period),
    onSuccess: () => toast(`Récompenses calculées pour ${period}.`),
    onError: (err: any) =>
      toast(err?.response?.data?.detail ?? "Erreur.", "error"),
  });

  const driverStats = useQuery({
    queryKey: ["driver-stats", period],
    queryFn: () => fetchDriverStats(period),
    enabled: rewardsOpen,
  });

  const drivers: Driver[] = data?.drivers ?? [];

  const columns = React.useMemo<ColumnDef<Driver, any>[]>(
    () => [
      {
        id: "name",
        header: "Livreur",
        accessorFn: (d) => d.name ?? d.full_name ?? "—",
        cell: ({ row }) => {
          const d = row.original;
          return (
            <Link
              href={`/dashboard/users/${d.user_id}`}
              className="group flex flex-col"
            >
              <span className="font-medium group-hover:text-primary group-hover:underline">
                {d.name ?? d.full_name ?? "—"}
              </span>
              <span className="text-xs text-muted-foreground">{d.phone}</span>
            </Link>
          );
        },
      },
      {
        id: "status",
        header: "Statut",
        cell: ({ row }) => {
          const d = row.original;
          if (d.is_banned) return <Badge tone="danger">Suspendu</Badge>;
          if (!d.is_active) return <Badge tone="default">Inactif</Badge>;
          return <Badge tone="success">Actif</Badge>;
        },
      },
      {
        id: "missions",
        header: "Missions",
        accessorKey: "missions_count",
        cell: ({ getValue }) => (
          <span className="font-medium">{(getValue() as number) ?? 0}</span>
        ),
      },
      {
        id: "deliveries",
        header: "Livraisons",
        accessorKey: "deliveries_completed",
        cell: ({ getValue }) => (
          <span className="font-medium">{(getValue() as number) ?? 0}</span>
        ),
      },
      {
        id: "rating",
        header: "Note",
        accessorKey: "average_rating",
        cell: ({ getValue }) => {
          const r = (getValue() as number) ?? 0;
          return (
            <span className={r >= 4 ? "text-green-600 font-medium" : ""}>
              {r > 0 ? r.toFixed(1) : "—"}
            </span>
          );
        },
      },
      {
        id: "earnings",
        header: "Gains",
        accessorKey: "total_earned",
        cell: ({ getValue }) => {
          const v = (getValue() as number) ?? 0;
          return (
            <span className="text-sm">{v > 0 ? `${xof.format(v)} XOF` : "—"}</span>
          );
        },
      },
      {
        id: "actions",
        header: "",
        enableSorting: false,
        cell: ({ row }) => (
          <Link href={`/dashboard/users/${row.original.user_id}`}>
            <Button size="sm" variant="outline">
              <Eye className="h-3.5 w-3.5" />
              Fiche
            </Button>
          </Link>
        ),
      },
    ],
    []
  );

  return (
    <div className="space-y-5 p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Livreurs</h1>
          <p className="text-sm text-muted-foreground">
            Suivi des performances, missions et gains de chaque livreur.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-sm text-muted-foreground">
            {drivers.length} livreur{drivers.length > 1 ? "s" : ""}
          </span>
          <Button
            variant="outline"
            size="sm"
            onClick={() => setRewardsOpen(!rewardsOpen)}
          >
            <Trophy className="h-4 w-4" />
            Récompenses
          </Button>
        </div>
      </div>

      {/* Monthly rewards panel */}
      {rewardsOpen && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Award className="h-4 w-4" />
              Récompenses mensuelles
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex flex-wrap items-end gap-3">
              <div className="w-40">
                <label className="mb-1.5 block text-sm font-medium">
                  Période (YYYY-MM)
                </label>
                <Input
                  value={period}
                  onChange={(e) => setPeriod(e.target.value)}
                  placeholder="2026-04"
                />
              </div>
              <Button
                size="sm"
                onClick={() => triggerMut.mutate()}
                disabled={triggerMut.isPending || !period}
              >
                {triggerMut.isPending && (
                  <Loader2 className="h-4 w-4 animate-spin" />
                )}
                Lancer le calcul
              </Button>
            </div>

            {triggerMut.isError && (
              <div className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
                {(triggerMut.error as any)?.response?.data?.detail ??
                  "Erreur lors du calcul."}
              </div>
            )}

            {driverStats.isLoading && (
              <div className="flex h-20 items-center justify-center">
                <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              </div>
            )}

            {driverStats.data?.stats && driverStats.data.stats.length > 0 && (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-muted/40">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-semibold uppercase text-muted-foreground">
                        Rang
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-semibold uppercase text-muted-foreground">
                        Livreur
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-semibold uppercase text-muted-foreground">
                        Livraisons
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-semibold uppercase text-muted-foreground">
                        Note moy.
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-semibold uppercase text-muted-foreground">
                        Gains
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-semibold uppercase text-muted-foreground">
                        Bonus
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {driverStats.data.stats.map((s: any, i: number) => (
                      <tr key={s.driver_id} className={i % 2 === 1 ? "bg-muted/10" : ""}>
                        <td className="px-3 py-2 font-bold">{s.rank ?? i + 1}</td>
                        <td className="px-3 py-2">
                          <Link
                            href={`/dashboard/users/${s.driver_id}`}
                            className="text-primary underline"
                          >
                            {s.driver_name ?? s.driver_id}
                          </Link>
                        </td>
                        <td className="px-3 py-2">{s.deliveries ?? 0}</td>
                        <td className="px-3 py-2">{(s.avg_rating ?? 0).toFixed(1)}</td>
                        <td className="px-3 py-2">{xof.format(s.total_earned ?? 0)} XOF</td>
                        <td className="px-3 py-2 font-medium text-green-600">
                          {s.bonus ? `${xof.format(s.bonus)} XOF` : "—"}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {driverStats.data?.stats?.length === 0 && (
              <div className="text-sm text-muted-foreground">
                Aucune statistique pour cette période. Lancez le calcul d'abord.
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement des livreurs.
        </div>
      )}
      {data && (
        <DataTable
          columns={columns}
          data={drivers}
          searchPlaceholder="Nom, téléphone, ID…"
          globalFilterFn={(d, q) =>
            (d.name ?? d.full_name ?? "").toLowerCase().includes(q) ||
            (d.phone ?? "").toLowerCase().includes(q) ||
            (d.user_id ?? "").toLowerCase().includes(q)
          }
        />
      )}
    </div>
  );
}
