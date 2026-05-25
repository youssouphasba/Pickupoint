"use client";

import * as React from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import {
  fetchClientStats,
  fetchDriverStats,
  fetchRelayStats,
} from "@/lib/api";
import { driverLevelTitle } from "@/lib/driver-levels";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  Loader2,
  PackageCheck,
  Star,
  Store,
  Trophy,
  Truck,
  Users,
  Wallet,
} from "lucide-react";

type DriverPerformance = {
  driver_id: string;
  driver_name?: string | null;
  driver_phone?: string | null;
  rank?: number | null;
  deliveries_total?: number;
  deliveries_success?: number;
  success_rate?: number;
  total_earned_xof?: number;
  bonus_paid_xof?: number;
  xp?: number;
  level?: number;
  average_rating?: number;
  total_ratings_count?: number;
  career_deliveries_completed?: number;
  career_total_earned_xof?: number;
  is_active?: boolean;
  is_available?: boolean;
  is_banned?: boolean;
};

type ClientPerformance = {
  user_id: string;
  name?: string | null;
  phone?: string | null;
  rank?: number | null;
  sent_parcels?: number;
  delivered_parcels?: number;
  success_rate?: number;
  spent_xof?: number;
  loyalty_points?: number;
  loyalty_tier?: string;
  account_role?: string;
  is_hybrid_client?: boolean;
  monthly_goal?: number;
  goal_progress?: number;
  is_active?: boolean;
  is_banned?: boolean;
};

type RelayPerformance = {
  relay_id: string;
  name?: string | null;
  phone?: string | null;
  owner_user_id?: string | null;
  rank?: number | null;
  parcels_processed?: number;
  parcels_delivered?: number;
  stock_count?: number;
  projected_bonus_xof?: number;
  next_bonus_threshold?: number | null;
  is_active?: boolean;
  is_verified?: boolean;
};

type Scope = "drivers" | "clients" | "relays";
type StatusFilter = "all" | "available" | "active" | "banned";
type PerformanceFilter = "all" | "podium" | "top10" | "rated" | "experienced";

const xof = new Intl.NumberFormat("fr-FR");

const SCOPES: { value: Scope; label: string; Icon: typeof Truck }[] = [
  { value: "drivers", label: "Livreurs", Icon: Truck },
  { value: "clients", label: "Clients", Icon: Users },
  { value: "relays", label: "Relais", Icon: Store },
];

const STATUS_FILTERS: { value: StatusFilter; label: string }[] = [
  { value: "all", label: "Tous" },
  { value: "available", label: "Disponibles" },
  { value: "active", label: "Actifs" },
  { value: "banned", label: "Suspendus" },
];

const PERFORMANCE_FILTERS: { value: PerformanceFilter; label: string }[] = [
  { value: "all", label: "Tous niveaux" },
  { value: "podium", label: "Podium" },
  { value: "top10", label: "Top 10" },
  { value: "rated", label: "Note 4+" },
  { value: "experienced", label: "Niveau 5+" },
];

function currentPeriod() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

export default function PerformancesPage() {
  const [period, setPeriod] = React.useState(currentPeriod);
  const [scope, setScope] = React.useState<Scope>("drivers");
  const [statusFilter, setStatusFilter] = React.useState<StatusFilter>("all");
  const [performanceFilter, setPerformanceFilter] =
    React.useState<PerformanceFilter>("all");

  const driversQuery = useQuery({
    queryKey: ["driver-performance-general", period],
    queryFn: () => fetchDriverStats(period),
    enabled: scope === "drivers" && Boolean(period),
  });
  const clientsQuery = useQuery({
    queryKey: ["client-performance-general", period],
    queryFn: () => fetchClientStats(period),
    enabled: scope === "clients" && Boolean(period),
  });
  const relaysQuery = useQuery({
    queryKey: ["relay-performance-general", period],
    queryFn: () => fetchRelayStats(period),
    enabled: scope === "relays" && Boolean(period),
  });

  const driverStats: DriverPerformance[] = driversQuery.data?.stats ?? [];
  const clientStats: ClientPerformance[] = clientsQuery.data?.stats ?? [];
  const relayStats: RelayPerformance[] = relaysQuery.data?.stats ?? [];

  const filteredDrivers = React.useMemo(() => {
    return driverStats.filter((driver) => {
      if (statusFilter === "available" && !driver.is_available) return false;
      if (statusFilter === "active" && !driver.is_active) return false;
      if (statusFilter === "banned" && !driver.is_banned) return false;
      const rank = driver.rank ?? 999999;
      const rating = driver.average_rating ?? 0;
      const level = driver.level ?? 1;
      if (performanceFilter === "podium" && rank > 3) return false;
      if (performanceFilter === "top10" && rank > 10) return false;
      if (performanceFilter === "rated" && rating < 4) return false;
      if (performanceFilter === "experienced" && level < 5) return false;
      return true;
    });
  }, [driverStats, statusFilter, performanceFilter]);

  const summary = React.useMemo(() => {
    if (scope === "clients") {
      const sent = clientStats.reduce((sum, item) => sum + (item.sent_parcels ?? 0), 0);
      const delivered = clientStats.reduce(
        (sum, item) => sum + (item.delivered_parcels ?? 0),
        0,
      );
      const spent = clientStats.reduce((sum, item) => sum + (item.spent_xof ?? 0), 0);
      const objectiveReached = clientStats.filter(
        (item) => (item.goal_progress ?? 0) >= 1,
      ).length;
      const hybridClients = clientStats.filter((item) => item.is_hybrid_client).length;
      const successRate = sent === 0 ? 0 : Math.round((delivered / sent) * 100);
      const loyaltyPoints = clientStats.reduce(
        (sum, item) => sum + (item.loyalty_points ?? 0),
        0,
      );
      const progress =
        clientStats.length === 0
          ? 0
          : clientStats.reduce((sum, item) => sum + (item.goal_progress ?? 0), 0) /
            clientStats.length;
      return [
        { icon: Users, label: "Clients suivis", value: clientStats.length },
        { icon: Users, label: "Clients hybrides", value: hybridClients },
        { icon: PackageCheck, label: "Colis crees", value: sent },
        { icon: PackageCheck, label: "Taux livres", value: `${successRate}%` },
        { icon: Trophy, label: "Objectif moyen", value: `${Math.round(progress * 100)}%` },
        { icon: Trophy, label: "Objectifs atteints", value: objectiveReached },
        { icon: Star, label: "Points fidelite", value: loyaltyPoints },
        { icon: Wallet, label: "CA clients", value: `${xof.format(spent)} XOF` },
      ];
    }
    if (scope === "relays") {
      const processed = relayStats.reduce(
        (sum, item) => sum + (item.parcels_processed ?? 0),
        0,
      );
      const delivered = relayStats.reduce(
        (sum, item) => sum + (item.parcels_delivered ?? 0),
        0,
      );
      const stock = relayStats.reduce((sum, item) => sum + (item.stock_count ?? 0), 0);
      const bonuses = relayStats.reduce(
        (sum, item) => sum + (item.projected_bonus_xof ?? 0),
        0,
      );
      const activeRelays = relayStats.filter((item) => item.is_active).length;
      const verifiedRelays = relayStats.filter((item) => item.is_verified).length;
      const bonusEligible = relayStats.filter(
        (item) => (item.projected_bonus_xof ?? 0) > 0,
      ).length;
      return [
        { icon: Store, label: "Relais suivis", value: relayStats.length },
        { icon: Store, label: "Actifs", value: activeRelays },
        { icon: Star, label: "Verifies", value: verifiedRelays },
        { icon: PackageCheck, label: "Colis traites", value: processed },
        { icon: Truck, label: "Livres via relais", value: delivered },
        { icon: Trophy, label: "Relais primes", value: bonusEligible },
        { icon: Trophy, label: "Bonus projetes", value: `${xof.format(bonuses)} XOF` },
        { icon: PackageCheck, label: "Stock actuel", value: stock },
      ];
    }
    const delivered = driverStats.reduce(
      (sum, item) => sum + (item.deliveries_success ?? 0),
      0,
    );
    const earned = driverStats.reduce(
      (sum, item) => sum + (item.total_earned_xof ?? 0),
      0,
    );
    const avgRating =
      driverStats.length === 0
        ? 0
        : driverStats.reduce((sum, item) => sum + (item.average_rating ?? 0), 0) /
          driverStats.length;
    const bonuses = driverStats.reduce(
      (sum, item) => sum + (item.bonus_paid_xof ?? 0),
      0,
    );
    const activeDrivers = driverStats.filter((item) => item.is_active).length;
    const availableDrivers = driverStats.filter((item) => item.is_available).length;
    const successRate =
      driverStats.length === 0
        ? 0
        : driverStats.reduce((sum, item) => sum + (item.success_rate ?? 0), 0) /
          driverStats.length;
    const bonusPaidCount = driverStats.filter((item) => (item.bonus_paid_xof ?? 0) > 0).length;
    return [
      { icon: Users, label: "Livreurs classes", value: driverStats.length },
      { icon: Truck, label: "Actifs", value: activeDrivers },
      { icon: Truck, label: "Disponibles", value: availableDrivers },
      { icon: Truck, label: "Livraisons mois", value: delivered },
      { icon: PackageCheck, label: "Taux reussite", value: `${successRate.toFixed(1)}%` },
      { icon: Wallet, label: "Gains mois", value: `${xof.format(earned)} XOF` },
      { icon: Star, label: "Note moyenne", value: avgRating.toFixed(1) },
      { icon: Trophy, label: "Livreurs primes", value: bonusPaidCount },
      { icon: Trophy, label: "Bonus verses", value: `${xof.format(bonuses)} XOF` },
    ];
  }, [clientStats, driverStats, relayStats, scope]);

  const isLoading =
    (scope === "drivers" && driversQuery.isLoading) ||
    (scope === "clients" && clientsQuery.isLoading) ||
    (scope === "relays" && relaysQuery.isLoading);
  const isError =
    (scope === "drivers" && driversQuery.isError) ||
    (scope === "clients" && clientsQuery.isError) ||
    (scope === "relays" && relaysQuery.isError);

  return (
    <div className="space-y-5 p-8">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Performances</h1>
          <p className="text-sm text-muted-foreground">
            Classements, objectifs, recompenses et activite des livreurs, clients
            et relais.
          </p>
        </div>
        <div className="w-40">
          <label className="mb-1.5 block text-sm font-medium">Periode</label>
          <Input value={period} onChange={(e) => setPeriod(e.target.value)} />
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        {SCOPES.map(({ value, label, Icon }) => (
          <FilterButton
            key={value}
            active={scope === value}
            onClick={() => setScope(value)}
          >
            <Icon className="h-4 w-4" />
            {label}
          </FilterButton>
        ))}
      </div>

      <div className="grid gap-3 md:grid-cols-4 xl:grid-cols-5">
        {summary.map((item) => (
          <MetricCard
            key={`${scope}-${item.label}`}
            icon={item.icon}
            label={item.label}
            value={item.value}
          />
        ))}
      </div>

      {scope === "drivers" && (
        <div className="flex flex-wrap gap-2">
          {STATUS_FILTERS.map((filter) => (
            <FilterButton
              key={filter.value}
              active={statusFilter === filter.value}
              onClick={() => setStatusFilter(filter.value)}
            >
              {filter.label}
            </FilterButton>
          ))}
          {PERFORMANCE_FILTERS.map((filter) => (
            <FilterButton
              key={filter.value}
              active={performanceFilter === filter.value}
              onClick={() => setPerformanceFilter(filter.value)}
            >
              {filter.label}
            </FilterButton>
          ))}
        </div>
      )}

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement des performances.
        </div>
      )}
      {!isLoading && !isError && scope === "drivers" && (
        <DataTable
          columns={driverColumns}
          data={filteredDrivers}
          searchPlaceholder="Livreur, telephone, ID..."
          globalFilterFn={(driver, query) =>
            (driver.driver_name ?? "").toLowerCase().includes(query) ||
            (driver.driver_phone ?? "").toLowerCase().includes(query) ||
            (driver.driver_id ?? "").toLowerCase().includes(query)
          }
          pageSize={25}
        />
      )}
      {!isLoading && !isError && scope === "clients" && (
        <DataTable
          columns={clientColumns}
          data={clientStats}
          searchPlaceholder="Client, telephone, ID..."
          globalFilterFn={(client, query) =>
            (client.name ?? "").toLowerCase().includes(query) ||
            (client.phone ?? "").toLowerCase().includes(query) ||
            (client.user_id ?? "").toLowerCase().includes(query)
          }
          pageSize={25}
        />
      )}
      {!isLoading && !isError && scope === "relays" && (
        <DataTable
          columns={relayColumns}
          data={relayStats}
          searchPlaceholder="Relais, telephone, ID..."
          globalFilterFn={(relay, query) =>
            (relay.name ?? "").toLowerCase().includes(query) ||
            (relay.phone ?? "").toLowerCase().includes(query) ||
            (relay.relay_id ?? "").toLowerCase().includes(query)
          }
          pageSize={25}
        />
      )}
    </div>
  );
}

const driverColumns: ColumnDef<DriverPerformance, any>[] = [
  {
    id: "rank",
    header: "Rang",
    accessorFn: (driver) => driver.rank ?? 999999,
    cell: ({ row }) => <span className="font-bold">#{row.original.rank ?? "-"}</span>,
  },
  {
    id: "driver",
    header: "Livreur",
    accessorFn: (driver) => driver.driver_name ?? driver.driver_id,
    cell: ({ row }) => (
      <Link
        href={`/dashboard/users/${row.original.driver_id}`}
        className="flex flex-col hover:text-primary hover:underline"
      >
        <span className="font-medium">{row.original.driver_name ?? "Livreur"}</span>
        <span className="text-xs text-muted-foreground">
          {row.original.driver_phone ?? row.original.driver_id}
        </span>
      </Link>
    ),
  },
  {
    id: "level",
    header: "XP / Niveau",
    accessorFn: (driver) => driver.level ?? 1,
    cell: ({ row }) => {
      const level = row.original.level ?? 1;
      return (
        <div className="flex flex-col">
          <span className="font-medium">
            Niv. {level} - {driverLevelTitle(level)}
          </span>
          <span className="text-xs text-muted-foreground">
            {row.original.xp ?? 0} XP
          </span>
        </div>
      );
    },
  },
  {
    id: "month",
    header: "Mois",
    accessorFn: (driver) => driver.deliveries_success ?? 0,
    cell: ({ row }) => (
      <div className="flex flex-col">
        <span className="font-medium">
          {row.original.deliveries_success ?? 0} livraisons
        </span>
        <span className="text-xs text-muted-foreground">
          {row.original.success_rate ?? 0}% reussite
        </span>
      </div>
    ),
  },
  {
    id: "rating",
    header: "Note",
    accessorFn: (driver) => driver.average_rating ?? 0,
    cell: ({ row }) => (
      <div className="flex flex-col">
        <span
          className={
            (row.original.average_rating ?? 0) >= 4
              ? "font-medium text-green-600"
              : "font-medium"
          }
        >
          {(row.original.average_rating ?? 0).toFixed(1)}
        </span>
        <span className="text-xs text-muted-foreground">
          {row.original.total_ratings_count ?? 0} avis
        </span>
      </div>
    ),
  },
  {
    id: "earned",
    header: "Gains mois",
    accessorFn: (driver) => driver.total_earned_xof ?? 0,
    cell: ({ row }) => `${xof.format(row.original.total_earned_xof ?? 0)} XOF`,
  },
  {
    id: "bonus",
    header: "Bonus",
    accessorFn: (driver) => driver.bonus_paid_xof ?? 0,
    cell: ({ row }) => {
      const bonus = row.original.bonus_paid_xof ?? 0;
      return bonus > 0 ? (
        <span className="font-medium text-green-600">{xof.format(bonus)} XOF</span>
      ) : (
        <span className="text-muted-foreground">-</span>
      );
    },
  },
  {
    id: "status",
    header: "Statut",
    accessorFn: (driver) =>
      driver.is_banned ? "banned" : driver.is_available ? "available" : "active",
    cell: ({ row }) => {
      const driver = row.original;
      if (driver.is_banned) return <Badge tone="danger">Suspendu</Badge>;
      if (driver.is_available) return <Badge tone="success">Disponible</Badge>;
      if (driver.is_active) return <Badge tone="info">Actif</Badge>;
      return <Badge tone="default">Inactif</Badge>;
    },
  },
];

const clientColumns: ColumnDef<ClientPerformance, any>[] = [
  {
    id: "rank",
    header: "Rang",
    accessorFn: (client) => client.rank ?? 999999,
    cell: ({ row }) => <span className="font-bold">#{row.original.rank ?? "-"}</span>,
  },
  {
    id: "client",
    header: "Client",
    accessorFn: (client) => client.name ?? client.user_id,
    cell: ({ row }) => (
      <Link
        href={`/dashboard/users/${row.original.user_id}`}
        className="flex flex-col hover:text-primary hover:underline"
      >
        <span className="font-medium">{row.original.name ?? "Client"}</span>
        <span className="text-xs text-muted-foreground">
          {row.original.phone ?? row.original.user_id}
        </span>
        {row.original.is_hybrid_client && (
          <span className="mt-1 w-fit rounded-full bg-blue-50 px-2 py-0.5 text-[11px] font-medium text-blue-700">
            {row.original.account_role === "driver"
              ? "Livreur + client"
              : `${row.original.account_role ?? "Compte"} + client`}
          </span>
        )}
      </Link>
    ),
  },
  {
    id: "sent",
    header: "Colis crees",
    accessorFn: (client) => client.sent_parcels ?? 0,
    cell: ({ row }) => `${row.original.sent_parcels ?? 0} colis`,
  },
  {
    id: "delivered",
    header: "Livres",
    accessorFn: (client) => client.delivered_parcels ?? 0,
    cell: ({ row }) => (
      <div className="flex flex-col">
        <span className="font-medium">{row.original.delivered_parcels ?? 0}</span>
        <span className="text-xs text-muted-foreground">
          {row.original.success_rate ?? 0}% reussite
        </span>
      </div>
    ),
  },
  {
    id: "goal",
    header: "Objectif",
    accessorFn: (client) => client.goal_progress ?? 0,
    cell: ({ row }) => {
      const progress = Math.round((row.original.goal_progress ?? 0) * 100);
      return (
        <div className="flex flex-col">
          <span className="font-medium">{progress}%</span>
          <span className="text-xs text-muted-foreground">
            Objectif {row.original.monthly_goal ?? 0}
          </span>
        </div>
      );
    },
  },
  {
    id: "loyalty",
    header: "Fidelite",
    accessorFn: (client) => client.loyalty_points ?? 0,
    cell: ({ row }) => (
      <div className="flex flex-col">
        <span className="font-medium">{row.original.loyalty_points ?? 0} pts</span>
        <span className="text-xs capitalize text-muted-foreground">
          {row.original.loyalty_tier ?? "bronze"}
        </span>
      </div>
    ),
  },
  {
    id: "spent",
    header: "CA mois",
    accessorFn: (client) => client.spent_xof ?? 0,
    cell: ({ row }) => `${xof.format(row.original.spent_xof ?? 0)} XOF`,
  },
  {
    id: "status",
    header: "Statut",
    accessorFn: (client) =>
      client.is_banned ? "banned" : client.is_active ? "active" : "inactive",
    cell: ({ row }) => {
      const client = row.original;
      if (client.is_banned) return <Badge tone="danger">Suspendu</Badge>;
      if (client.is_active) return <Badge tone="success">Actif</Badge>;
      return <Badge tone="default">Inactif</Badge>;
    },
  },
];

const relayColumns: ColumnDef<RelayPerformance, any>[] = [
  {
    id: "rank",
    header: "Rang",
    accessorFn: (relay) => relay.rank ?? 999999,
    cell: ({ row }) => <span className="font-bold">#{row.original.rank ?? "-"}</span>,
  },
  {
    id: "relay",
    header: "Relais",
    accessorFn: (relay) => relay.name ?? relay.relay_id,
    cell: ({ row }) => (
      <Link
        href={`/dashboard/relays/${row.original.relay_id}`}
        className="flex flex-col hover:text-primary hover:underline"
      >
        <span className="font-medium">{row.original.name ?? "Relais"}</span>
        <span className="text-xs text-muted-foreground">
          {row.original.phone ?? row.original.relay_id}
        </span>
      </Link>
    ),
  },
  {
    id: "processed",
    header: "Traites",
    accessorFn: (relay) => relay.parcels_processed ?? 0,
    cell: ({ row }) => `${row.original.parcels_processed ?? 0} colis`,
  },
  {
    id: "delivered",
    header: "Livres",
    accessorFn: (relay) => relay.parcels_delivered ?? 0,
    cell: ({ row }) => `${row.original.parcels_delivered ?? 0} colis`,
  },
  {
    id: "stock",
    header: "Stock",
    accessorFn: (relay) => relay.stock_count ?? 0,
    cell: ({ row }) => `${row.original.stock_count ?? 0} colis`,
  },
  {
    id: "bonus",
    header: "Bonus projete",
    accessorFn: (relay) => relay.projected_bonus_xof ?? 0,
    cell: ({ row }) => `${xof.format(row.original.projected_bonus_xof ?? 0)} XOF`,
  },
  {
    id: "next_bonus",
    header: "Prochain palier",
    accessorFn: (relay) => relay.next_bonus_threshold ?? 999999,
    cell: ({ row }) =>
      row.original.next_bonus_threshold ? (
        `${row.original.next_bonus_threshold} colis`
      ) : (
        <span className="text-muted-foreground">-</span>
      ),
  },
  {
    id: "status",
    header: "Statut",
    accessorFn: (relay) =>
      relay.is_active ? (relay.is_verified ? "verified" : "active") : "inactive",
    cell: ({ row }) => {
      const relay = row.original;
      if (!relay.is_active) return <Badge tone="default">Inactif</Badge>;
      if (relay.is_verified) return <Badge tone="success">Verifie</Badge>;
      return <Badge tone="warning">A verifier</Badge>;
    },
  },
];

function MetricCard({
  icon: Icon,
  label,
  value,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  value: string | number;
}) {
  return (
    <Card>
      <CardContent className="flex items-center gap-3 p-4">
        <div className="rounded-md bg-primary/10 p-2 text-primary">
          <Icon className="h-4 w-4" />
        </div>
        <div>
          <div className="text-xs text-muted-foreground">{label}</div>
          <div className="font-bold">{value}</div>
        </div>
      </CardContent>
    </Card>
  );
}

function FilterButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={`inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-sm transition-colors ${
        active
          ? "border-primary bg-primary text-primary-foreground"
          : "border-input bg-background hover:bg-accent"
      }`}
    >
      {children}
    </button>
  );
}
