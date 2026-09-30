"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { BarChart3, Clock3, DollarSign, MapPin, ShieldAlert, Truck, Users } from "lucide-react";
import { fetchAdminAnalytics } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";

const xof = new Intl.NumberFormat("fr-FR");

function dateValue(date: Date) {
  return date.toISOString().slice(0, 10);
}

function formatDuration(seconds?: number | null) {
  if (seconds == null) return "—";
  if (seconds < 3600) return `${Math.max(1, Math.round(seconds / 60))} min`;
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.round((seconds % 3600) / 60);
  return `${hours} h${minutes ? ` ${minutes} min` : ""}`;
}

function formatXof(value?: number | null) {
  return `${xof.format(Math.round(value ?? 0))} XOF`;
}

function Metric({ label, value, hint, icon: Icon, tone = "text-foreground" }: { label: string; value: React.ReactNode; hint?: string; icon: React.ComponentType<{ className?: string }>; tone?: string }) {
  return (
    <Card>
      <CardContent className="flex items-start justify-between gap-3 p-5">
        <div>
          <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</div>
          <div className={`mt-1 text-2xl font-bold ${tone}`}>{value}</div>
          {hint ? <div className="mt-1 text-xs text-muted-foreground">{hint}</div> : null}
        </div>
        <Icon className="h-5 w-5 text-muted-foreground" />
      </CardContent>
    </Card>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="space-y-3">
      <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">{title}</h2>
      {children}
    </section>
  );
}

export default function AnalyticsPage() {
  const today = new Date();
  const [fromDate, setFromDate] = React.useState(() => dateValue(new Date(today.getTime() - 30 * 86400000)));
  const [toDate, setToDate] = React.useState(() => dateValue(today));
  const analytics = useQuery({
    queryKey: ["admin-analytics", fromDate, toDate],
    queryFn: () => fetchAdminAnalytics({ from_date: fromDate, to_date: toDate }),
  });

  const data = analytics.data;
  const overview = data?.overview;
  const durations = data?.durations;
  const finance = data?.finance;
  const modes = Object.entries(data?.by_mode ?? {}) as [string, Record<string, any>][];
  const drivers = (data?.drivers ?? []) as Record<string, any>[];
  const relays = (data?.relays ?? []) as Record<string, any>[];

  return (
    <div className="space-y-6 p-4 sm:p-6 lg:p-8">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Analyses de l’activité</h1>
          <p className="text-sm text-muted-foreground">Performance, délais, finance, réseau et risques sur la période choisie.</p>
        </div>
        <div className="flex items-end gap-3">
          <label className="text-sm">Du<Input type="date" value={fromDate} onChange={(event) => setFromDate(event.target.value)} /></label>
          <label className="text-sm">Au<Input type="date" value={toDate} onChange={(event) => setToDate(event.target.value)} /></label>
        </div>
      </div>

      {analytics.isLoading ? <div className="rounded-md border p-8 text-center text-sm text-muted-foreground">Chargement des analyses…</div> : null}
      {analytics.isError ? <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">Impossible de charger les analyses.</div> : null}

      {data && overview ? (
        <>
          <Section title="Vue d’ensemble">
            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
              <Metric label="Colis créés" value={overview.parcels} hint={`${overview.terminal} colis terminés`} icon={BarChart3} />
              <Metric label="Taux de réussite" value={`${overview.success_rate}%`} hint={`${overview.delivered} livrés · ${overview.failed} échecs`} icon={Truck} tone={overview.success_rate >= 90 ? "text-green-600" : "text-amber-600"} />
              <Metric label="Clients actifs" value={overview.clients} hint={`${overview.returning_clients} clients récurrents`} icon={Users} />
              <Metric label="Alertes sécurité" value={overview.security_blocks} hint="Blocages GPS ou géofence" icon={ShieldAlert} tone={overview.security_blocks ? "text-red-600" : "text-green-600"} />
              <Metric label="Taux d’acceptation" value={`${overview.acceptance_rate ?? 0}%`} hint={`${data.operations?.declined_missions ?? 0} refus enregistrés`} icon={Truck} />
              <Metric label="Distance moyenne" value={overview.average_distance_km == null ? "—" : `${overview.average_distance_km} km`} hint={`${data.durations?.distance_km?.sample_count ?? 0} trajets GPS exploitables`} icon={MapPin} />
            </div>
          </Section>

          <Section title="Délais de livraison">
            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
              <Metric label="Avant collecte" value={formatDuration(durations.before_pickup.average_seconds)} hint={`Médiane ${formatDuration(durations.before_pickup.median_seconds)}`} icon={Clock3} />
              <Metric label="Collecte → livraison" value={formatDuration(durations.delivery.average_seconds)} hint={`P90 ${formatDuration(durations.delivery.p90_seconds)}`} icon={Clock3} />
              <Metric label="Durée totale" value={formatDuration(durations.total.average_seconds)} hint={`Échantillon ${durations.total.sample_count}`} icon={Clock3} />
              <Metric label="Plus lente" value={formatDuration(durations.total.slowest_seconds)} hint={`Plus rapide ${formatDuration(durations.total.fastest_seconds)}`} icon={Clock3} />
              <Metric label="Délai d’acceptation" value={formatDuration(durations.acceptance?.average_seconds)} hint="Notification de mission → acceptation" icon={Clock3} />
              <Metric label="Temps au relais" value={formatDuration(durations.relay_dwell?.average_seconds)} hint="Arrivée au relais → événement suivant" icon={Clock3} />
            </div>
          </Section>

          <Section title="Finance">
            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
              <Metric label="Chiffre brut" value={formatXof(overview.gross_revenue_xof)} icon={DollarSign} />
              <Metric label="Commission plateforme" value={formatXof(finance.platform_commission_xof)} icon={DollarSign} />
              <Metric label="Part livreurs" value={formatXof(finance.driver_commission_xof)} icon={DollarSign} />
              <Metric label="Décaissements en attente" value={finance.payouts?.pending?.count ?? 0} hint={formatXof(finance.payouts?.pending?.amount_xof)} icon={DollarSign} tone="text-amber-600" />
              <Metric label="Âge moyen des décaissements" value={formatDuration(finance.pending_age?.average_seconds)} hint="Demandes encore en attente" icon={Clock3} tone="text-amber-600" />
              <Metric label="Revenu moyen client" value={formatXof(data.clients?.average_spend_xof)} hint={`${data.clients?.repeat_rate ?? 0}% de clients récurrents`} icon={Users} />
            </div>
          </Section>

          <Section title="Comparaison des modes">
            <Card><CardContent className="overflow-x-auto p-0"><table className="w-full text-sm"><thead><tr className="border-b text-left text-muted-foreground"><th className="p-4">Mode</th><th className="p-4">Colis</th><th className="p-4">Livrés</th><th className="p-4">Réussite</th><th className="p-4">Durée</th><th className="p-4">Distance</th><th className="p-4">CA brut</th></tr></thead><tbody>{modes.map(([mode, row]) => <tr key={mode} className="border-b last:border-0"><td className="p-4 font-medium">{mode.replaceAll("_", " → ")}</td><td className="p-4">{row.parcels}</td><td className="p-4">{row.delivered}</td><td className="p-4">{row.success_rate ?? "—"}{row.success_rate != null ? "%" : ""}</td><td className="p-4">{formatDuration(row.duration?.average_seconds)}</td><td className="p-4">{row.average_distance_km == null ? "—" : `${row.average_distance_km} km`}</td><td className="p-4">{formatXof(row.gross_revenue_xof)}</td></tr>)}</tbody></table></CardContent></Card>
          </Section>

          <div className="grid gap-6 xl:grid-cols-2">
            <Section title="Parcours opérationnel">
              <Card><CardContent className="grid gap-3 p-5 sm:grid-cols-5">{Object.entries(data.funnel ?? {}).map(([key, value]) => <div key={key} className="rounded-md bg-muted/50 p-3"><div className="text-xs text-muted-foreground">{key === "created" ? "Créés" : key === "assigned" ? "Assignés" : key === "accepted" ? "Acceptés" : key === "picked_up" ? "Collectés" : "Livrés"}</div><div className="mt-1 text-xl font-bold">{String(value)}</div></div>)}</CardContent></Card>
            </Section>
            <Section title="Clients et qualité">
              <Card><CardContent className="grid gap-3 p-5 sm:grid-cols-2"><div><div className="text-xs text-muted-foreground">Nouveaux clients</div><div className="text-xl font-bold">{data.clients?.new ?? 0}</div></div><div><div className="text-xs text-muted-foreground">Clients récurrents</div><div className="text-xl font-bold">{data.clients?.returning ?? 0}</div></div><div><div className="text-xs text-muted-foreground">Taux de répétition</div><div className="text-xl font-bold">{data.clients?.repeat_rate ?? 0}%</div></div><div><div className="text-xs text-muted-foreground">Annulations</div><div className="text-xl font-bold">{data.operations?.cancellation_rate ?? 0}%</div></div></CardContent></Card>
            </Section>
          </div>

          <div className="grid gap-6 xl:grid-cols-2">
            <Section title="Livreurs">
              <Card><CardContent className="overflow-x-auto p-0"><table className="w-full text-sm"><thead><tr className="border-b text-left text-muted-foreground"><th className="p-4">Livreur</th><th className="p-4">Réussite</th><th className="p-4">Acceptation</th><th className="p-4">Durée totale</th><th className="p-4">Distance</th><th className="p-4">XOF/h</th><th className="p-4">Alertes</th></tr></thead><tbody>{drivers.slice(0, 20).map((driver) => <tr key={driver.driver_id} className="border-b last:border-0"><td className="p-4 font-medium">{driver.name}</td><td className="p-4">{driver.success_rate}%</td><td className="p-4">{formatDuration(driver.average_acceptance_seconds)}</td><td className="p-4">{formatDuration(driver.average_total_seconds)}</td><td className="p-4">{driver.average_distance_km == null ? "—" : `${driver.average_distance_km} km`}</td><td className="p-4">{formatXof(driver.earnings_per_hour_xof)}</td><td className="p-4">{driver.security_blocks ? <Badge tone="danger">{driver.security_blocks}</Badge> : <Badge tone="success">0</Badge>}</td></tr>)}</tbody></table></CardContent></Card>
            </Section>
            <Section title="Relais">
              <Card><CardContent className="overflow-x-auto p-0"><table className="w-full text-sm"><thead><tr className="border-b text-left text-muted-foreground"><th className="p-4">Relais</th><th className="p-4">Traités</th><th className="p-4">Livrés</th><th className="p-4">Occupation</th></tr></thead><tbody>{relays.slice(0, 20).map((relay) => <tr key={relay.relay_id} className="border-b last:border-0"><td className="p-4 font-medium">{relay.name}</td><td className="p-4">{relay.processed}</td><td className="p-4">{relay.delivered}</td><td className="p-4">{relay.occupancy_rate == null ? "—" : `${relay.occupancy_rate}%`}</td></tr>)}</tbody></table></CardContent></Card>
            </Section>
          </div>

          <Section title="Évolution quotidienne">
            <Card><CardContent className="space-y-3 p-5">{(data.daily ?? []).map((day: any) => <div key={day.date} className="grid grid-cols-[6rem_1fr_5rem] items-center gap-3 text-sm"><span className="text-muted-foreground">{day.date}</span><div className="h-2 overflow-hidden rounded-full bg-muted"><div className="h-full rounded-full bg-emerald-500" style={{ width: `${Math.min(100, day.created ? (day.delivered / day.created) * 100 : 0)}%` }} /></div><span className="text-right">{day.created} créés</span></div>)}</CardContent></Card>
          </Section>
        </>
      ) : null}
    </div>
  );
}
