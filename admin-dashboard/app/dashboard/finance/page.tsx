"use client";

import * as React from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { Loader2 } from "lucide-react";

import {
  fetchFinanceOverview,
  fetchFinanceReconciliation,
} from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

const xof = new Intl.NumberFormat("fr-FR");

function monthValue(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function monthLabel(value: string) {
  const [year, month] = value.split("-").map(Number);
  const labels = [
    "janvier",
    "février",
    "mars",
    "avril",
    "mai",
    "juin",
    "juillet",
    "août",
    "septembre",
    "octobre",
    "novembre",
    "décembre",
  ];
  return `${labels[month - 1] ?? value} ${year}`;
}

function monthOptions() {
  const now = new Date();
  return Array.from({ length: 18 }, (_, index) => {
    const date = new Date(now.getFullYear(), now.getMonth() - index, 1);
    const value = monthValue(date);
    return { value, label: monthLabel(value) };
  });
}

function periodBounds(period: string) {
  const [year, month] = period.split("-").map(Number);
  const start = `${year}-${String(month).padStart(2, "0")}-01`;
  const endDate = new Date(year, month, 0);
  const end = `${year}-${String(month).padStart(2, "0")}-${String(endDate.getDate()).padStart(2, "0")}`;
  return { start, end };
}

function buildParcelHref(
  period: string,
  params: Record<string, string | undefined>
) {
  const { start, end } = periodBounds(period);
  const query = new URLSearchParams({
    from_date: start,
    to_date: end,
  });
  Object.entries(params).forEach(([key, value]) => {
    if (value) query.set(key, value);
  });
  return `/dashboard/parcels?${query.toString()}`;
}

function StatCard({
  label,
  value,
  hint,
  href,
}: {
  label: string;
  value: React.ReactNode;
  hint?: string;
  href?: string;
}) {
  const content = (
    <Card className="h-full">
      <CardContent className="p-5">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          {label}
        </div>
        <div className="mt-1 text-xl font-bold">{value}</div>
        {hint ? <div className="mt-1 text-xs text-muted-foreground">{hint}</div> : null}
      </CardContent>
    </Card>
  );

  if (!href) return content;

  return (
    <Link href={href} className="block h-full transition-transform hover:-translate-y-0.5">
      {content}
    </Link>
  );
}

function DetailRow({
  label,
  value,
  href,
  hint,
}: {
  label: string;
  value: React.ReactNode;
  href?: string;
  hint?: string;
}) {
  const content = (
    <div className="flex items-center justify-between gap-4 border-b border-border/60 py-3 last:border-b-0">
      <div>
        <div className="text-sm text-muted-foreground">{label}</div>
        {hint ? <div className="mt-1 text-xs text-muted-foreground">{hint}</div> : null}
      </div>
      <div className="text-right text-sm font-medium">{value}</div>
    </div>
  );

  if (!href) {
    return content;
  }

  return (
    <Link href={href} className="block transition-colors hover:text-primary">
      {content}
    </Link>
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
  delivered_unpaid: "Colis livrés non réglés",
};

export default function FinancePage() {
  const [period, setPeriod] = React.useState(() => monthValue(new Date()));

  const overview = useQuery({
    queryKey: ["finance-overview", period],
    queryFn: () => fetchFinanceOverview(period),
  });

  const recon = useQuery({
    queryKey: ["finance-recon"],
    queryFn: fetchFinanceReconciliation,
  });

  const loading = overview.isLoading || recon.isLoading;
  const error = overview.isError || recon.isError;
  const data = overview.data;
  const issues = [
    "wallet_pending_mismatches",
    "negative_wallets",
    "payout_ledger_gaps",
    "mission_parcel_mismatches",
    "delivered_unpaid",
  ];

  const routes = {
    active: buildParcelHref(period, { scope: "active" }),
    blockedPayment: buildParcelHref(period, { payment_blocked: "true" }),
    delivered: buildParcelHref(period, { status: "delivered" }),
    deliveredPaid: buildParcelHref(period, { finance_filter: "delivered_paid" }),
    deliveredUnpaid: buildParcelHref(period, { finance_filter: "delivered_unpaid" }),
    cancelled: buildParcelHref(period, { status: "cancelled" }),
    commissionReceived: buildParcelHref(period, { finance_filter: "commission_received" }),
    commissionDebt: buildParcelHref(period, { finance_filter: "commission_debt" }),
    commissionOffered: buildParcelHref(period, { finance_filter: "commission_offered" }),
    allParcels: buildParcelHref(period, {}),
  };

  return (
    <div className="space-y-6 p-8">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Finance</h1>
          <p className="text-sm text-muted-foreground">
            Vue claire des paiements, des commissions, des relais et des retraits.
          </p>
        </div>
        <div className="flex items-center gap-3">
          <select
            value={period}
            onChange={(event) => setPeriod(event.target.value)}
            className="h-9 rounded-md border border-input bg-background px-3 text-sm"
          >
            {monthOptions().map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
          <Link
            href="/dashboard/payouts"
            className="inline-flex h-9 items-center rounded-md border border-input px-3 text-sm font-medium hover:bg-accent"
          >
            Voir les retraits
          </Link>
        </div>
      </div>

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
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                À surveiller
              </h2>
              {data.alerts.length === 0 ? <Badge tone="success">Rien d urgent</Badge> : null}
            </div>
            {data.alerts.length > 0 ? (
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                {data.alerts.map((alert: any) => {
                  const lowerLabel = `${alert.label ?? ""}`.toLowerCase();
                  const href = lowerLabel.includes("retrait")
                    ? "/dashboard/payouts"
                    : lowerLabel.includes("paiement")
                      ? routes.blockedPayment
                      : routes.allParcels;

                  return (
                    <Link
                      key={alert.label}
                      href={href}
                      className="block transition-transform hover:-translate-y-0.5"
                    >
                      <Card>
                        <CardContent className="flex items-center justify-between gap-4 p-5">
                          <div className="text-sm font-medium">{alert.label}</div>
                          <Badge tone={AlertTone({ tone: alert.tone })}>{alert.value}</Badge>
                        </CardContent>
                      </Card>
                    </Link>
                  );
                })}
              </div>
            ) : null}
          </section>

          <section className="space-y-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
              Paiements colis
            </h2>
            <p className="text-sm text-muted-foreground">
              Suivi du règlement des colis sur la période. Denkma n’encaisse pas ce paiement;
              la recette Denkma se trouve dans les commissions.
            </p>
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              <StatCard
                label="Valeur des colis en cours"
                value={`${xof.format(data.payments.active_expected_amount_xof ?? 0)} XOF`}
                hint={`${data.payments.active_parcels ?? 0} colis actifs`}
                href={routes.active}
              />
              <StatCard
                label="Valeur des colis livrés payés"
                value={`${xof.format(data.payments.delivered_received_amount_xof ?? 0)} XOF`}
                hint={`${data.payments.delivered_received_parcels ?? 0} colis livrés payés`}
                href={routes.deliveredPaid}
              />
              <StatCard
                label="Colis livrés"
                value={data.payments.delivered_parcels ?? 0}
                hint={`${xof.format(data.payments.delivered_amount_xof ?? 0)} XOF à la livraison`}
                href={routes.delivered}
              />
              <StatCard
                label="Colis annulés"
                value={data.payments.cancelled_parcels ?? 0}
                hint={`${xof.format(data.payments.cancelled_amount_xof ?? 0)} XOF sortis du flux`}
                href={routes.cancelled}
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
                  hint="Tous statuts confondus sur la période sélectionnée"
                  href={buildParcelHref(period, { finance_filter: "sender_pays" })}
                />
                <DetailRow
                  label="Destinataire paie"
                  value={`${data.payments.recipient_pays_parcels ?? 0} colis`}
                  hint="Tous statuts confondus sur la période sélectionnée"
                  href={buildParcelHref(period, { finance_filter: "recipient_pays" })}
                />
                <DetailRow
                  label="Colis livrés"
                  value={`${data.payments.delivered_parcels ?? 0} colis`}
                  href={routes.delivered}
                />
                <DetailRow
                  label="Colis livrés non payés"
                  value={
                    <Link href={routes.deliveredUnpaid}>
                      <Badge
                        tone={
                          (data.payments.delivered_waiting_payment_parcels ?? 0) > 0
                            ? "warning"
                            : "success"
                        }
                      >
                        {data.payments.delivered_waiting_payment_parcels ?? 0}
                      </Badge>
                    </Link>
                  }
                  href={routes.deliveredUnpaid}
                />
                <DetailRow
                  label="Valeur des colis livrés non payés"
                  value={`${xof.format(data.payments.delivered_waiting_payment_amount_xof ?? 0)} XOF`}
                  href={routes.deliveredUnpaid}
                />
              </CardContent>
            </Card>
          </section>

          <div className="grid gap-6 xl:grid-cols-2">
            <section className="space-y-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                Commissions
              </h2>
              <p className="text-sm text-muted-foreground">
                Partie réellement liée au revenu Denkma, prélevée depuis les soldes livreurs.
              </p>
              <div className="grid gap-4 sm:grid-cols-2">
                <StatCard
                  label="Commission Denkma attendue"
                  value={`${xof.format(data.commissions.platform_expected_xof ?? 0)} XOF`}
                  href={routes.active}
                />
                <StatCard
                  label="Commission Denkma reçue"
                  value={`${xof.format(data.commissions.platform_received_xof ?? 0)} XOF`}
                  href={routes.commissionReceived}
                />
                <StatCard
                  label="Commission en dette"
                  value={`${xof.format(data.commissions.platform_debt_xof ?? 0)} XOF`}
                  href={routes.commissionDebt}
                />
                <StatCard
                  label="Commission offerte"
                  value={`${xof.format(data.commissions.platform_offered_xof ?? 0)} XOF`}
                  hint={`${data.commissions.offered_by_denkma_count ?? 0} courses`}
                  href={routes.commissionOffered}
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
                    href={buildParcelHref(period, { finance_filter: "charge_mode_wallet_hold" })}
                  />
                  <DetailRow
                    label="Mise à la charge du livreur"
                    value={`${data.commissions.charged_as_debt_count ?? 0} courses`}
                    href={buildParcelHref(period, { finance_filter: "charge_mode_driver_debt" })}
                  />
                  <DetailRow
                    label="Offerte par Denkma"
                    value={`${data.commissions.offered_by_denkma_count ?? 0} courses`}
                    href={buildParcelHref(period, { finance_filter: "charge_mode_platform_sponsored" })}
                  />
                  <DetailRow
                    label="Montant encore à récupérer"
                    value={`${xof.format(data.commissions.debt_amount_xof ?? 0)} XOF`}
                    href={routes.commissionDebt}
                  />
                  <DetailRow
                    label="En attente de réponse livreur"
                    value={`${data.commissions.waiting_driver_confirmation_count ?? 0} courses`}
                    href={buildParcelHref(period, { finance_filter: "awaiting_driver_response" })}
                  />
                </CardContent>
              </Card>
            </section>

            <section className="space-y-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                Relais
              </h2>
              <div className="grid gap-4 sm:grid-cols-2">
                <StatCard
                  label="Montant à verser"
                  value={`${xof.format(data.relays.amount_due_xof ?? 0)} XOF`}
                  href={routes.delivered}
                />
                <StatCard
                  label="Déjà envoyé"
                  value={`${xof.format(data.relays.amount_already_sent_xof ?? 0)} XOF`}
                  href="/dashboard/payouts"
                />
                <StatCard
                  label="Reste à verser"
                  value={`${xof.format(data.relays.amount_remaining_xof ?? 0)} XOF`}
                  href="/dashboard/payouts"
                />
                <StatCard
                  label="Colis à régulariser"
                  value={data.relays.parcels_waiting_relay_payment ?? 0}
                  href={routes.deliveredUnpaid}
                />
              </div>
              <Card>
                <CardHeader>
                  <CardTitle className="text-base">Détail relais</CardTitle>
                </CardHeader>
                <CardContent>
                  <DetailRow
                    label="Part relais de départ"
                    value={`${xof.format(data.relays.origin_amount_due_xof ?? 0)} XOF`}
                  />
                  <DetailRow
                    label="Part relais d arrivée"
                    value={`${xof.format(data.relays.destination_amount_due_xof ?? 0)} XOF`}
                  />
                </CardContent>
              </Card>
            </section>
          </div>

          <div className="grid gap-6 xl:grid-cols-2">
            <section className="space-y-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                Retraits
              </h2>
              <div className="grid gap-4 sm:grid-cols-3">
                <StatCard
                  label="En attente"
                  value={`${data.payouts.waiting_count ?? 0}`}
                  hint={`${xof.format(data.payouts.waiting_amount_xof ?? 0)} XOF`}
                  href="/dashboard/payouts"
                />
                <StatCard
                  label="Envoyés"
                  value={`${data.payouts.sent_count ?? 0}`}
                  hint={`${xof.format(data.payouts.sent_amount_xof ?? 0)} XOF`}
                  href="/dashboard/payouts"
                />
                <StatCard
                  label="Refusés"
                  value={`${data.payouts.refused_count ?? 0}`}
                  hint={`${xof.format(data.payouts.refused_amount_xof ?? 0)} XOF`}
                  href="/dashboard/payouts"
                />
              </div>
              <Link href="/dashboard/payouts" className="block transition-transform hover:-translate-y-0.5">
                <Card>
                  <CardContent className="p-5">
                    <div className="flex items-center justify-between gap-4">
                      <div>
                        <div className="text-sm font-medium">Comptes bloqués pour retrait</div>
                        <div className="text-xs text-muted-foreground">
                          Comptes qui ne peuvent pas demander un retrait pour le moment
                        </div>
                      </div>
                      <Badge
                        tone={
                          (data.payouts.blocked_wallets ?? 0) > 0 ? "warning" : "success"
                        }
                      >
                        {data.payouts.blocked_wallets ?? 0}
                      </Badge>
                    </div>
                  </CardContent>
                </Card>
              </Link>
            </section>

            <section className="space-y-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                Soldes
              </h2>
              <div className="grid gap-4 sm:grid-cols-2">
                <StatCard
                  label="Solde disponible"
                  value={`${xof.format(data.wallets.total_available_amount_xof ?? 0)} XOF`}
                />
                <StatCard
                  label="Montant en attente"
                  value={`${xof.format(data.wallets.total_waiting_amount_xof ?? 0)} XOF`}
                />
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
                    value={
                      <Badge
                        tone={
                          (data.wallets.negative_wallets ?? 0) > 0 ? "warning" : "success"
                        }
                      >
                        {data.wallets.negative_wallets ?? 0}
                      </Badge>
                    }
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
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                Points à vérifier
              </h2>
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
                {issues.map((key) => {
                  const count = recon.data?.[key]?.length ?? 0;
                  if (count === 0) return null;
                  return (
                    <Link
                      key={key}
                      href={routes.allParcels}
                      className="block transition-transform hover:-translate-y-0.5"
                    >
                      <Card>
                        <CardContent className="p-5">
                          <div className="text-sm font-medium">{ISSUE_LABELS[key] ?? key}</div>
                          <div className="mt-2">
                            <Badge tone="warning">{count}</Badge>
                          </div>
                        </CardContent>
                      </Card>
                    </Link>
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
