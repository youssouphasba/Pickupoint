"use client";

import * as React from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { api, type ActionItem } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { ActionCenterSection } from "@/components/action-center-section";
import { useActionCenter } from "@/lib/use-action-center";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
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

type Tone = "neutral" | "success" | "warning" | "danger" | "info";

type DetailState = {
  title: string;
  description?: string;
  items: ActionItem[];
} | null;

async function fetchDashboard(): Promise<DashboardKpis> {
  const { data } = await api.get("/api/admin/dashboard");
  return data;
}

const xof = new Intl.NumberFormat("fr-FR");

const toneStyles: Record<Tone, string> = {
  neutral: "bg-muted/50 text-foreground",
  success: "bg-green-50 text-green-700",
  warning: "bg-amber-50 text-amber-700",
  danger: "bg-red-50 text-red-700",
  info: "bg-blue-50 text-blue-700",
};

function asText(value: unknown, fallback = "-") {
  if (typeof value !== "string") return fallback;
  const trimmed = value.trim();
  return trimmed.length ? trimmed : fallback;
}

function KpiCard({
  label,
  value,
  Icon,
  tone = "neutral",
  hint,
  href,
  onClick,
}: {
  label: string;
  value: string | number;
  Icon: React.ComponentType<{ className?: string }>;
  tone?: Tone;
  hint?: string;
  href?: string;
  onClick?: () => void;
}) {
  const interactive = Boolean(href || onClick);

  const card = (
    <Card className={interactive ? "h-full transition hover:-translate-y-0.5 hover:border-emerald-300 hover:shadow-md" : "h-full"}>
      <CardContent className="flex items-start justify-between p-5">
        <div>
          <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {label}
          </div>
          <div className="mt-1 text-2xl font-bold">{value}</div>
          {hint && <div className="mt-1 text-xs text-muted-foreground">{hint}</div>}
          {interactive && (
            <div className="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-emerald-700">
              Voir le détail
              <ArrowUpRight className="h-3.5 w-3.5" />
            </div>
          )}
        </div>
        <div className={`flex h-10 w-10 items-center justify-center rounded-lg ${toneStyles[tone]}`}>
          <Icon className="h-5 w-5" />
        </div>
      </CardContent>
    </Card>
  );

  if (onClick) {
    return (
      <button type="button" onClick={onClick} className="block h-full w-full text-left">
        {card}
      </button>
    );
  }

  if (href) {
    return (
      <Link href={href} aria-label={`Voir le détail : ${label}`}>
        {card}
      </Link>
    );
  }

  return card;
}

function DashboardDetailModal({
  state,
  onOpenChange,
}: {
  state: DetailState;
  onOpenChange: (open: boolean) => void;
}) {
  return (
    <Dialog open={Boolean(state)} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-hidden p-0">
        <DialogHeader className="border-b px-6 py-5">
          <DialogTitle>{state?.title ?? "Détail"}</DialogTitle>
          {state?.description ? <DialogDescription>{state.description}</DialogDescription> : null}
        </DialogHeader>
        <div className="max-h-[70vh] overflow-y-auto px-6 py-5">
          {state?.items?.length ? (
            <div className="space-y-3">
              {state.items.map((item, index) => (
                <div key={`${String(item.id ?? index)}-${index}`} className="rounded-lg border border-border/70 p-4">
                  <div className="text-sm font-semibold">
                    {asText(item.tracking_code) !== "-"
                      ? `Colis ${asText(item.tracking_code)}`
                      : asText(item.owner_name, asText(item.driver_name, asText(item.full_name, "Élément")))}
                  </div>
                  <div className="mt-1 text-sm text-muted-foreground">
                    {[
                      asText(item.parcel_status, ""),
                      asText(item.payment_status, ""),
                      asText(item.phone, ""),
                      asText(item.preview, ""),
                    ]
                      .filter(Boolean)
                      .join(" · ") || "Aucun détail complémentaire."}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="rounded-lg border border-dashed border-border px-4 py-6 text-sm text-muted-foreground">
              Aucun élément à afficher pour ce KPI.
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

export default function DashboardHome() {
  const [detailState, setDetailState] = React.useState<DetailState>(null);
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
    return <div className="p-8 text-sm text-red-700">Erreur de chargement du tableau de bord.</div>;
  }

  const category = actionCenter?.categories;
  const actionCounts = {
    payouts: category?.payouts.count ?? data.pending_payouts,
    paymentBlocked: category?.payment_blocked.count ?? data.payment_blocked_parcels,
    anomalies: category?.anomalies.count ?? data.signal_lost,
    stale: category?.stale_parcels.count ?? data.stale_parcels,
  };

  function openDetails(title: string, items: ActionItem[], description?: string) {
    setDetailState({ title, items, description });
  }

  return (
    <div className="space-y-6 p-8">
      <DashboardDetailModal state={detailState} onOpenChange={(open) => !open && setDetailState(null)} />

      <div>
        <h1 className="text-2xl font-bold">Tableau de bord</h1>
        <p className="text-sm text-muted-foreground">
          Vue temps réel. Les alertes ouvrent directement les éléments concernés.
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
            label="Livrés"
            value={data.delivered}
            Icon={CheckCircle2}
            tone="success"
            hint={`${data.success_rate}% de réussite`}
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
          Finance et flux
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <KpiCard
            label="Commission Denkma"
            value={`${xof.format(Math.round(data.revenue_xof))} XOF`}
            Icon={TrendingUp}
            tone="success"
            href="/dashboard/finance"
          />
          <KpiCard
            label="Paiements bloqués"
            value={actionCounts.paymentBlocked}
            Icon={Banknote}
            tone="warning"
            hint="Colis à débloquer"
            onClick={() => openDetails("Paiements bloqués", category?.payment_blocked.items ?? [], "Colis encore bloqués côté exploitation.")}
          />
          <KpiCard
            label="Retraits à valider"
            value={actionCounts.payouts}
            Icon={Wallet}
            tone="warning"
            onClick={() => openDetails("Retraits à valider", category?.payouts.items ?? [], "Demandes en attente de validation admin.")}
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
            onClick={() => openDetails("Anomalies flotte", category?.anomalies.items ?? [], "Signaux GPS perdus et retards critiques.")}
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
            onClick={() =>
              openDetails(
                "Retards critiques",
                (category?.anomalies.items ?? []).filter((item) => item.type === "critical_delay"),
                "Missions encore ouvertes avec un retard critique."
              )
            }
          />
          <KpiCard
            label="Colis stagnants"
            value={actionCounts.stale}
            Icon={Clock}
            tone={actionCounts.stale > 0 ? "warning" : "neutral"}
            hint="Plus de 7 jours en relais"
            onClick={() => openDetails("Colis stagnants", category?.stale_parcels.items ?? [], "Colis à relancer en priorité.")}
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
