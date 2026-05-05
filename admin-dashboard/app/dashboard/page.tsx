"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { ActionCenterSection } from "@/components/action-center-section";
import { useActionCenter } from "@/lib/use-action-center";
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
  ArrowUpRight,
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
  href,
}: {
  label: string;
  value: string | number;
  Icon: React.ComponentType<{ className?: string }>;
  tone?: Tone;
  hint?: string;
  href?: string;
}) {
  const card = (
    <Card
      className={
        href
          ? "h-full transition hover:-translate-y-0.5 hover:border-emerald-300 hover:shadow-md"
          : "h-full"
      }
    >
      <CardContent className="flex items-start justify-between p-5">
        <div>
          <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {label}
          </div>
          <div className="mt-1 text-2xl font-bold">{value}</div>
          {hint && (
            <div className="mt-1 text-xs text-muted-foreground">{hint}</div>
          )}
          {href && (
            <div className="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-emerald-700">
              Voir les détails
              <ArrowUpRight className="h-3.5 w-3.5" />
            </div>
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

  if (!href) return card;

  return (
    <Link href={href} aria-label={`Voir les détails : ${label}`}>
      {card}
    </Link>
  );
}

export default function DashboardHome() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["dashboard"],
    queryFn: fetchDashboard,
    refetchInterval: 30_000,
  });
  const { data: actionCenter } = useActionCenter();

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

  const actionCounts = {
    payouts: actionCenter?.categories.payouts.count ?? data.pending_payouts,
    paymentBlocked:
      actionCenter?.categories.payment_blocked.count ??
      data.payment_blocked_parcels,
    anomalies: actionCenter?.categories.anomalies.count ?? data.signal_lost,
    stale: actionCenter?.categories.stale_parcels.count ?? data.stale_parcels,
  };

  return (
    <div className="space-y-6 p-8">
      <div>
        <h1 className="text-2xl font-bold">Tableau de bord</h1>
        <p className="text-sm text-muted-foreground">
          Vue temps réel. Cliquez sur une carte pour ouvrir le module de
          contrôle correspondant.
        </p>
      </div>

      <ActionCenterSection />

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
            href="/dashboard/parcels?created_today=true"
          />
          <KpiCard
            label="Actifs"
            value={data.active_parcels}
            Icon={Activity}
            tone="info"
            href="/dashboard/parcels?scope=active"
          />
          <KpiCard
            label="Livrés (total)"
            value={data.delivered}
            Icon={CheckCircle2}
            tone="success"
            hint={`${data.success_rate}% réussite`}
            href="/dashboard/parcels?status=delivered"
          />
          <KpiCard
            label="Échecs"
            value={data.failed}
            Icon={XCircle}
            tone="danger"
            href="/dashboard/parcels?status=delivery_failed"
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
            href="/dashboard/finance"
          />
          <KpiCard
            label="Paiements en attente"
            value={actionCounts.paymentBlocked}
            Icon={Banknote}
            tone="warning"
            hint="Colis bloqués pour paiement"
            href="/dashboard/parcels?payment_blocked=true"
          />
          <KpiCard
            label="Demandes de retrait"
            value={actionCounts.payouts}
            Icon={Wallet}
            tone="warning"
            href="/dashboard/payouts"
          />
          <KpiCard
            label="Colis total"
            value={data.total_parcels}
            Icon={Package}
            href="/dashboard/parcels"
          />
        </div>
      </section>

      <section>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
          Flotte et réseau
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard
            label="Livreurs actifs"
            value={data.active_drivers}
            Icon={Users}
            tone="info"
            href="/dashboard/drivers?active=true"
          />
          <KpiCard
            label="Relais actifs"
            value={data.active_relays}
            Icon={Store}
            tone="info"
            href="/dashboard/relays?active=true"
          />
          <KpiCard
            label="Positions live"
            value={data.live_fleet}
            Icon={Radar}
            tone="success"
            hint="Dernière heure"
            href="/dashboard/fleet?filter=live"
          />
          <KpiCard
            label="Anomalies flotte"
            value={actionCounts.anomalies}
            Icon={RadioTower}
            tone={actionCounts.anomalies > 0 ? "danger" : "neutral"}
            hint="GPS perdu ou mission trop longue"
            href="/dashboard/anomalies"
          />
        </div>
      </section>

      <section>
        <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
          Alertes opérationnelles
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <KpiCard
            label="Missions de plus de 3 h"
            value={data.critical_delay}
            Icon={TimerOff}
            tone={data.critical_delay > 0 ? "danger" : "neutral"}
            href="/dashboard/anomalies"
          />
          <KpiCard
            label="Colis stagnants"
            value={actionCounts.stale}
            Icon={Clock}
            tone={actionCounts.stale > 0 ? "warning" : "neutral"}
            hint="Plus de 7 jours en relais"
            href="/dashboard/stale"
          />
          <KpiCard
            label="Échecs de livraison"
            value={data.failed}
            Icon={AlertTriangle}
            tone={data.failed > 0 ? "warning" : "neutral"}
            href="/dashboard/parcels?status=delivery_failed"
          />
        </div>
      </section>
    </div>
  );
}
