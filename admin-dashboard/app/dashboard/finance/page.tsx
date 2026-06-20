"use client";

import * as React from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { Loader2 } from "lucide-react";

import { fetchFinanceOverview, fetchFinanceReconciliation } from "@/lib/api";
import { DateRangeFilter, type DateRange } from "@/components/date-range-filter";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

const xof = new Intl.NumberFormat("fr-FR");

type FinanceDetailItem = {
  id?: string;
  title?: string;
  subtitle?: string;
  status?: string;
  amount_xof?: number;
  meta?: string;
};

type DetailModalState = {
  title: string;
  description?: string;
  items: FinanceDetailItem[];
} | null;

function monthValue(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function periodBounds(period: string) {
  const [year, month] = period.split("-").map(Number);
  const start = `${year}-${String(month).padStart(2, "0")}-01`;
  const endDate = new Date(year, month, 0);
  const end = `${year}-${String(month).padStart(2, "0")}-${String(endDate.getDate()).padStart(2, "0")}`;
  return { start, end };
}

function currentMonthRange(): DateRange {
  const { start, end } = periodBounds(monthValue(new Date()));
  return { from: start, to: end };
}

function formatXof(value?: number | null) {
  return `${xof.format(value ?? 0)} XOF`;
}

function clickableClass(disabled?: boolean) {
  return disabled ? "" : "cursor-pointer transition-transform hover:-translate-y-0.5";
}

function StatCard({
  label,
  value,
  hint,
  onClick,
}: {
  label: string;
  value: React.ReactNode;
  hint?: string;
  onClick?: () => void;
}) {
  return (
    <button type="button" onClick={onClick} className={`block h-full w-full text-left ${clickableClass(!onClick)}`}>
      <Card className="h-full">
        <CardContent className="p-5">
          <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</div>
          <div className="mt-1 text-xl font-bold">{value}</div>
          {hint ? <div className="mt-1 text-xs text-muted-foreground">{hint}</div> : null}
        </CardContent>
      </Card>
    </button>
  );
}

function DetailRow({
  label,
  value,
  hint,
  onClick,
}: {
  label: string;
  value: React.ReactNode;
  hint?: string;
  onClick?: () => void;
}) {
  const body = (
    <div className="flex items-center justify-between gap-4 border-b border-border/60 py-3 last:border-b-0">
      <div>
        <div className="text-sm text-muted-foreground">{label}</div>
        {hint ? <div className="mt-1 text-xs text-muted-foreground">{hint}</div> : null}
      </div>
      <div className="text-right text-sm font-medium">{value}</div>
    </div>
  );

  if (!onClick) return body;

  return (
    <button type="button" onClick={onClick} className="block w-full text-left transition-colors hover:text-primary">
      {body}
    </button>
  );
}

function AlertTone({ tone }: { tone?: string }) {
  if (tone === "danger") return "danger" as const;
  if (tone === "warning") return "warning" as const;
  return "info" as const;
}

const ISSUE_LABELS: Record<string, string> = {
  wallet_pending_mismatches: "Montants en attente à corriger",
  negative_wallets: "Soldes négatifs à vérifier",
  payout_ledger_gaps: "Retraits à revoir",
  mission_parcel_mismatches: "Courses à revoir",
};

function FinanceDetailModal({
  open,
  onOpenChange,
  state,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  state: DetailModalState;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-hidden p-0">
        <DialogHeader className="border-b px-6 py-5">
          <DialogTitle>{state?.title ?? "Détail"}</DialogTitle>
          {state?.description ? <DialogDescription>{state.description}</DialogDescription> : null}
        </DialogHeader>
        <div className="max-h-[70vh] overflow-y-auto px-6 py-5">
          {state?.items?.length ? (
            <div className="space-y-3">
              {state.items.map((item, index) => (
                <div key={`${item.id ?? item.title ?? "item"}-${index}`} className="rounded-lg border border-border/70 p-4">
                  <div className="flex items-start justify-between gap-4">
                    <div className="min-w-0">
                      <div className="truncate text-sm font-semibold">{item.title || "Élément"}</div>
                      {item.subtitle ? <div className="mt-1 text-sm text-muted-foreground">{item.subtitle}</div> : null}
                      {item.meta ? <div className="mt-2 text-xs text-muted-foreground">{item.meta}</div> : null}
                    </div>
                    <div className="text-right">
                      {typeof item.amount_xof === "number" ? <div className="text-sm font-semibold">{formatXof(item.amount_xof)}</div> : null}
                      {item.status ? <Badge tone="info">{item.status}</Badge> : null}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="rounded-lg border border-dashed border-border px-4 py-6 text-sm text-muted-foreground">
              Aucun élément à afficher pour ce KPI sur la période choisie.
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

export default function FinancePage() {
  const [dateRange, setDateRange] = React.useState<DateRange>(() => currentMonthRange());
  const [detailModal, setDetailModal] = React.useState<DetailModalState>(null);

  const overview = useQuery({
    queryKey: ["finance-overview", dateRange.from ?? "", dateRange.to ?? ""],
    queryFn: () =>
      fetchFinanceOverview({
        ...(dateRange.from ? { from_date: dateRange.from } : {}),
        ...(dateRange.to ? { to_date: dateRange.to } : {}),
      }),
  });

  const recon = useQuery({
    queryKey: ["finance-recon"],
    queryFn: fetchFinanceReconciliation,
  });

  const loading = overview.isLoading || recon.isLoading;
  const error = overview.isError || recon.isError;
  const data = overview.data as any;
  const issues = [
    "wallet_pending_mismatches",
    "negative_wallets",
    "payout_ledger_gaps",
    "mission_parcel_mismatches",
  ];

  function openDetails(title: string, items: FinanceDetailItem[], description?: string) {
    setDetailModal({ title, items, description });
  }

  return (
    <div className="space-y-6 p-8">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Finance</h1>
          <p className="text-sm text-muted-foreground">
            Vue claire des commissions Denkma, des recharges livreurs, des relais et des retraits.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <DateRangeFilter value={dateRange} onChange={setDateRange} />
          <Link
            href="/dashboard/payouts"
            className="inline-flex h-9 items-center rounded-md border border-input px-3 text-sm font-medium hover:bg-accent"
          >
            Voir les retraits
          </Link>
        </div>
      </div>

      <FinanceDetailModal
        open={Boolean(detailModal)}
        onOpenChange={(open) => {
          if (!open) setDetailModal(null);
        }}
        state={detailModal}
      />

      {loading ? (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      ) : null}

      {error ? (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Impossible de charger les données finance pour le moment.
        </div>
      ) : null}

      {data ? (
        <>
          <section className="space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">À surveiller</h2>
              {data.alerts.length === 0 ? <Badge tone="success">Rien d'urgent</Badge> : null}
            </div>
            {data.alerts.length > 0 ? (
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                {data.alerts.map((alert: any) => (
                  <button
                    key={alert.label}
                    type="button"
                    onClick={() => openDetails(alert.label, alert.items ?? [], "Éléments concernés sur la période choisie")}
                    className="block text-left transition-transform hover:-translate-y-0.5"
                  >
                    <Card>
                      <CardContent className="flex items-center justify-between gap-4 p-5">
                        <div className="text-sm font-medium">{alert.label}</div>
                        <Badge tone={AlertTone({ tone: alert.tone })}>{alert.value}</Badge>
                      </CardContent>
                    </Card>
                  </button>
                ))}
              </div>
            ) : null}
          </section>

          <section className="space-y-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">Paiements colis</h2>
            <p className="text-sm text-muted-foreground">
              Le client paie hors application. Cette zone sert seulement à suivre les colis et le payeur choisi.
            </p>
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
              <StatCard
                label="Valeur des colis en cours"
                value={formatXof(data.payments.active_expected_amount_xof)}
                hint={`${data.payments.active_parcels ?? 0} colis actifs`}
                onClick={() => openDetails("Colis en cours", data.payments.details?.active ?? [])}
              />
              <StatCard
                label="Colis livrés"
                value={data.payments.delivered_parcels ?? 0}
                hint={`${formatXof(data.payments.delivered_amount_xof)} à la livraison`}
                onClick={() => openDetails("Colis livrés", data.payments.details?.delivered ?? [])}
              />
              <StatCard
                label="Colis annulés"
                value={data.payments.cancelled_parcels ?? 0}
                hint={`${formatXof(data.payments.cancelled_amount_xof)} sortis du flux`}
                onClick={() => openDetails("Colis annulés", data.payments.details?.cancelled ?? [])}
              />
            </div>
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Répartition du paiement des colis</CardTitle>
              </CardHeader>
              <CardContent>
                <DetailRow
                  label="Expéditeur paie"
                  value={`${data.payments.sender_pays_parcels ?? 0} colis`}
                  hint="Tous statuts confondus sur la période choisie"
                  onClick={() => openDetails("Colis payés par l'expéditeur", data.payments.details?.sender_pays ?? [])}
                />
                <DetailRow
                  label="Destinataire paie"
                  value={`${data.payments.recipient_pays_parcels ?? 0} colis`}
                  hint="Tous statuts confondus sur la période choisie"
                  onClick={() => openDetails("Colis payés par le destinataire", data.payments.details?.recipient_pays ?? [])}
                />
                <DetailRow
                  label="Colis livrés"
                  value={`${data.payments.delivered_parcels ?? 0} colis`}
                  onClick={() => openDetails("Colis livrés", data.payments.details?.delivered ?? [])}
                />
              </CardContent>
            </Card>
          </section>

          <div className="grid gap-6 xl:grid-cols-2">
            <section className="space-y-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">Commissions Denkma</h2>
              <p className="text-sm text-muted-foreground">
                Denkma encaisse ses commissions depuis les soldes livreurs après leurs recharges.
              </p>
              <div className="grid gap-4 sm:grid-cols-2">
                <StatCard
                  label="Commission totale"
                  value={formatXof(data.commissions.platform_total_xof ?? data.commissions.platform_expected_xof)}
                  onClick={() =>
                    openDetails("Toutes les commissions Denkma", [
                      ...(data.commissions.details?.collectable ?? []),
                      ...(data.commissions.details?.received ?? []),
                      ...(data.commissions.details?.debt ?? []),
                      ...(data.commissions.details?.offered ?? []),
                    ])
                  }
                />
                <StatCard
                  label="Commission à percevoir"
                  value={formatXof(data.commissions.platform_collectable_xof)}
                  hint={`${data.commissions.details?.collectable?.length ?? 0} courses`}
                  onClick={() => openDetails("Commission à percevoir", data.commissions.details?.collectable ?? [], "Commissions encore non prélevées sur le solde des livreurs")}
                />
                <StatCard
                  label="Commission reçue"
                  value={formatXof(data.commissions.platform_received_xof)}
                  onClick={() => openDetails("Commission déjà reçue", data.commissions.details?.received ?? [])}
                />
                <StatCard
                  label="Commission offerte"
                  value={formatXof(data.commissions.platform_offered_xof)}
                  hint={`${data.commissions.offered_by_denkma_count ?? 0} courses`}
                  onClick={() => openDetails("Commission offerte", data.commissions.details?.offered ?? [])}
                />
              </div>
              <Card>
                <CardHeader>
                  <CardTitle className="text-base">Mode de prise en charge</CardTitle>
                </CardHeader>
                <CardContent>
                  <DetailRow
                    label="Prélevée sur le solde du livreur"
                    value={`${data.commissions.charged_to_balance_count ?? 0} courses`}
                    onClick={() => openDetails("Commissions prélevées sur le solde", data.commissions.details?.charged_to_balance ?? [])}
                  />
                  <DetailRow
                    label="Mise en dette du livreur"
                    value={`${data.commissions.charged_as_debt_count ?? 0} courses`}
                    onClick={() => openDetails("Commissions mises en dette", data.commissions.details?.charged_as_debt ?? [])}
                  />
                  <DetailRow
                    label="Montant en dette"
                    value={formatXof(data.commissions.debt_amount_xof)}
                    onClick={() => openDetails("Montants en dette", data.commissions.details?.debt ?? [])}
                  />
                  <DetailRow
                    label="En attente de réponse livreur"
                    value={`${data.commissions.waiting_driver_confirmation_count ?? 0} courses`}
                    onClick={() => openDetails("Courses en attente de réponse livreur", data.commissions.details?.waiting_driver_confirmation ?? [])}
                  />
                </CardContent>
              </Card>
            </section>

            <section className="space-y-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">Recharges Stripe</h2>
              <div className="grid gap-4 sm:grid-cols-2">
                <StatCard
                  label="Recharges payées"
                  value={formatXof(data.topups.paid_amount_xof)}
                  hint={`${data.topups.paid_count ?? 0} recharges`}
                  onClick={() => openDetails("Recharges Stripe payées", data.topups.details?.paid ?? [], "Argent encaissé par Denkma avant crédit du solde livreur")}
                />
                <StatCard
                  label="Retraits en attente"
                  value={`${data.payouts.waiting_count ?? 0}`}
                  hint={formatXof(data.payouts.waiting_amount_xof)}
                  onClick={() => openDetails("Retraits en attente", data.payouts.details?.waiting ?? [])}
                />
              </div>
              <Card>
                <CardHeader>
                  <CardTitle className="text-base">Relais</CardTitle>
                </CardHeader>
                <CardContent>
                  <DetailRow
                    label="Montant à verser"
                    value={formatXof(data.relays.amount_due_xof)}
                    onClick={() => openDetails("Relais à payer", data.relays.details?.due ?? [])}
                  />
                  <DetailRow
                    label="Déjà versé"
                    value={formatXof(data.relays.amount_already_sent_xof)}
                    onClick={() => openDetails("Relais déjà payés", data.relays.details?.sent ?? [])}
                  />
                  <DetailRow
                    label="Reste à verser"
                    value={formatXof(data.relays.amount_remaining_xof)}
                    onClick={() => openDetails("Relais restant à payer", data.relays.details?.due ?? [])}
                  />
                </CardContent>
              </Card>
            </section>
          </div>

          <div className="grid gap-6 xl:grid-cols-2">
            <section className="space-y-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">Retraits</h2>
              <div className="grid gap-4 sm:grid-cols-3">
                <StatCard
                  label="En attente"
                  value={`${data.payouts.waiting_count ?? 0}`}
                  hint={formatXof(data.payouts.waiting_amount_xof)}
                  onClick={() => openDetails("Retraits en attente", data.payouts.details?.waiting ?? [])}
                />
                <StatCard
                  label="Envoyés"
                  value={`${data.payouts.sent_count ?? 0}`}
                  hint={formatXof(data.payouts.sent_amount_xof)}
                  onClick={() => openDetails("Retraits envoyés", data.payouts.details?.sent ?? [])}
                />
                <StatCard
                  label="Refusés"
                  value={`${data.payouts.refused_count ?? 0}`}
                  hint={formatXof(data.payouts.refused_amount_xof)}
                  onClick={() => openDetails("Retraits refusés", data.payouts.details?.refused ?? [])}
                />
              </div>
            </section>

            <section className="space-y-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">Soldes</h2>
              <div className="grid gap-4 sm:grid-cols-2">
                <StatCard label="Solde disponible" value={formatXof(data.wallets.total_available_amount_xof)} />
                <StatCard label="Montant en attente" value={formatXof(data.wallets.total_waiting_amount_xof)} />
                <StatCard label="Comptes livreurs" value={data.wallets.driver_wallets ?? 0} />
                <StatCard label="Comptes relais" value={data.wallets.relay_wallets ?? 0} />
              </div>
              <Card>
                <CardHeader>
                  <CardTitle className="text-base">À surveiller sur les soldes</CardTitle>
                </CardHeader>
                <CardContent>
                  <DetailRow
                    label="Soldes négatifs"
                    value={<Badge tone={(data.wallets.negative_wallets ?? 0) > 0 ? "warning" : "success"}>{data.wallets.negative_wallets ?? 0}</Badge>}
                  />
                  <DetailRow
                    label="Comptes avec montant en attente"
                    value={`${data.wallets.wallets_with_waiting_money ?? 0} comptes`}
                  />
                </CardContent>
              </Card>
            </section>
          </div>

          {recon.data ? (
            <section className="space-y-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">Points à vérifier</h2>
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
                {issues.map((key) => {
                  const items = recon.data?.[key] ?? [];
                  const count = items.length ?? 0;
                  if (count === 0) return null;
                  return (
                    <button
                      key={key}
                      type="button"
                      onClick={() => openDetails(ISSUE_LABELS[key] ?? key, items, "Éléments du contrôle de cohérence")}
                      className="block text-left transition-transform hover:-translate-y-0.5"
                    >
                      <Card>
                        <CardContent className="p-5">
                          <div className="text-sm font-medium">{ISSUE_LABELS[key] ?? key}</div>
                          <div className="mt-2"><Badge tone="warning">{count}</Badge></div>
                        </CardContent>
                      </Card>
                    </button>
                  );
                })}
              </div>
            </section>
          ) : null}
        </>
      ) : null}
    </div>
  );
}
