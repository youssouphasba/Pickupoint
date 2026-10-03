"use client";

import * as React from "react";
import Link from "next/link";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { updateRelaySettlement } from "@/lib/api";
import { settlementStatusLabel } from "@/lib/admin-display";
import { formatDate } from "@/lib/utils";
import { formatSettlementAmount, type RelaySettlementAction } from "@/lib/relay-settlements";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { useToast } from "@/components/ui/toaster";

export function RelaySettlementActionCard({ item }: { item: RelaySettlementAction }) {
  const [decision, setDecision] = React.useState<"validated" | "rejected" | null>(null);
  const [reviewItem, setReviewItem] = React.useState(item);
  const [note, setNote] = React.useState("");
  const [error, setError] = React.useState<string>();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const refresh = () => Promise.all([
    queryClient.invalidateQueries({ queryKey: ["finance-relay-settlements"] }),
    queryClient.invalidateQueries({ queryKey: ["finance-relay-actions"] }),
    queryClient.invalidateQueries({ queryKey: ["finance-overview"] }),
    queryClient.invalidateQueries({ queryKey: ["parcel-audit", item.parcel_id] }),
    queryClient.invalidateQueries({ queryKey: ["parcel-detail", item.parcel_id] }),
  ]);
  const mutation = useMutation({
    mutationFn: (status: "validated" | "rejected") => updateRelaySettlement(reviewItem.parcel_id, {
      action: reviewItem.action, relay_id: reviewItem.relay_id, status, expected_status: reviewItem.status,
      expected_amount_xof: reviewItem.amount_xof, expected_updated_at: reviewItem.updated_at, note: note.trim(),
    }),
    onSuccess: async () => {
      setDecision(null);
      toast("Règlement enregistré. Aucun transfert d’argent n’a été déclenché.");
      await refresh();
    },
    onError: (failure: unknown) => {
      const response = (failure as { response?: { status?: number; data?: { detail?: unknown } } }).response;
      setError(typeof response?.data?.detail === "string" ? response.data.detail : "Enregistrement impossible. Réessayez après actualisation.");
      if (response?.status === 409) void refresh();
    },
  });
  const open = (status: "validated" | "rejected") => { setReviewItem(item); setDecision(status); setNote(""); setError(undefined); };
  const isUpcoming = item.stage === "upcoming";
  const recordingPayment = item.direction === "to_relay" && item.status !== "declared";

  return (
    <div className="space-y-3 rounded-lg border bg-background p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="font-semibold">{item.label}</div>
          <Link className="text-sm text-primary underline-offset-4 hover:underline" href={`/dashboard/parcels/${encodeURIComponent(item.parcel_id)}`}>{item.tracking_code}</Link>
          <span className="mx-2 text-muted-foreground">·</span>
          <Link className="text-sm text-primary hover:underline" href={`/dashboard/relays/${encodeURIComponent(item.relay_id)}`}>{item.relay_name ?? item.relay_id}</Link>
        </div>
        <div className="space-y-1 text-right">
          <div className="font-semibold">{formatSettlementAmount(item.amount_xof)}</div>
          <Badge tone={isUpcoming ? "default" : item.status === "validated" ? "success" : item.status === "rejected" ? "danger" : "warning"}>{isUpcoming ? "À venir" : settlementStatusLabel(item.status)}</Badge>
        </div>
      </div>
      {item.direction === "to_driver" && <div className="text-sm text-muted-foreground">Bénéficiaire : {item.beneficiary_name ?? item.driver_id ?? "Livreur du colis"}</div>}
      {isUpcoming && <p className="text-sm text-muted-foreground">{item.direction === "to_relay" ? "Commission prévue, due après livraison. Exclue du montant à payer." : "Paiement prévu après collecte. Exclu des sommes actuellement dues."}</p>}
      {item.declared_at && <p className="text-xs text-muted-foreground">Déclaré le {formatDate(item.declared_at)}</p>}
      {item.reviewed_at && <p className="text-xs text-muted-foreground">Contrôlé le {formatDate(item.reviewed_at)}</p>}
      {item.note && <p className="break-words text-sm">Référence / motif : {item.note}</p>}
      {item.funding_review_required && <p className="text-sm text-amber-700">Commission du relais après changement de destination : prise en charge à contrôler par Denkma. Ne la facturez pas une deuxième fois au client et ne repayez pas le livreur.</p>}
      <div className="flex flex-wrap gap-2">
        {item.can_validate && <Button size="sm" onClick={() => open("validated")}>{recordingPayment ? "Enregistrer le versement" : "Valider le paiement"}</Button>}
        {item.can_reject && <Button size="sm" variant="outline" onClick={() => open("rejected")}>Rejeter la déclaration</Button>}
        {!isUpcoming && !item.can_validate && item.status !== "validated" && <p className="text-sm text-muted-foreground">Le relais doit effectuer ce paiement puis le déclarer dans l’application.</p>}
      </div>
      <Dialog open={decision !== null} onOpenChange={(value) => { if (!value && !mutation.isPending) setDecision(null); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{decision === "rejected" ? "Rejeter la déclaration" : reviewItem.direction === "to_relay" && reviewItem.status !== "declared" ? "Enregistrer un versement effectué" : "Confirmer le paiement reçu"}</DialogTitle>
            <DialogDescription>{reviewItem.tracking_code} · {reviewItem.label} · {formatSettlementAmount(reviewItem.amount_xof)}. Cette action enregistre un paiement hors plateforme, sans envoyer d’argent ni modifier le portefeuille.</DialogDescription>
          </DialogHeader>
          <p className="my-4 text-sm">{decision === "rejected" ? "Le montant restera dû et le relais pourra refaire sa déclaration." : "Vérifiez la preuve et le bénéficiaire avant de confirmer. Un paiement validé ne peut pas être annulé depuis cet écran."}</p>
          <form onSubmit={(event) => { event.preventDefault(); if (decision && note.trim().length >= 3) mutation.mutate(decision); }} className="space-y-4">
            <label className="block space-y-2 text-sm">
              <span>{decision === "rejected" ? "Motif du rejet" : "Référence ou preuve du paiement"}</span>
              <textarea required minLength={3} maxLength={1000} value={note} onChange={(event) => setNote(event.target.value)} disabled={mutation.isPending} className="min-h-24 w-full rounded-md border bg-background p-3" />
            </label>
            {error && <p role="alert" className="text-sm text-red-700">{error}</p>}
            <DialogFooter>
              <Button type="button" variant="outline" disabled={mutation.isPending} onClick={() => setDecision(null)}>Annuler</Button>
              <Button type="submit" disabled={mutation.isPending || note.trim().length < 3}>{mutation.isPending ? "Enregistrement…" : "Confirmer"}</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
