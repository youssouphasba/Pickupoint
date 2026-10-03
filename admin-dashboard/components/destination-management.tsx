"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api, fetchRelays } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatSettlementAmount } from "@/lib/relay-settlements";

type CollectionPlan = { collector?: string | null; status: string; amount_due_xof: number; amount_received_xof: number; receipts?: { collector: string; collector_id: string; amount_xof: number }[] };
type ManagedParcel = {
  parcel_id: string; status: string; updated_at: string; payment_status?: string; payment_override?: boolean;
  recipient_collection_plan?: CollectionPlan; who_pays?: string; quoted_price?: number; paid_price?: number;
  delivery_mode: string; destination_relay_id?: string; redirect_relay_id?: string;
  delivery_destination?: { address?: { label?: string }; relay_id?: string };
  original_delivery_destination?: { address?: { label?: string } };
   financial_contract?: { price_xof: number; delivery_mode: string; breakdown?: { driver_revenue_xof: number } };
   destination_financial_review?: { status: string; amount_xof: number };
  relay_settlement?: { driver_payment_status?: string };
};

export function DestinationManagement({ parcel }: { parcel: ManagedParcel }) {
  const [relayId, setRelayId] = React.useState("");
  const [collector, setCollector] = React.useState("");
  const [received, setReceived] = React.useState("0");
  const [driverPaid, setDriverPaid] = React.useState(false);
  const [note, setNote] = React.useState("");
  const [error, setError] = React.useState<string>();
  const [preview, setPreview] = React.useState<{ preview_token: string; price_xof: number; payment_preserved: boolean }>();
  const queryClient = useQueryClient();
  const early = ["created", "dropped_at_origin_relay"].includes(parcel.status);
  const redirectable = ["out_for_delivery", "delivery_failed", "redirected_to_relay"].includes(parcel.status);
  const relays = useQuery({ queryKey: ["destination-management-relays"], queryFn: () => fetchRelays({ active: true }), enabled: early || redirectable });
  const plan = parcel.recipient_collection_plan;
  const paid = parcel.payment_status === "paid" || parcel.payment_override;
  const due = paid ? 0 : plan?.amount_due_xof ?? 0;
  const refresh = () => Promise.all([
    queryClient.invalidateQueries({ queryKey: ["parcel-detail", parcel.parcel_id] }),
    queryClient.invalidateQueries({ queryKey: ["parcel-audit", parcel.parcel_id] }),
    queryClient.invalidateQueries({ queryKey: ["finance-relay-settlements"] }),
    queryClient.invalidateQueries({ queryKey: ["finance-relay-actions"] }),
    queryClient.invalidateQueries({ queryKey: ["finance-overview"] }),
  ]);
  const mutation = useMutation({
    mutationFn: async (action: "preview" | "destination" | "collection") => {
      setError(undefined);
      if (action === "preview") {
        const response = await api.post(`/api/parcels/${parcel.parcel_id}/change-delivery-mode/preview`, { new_mode: "relay", relay_id: relayId });
        setPreview(response.data);
        return;
      }
      if (action === "destination") {
        if (early) await api.put(`/api/parcels/${parcel.parcel_id}/change-delivery-mode`, { new_mode: "relay", relay_id: relayId, preview_token: preview?.preview_token });
        else await api.post(`/api/parcels/${parcel.parcel_id}/redirect-relay`, { redirect_relay_id: relayId, notes: note });
        setPreview(undefined);
      } else {
        await api.post(`/api/admin/parcels/${parcel.parcel_id}/recipient-collection`, {
          collector, amount_received_xof: Number(received), driver_already_paid: driverPaid,
          expected_updated_at: parcel.updated_at, note,
        });
        setReceived("0");
      }
      await refresh();
    },
    onError: (failure: unknown) => {
      const response = (failure as { response?: { data?: { detail?: unknown } } }).response;
      setError(typeof response?.data?.detail === "string" ? response.data.detail : "Opération impossible. Actualisez les informations.");
      setPreview(undefined);
      void refresh();
    },
  });

  if (!early && !redirectable && !plan && !parcel.delivery_destination) return null;
  return <Card>
    <CardHeader><CardTitle>Destination et règlement après changement</CardTitle></CardHeader>
    <CardContent className="space-y-4">
      {parcel.delivery_destination && <p>Destination effective : {parcel.delivery_destination.address?.label ?? parcel.delivery_destination.relay_id ?? "Adresse confirmée"}.</p>}
      {parcel.original_delivery_destination?.address?.label && <p className="text-sm text-muted-foreground">Adresse initiale : {parcel.original_delivery_destination.address.label}.</p>}
      {parcel.financial_contract && <p className="text-sm">Règlement convenu conservé : {formatSettlementAmount(parcel.financial_contract.price_xof)}. Les paiements et la part du livreur ne sont pas recréés.</p>}
      {parcel.destination_financial_review?.status === "pending" && <p role="status" className="rounded-md border p-3 text-sm">Répartition à contrôler : {formatSettlementAmount(parcel.destination_financial_review.amount_xof)} étaient prévus pour l’ancien relais d’arrivée. Aucun versement à un relais qui n’a pas effectué la remise, aucun remboursement ni nouveau prélèvement n’est déclenché automatiquement.</p>}
      {(early || redirectable) && <div className="space-y-2">
        <label className="block text-sm font-medium" htmlFor="destination-relay">Nouveau relais de retrait</label>
        <select id="destination-relay" value={relayId} onChange={(event) => { setRelayId(event.target.value); setPreview(undefined); }} className="w-full rounded-md border bg-background p-2" disabled={mutation.isPending}>
          <option value="">Choisir un relais validé</option>
          {relays.data?.relay_points.filter((relay) => relay.is_verified && relay.max_capacity != null && (relay.current_load ?? 0) < relay.max_capacity).map((relay) => <option value={relay.relay_id} key={relay.relay_id}>{relay.name}</option>)}
        </select>
        {relays.isError && <p role="alert">La liste des relais n’a pas pu être chargée.</p>}
        {preview && <p className="text-sm">Prix total : {formatSettlementAmount(preview.price_xof)}. {preview.payment_preserved ? "Paiement existant conservé, sans deuxième demande." : "Ce devis remplace le précédent."}</p>}
        <Button disabled={!relayId || mutation.isPending || (!early && note.trim().length < 3)} onClick={() => mutation.mutate(early && !preview ? "preview" : "destination")}>{early && !preview ? "Vérifier le changement" : "Confirmer le nouveau relais"}</Button>
        {!early && <p className="text-sm text-muted-foreground">Un relais ouvert est obligatoire. Le livreur est informé et l’ancien itinéraire est invalidé.</p>}
      </div>}
      {plan && <div className="space-y-3 rounded-md border p-3">
        <h3 className="font-semibold">Le destinataire paie</h3>
        <p>Déjà reçu : {formatSettlementAmount(paid ? parcel.paid_price ?? parcel.financial_contract?.price_xof ?? parcel.quoted_price ?? 0 : plan.amount_received_xof)} · Reste dû : {formatSettlementAmount(due)}.</p>
        <p className="text-sm">{due === 0 ? "Aucun nouvel encaissement à demander." : plan.status === "admin_review" ? "Décision admin nécessaire avant la remise." : `Encaissement prévu : ${({ relay: "relais de retrait", driver: "livreur affecté", denkma: "Denkma" } as Record<string, string>)[plan.collector ?? ""] ?? "à préciser"}.`}</p>
        {(plan.receipts?.length ?? 0) > 0 && <ul className="space-y-1 text-sm">{plan.receipts?.map((receipt, index) => <li key={index}>{formatSettlementAmount(receipt.amount_xof)} encaissés par {({ relay: "le relais", driver: "le livreur", denkma: "Denkma" } as Record<string, string>)[receipt.collector]} · {receipt.collector_id}</li>)}</ul>}
        <label className="block text-sm" htmlFor="collection-actor">Qui encaisse le reste dû ?</label>
        <select id="collection-actor" value={collector} onChange={(event) => setCollector(event.target.value)} className="w-full rounded-md border bg-background p-2">
          <option value="">Choisir le responsable</option><option value="relay">Relais de retrait</option><option value="driver">Livreur affecté</option><option value="denkma">Denkma</option>
        </select>
        <label className="block text-sm" htmlFor="collection-amount">Montant supplémentaire réellement reçu, pas le prix complet</label>
        <input id="collection-amount" type="number" min={0} max={due} step="0.01" value={received} onChange={(event) => setReceived(event.target.value)} className="w-full rounded-md border bg-background p-2" />
        <label className="flex gap-2 text-sm"><input type="checkbox" checked={driverPaid || parcel.relay_settlement?.driver_payment_status === "validated"} disabled={parcel.relay_settlement?.driver_payment_status === "validated"} onChange={(event) => setDriverPaid(event.target.checked)} />La part du livreur a déjà été remise, preuve vérifiée</label>
        {parcel.financial_contract?.breakdown && <p className="text-sm">Part convenue du livreur : {formatSettlementAmount(parcel.financial_contract.breakdown.driver_revenue_xof)} · {parcel.relay_settlement?.driver_payment_status === "validated" ? "Déjà réglée : ne pas payer à nouveau." : "Paiement à vérifier séparément. L’encaissement par le relais ne paie pas automatiquement le livreur."}</p>}
        <Button disabled={!collector || note.trim().length < 3 || mutation.isPending || !Number.isFinite(Number(received)) || Number(received) < 0 || Number(received) > due} onClick={() => mutation.mutate("collection")}>Enregistrer la décision et le paiement reçu</Button>
        <p className="text-xs text-muted-foreground">Aucun transfert d’argent n’est déclenché. La remise au destinataire reste bloquée tant que le règlement dû n’est pas confirmé.</p>
        <p className="text-xs text-muted-foreground">Les encaissements du relais apparaissent dans Finance comme des reversements à Denkma, séparés de sa commission.</p>
      </div>}
      <label className="block text-sm" htmlFor="destination-note">Motif / référence de paiement vérifiée</label>
      <textarea id="destination-note" value={note} onChange={(event) => setNote(event.target.value)} maxLength={1000} className="w-full rounded-md border bg-background p-2" />
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    </CardContent>
  </Card>;
}
