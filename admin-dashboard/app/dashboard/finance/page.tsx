"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import {
  fetchFinanceOverview,
  fetchFinanceReconciliation,
} from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Loader2 } from "lucide-react";
import Link from "next/link";

const xof = new Intl.NumberFormat("fr-FR");

function monthValue(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function monthOptions() {
  const now = new Date();
  return Array.from({ length: 18 }, (_, index) => {
    const date = new Date(now.getFullYear(), now.getMonth() - index, 1);
    const value = monthValue(date);
    return { value, label: monthLabel(value) };
  });
}

function monthLabel(value: string) {
  const [year, month] = value.split("-").map(Number);
  const labels = [
    "janvier",
    "fevrier",
    "mars",
    "avril",
    "mai",
    "juin",
    "juillet",
    "aout",
    "septembre",
    "octobre",
    "novembre",
    "decembre",
  ];
  return `${labels[month - 1] ?? value} ${year}`;
}

function StatCard({
  label,
  value,
  hint,
}: {
  label: string;
  value: React.ReactNode;
  hint?: string;
}) {
  return (
    <Card>
      <CardContent className="p-5">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          {label}
        </div>
        <div className="mt-1 text-xl font-bold">{value}</div>
        {hint ? (
          <div className="mt-1 text-xs text-muted-foreground">{hint}</div>
        ) : null}
      </CardContent>
    </Card>
  );
}

function DetailRow({
  label,
  value,
}: {
  label: string;
  value: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-border/60 py-3 last:border-b-0">
      <div className="text-sm text-muted-foreground">{label}</div>
      <div className="text-sm font-medium text-right">{value}</div>
    </div>
  );
}

function AlertTone({
  tone,
}: {
  tone?: string;
}) {
  if (tone === "danger") {
    return "danger" as const;
  }
  if (tone === "warning") {
    return "warning" as const;
  }
  return "info" as const;
}

const ISSUE_LABELS: Record<string, string> = {
  wallet_pending_mismatches: "Montants en attente a corriger",
  negative_wallets: "Soldes negatifs a verifier",
  payout_ledger_gaps: "Retraits a revoir",
  mission_parcel_mismatches: "Courses a revoir",
  delivered_unpaid: "Colis livres non regles",
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
  const summary = recon.data?.summary;
  const issues = [
    "wallet_pending_mismatches",
    "negative_wallets",
    "payout_ledger_gaps",
    "mission_parcel_mismatches",
    "delivered_unpaid",
  ];

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
          Impossible de charger les donnees finance pour le moment.
        </div>
      ) : null}

      {data ? (
        <>
          <section className="space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                A surveiller
              </h2>
              {data.alerts.length === 0 ? (
                <Badge tone="success">Rien d urgent</Badge>
              ) : null}
            </div>
            {data.alerts.length > 0 ? (
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                {data.alerts.map((alert: any) => (
                  <Card key={alert.label}>
                    <CardContent className="flex items-center justify-between gap-4 p-5">
                      <div>
                        <div className="text-sm font-medium">{alert.label}</div>
                      </div>
                      <Badge tone={AlertTone({ tone: alert.tone })}>
                        {alert.value}
                      </Badge>
                    </CardContent>
                  </Card>
                ))}
              </div>
            ) : null}
          </section>

          <section className="space-y-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
              Paiements colis
            </h2>
            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              <StatCard
                label="Montant attendu"
                value={`${xof.format(data.payments.expected_amount_xof ?? 0)} XOF`}
                hint={`${data.payments.total_parcels ?? 0} colis sur ${monthLabel(period)}`}
              />
              <StatCard
                label="Montant confirme"
                value={`${xof.format(data.payments.received_amount_xof ?? 0)} XOF`}
                hint={`${data.payments.paid_parcels ?? 0} colis regles`}
              />
              <StatCard
                label="En attente"
                value={data.payments.waiting_payment_parcels ?? 0}
                hint="Colis qui attendent encore un reglement"
              />
              <StatCard
                label="Validation admin"
                value={data.payments.admin_validated_parcels ?? 0}
                hint="Colis valides sans paiement standard"
              />
            </div>
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Repartition des paiements</CardTitle>
              </CardHeader>
              <CardContent>
                <DetailRow
                  label="Expediteur paie"
                  value={`${data.payments.sender_pays_parcels ?? 0} colis`}
                />
                <DetailRow
                  label="Destinataire paie"
                  value={`${data.payments.recipient_pays_parcels ?? 0} colis`}
                />
                <DetailRow
                  label="Colis livres"
                  value={`${data.payments.delivered_parcels ?? 0} colis`}
                />
                <DetailRow
                  label="Colis livres en attente de paiement"
                  value={
                    <Badge
                      tone={
                        (data.payments.delivered_waiting_payment_parcels ?? 0) > 0
                          ? "warning"
                          : "success"
                      }
                    >
                      {data.payments.delivered_waiting_payment_parcels ?? 0}
                    </Badge>
                  }
                />
              </CardContent>
            </Card>
          </section>

          <div className="grid gap-6 xl:grid-cols-2">
            <section className="space-y-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                Commissions
              </h2>
              <div className="grid gap-4 sm:grid-cols-2">
                <StatCard
                  label="Part Denkma"
                  value={`${xof.format(data.commissions.platform_amount_xof ?? 0)} XOF`}
                />
                <StatCard
                  label="Part relais"
                  value={`${xof.format(data.commissions.relay_amount_xof ?? 0)} XOF`}
                />
                <StatCard
                  label="Commission totale"
                  value={`${xof.format(data.commissions.total_amount_xof ?? 0)} XOF`}
                />
                <StatCard
                  label="Commission offerte"
                  value={`${xof.format(data.commissions.offered_amount_xof ?? 0)} XOF`}
                  hint={`${data.commissions.offered_by_denkma_count ?? 0} courses`}
                />
              </div>
              <Card>
                <CardHeader>
                  <CardTitle className="text-base">Mode de prise en charge</CardTitle>
                </CardHeader>
                <CardContent>
                  <DetailRow
                    label="Prelevee sur le solde du livreur"
                    value={`${data.commissions.charged_to_balance_count ?? 0} courses`}
                  />
                  <DetailRow
                    label="Mise a la charge du livreur"
                    value={`${data.commissions.charged_as_debt_count ?? 0} courses`}
                  />
                  <DetailRow
                    label="Offerte par Denkma"
                    value={`${data.commissions.offered_by_denkma_count ?? 0} courses`}
                  />
                  <DetailRow
                    label="Montant encore a recuperer"
                    value={`${xof.format(data.commissions.debt_amount_xof ?? 0)} XOF`}
                  />
                  <DetailRow
                    label="En attente de reponse livreur"
                    value={`${data.commissions.waiting_driver_confirmation_count ?? 0} courses`}
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
                  label="Montant a verser"
                  value={`${xof.format(data.relays.amount_due_xof ?? 0)} XOF`}
                />
                <StatCard
                  label="Deja envoye"
                  value={`${xof.format(data.relays.amount_already_sent_xof ?? 0)} XOF`}
                />
                <StatCard
                  label="Reste a verser"
                  value={`${xof.format(data.relays.amount_remaining_xof ?? 0)} XOF`}
                />
                <StatCard
                  label="Colis a regulariser"
                  value={data.relays.parcels_waiting_relay_payment ?? 0}
                />
              </div>
              <Card>
                <CardHeader>
                  <CardTitle className="text-base">Detail relais</CardTitle>
                </CardHeader>
                <CardContent>
                  <DetailRow
                    label="Part relais de depart"
                    value={`${xof.format(data.relays.origin_amount_due_xof ?? 0)} XOF`}
                  />
                  <DetailRow
                    label="Part relais d arrivee"
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
                />
                <StatCard
                  label="Envoyes"
                  value={`${data.payouts.sent_count ?? 0}`}
                  hint={`${xof.format(data.payouts.sent_amount_xof ?? 0)} XOF`}
                />
                <StatCard
                  label="Refuses"
                  value={`${data.payouts.refused_count ?? 0}`}
                  hint={`${xof.format(data.payouts.refused_amount_xof ?? 0)} XOF`}
                />
              </div>
              <Card>
                <CardContent className="p-5">
                  <div className="flex items-center justify-between gap-4">
                    <div>
                      <div className="text-sm font-medium">Comptes bloques pour retrait</div>
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
                <StatCard
                  label="Comptes livreurs"
                  value={data.wallets.driver_wallets ?? 0}
                />
                <StatCard
                  label="Comptes relais"
                  value={data.wallets.relay_wallets ?? 0}
                />
              </div>
              <Card>
                <CardHeader>
                  <CardTitle className="text-base">A surveiller sur les soldes</CardTitle>
                </CardHeader>
                <CardContent>
                  <DetailRow
                    label="Soldes negatifs"
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

          {summary ? (
            <section className="space-y-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
                Points a verifier
              </h2>
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
                {issues.map((key) => {
                  const count = recon.data?.[key]?.length ?? 0;
                  if (count === 0) {
                    return null;
                  }
                  return (
                    <Card key={key}>
                      <CardContent className="p-5">
                        <div className="text-sm font-medium">
                          {ISSUE_LABELS[key] ?? key}
                        </div>
                        <div className="mt-2">
                          <Badge tone={count > 0 ? "warning" : "success"}>{count}</Badge>
                        </div>
                      </CardContent>
                    </Card>
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
