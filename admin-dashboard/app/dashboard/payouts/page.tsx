"use client";

import * as React from "react";
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
import { useToast } from "@/components/ui/toaster";
import { formatDate } from "@/lib/utils";
import { CheckCircle2, Loader2, XCircle } from "lucide-react";

const xof = new Intl.NumberFormat("fr-FR");

const METHOD_LABELS: Record<string, string> = {
  wave: "Wave",
  orange_money: "Orange Money",
  free_money: "Free Money",
  bank: "Virement bancaire",
  cash: "Espèces",
};

export default function PayoutsPage() {
  const qc = useQueryClient();
  const { toast } = useToast();

  const { data, isLoading, isError } = useQuery({
    queryKey: ["payouts", "pending"],
    queryFn: fetchPendingPayouts,
    refetchInterval: 30_000,
  });

  const invalidate = () =>
    qc.invalidateQueries({ queryKey: ["payouts"], exact: false });

  const [approveTarget, setApproveTarget] = React.useState<AdminPayout | null>(null);
  const [rejectTarget, setRejectTarget] = React.useState<AdminPayout | null>(null);

  const payouts = data?.payouts ?? [];

  return (
    <div className="space-y-5 p-8">
      <div>
        <h1 className="text-2xl font-bold">Demandes de retrait</h1>
        <p className="text-sm text-muted-foreground">
          Valider ou rejeter les demandes de retrait des livreurs et relais.
        </p>
      </div>

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement des retraits.
        </div>
      )}

      {data && payouts.length === 0 && (
        <Card>
          <CardContent className="p-10 text-center text-sm text-muted-foreground">
            Aucune demande de retrait en attente.
          </CardContent>
        </Card>
      )}

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

      {/* Approve modal */}
      <ActionModal
        open={!!approveTarget}
        onOpenChange={(o) => !o && setApproveTarget(null)}
        title={`Valider le retrait de ${approveTarget ? xof.format(approveTarget.amount) : ""} XOF`}
        description="Note optionnelle (référence de transaction, numéro de virement…)"
        inputLabel="Note (optionnel)"
        inputPlaceholder="Ex: TX-20260417-001"
        confirmLabel="Valider le retrait"
        confirmVariant="default"
        required={false}
        onConfirm={async (note) => {
          await approvePayout(approveTarget!.payout_id, note || undefined);
          invalidate();
          toast("Retrait validé avec succès.");
          setApproveTarget(null);
        }}
      />

      {/* Reject modal */}
      <ActionModal
        open={!!rejectTarget}
        onOpenChange={(o) => !o && setRejectTarget(null)}
        title={`Rejeter le retrait de ${rejectTarget ? xof.format(rejectTarget.amount) : ""} XOF`}
        description="Indiquez le motif du rejet. Le solde sera restauré au portefeuille de l'utilisateur."
        inputLabel="Motif du rejet"
        inputPlaceholder="Ex: Numéro de destination invalide"
        confirmLabel="Rejeter"
        confirmVariant="destructive"
        onConfirm={async (reason) => {
          await rejectPayout(rejectTarget!.payout_id, reason);
          invalidate();
          toast("Retrait rejeté.");
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
            <Badge tone="warning">En attente</Badge>
          </div>
          <div className="mt-1 text-sm text-muted-foreground">
            {METHOD_LABELS[payout.method] ?? payout.method}
            {payout.destination ? ` • ${payout.destination}` : ""}
          </div>
          <div className="mt-1 text-xs text-muted-foreground">
            User #{payout.user_id} • demandé le {formatDate(payout.created_at)}
          </div>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={onReject}>
            <XCircle className="h-4 w-4" />
            Rejeter
          </Button>
          <Button size="sm" onClick={onApprove}>
            <CheckCircle2 className="h-4 w-4" />
            Valider
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
