"use client";

import * as React from "react";
import Link from "next/link";
import { payoutMethodLabel } from "@/lib/admin-display";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  AdminPayout,
  approvePayout,
  fetchPendingPayouts,
  rejectPayout,
} from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ActionModal } from "@/components/action-modal";
import { DateRangeFilter, type DateRange } from "@/components/date-range-filter";
import { useToast } from "@/components/ui/toaster";
import { formatDate } from "@/lib/utils";
import { CheckCircle2, Loader2, XCircle } from "lucide-react";

const xof = new Intl.NumberFormat("fr-FR");



export default function PayoutsPage() {
  const qc = useQueryClient();
  const { toast } = useToast();

  const [dateRange, setDateRange] = React.useState<DateRange>({});
  const [statusFilter, setStatusFilter] = React.useState<"pending" | "approved" | "rejected">("pending");
  const { data, isLoading, isError } = useQuery({
    queryKey: ["payouts", statusFilter, dateRange.from ?? "", dateRange.to ?? ""],
    queryFn: () =>
      fetchPendingPayouts({
        ...(dateRange.from ? { from_date: dateRange.from } : {}),
        ...(dateRange.to ? { to_date: dateRange.to } : {}),
        status: statusFilter,
      }),
    refetchInterval: 30_000,
  });

  const invalidate = () =>
    qc.invalidateQueries({ queryKey: ["payouts"], exact: false });

  const [approveTarget, setApproveTarget] = React.useState<AdminPayout | null>(null);
  const [rejectTarget, setRejectTarget] = React.useState<AdminPayout | null>(null);

  const payouts = data?.payouts ?? [];

  return (
    <div className="space-y-5 p-4 sm:p-6 lg:p-8">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Demandes de retrait</h1>
          <p className="text-sm text-muted-foreground">
            Vérifiez le bénéficiaire, effectuez le versement hors plateforme, puis enregistrez sa référence. Confirmer un envoi ne transfère pas d’argent.
          </p>
        </div>
        <DateRangeFilter value={dateRange} onChange={setDateRange} />
      </div>

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Impossible de charger les demandes de retrait.
        </div>
      )}

      {data && payouts.length === 0 && (
        <Card>
          <CardContent className="p-10 text-center text-sm text-muted-foreground">
            Aucune demande de retrait pour ce statut et cette période.
          </CardContent>
        </Card>
      )}

      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <div className="text-sm font-medium">Demandes et historique des retraits</div>
          <div className="text-xs text-muted-foreground">Les demandes sont conservées après l’envoi ou le rejet.</div>
        </div>
        <label className="text-sm">Statut<select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value as typeof statusFilter)} className="mt-1 block h-9 rounded-md border border-input bg-background px-3 text-sm"><option value="pending">En attente</option><option value="approved">Envoyés</option><option value="rejected">Rejetés</option></select></label>
      </div>

      <div className="grid gap-3">
        {payouts.map((p) => (
          <PayoutCard
            key={p.payout_id}
            payout={p}
            onApprove={() => setApproveTarget(p)}
            onReject={() => setRejectTarget(p)}
          />
        ))}
      </div>

      <ActionModal
        open={!!approveTarget}
        onOpenChange={(o) => !o && setApproveTarget(null)}
        title={`Confirmer le versement de ${approveTarget ? xof.format(approveTarget.amount) : ""} XOF`}
        description={`Effectuez d’abord le versement hors plateforme (${payoutMethodLabel(approveTarget?.method)}), puis saisissez sa référence ou celle du justificatif.`}
        inputLabel="Référence du versement ou du justificatif"
        inputPlaceholder="Ex: TX-20260417-001"
        confirmLabel="Confirmer l’envoi"
        confirmVariant="default"
        required
        onConfirm={async (reference) => {
          await approvePayout(approveTarget!.payout_id, reference);
          invalidate();
          toast("Versement enregistré avec succès.");
          setApproveTarget(null);
        }}
      />

      <ActionModal
        open={!!rejectTarget}
        onOpenChange={(o) => !o && setRejectTarget(null)}
        title={`Rejeter le décaissement de ${rejectTarget ? xof.format(rejectTarget.amount) : ""} XOF`}
        description="Indiquez le motif du rejet. Le solde sera restauré au portefeuille de l'utilisateur."
        inputLabel="Motif du rejet"
        inputPlaceholder="Ex: Numéro de destination invalide"
        confirmLabel="Rejeter"
        confirmVariant="destructive"
        onConfirm={async (reason) => {
          await rejectPayout(rejectTarget!.payout_id, reason);
          invalidate();
          toast("Décaissement rejeté.");
          setRejectTarget(null);
        }}
      />
    </div>
  );
}

function PayoutCard({
  payout,
  onApprove,
  onReject,
}: {
  payout: AdminPayout;
  onApprove: () => void;
  onReject: () => void;
}) {
  return (
    <Card>
      <CardContent className="flex flex-wrap items-center justify-between gap-4 p-5">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className="text-lg font-bold">
              {xof.format(payout.amount)} XOF
            </span>
            <Badge tone={payout.status === "approved" ? "success" : payout.status === "rejected" ? "danger" : "warning"}>{payout.status === "approved" ? "Envoyé" : payout.status === "rejected" ? "Rejeté" : "En attente"}</Badge>
          </div>
          <div className="mt-1 text-sm text-muted-foreground">
            {payoutMethodLabel(payout.method)}
            {payout.destination ? ` • ${payout.destination}` : ""}
          </div>
          <div className="mt-1 text-xs text-muted-foreground">
            <Link href={`/dashboard/users/${encodeURIComponent(payout.user_id)}`} className="font-medium text-primary hover:underline">{payout.user_name || "Ouvrir le bénéficiaire"}</Link>{payout.user_phone ? ` • ${payout.user_phone}` : ""} • demandé le {formatDate(payout.created_at)}
            {payout.sent_at ? ` • envoyé le ${formatDate(payout.sent_at)}` : ""}
            {payout.transfer_reference ? ` • réf. ${payout.transfer_reference}` : ""}
            {payout.rejection_reason ? ` • motif : ${payout.rejection_reason}` : ""}
          </div>
        </div>
        <div className="flex gap-2">
          {payout.status === "pending" ? <Button variant="outline" size="sm" onClick={onReject}>
            <XCircle className="h-4 w-4" />
            Rejeter
          </Button> : null}
          {payout.status === "pending" ? <Button size="sm" onClick={onApprove}>
            <CheckCircle2 className="h-4 w-4" />
            Confirmer l’envoi
          </Button> : null}
        </div>
      </CardContent>
    </Card>
  );
}
