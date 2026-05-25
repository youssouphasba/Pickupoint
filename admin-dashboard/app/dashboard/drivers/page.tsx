"use client";

import * as React from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useMutation, useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import {
  fetchDrivers,
  fetchDriverStats,
  triggerMonthlyRewards,
} from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { SecureProfileImage } from "@/components/secure-profile-image";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/ui/toaster";
import { driverLevelTitle as driverLevelName } from "@/lib/driver-levels";
import { formatDate } from "@/lib/utils";
import { Award, Eye, Loader2, MapPin, RadioTower, Trophy } from "lucide-react";

type ActiveMission = {
  mission_id?: string | null;
  parcel_id?: string | null;
  tracking_code?: string | null;
  status?: string | null;
  location_updated_at?: string | null;
};

type Driver = {
  user_id: string;
  phone: string;
  full_name?: string | null;
  name?: string | null;
  is_active: boolean;
  is_banned?: boolean;
  is_available?: boolean;
  kyc_status?: string | null;
  profile_picture_url?: string | null;
  profile_picture_status?: string | null;
  last_driver_location?: { lat?: number; lng?: number } | null;
  last_driver_location_at?: string | null;
  average_rating?: number;
  total_ratings_count?: number;
  xp?: number;
  level?: number;
  deliveries_completed?: number;
  total_earned?: number;
  monthly_rank?: number | null;
  monthly_deliveries_success?: number;
  monthly_success_rate?: number;
  monthly_earned_xof?: number;
  monthly_bonus_paid_xof?: number;
  total_ranked_drivers?: number;
  missions_count?: number;
  active_mission?: ActiveMission | null;
  created_at?: string;
};

const xof = new Intl.NumberFormat("fr-FR");

type DriverFilter = "all" | "available" | "active_mission" | "offline" | "banned";
type PhotoFilter = "all" | "approved" | "pending" | "rejected" | "missing";
type PerformanceFilter = "all" | "top_rated" | "experienced" | "new";

const DRIVER_FILTERS: { value: DriverFilter; label: string }[] = [
  { value: "all", label: "Tous" },
  { value: "available", label: "Disponibles" },
  { value: "active_mission", label: "En mission" },
  { value: "offline", label: "Hors ligne" },
  { value: "banned", label: "Suspendus" },
];

const PHOTO_FILTERS: { value: PhotoFilter; label: string }[] = [
  { value: "all", label: "Photos" },
  { value: "approved", label: "Approuvées" },
  { value: "pending", label: "À vérifier" },
  { value: "rejected", label: "Rejetées" },
  { value: "missing", label: "Manquantes" },
];

const PERFORMANCE_FILTERS: { value: PerformanceFilter; label: string }[] = [
  { value: "all", label: "Performance" },
  { value: "top_rated", label: "Note 4+" },
  { value: "experienced", label: "Niveau 5+" },
  { value: "new", label: "Nouveaux" },
];

const PHOTO_LABELS: Record<string, string> = {
  approved: "Photo approuvée",
  pending: "Photo à vérifier",
  rejected: "Photo rejetée",
  missing: "Photo manquante",
};

const PHOTO_TONES: Record<string, "success" | "warning" | "danger" | "default"> = {
  approved: "success",
  pending: "warning",
  rejected: "danger",
  missing: "default",
};

function driverName(driver: Driver) {
  return driver.name ?? driver.full_name ?? "Livreur sans nom";
}

function missionLabel(status?: string | null) {
  if (status === "assigned") return "Assignée";
  if (status === "in_progress") return "En cours";
  if (status === "incident_reported") return "Incident";
  return status ?? "Aucune";
}

function missionTone(status?: string | null) {
  if (status === "in_progress") return "success";
  if (status === "assigned") return "info";
  if (status === "incident_reported") return "danger";
  return "default";
}

function locationTone(lastSeen?: string | null) {
  if (!lastSeen) return "danger";
  const ageMs = Date.now() - new Date(lastSeen).getTime();
  if (!Number.isFinite(ageMs)) return "danger";
  if (ageMs <= 20 * 60 * 1000) return "success";
  if (ageMs <= 60 * 60 * 1000) return "warning";
  return "danger";
}

function locationLabel(lastSeen?: string | null) {
  if (!lastSeen) return "Aucune position";
  const ageMs = Date.now() - new Date(lastSeen).getTime();
  if (!Number.isFinite(ageMs)) return "Position invalide";
  const minutes = Math.max(0, Math.round(ageMs / 60000));
  if (minutes < 1) return "À l’instant";
  if (minutes < 60) return `Il y a ${minutes} min`;
  const hours = Math.round(minutes / 60);
  return `Il y a ${hours} h`;
}

export default function DriversPage() {
  const { toast } = useToast();
  const searchParams = useSearchParams();
  const activeOnly = searchParams.get("active") === "true";

  const { data, isLoading, isError } = useQuery({
    queryKey: ["drivers-list", activeOnly],
    queryFn: () => fetchDrivers(activeOnly ? { active: true } : undefined),
  });

  const [period, setPeriod] = React.useState(() => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
  });
  const [rewardsOpen, setRewardsOpen] = React.useState(false);
  const [driverFilter, setDriverFilter] = React.useState<DriverFilter>("all");
  const [photoFilter, setPhotoFilter] = React.useState<PhotoFilter>("all");
  const [performanceFilter, setPerformanceFilter] =
    React.useState<PerformanceFilter>("all");

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
  const filteredDrivers = React.useMemo(() => {
    return drivers.filter((driver) => {
      if (driverFilter === "available" && !driver.is_available) return false;
      if (driverFilter === "active_mission" && !driver.active_mission) return false;
      if (driverFilter === "offline" && (driver.is_available || driver.active_mission)) return false;
      if (driverFilter === "banned" && !driver.is_banned) return false;
      const photo = driver.profile_picture_status ?? "missing";
      if (photoFilter !== "all" && photo !== photoFilter) return false;
      const rating = driver.average_rating ?? 0;
      const level = driver.level ?? 1;
      const completed = driver.deliveries_completed ?? 0;
      if (performanceFilter === "top_rated" && rating < 4) return false;
      if (performanceFilter === "experienced" && level < 5) return false;
      if (performanceFilter === "new" && completed > 3) return false;
      return true;
    });
  }, [drivers, driverFilter, photoFilter, performanceFilter]);

  const columns = React.useMemo<ColumnDef<Driver, any>[]>(
    () => [
      {
        id: "name",
        header: "Livreur",
        accessorFn: (d) => driverName(d),
        cell: ({ row }) => {
          const d = row.original;
          return (
            <Link
              href={`/dashboard/users/${d.user_id}`}
              className="group flex items-center gap-3"
            >
              <SecureProfileImage
                src={d.profile_picture_url}
                alt={driverName(d)}
                className="h-10 w-10 border"
              />
              <span className="flex flex-col">
                <span className="font-medium group-hover:text-primary group-hover:underline">
                  {driverName(d)}
                </span>
                <span className="text-xs text-muted-foreground">{d.phone}</span>
              </span>
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
          if (d.is_available) return <Badge tone="success">Disponible</Badge>;
          return <Badge tone="info">Actif</Badge>;
        },
      },
      {
        id: "photo",
        header: "Photo",
        accessorFn: (d) => d.profile_picture_status ?? "missing",
        cell: ({ row }) => {
          const status = row.original.profile_picture_status ?? "missing";
          return (
            <Badge tone={PHOTO_TONES[status] ?? "default"}>
              {PHOTO_LABELS[status] ?? status}
            </Badge>
          );
        },
      },
      {
        id: "gps",
        header: "GPS",
        accessorFn: (d) => d.last_driver_location_at ?? "",
        cell: ({ row }) => {
          const lastSeen = row.original.last_driver_location_at;
          const hasPoint = Boolean(row.original.last_driver_location);
          return (
            <div className="flex flex-col gap-1 text-sm">
              <span className="inline-flex items-center gap-1">
                {hasPoint ? (
                  <MapPin className="h-3.5 w-3.5 text-green-600" />
                ) : (
                  <RadioTower className="h-3.5 w-3.5 text-amber-700" />
                )}
                <Badge tone={locationTone(lastSeen)}>
                  {locationLabel(lastSeen)}
                </Badge>
              </span>
              {lastSeen && (
                <span className="text-xs text-muted-foreground">
                  {formatDate(lastSeen)}
                </span>
              )}
            </div>
          );
        },
      },
      {
        id: "active_mission",
        header: "Mission active",
        accessorFn: (d) => d.active_mission?.status ?? "",
        cell: ({ row }) => {
          const mission = row.original.active_mission;
          if (!mission) return <span className="text-muted-foreground">Aucune</span>;
          return (
            <div className="flex flex-col gap-1">
              <Badge tone={missionTone(mission.status)}>
                {missionLabel(mission.status)}
              </Badge>
              <span className="text-xs text-muted-foreground">
                {mission.tracking_code ?? mission.mission_id}
              </span>
            </div>
          );
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
        id: "monthly_rank",
        header: "Classement",
        accessorFn: (d) => d.monthly_rank ?? 999999,
        cell: ({ row }) => {
          const d = row.original;
          return (
            <div className="flex flex-col gap-1">
              <span className="font-medium">
                {d.monthly_rank
                  ? `#${d.monthly_rank} / ${d.total_ranked_drivers ?? "-"}`
                  : "Non classé"}
              </span>
              <span className="text-xs text-muted-foreground">
                {d.monthly_deliveries_success ?? 0} courses ce mois
              </span>
            </div>
          );
        },
      },
      {
        id: "level",
        header: "XP / Niveau",
        accessorFn: (d) => d.level ?? 1,
        cell: ({ row }) => {
          const level = row.original.level ?? 1;
          return (
            <div className="flex flex-col gap-1">
              <span className="font-medium">
                Niv. {level} · {driverLevelName(level)}
              </span>
              <span className="text-xs text-muted-foreground">
                {row.original.xp ?? 0} XP
              </span>
            </div>
          );
        },
      },
      {
        id: "rating",
        header: "Note",
        accessorKey: "average_rating",
        cell: ({ getValue }) => {
          const r = (getValue() as number) ?? 0;
          return (
            <span className={r >= 4 ? "font-medium text-green-600" : ""}>
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
            Suivi des statuts, photos, positions GPS, missions et gains de chaque livreur.
            {activeOnly ? " Filtre actif : livreurs actifs uniquement." : ""}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-sm text-muted-foreground">
            {filteredDrivers.length} / {drivers.length} livreur
            {drivers.length > 1 ? "s" : ""}
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

      <div className="flex flex-wrap gap-2">
        {DRIVER_FILTERS.map((filter) => (
          <button
            key={filter.value}
            onClick={() => setDriverFilter(filter.value)}
            className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
              driverFilter === filter.value
                ? "border-primary bg-primary text-primary-foreground"
                : "border-input bg-background hover:bg-accent"
            }`}
          >
            {filter.label}
          </button>
        ))}
        {PHOTO_FILTERS.map((filter) => (
          <button
            key={filter.value}
            onClick={() => setPhotoFilter(filter.value)}
            className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
              photoFilter === filter.value
                ? "border-primary bg-primary text-primary-foreground"
                : "border-input bg-background hover:bg-accent"
            }`}
          >
            {filter.label}
          </button>
        ))}
        {PERFORMANCE_FILTERS.map((filter) => (
          <button
            key={filter.value}
            onClick={() => setPerformanceFilter(filter.value)}
            className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
              performanceFilter === filter.value
                ? "border-primary bg-primary text-primary-foreground"
                : "border-input bg-background hover:bg-accent"
            }`}
          >
            {filter.label}
          </button>
        ))}
      </div>

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
                        <td className="px-3 py-2">
                          {s.deliveries_success ?? s.deliveries_total ?? s.deliveries ?? 0}
                        </td>
                        <td className="px-3 py-2">{(s.avg_rating ?? 0).toFixed(1)}</td>
                        <td className="px-3 py-2">
                          {xof.format(s.total_earned_xof ?? s.total_earned ?? 0)} XOF
                        </td>
                        <td className="px-3 py-2 font-medium text-green-600">
                          {s.bonus_paid_xof
                            ? `${xof.format(s.bonus_paid_xof)} XOF`
                            : s.bonus
                              ? `${xof.format(s.bonus)} XOF`
                              : "—"}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {driverStats.data?.stats?.length === 0 && (
              <div className="text-sm text-muted-foreground">
                Aucune statistique pour cette période. Lancez le calcul d’abord.
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
          data={filteredDrivers}
          searchPlaceholder="Nom, téléphone, ID…"
          globalFilterFn={(d, q) =>
            driverName(d).toLowerCase().includes(q) ||
            (d.phone ?? "").toLowerCase().includes(q) ||
            (d.user_id ?? "").toLowerCase().includes(q)
          }
        />
      )}
    </div>
  );
}
