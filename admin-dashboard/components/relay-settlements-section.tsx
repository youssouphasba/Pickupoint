"use client";

import * as React from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { fetchRelaySettlementActions, fetchRelaySettlementOverview } from "@/lib/api";
import { formatSettlementAmount, SETTLEMENT_DIRECTIONS, type SettlementDirection, type SettlementFilter } from "@/lib/relay-settlements";
import { RelaySettlementActionCard } from "@/components/relay-settlement-action";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";

const PAGE_SIZE = 20;
const FILTERS: Record<SettlementFilter, string> = {
  outstanding: "Tous les règlements dus", pending: "À effectuer", declared: "À valider",
  rejected: "Déclarations rejetées", validated: "Paiements validés", upcoming: "À venir",
  all: "Tous les règlements", issues: "Données à vérifier",
};

function Pagination({ page, total, hasMore, onPage }: { page: number; total: number; hasMore: boolean; onPage: (page: number) => void }) {
  if (!total) return null;
  return <div className="flex flex-wrap items-center justify-between gap-3 text-sm">
    <span>{page * PAGE_SIZE + 1}–{Math.min((page + 1) * PAGE_SIZE, total)} sur {total}</span>
    <div className="flex gap-2">
      <Button variant="outline" size="sm" disabled={!page} onClick={() => onPage(page - 1)}>Précédent</Button>
      <Button variant="outline" size="sm" disabled={!hasMore} onClick={() => onPage(page + 1)}>Suivant</Button>
    </div>
  </div>;
}

export function RelaySettlementsSection() {
  const [search, setSearch] = React.useState("");
  const [relayPage, setRelayPage] = React.useState(0);
  const [relayId, setRelayId] = React.useState("");
  const [status, setStatus] = React.useState<SettlementFilter>("outstanding");
  const [direction, setDirection] = React.useState<SettlementDirection | "">("");
  const [actionPage, setActionPage] = React.useState(0);
  React.useEffect(() => { setRelayId(new URLSearchParams(window.location.search).get("relay_id") ?? ""); }, []);
  const overview = useQuery({
    queryKey: ["finance-relay-settlements", search, relayPage],
    queryFn: () => fetchRelaySettlementOverview({ search, skip: relayPage * PAGE_SIZE, limit: PAGE_SIZE }),
    refetchInterval: 60_000,
  });
  const actions = useQuery({
    queryKey: ["finance-relay-actions", relayId, status, direction, actionPage],
    queryFn: () => fetchRelaySettlementActions({ relay_id: relayId || undefined, status, direction: direction || undefined, skip: actionPage * PAGE_SIZE, limit: PAGE_SIZE }),
    refetchInterval: 60_000,
  });
  const totals = overview.data?.totals;
  React.useEffect(() => {
    if (overview.data && relayPage > 0 && relayPage * PAGE_SIZE >= overview.data.total) setRelayPage(Math.max(0, Math.ceil(overview.data.total / PAGE_SIZE) - 1));
  }, [overview.data, relayPage]);
  React.useEffect(() => {
    if (actions.data && actionPage > 0 && actionPage * PAGE_SIZE >= actions.data.total) setActionPage(Math.max(0, Math.ceil(actions.data.total / PAGE_SIZE) - 1));
  }, [actions.data, actionPage]);
  const selectRelay = (id: string) => {
    setRelayId(id); setStatus("outstanding"); setDirection(""); setActionPage(0);
    document.getElementById("relay-actions")?.scrollIntoView({ behavior: "smooth", block: "start" });
  };
  const selectFilter = (filter: SettlementFilter, selectedDirection: SettlementDirection | "" = "") => {
    setStatus(filter); setDirection(selectedDirection); setActionPage(0);
  };

  return <div className="space-y-4">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 className="text-lg font-semibold">Règlements des relais</h2>
        <p className="text-sm text-muted-foreground">Situation actuelle, sans filtre de période. Les paiements se font hors plateforme ; une déclaration reste due jusqu’à validation.</p>
      </div>
      <Button variant="outline" size="sm" disabled={overview.isFetching || actions.isFetching} onClick={() => { void overview.refetch(); void actions.refetch(); }}>Actualiser</Button>
    </div>
    {overview.isLoading ? <p role="status">Chargement des montants par relais…</p> : overview.isError || !totals ?
      <p role="alert" className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">Impossible de charger les montants dus. Actualisez pour réessayer.</p> : <>
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {(["to_relay", "to_denkma", "to_driver"] as SettlementDirection[]).map((key) => <button key={key} type="button" className="text-left" onClick={() => { setRelayId(""); selectFilter("outstanding", key); }}>
          <Card className="h-full transition-colors hover:bg-muted/30"><CardContent className="space-y-2 p-4">
            <div className="text-sm font-medium">{key === "to_relay" ? "Denkma doit aux relais" : key === "to_denkma" ? "Les relais doivent à Denkma" : "Les relais doivent aux livreurs"}</div>
            <div className="text-xl font-bold">{formatSettlementAmount(totals[`${key}_xof`])}</div>
            <div className="text-xs text-muted-foreground">Dont {formatSettlementAmount(totals[`${key}_declared_xof`])} déclarés, à vérifier</div>
          </CardContent></Card>
        </button>)}
        <button type="button" className="text-left" onClick={() => { setRelayId(""); selectFilter("declared"); }}>
          <Card className="h-full transition-colors hover:bg-muted/30"><CardContent className="space-y-2 p-4">
            <div className="text-sm font-medium">Déclarations à valider</div><div className="text-xl font-bold">{totals.declared_count}</div>
            <div className="text-xs text-muted-foreground">Les trois types de versement, livreurs inclus</div>
          </CardContent></Card>
        </button>
      </div>
      <p className="text-xs text-muted-foreground">Totaux de tous les relais, sans compensation entre les deux sens ni modification du solde. Commissions à venir : {formatSettlementAmount(totals.upcoming_to_relay_xof)}, exclues des sommes dues avant livraison.</p>
      {totals.unavailable_count > 0 && <div role="alert" className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
        <span>{totals.unavailable_count} colis non calculables : les totaux sont incomplets jusqu’à correction.</span>
        <Button size="sm" variant="outline" onClick={() => { setRelayId(""); selectFilter("issues"); }}>Voir les colis à vérifier</Button>
      </div>}
      <Card><CardContent className="space-y-4 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h3 className="font-semibold">Montants par relais</h3>
          <Input aria-label="Rechercher un relais" placeholder="Rechercher un relais…" value={search} onChange={(event) => { setSearch(event.target.value); setRelayPage(0); }} className="max-w-sm" />
        </div>
        <div className="overflow-x-auto"><table className="w-full text-left text-sm">
          <thead><tr className="border-b text-muted-foreground"><th className="p-3">Relais</th><th className="p-3">Denkma lui doit</th><th className="p-3">Il doit à Denkma</th><th className="p-3">Il doit au livreur</th><th className="p-3">À vérifier</th><th className="p-3">Colis / actions</th></tr></thead>
          <tbody>{overview.data?.relays.map((relay) => <tr key={relay.relay_id} className={`border-b last:border-0 ${relayId === relay.relay_id ? "bg-muted/50" : ""}`}>
            <td className="p-3"><Link className="font-medium text-primary hover:underline" href={`/dashboard/relays/${encodeURIComponent(relay.relay_id)}`}>{relay.name}</Link>{relay.missing_relay ? <div className="text-xs text-red-700">Fiche introuvable</div> : relay.is_active === false ? <div className="text-xs text-muted-foreground">Relais inactif</div> : null}{relay.unavailable_count > 0 && <div className="text-xs text-amber-800">Montants incomplets · {relay.unavailable_count} colis à vérifier</div>}</td>
            {(["to_relay", "to_denkma", "to_driver"] as SettlementDirection[]).map((key) => <td key={key} className="whitespace-nowrap p-3">{formatSettlementAmount(relay[`${key}_xof`])}</td>)}
            <td className="p-3"><Badge tone={relay.declared_count ? "warning" : "default"}>{relay.declared_count} déclaration{relay.declared_count > 1 ? "s" : ""}</Badge></td>
            <td className="p-3"><Button size="sm" variant="outline" onClick={() => selectRelay(relay.relay_id)}>Voir ({relay.outstanding_count})</Button></td>
          </tr>)}</tbody>
        </table></div>
        {!overview.data?.total && <p className="text-sm text-muted-foreground">Aucun relais pour cette recherche.</p>}
        <Pagination page={relayPage} total={overview.data?.total ?? 0} hasMore={overview.data?.has_more ?? false} onPage={setRelayPage} />
      </CardContent></Card>
    </>}
    <div id="relay-actions" className="admin-section space-y-4 rounded-lg border p-4">
      <div className="flex flex-wrap items-center justify-between gap-3"><h3 className="font-semibold">Colis et actions de paiement</h3>{relayId && <Button variant="outline" size="sm" onClick={() => selectRelay("")}>Afficher tous les relais</Button>}</div>
      {relayId && <p className="text-sm text-muted-foreground">Relais sélectionné : {overview.data?.relays.find((relay) => relay.relay_id === relayId)?.name ?? relayId}</p>}
      <div className="flex flex-wrap gap-3">
        <label className="space-y-1 text-sm"><span className="block">État du règlement</span><select className="rounded-md border bg-background p-2" value={status} onChange={(event) => selectFilter(event.target.value as SettlementFilter, direction)}>{Object.entries(FILTERS).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select></label>
        <label className="space-y-1 text-sm"><span className="block">Sens du versement</span><select className="rounded-md border bg-background p-2" value={direction} disabled={status === "issues"} onChange={(event) => selectFilter(status, event.target.value as SettlementDirection | "")}><option value="">Tous les versements</option>{Object.entries(SETTLEMENT_DIRECTIONS).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select></label>
      </div>
      {actions.isLoading ? <p role="status">Chargement des colis et des actions…</p> : actions.isError ? <p role="alert" className="text-sm text-red-700">Impossible de charger les actions. Actualisez pour réessayer.</p> : <>
        {!actions.data?.total && <p className="rounded-md border border-dashed p-4 text-sm text-muted-foreground">Aucun règlement pour ces filtres.</p>}
        <div className="grid items-start gap-3 lg:grid-cols-2">{actions.data?.actions.map((item) => "issue" in item ? <div key={item.parcel_id} className="rounded-md border border-amber-200 bg-amber-50 p-4 text-sm"><Link className="font-semibold text-primary hover:underline" href={`/dashboard/parcels/${encodeURIComponent(item.parcel_id)}`}>{item.tracking_code}</Link><p className="mt-2">{item.issue}</p></div> : <RelaySettlementActionCard key={`${item.parcel_id}:${item.action}:${item.relay_id}`} item={item} />)}</div>
        <Pagination page={actionPage} total={actions.data?.total ?? 0} hasMore={actions.data?.has_more ?? false} onPage={setActionPage} />
      </>}
    </div>
  </div>;
}
