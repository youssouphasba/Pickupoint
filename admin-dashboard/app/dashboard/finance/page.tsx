"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchCodMonitoring,
  fetchDrivers,
  fetchFinanceMonthlySummary,
  fetchFinanceReconciliation,
  settleCod,
} from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { useToast } from "@/components/ui/toaster";
import { Banknote, Loader2 } from "lucide-react";
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

const SUMMARY_LABELS: Record<string, string> = {
  wallets_checked: "Wallets vérifiés",
  payouts_checked: "Payouts vérifiés",
  wallet_pending_mismatches: "Écarts pending",
  negative_wallets: "Wallets négatifs",
  payout_ledger_gaps: "Écarts payout/ledger",
  mission_parcel_mismatches: "Écarts mission/colis",
  delivered_unpaid: "Livrés non payés",
  issues_total: "Problèmes total",
};

export default function FinancePage() {
  const qc = useQueryClient();
  const { toast } = useToast();
  const [period, setPeriod] = React.useState(() => monthValue(new Date()));

  const recon = useQuery({
    queryKey: ["finance-recon"],
    queryFn: fetchFinanceReconciliation,
  });

  const monthly = useQuery({
    queryKey: ["finance-monthly", period],
    queryFn: () => fetchFinanceMonthlySummary(period),
  });

  const cod = useQuery({
    queryKey: ["finance-cod"],
    queryFn: fetchCodMonitoring,
  });

  const drivers = useQuery({
    queryKey: ["drivers-list"],
    queryFn: () => fetchDrivers(),
  });

  const loading = recon.isLoading || cod.isLoading || monthly.isLoading;
  const error = recon.isError || cod.isError || monthly.isError;

  const [settleOpen, setSettleOpen] = React.useState(false);
  const [settleDriverId, setSettleDriverId] = React.useState("");
  const [settleAmount, setSettleAmount] = React.useState("");

  const settleMut = useMutation({
    mutationFn: () =>
      settleCod(
        settleDriverId,
        settleAmount ? parseFloat(settleAmount) : undefined
      ),
    onSuccess: (res) => {
      qc.invalidateQueries({ queryKey: ["finance-cod"] });
      toast(
        `COD encaissé : ${xof.format(res.amount_settled ?? 0)} XOF`
      );
      setSettleOpen(false);
      setSettleDriverId("");
      setSettleAmount("");
    },
  });

  const summary = recon.data?.summary;
  const codEntities = cod.data?.entities ?? [];
  const monthlySummary = monthly.data;

  return (
    <div className="space-y-6 p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Finance</h1>
          <p className="text-sm text-muted-foreground">
            Réconciliation financière et suivi du cash en circulation.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
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
          <Button
            variant="outline"
            size="sm"
            onClick={() => setSettleOpen(!settleOpen)}
          >
            <Banknote className="h-4 w-4" />
            Encaisser COD
          </Button>
        </div>
      </div>

      {monthlySummary && (
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Synthèse {monthLabel(period)}
          </h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Card>
              <CardContent className="p-5">
                <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Ventes
                </div>
                <div className="mt-1 text-xl font-bold">
                  {xof.format(monthlySummary.sales_xof ?? 0)} XOF
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-5">
                <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Dépenses
                </div>
                <div className="mt-1 text-xl font-bold">
                  {xof.format(monthlySummary.commissions_xof ?? 0)} XOF
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-5">
                <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Net estimé
                </div>
                <div className="mt-1 text-xl font-bold">
                  {xof.format(monthlySummary.net_after_commissions_xof ?? 0)} XOF
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-5">
                <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  Colis livrés
                </div>
                <div className="mt-1 text-xl font-bold">
                  {monthlySummary.parcels_delivered ?? 0} / {monthlySummary.parcels_created ?? 0}
                </div>
              </CardContent>
            </Card>
          </div>
          <div className="mt-3 grid gap-3 sm:grid-cols-3">
            <Card>
              <CardContent className="p-4">
                <div className="text-xs text-muted-foreground">Paiements reçus</div>
                <div className="mt-1 font-semibold">
                  {xof.format(monthlySummary.paid_sales_xof ?? 0)} XOF
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-4">
                <div className="text-xs text-muted-foreground">Retraits validés</div>
                <div className="mt-1 font-semibold">
                  {xof.format(monthlySummary.payouts_approved_xof ?? 0)} XOF
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-4">
                <div className="text-xs text-muted-foreground">Retraits en attente</div>
                <div className="mt-1 font-semibold">
                  {xof.format(monthlySummary.payouts_pending_xof ?? 0)} XOF
                </div>
              </CardContent>
            </Card>
          </div>
        </section>
      )}

      {settleOpen && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">
              Confirmer l'encaissement du cash (COD)
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex flex-wrap items-end gap-3">
              <div className="min-w-[200px] flex-1">
                <label className="mb-1.5 block text-sm font-medium">
                  Livreur
                </label>
                <select
                  value={settleDriverId}
                  onChange={(e) => setSettleDriverId(e.target.value)}
                  className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
                >
                  <option value="">Sélectionner un livreur…</option>
                  {(drivers.data?.drivers ?? []).map((d: any) => (
                    <option key={d.user_id} value={d.user_id}>
                      {d.name ?? d.full_name ?? d.phone} — {d.user_id}
                    </option>
                  ))}
                </select>
              </div>
              <div className="w-40">
                <label className="mb-1.5 block text-sm font-medium">
                  Montant (vide = tout)
                </label>
                <Input
                  type="number"
                  placeholder="XOF"
                  value={settleAmount}
                  onChange={(e) => setSettleAmount(e.target.value)}
                />
              </div>
              <Button
                onClick={() => settleMut.mutate()}
                disabled={!settleDriverId || settleMut.isPending}
              >
                {settleMut.isPending && (
                  <Loader2 className="h-4 w-4 animate-spin" />
                )}
                Encaisser
              </Button>
            </div>
            {settleMut.isError && (
              <div className="mt-3 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
                {(settleMut.error as any)?.response?.data?.detail ??
                  "Erreur lors de l'encaissement."}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {loading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {error && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement des données financières.
        </div>
      )}

      {/* Reconciliation summary */}
      {summary && (
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Réconciliation
          </h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {Object.entries(summary).map(([key, val]) => (
              <Card key={key}>
                <CardContent className="p-5">
                  <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {SUMMARY_LABELS[key] ?? key.replace(/_/g, " ")}
                  </div>
                  <div className={`mt-1 text-xl font-bold ${key === "issues_total" && (val as number) > 0 ? "text-red-600" : ""}`}>
                    {typeof val === "number" ? val : String(val)}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>

          {recon.data && (() => {
            const issues = [
              { key: "wallet_pending_mismatches", label: "Écarts pending wallet" },
              { key: "negative_wallets", label: "Wallets négatifs" },
              { key: "payout_ledger_gaps", label: "Écarts payout/ledger" },
              { key: "mission_parcel_mismatches", label: "Écarts mission/colis" },
              { key: "delivered_unpaid", label: "Livrés non payés" },
            ];
            const hasIssues = issues.some((i) => (recon.data[i.key]?.length ?? 0) > 0);
            if (!hasIssues) return null;
            return (
              <div className="mt-4 space-y-3">
                {issues.map(({ key, label }) => {
                  const items = recon.data[key] ?? [];
                  if (items.length === 0) return null;
                  return (
                    <Card key={key}>
                      <CardHeader>
                        <CardTitle className="text-sm text-red-600">
                          {label} ({items.length})
                        </CardTitle>
                      </CardHeader>
                      <CardContent>
                        <div className="space-y-2">
                          {items.slice(0, 10).map((item: any, i: number) => (
                            <div key={i} className="rounded border p-2 text-xs font-mono">
                              {JSON.stringify(item)}
                            </div>
                          ))}
                        </div>
                      </CardContent>
                    </Card>
                  );
                })}
              </div>
            );
          })()}
        </section>
      )}

      {codEntities.length > 0 && (
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Cash on delivery (COD) — Soldes livreurs
          </h2>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {codEntities.map((e: any) => (
              <Card key={e.user_id}>
                <CardContent className="flex items-center justify-between p-5">
                  <div>
                    <Link
                      href={`/dashboard/users/${e.user_id}`}
                      className="font-medium text-primary hover:underline"
                    >
                      {e.name ?? e.user_id}
                    </Link>
                    <div className="text-xs text-muted-foreground">{e.user_id}</div>
                  </div>
                  <div className="text-right">
                    <div className={`text-lg font-bold ${(e.cod_balance ?? 0) > 0 ? "text-amber-600" : ""}`}>
                      {xof.format(e.cod_balance ?? 0)} XOF
                    </div>
                    {(e.cod_balance ?? 0) > 0 && (
                      <Badge tone="warning">À encaisser</Badge>
                    )}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </section>
      )}

      {codEntities.length === 0 && !loading && cod.data && (
        <Card>
          <CardContent className="p-10 text-center text-sm text-muted-foreground">
            Aucun solde COD en cours.
          </CardContent>
        </Card>
      )}
    </div>
  );
}
