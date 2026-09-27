"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { fetchPrivacyRequests, updatePrivacyRequest, type PrivacyRequest } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Loader2, Search } from "lucide-react";
import { useToast } from "@/components/ui/toaster";

const TYPE_LABELS: Record<string, string> = {
  export: "Export",
  access: "Accès",
  rectification: "Rectification",
  deletion: "Suppression",
  opposition: "Opposition",
  restriction: "Limitation",
};

const STATUS_LABELS: Record<string, string> = {
  pending: "À traiter",
  in_progress: "En cours",
  completed: "Terminée",
  rejected: "Refusée",
};

function formatDate(value?: string) {
  if (!value) return "—";
  return new Date(value).toLocaleString("fr-FR");
}

export default function PrivacyRequestsPage() {
  const qc = useQueryClient();
  const { toast } = useToast();
  const [search, setSearch] = React.useState("");
  const [selected, setSelected] = React.useState<PrivacyRequest | null>(null);
  const [status, setStatus] = React.useState("in_progress");
  const [response, setResponse] = React.useState("");
  const { data, isLoading, isError } = useQuery({
    queryKey: ["privacy-requests", search],
    queryFn: () => fetchPrivacyRequests({ search: search.trim() || undefined }),
    refetchInterval: 30_000,
  });
  const update = useMutation({
    mutationFn: () => updatePrivacyRequest(selected!.request_id, { status, admin_response: response }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["privacy-requests"] });
      setSelected(null);
      setResponse("");
      toast("Demande mise à jour.");
    },
  });

  function selectRequest(item: PrivacyRequest) {
    setSelected(item);
    setStatus(item.status === "pending" ? "in_progress" : item.status);
    setResponse(item.admin_response ?? "");
  }

  return (
    <div className="space-y-5 p-4 sm:p-6 lg:p-8">
      <div>
        <h1 className="text-2xl font-bold">Demandes de données</h1>
        <p className="text-sm text-muted-foreground">Consulter, répondre et suivre les demandes des utilisateurs.</p>
      </div>
      <div className="flex items-center gap-2">
        <Search className="h-4 w-4 text-muted-foreground" />
        <Input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Nom, téléphone ou numéro de demande…" className="max-w-xl" />
      </div>
      {isLoading && <div className="flex h-32 items-center justify-center"><Loader2 className="h-5 w-5 animate-spin" /></div>}
      {isError && <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">Impossible de charger les demandes.</div>}
      {data && (
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(20rem,28rem)]">
          <Card>
            <CardHeader><CardTitle className="text-base">{data.total} demande(s)</CardTitle></CardHeader>
            <CardContent className="space-y-2">
              {data.requests.length === 0 && <p className="text-sm text-muted-foreground">Aucune demande.</p>}
              {data.requests.map((item) => (
                <button key={item.request_id} type="button" onClick={() => selectRequest(item)} className={`w-full rounded-lg border p-3 text-left transition hover:bg-accent ${selected?.request_id === item.request_id ? "border-primary bg-primary/5" : ""}`}>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-medium">{TYPE_LABELS[item.request_type] ?? item.request_type}</span>
                    <Badge tone={item.status === "pending" ? "warning" : item.status === "completed" ? "success" : item.status === "rejected" ? "danger" : "info"}>{STATUS_LABELS[item.status] ?? item.status}</Badge>
                    <span className="ml-auto text-xs text-muted-foreground">{formatDate(item.created_at)}</span>
                  </div>
                  <div className="mt-1 text-sm">{item.user_name || "Utilisateur"} · {item.user_phone || "Téléphone non renseigné"}</div>
                  <div className="mt-1 text-xs text-muted-foreground">{item.request_id}</div>
                </button>
              ))}
            </CardContent>
          </Card>
          <Card>
            <CardHeader><CardTitle className="text-base">{selected ? "Traiter la demande" : "Sélectionner une demande"}</CardTitle></CardHeader>
            <CardContent>
              {selected ? (
                <div className="space-y-4">
                  <div className="rounded-md bg-muted p-3 text-sm"><div><strong>{TYPE_LABELS[selected.request_type] ?? selected.request_type}</strong></div><div className="text-muted-foreground">{selected.user_name} · {selected.user_phone}</div><div className="mt-2">{selected.message || "Aucun message complémentaire."}</div></div>
                  <label className="block text-sm font-medium">Statut<select value={status} onChange={(event) => setStatus(event.target.value)} className="mt-1 w-full rounded-md border bg-background px-3 py-2"><option value="pending">À traiter</option><option value="in_progress">En cours</option><option value="completed">Terminée</option><option value="rejected">Refusée</option></select></label>
                  <label className="block text-sm font-medium">Réponse à l’utilisateur<Textarea value={response} onChange={(event) => setResponse(event.target.value)} rows={7} className="mt-1" placeholder="Expliquez la suite donnée à la demande…" /></label>
                  <Button onClick={() => update.mutate()} disabled={update.isPending}>{update.isPending && <Loader2 className="h-4 w-4 animate-spin" />}Enregistrer et répondre</Button>
                </div>
              ) : <p className="text-sm text-muted-foreground">Les détails et la réponse apparaîtront ici.</p>}
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
