"use client";

import * as React from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { confirmReferralPayment, fetchReferrals, ReferralRecord } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";

const money = (amount: number) => new Intl.NumberFormat("fr-FR").format(amount) + " XOF";
const date = (value?: string | null) => value ? new Date(value).toLocaleString("fr-FR") : "Date non renseignée";
const statuses: Record<string, string> = {
  pending: "Objectif en cours", qualified: "Primes à payer", partially_paid: "Paiement partiel",
  rewarded: "Primes réglées", qualified_no_bonus: "Objectif atteint · sans prime",
};
const paymentLabels: Record<string, string> = {
  confirmed: "Payé hors plateforme", legacy_confirmed: "Ancien paiement confirmé",
  legacy_wallet: "Crédit wallet historique", not_due: "Aucune prime prévue",
  needs_review: "Historique à vérifier avant tout paiement",
};

function localNow() {
  const value = new Date();
  return new Date(value.getTime() - value.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}

function PaymentControl({record, beneficiary, onSuccess}: {
  record: ReferralRecord; beneficiary: "sponsor" | "referred"; onSuccess?: () => void;
}) {
  const qc = useQueryClient();
  const payment = record.payments[beneficiary];
  const name = beneficiary === "sponsor" ? record.sponsor_name : record.referred_name;
  const [open, setOpen] = React.useState(false);
  const [paidAt, setPaidAt] = React.useState(localNow);
  const [reference, setReference] = React.useState("");
  const [note, setNote] = React.useState("");
  const [checked, setChecked] = React.useState(false);
  const mutation = useMutation({
    mutationFn: () => confirmReferralPayment(record.referral_id, {
      beneficiary, amount_xof: payment.amount_xof, paid_at: new Date(paidAt).toISOString(),
      reference: reference.trim(), note: note.trim(),
    }),
    onSuccess: () => {
      setOpen(false);
      qc.invalidateQueries({queryKey: ["referral-ledger"]});
      qc.invalidateQueries({queryKey: ["referral-stats"]});
      onSuccess?.();
    },
  });
  const errorDetail = (mutation.error as {response?: {data?: {detail?: unknown}}} | null)?.response?.data?.detail;
  const due = payment.status === "pending" && ["qualified", "partially_paid"].includes(record.status);
  const validDate = paidAt && Number.isFinite(new Date(paidAt).getTime()) && new Date(paidAt).getTime() <= Date.now();
  return <div className="space-y-2 rounded-md border p-3">
    <div className="font-medium">{beneficiary === "sponsor" ? "Parrain" : "Filleul"} · {name}</div>
    <div>{money(payment.paid_amount_xof ?? payment.amount_xof)}</div>
    <div className="text-sm text-muted-foreground">{paymentLabels[payment.status] ?? (due ? "À payer hors plateforme" : "En attente de l’objectif")}</div>
    {payment.paid_at && <div className="text-sm">{date(payment.paid_at)}</div>}
    {payment.reference && <div className="break-words text-xs">Référence : {payment.reference}</div>}
    {payment.note && <div className="break-words text-xs">{payment.note}</div>}
    {due && <Button variant="outline" size="sm" onClick={() => {
      mutation.reset(); setChecked(false); setPaidAt(localNow()); setReference(""); setNote(""); setOpen(true);
    }}>Confirmer le paiement du {beneficiary === "sponsor" ? "parrain" : "filleul"}</Button>}
    <Dialog open={open} onOpenChange={(value) => {if (!mutation.isPending) setOpen(value);}}>
      <DialogContent onEscapeKeyDown={(event) => {if (mutation.isPending) event.preventDefault();}} onInteractOutside={(event) => {if (mutation.isPending) event.preventDefault();}}>
        <DialogTitle>Confirmer un paiement déjà effectué</DialogTitle>
        <DialogDescription>Aucun argent n’est envoyé depuis cet écran et aucun wallet n’est crédité.</DialogDescription>
        <form className="space-y-4" onSubmit={(event) => {event.preventDefault(); if (checked && validDate && !mutation.isPending) mutation.mutate();}}>
          <div>{name} · {money(payment.amount_xof)}</div>
          <label className="block text-sm">Date et heure du paiement
            <Input type="datetime-local" required value={paidAt} max={localNow()} onChange={(event) => setPaidAt(event.target.value)} disabled={mutation.isPending} />
          </label>
          <label className="block text-sm">Référence du paiement (facultatif)
            <Input value={reference} maxLength={120} onChange={(event) => setReference(event.target.value)} disabled={mutation.isPending} />
          </label>
          <label className="block text-sm">Note interne (facultatif)
            <Input value={note} maxLength={300} onChange={(event) => setNote(event.target.value)} disabled={mutation.isPending} />
          </label>
          <label className="flex items-start gap-2 text-sm"><input type="checkbox" checked={checked} onChange={(event) => setChecked(event.target.checked)} disabled={mutation.isPending} />
            Je confirme que Denkma a payé ce bénéficiaire hors plateforme.
          </label>
          {mutation.isError && <p role="alert" className="text-sm text-red-700">{typeof errorDetail === "string" ? errorDetail : "Confirmation impossible. Réessayez."}</p>}
          <Button type="submit" disabled={!checked || !validDate || mutation.isPending}>{mutation.isPending ? "Confirmation…" : "Enregistrer le paiement"}</Button>
        </form>
      </DialogContent>
    </Dialog>
  </div>;
}

export function ReferralRecordCard({record, onSuccess}: {record: ReferralRecord; onSuccess?: () => void}) {
  return <article className="space-y-3 rounded-lg border p-4">
    <div className="flex flex-wrap items-start justify-between gap-2">
      <div>
        <Link href={"/dashboard/users/" + record.referred_user_id} className="font-semibold underline">{record.referred_name}</Link>
        <p className="text-sm text-muted-foreground">{record.referred_role === "driver" ? "Filleul livreur" : "Filleul client"} · {record.referred_phone}</p>
        <p className="text-sm">Parrain : <Link className="underline" href={"/dashboard/users/" + record.sponsor_user_id}>{record.sponsor_name}</Link> {record.sponsor_phone}</p>
      </div>
      <span className="text-sm font-medium">{statuses[record.status] ?? record.status}</span>
    </div>
    <p className="text-sm">{record.reward_metric_count ?? 0} / {record.reward_count} {record.reward_metric_label} · conditions enregistrées pour ce parrainage</p>
    <div className="grid gap-3 md:grid-cols-2">
      <PaymentControl record={record} beneficiary="sponsor" onSuccess={onSuccess} />
      <PaymentControl record={record} beneficiary="referred" onSuccess={onSuccess} />
    </div>
    {!!record.payment_history?.length && <details className="text-sm">
      <summary className="cursor-pointer">Historique des confirmations</summary>
      <ul className="mt-2 space-y-2">{record.payment_history.map((event) => <li key={event.event_id}>
        {event.beneficiary === "sponsor" ? "Parrain" : "Filleul"} · {money(event.paid_amount_xof ?? event.amount_xof)} · payé le {date(event.paid_at)} · confirmé par {event.confirmed_by_name ?? "Administrateur"} le {date(event.confirmed_at)}
      </li>)}</ul>
    </details>}
  </article>;
}

export function ReferralLedger() {
  const [skip, setSkip] = React.useState(0);
  const [status, setStatus] = React.useState("");
  const [role, setRole] = React.useState("");
  const [search, setSearch] = React.useState("");
  const [submittedSearch, setSubmittedSearch] = React.useState("");
  React.useEffect(() => {
    const timer = window.setTimeout(() => {setSubmittedSearch(search); setSkip(0);}, 350);
    return () => window.clearTimeout(timer);
  }, [search]);
  const limit = 20;
  const query = useQuery({
    queryKey: ["referral-ledger", skip, status, role, submittedSearch],
    queryFn: () => fetchReferrals({skip, limit, status: status || undefined, role: role || undefined, search: submittedSearch || undefined}),
  });
  const totals = query.data?.totals;
  return <section className="space-y-4">
    <h2 className="font-semibold">Parrainages et paiements</h2>
    <p className="text-sm text-muted-foreground">Atteindre l’objectif ne déclenche pas de paiement. Payez chaque bénéficiaire hors plateforme, puis confirmez séparément ici. Les anciennes primes ne sont pas repayées automatiquement.</p>
    <div className="flex flex-wrap gap-3">
      <Input aria-label="Rechercher un parrainage" className="max-w-sm" placeholder="Nom, téléphone ou code" value={search} onChange={(event) => {setSearch(event.target.value); setSkip(0);}} />
      <select aria-label="Statut du parrainage" className="rounded-md border p-2" value={status} onChange={(event) => {setStatus(event.target.value); setSkip(0);}}>
        <option value="">Tous les statuts</option>
        {Object.entries(statuses).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        <option value="needs_review">Historique à vérifier</option>
      </select>
      <select aria-label="Type de filleul" className="rounded-md border p-2" value={role} onChange={(event) => {setRole(event.target.value); setSkip(0);}}>
        <option value="">Tous les filleuls</option><option value="client">Clients</option><option value="driver">Livreurs</option>
      </select>
      <Button variant="outline" onClick={() => query.refetch()} disabled={query.isFetching}>Actualiser</Button>
    </div>
    {totals && <div className="flex flex-wrap gap-4 text-sm">
      <span>{totals.total} parrainages</span>
      <span>Parrains à payer : {money(totals.sponsor_due_xof)}</span>
      <span>Filleuls à payer : {money(totals.referred_due_xof)}</span>
      <span>Payé hors plateforme : {money(totals.total_sponsor_bonus_xof + totals.total_referred_bonus_xof)}</span>
    </div>}
    {query.isPending ? <p>Chargement des parrainages…</p> : query.isError ? <p role="alert">Impossible de charger les parrainages. Utilisez Actualiser pour réessayer.</p> :
      query.data.items.length ? query.data.items.map((record) => <ReferralRecordCard key={record.referral_id} record={record} />) : <p>Aucun parrainage ne correspond aux filtres.</p>}
    <div className="flex flex-wrap items-center gap-3">
      <Button variant="outline" disabled={!skip || query.isFetching} onClick={() => setSkip(Math.max(0, skip - limit))}>Précédent</Button>
      <span className="text-sm">{query.data?.total ? skip + 1 : 0}–{Math.min(skip + limit, query.data?.total ?? 0)} sur {query.data?.total ?? 0}</span>
      <Button variant="outline" disabled={query.isFetching || skip + limit >= (query.data?.total ?? 0)} onClick={() => setSkip(skip + limit)}>Suivant</Button>
    </div>
  </section>;
}
