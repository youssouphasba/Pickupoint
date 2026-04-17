"use client";

import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Package,
  CheckCircle2,
  XCircle,
  Activity,
  Wallet,
  Store,
  Users,
  Radar,
  RadioTower,
  TimerOff,
  Clock,
  AlertTriangle,
  Banknote,
  Loader2,
  TrendingUp,
} from "lucide-react";

type DashboardKpis = {
  total_parcels: number;
  parcels_today: number;
  delivered: number;
  failed: number;
  active_parcels: number;
  pending_payouts: number;
  success_rate: number;
  active_relays: number;
  active_drivers: number;
  live_fleet: number;
  signal_lost: number;
  critical_delay: number;
  stale_parcels: number;
  payment_blocked_parcels: number;
  revenue_xof: number;
};

async function fetchDashboard(): Promise<DashboardKpis> {
  const { data } = await api.get("/api/admin/dashboard");
  return data;
}

const xof = new Intl.NumberFormat("fr-FR");

type Tone = "neutral" | "success" | "warning" | "danger" | "info";

const toneStyles: Record<Tone, string> = {
  neutral: "bg-muted/50 text-foreground",
  success: "bg-green-50 text-green-700",
  warning: "bg-amber-50 text-amber-700",
  danger: "bg-red-50 text-red-700",
  info: "bg-blue-50 text-blue-700",
};

function KpiCard({
  label,
  value,
  Icon,
  tone = "neutral",
  hint,
}: {
  label: string;
  value: string | number;
  Icon: React.ComponentType<{ className?: string }>;
  tone?: Tone;
  hint?: string;
}) {
  return (
    <Card>
      <CardContent className="flex items-start justify-between p-5">
        <div>
          <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {label}
          </div>
          <div className="mt-1 text-2xl font-bold">{value}</div>
          {hint && (
            <div className="mt-1 text-xs text-muted-foreground">{hint}</div>
          )}
        </div>
        <div
          className={`flex h-10 w-10 items-center justify-center rounded-lg ${toneStyles[tone]}`}
        >
          <Icon className="h-5 w-5" />
        </div>
      </CardContent>
    </Card>
  );
}

export default function DashboardHome() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["dashboard"],
    queryFn: fetchDashboard,
    refetchInterval: 30_000,
  });

  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="p-8 text-sm text-red-700">
        Erreur de chargement du tableau de bord.
      </div>
    );
  }

  return (
    <div className="space-y-6 p-8">
      <div>
        <h1 className="text-2xl font-bold">Tableau de bord</h1>
        <p className="text-sm text-muted-foreground">
          Vue temps réel. Rafraîchissement toutes les 30 secondes.
        </p>
      </div>

      <section>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
          Activité colis
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard
            label="Aujourd'hui"
            value={data.parcels_today}
            Icon={Package}
            tone="info"
          />
          <KpiCard
            label="Actifs"
            value={data.active_parcels}
            Icon={Activity}
            tone="info"
          />
          <KpiCard
            label="Livrés (total)"
            value={data.delivered}
            Icon={CheckCircle2}
            tone="success"
            hint={`${data.success_rate}% réussite`}
          />
          <KpiCard
            label="Échecs"
            value={data.failed}
            Icon={XCircle}
            tone="danger"
          />
        </div>
      </section>

      <section>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
          Chiffre d'affaires
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard
            label="Revenu total"
            value={`${xof.format(Math.round(data.revenue_xof))} XOF`}
            Icon={TrendingUp}
            tone="success"
          />
          <KpiCard
            label="Paiements en attente"
            value={data.payment_blocked_parcels}
            Icon={Banknote}
            tone="warning"
            hint="Colis bloqués pour paiement"
          />
          <KpiCard
            label="Demandes de retrait"
            value={data.pending_payouts}
            Icon={Wallet}
            tone="warning"
          />
          <KpiCard
            label="Colis total"
            value={data.total_parcels}
            Icon={Package}
          />
        </div>
      </section>

      <section>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
          Flotte & réseau
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard
            label="Livreurs actifs"
            value={data.active_drivers}
            Icon={Users}
            tone="info"
          />
          <KpiCard
            label="Relais actifs"
            value={data.active_relays}
            Icon={Store}
            tone="info"
          />
          <KpiCard
            label="Positions live"
            value={data.live_fleet}
            Icon={Radar}
            tone="success"
            hint="Dernière heure"
          />
          <KpiCard
            label="Signal perdu"
            value={data.signal_lost}
            Icon={RadioTower}
            tone={data.signal_lost > 0 ? "danger" : "neutral"}
            hint="> 20 min sans GPS"
          />
        </div>
      </section>

      <section>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
          Alertes opérationnelles
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <KpiCard
            label="Missions > 3 h"
            value={data.critical_delay}
            Icon={TimerOff}
            tone={data.critical_delay > 0 ? "danger" : "neutral"}
          />
          <KpiCard
            label="Colis stagnants"
            value={data.stale_parcels}
            Icon={Clock}
            tone={data.stale_parcels > 0 ? "warning" : "neutral"}
            hint="> 7 j en relais"
          />
          <KpiCard
            label="Échecs de livraison"
            value={data.failed}
            Icon={AlertTriangle}
            tone={data.failed > 0 ? "warning" : "neutral"}
          />
        </div>
      </section>
    </div>
  );
}
