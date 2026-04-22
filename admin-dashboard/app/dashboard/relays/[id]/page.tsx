"use client";

import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api, fetchRelayDetail, verifyRelay } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/toaster";
import { formatDate } from "@/lib/utils";
import {
  ArrowLeft,
  CheckCircle2,
  Loader2,
  MapPin,
  Package,
  Users,
  Wallet,
} from "lucide-react";
import Link from "next/link";

export const runtime = "edge";

const xof = new Intl.NumberFormat("fr-FR");

type BadgeTone = NonNullable<React.ComponentProps<typeof Badge>["tone"]>;

type ApplicationDocument = {
  label: string;
  url?: string | null;
};

function textOrDash(value: unknown) {
  const text = String(value ?? "").trim();
  return text || "—";
}

function applicationStatusLabel(status: unknown) {
  switch (String(status ?? "")) {
    case "approved":
      return "Approuvée";
    case "rejected":
      return "Refusée";
    case "pending":
      return "En attente";
    default:
      return textOrDash(status);
  }
}

function applicationStatusTone(status: unknown): BadgeTone {
  switch (String(status ?? "")) {
    case "approved":
      return "success";
    case "rejected":
      return "danger";
    case "pending":
      return "warning";
    default:
      return "default";
  }
}

async function openSecureDocument(url: string) {
  const response = await api.get(url, { responseType: "blob" });
  const objectUrl = URL.createObjectURL(response.data);
  window.open(objectUrl, "_blank", "noopener,noreferrer");
  window.setTimeout(() => URL.revokeObjectURL(objectUrl), 60_000);
}

function InfoLine({
  label,
  value,
}: {
  label: string;
  value: unknown;
}) {
  return (
    <div className="flex justify-between gap-3">
      <span className="text-muted-foreground">{label}</span>
      <span className="max-w-[65%] text-right">{textOrDash(value)}</span>
    </div>
  );
}

export default function RelayDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const qc = useQueryClient();
  const { toast } = useToast();

  const { data, isLoading, isError } = useQuery({
    queryKey: ["relay-detail", id],
    queryFn: () => fetchRelayDetail(id),
    enabled: !!id,
  });

  const verifyMut = useMutation({
    mutationFn: () => verifyRelay(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["relay-detail", id] });
      qc.invalidateQueries({ queryKey: ["relays"] });
      toast("Relais vérifié.");
    },
  });

  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="p-8">
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Point relais introuvable.
        </div>
      </div>
    );
  }

  const relay = data.relay_point;
  const stock = data.stock_summary;
  const wallet = data.wallet;

  return (
    <div className="space-y-6 p-8">
      {/* Header */}
      <div className="flex items-start gap-4">
        <Button variant="ghost" size="icon" onClick={() => router.back()}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="flex-1">
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold">{relay.name}</h1>
            <Badge tone={relay.is_active ? "success" : "default"}>
              {relay.is_active ? "Actif" : "Inactif"}
            </Badge>
            {relay.is_verified ? (
              <Badge tone="success">Vérifié</Badge>
            ) : (
              <Badge tone="warning">Non vérifié</Badge>
            )}
          </div>
          <div className="mt-1 text-sm text-muted-foreground">
            {relay.city ?? ""} {relay.address ? `— ${relay.address}` : ""} •
            ID: {relay.relay_id}
          </div>
          {relay.latitude && relay.longitude && (
            <div className="mt-1 flex items-center gap-1 text-xs text-muted-foreground">
              <MapPin className="h-3.5 w-3.5" />
              {relay.latitude.toFixed(5)}, {relay.longitude.toFixed(5)}
            </div>
          )}
        </div>
        {!relay.is_verified && (
          <Button
            size="sm"
            disabled={verifyMut.isPending}
            onClick={() => verifyMut.mutate()}
          >
            <CheckCircle2 className="h-4 w-4" />
            Vérifier
          </Button>
        )}
      </div>

      {data.applications && data.applications.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Candidatures et documents</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {data.applications.map((application: any) => {
              const applicationData = application.data ?? {};
              const isDriver = application.type === "driver";
              const documents: ApplicationDocument[] = [
                { label: "Pièce d'identité", url: applicationData.id_card_url },
                { label: "Permis de conduire", url: applicationData.license_url },
                { label: "Document commerce", url: applicationData.business_doc_url },
                { label: "Registre commerce", url: applicationData.business_reg_url },
              ];
              const availableDocuments = documents.filter((doc) => doc.url);

              return (
                <div
                  key={application.application_id}
                  className="rounded-lg border bg-muted/20 p-4 text-sm"
                >
                  <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                    <div className="font-semibold">
                      {isDriver ? "Candidature livreur" : "Candidature point relais"}
                    </div>
                    <Badge tone={applicationStatusTone(application.status)}>
                      {applicationStatusLabel(application.status)}
                    </Badge>
                  </div>
                  <div className="grid gap-2 md:grid-cols-2">
                    <InfoLine label="ID candidature" value={application.application_id} />
                    <InfoLine label="Utilisateur" value={application.user_name} />
                    <InfoLine label="Téléphone" value={application.user_phone} />
                    <InfoLine label="Soumise le" value={formatDate(application.created_at)} />
                    <InfoLine label="Mise à jour" value={formatDate(application.updated_at)} />
                    <InfoLine label="Nom du commerce" value={applicationData.business_name} />
                    <InfoLine label="Adresse" value={applicationData.address_label} />
                    <InfoLine label="Ville" value={applicationData.city} />
                    <InfoLine label="Registre commerce" value={applicationData.business_reg} />
                    <InfoLine label="Horaires" value={applicationData.opening_hours} />
                    <InfoLine label="Message candidat" value={applicationData.message} />
                    <InfoLine label="Note admin" value={application.admin_notes} />
                  </div>
                  <div className="mt-3 flex flex-wrap gap-2">
                    {availableDocuments.length > 0 ? (
                      availableDocuments.map((document) => (
                        <Button
                          key={document.label}
                          size="sm"
                          variant="outline"
                          onClick={() => openSecureDocument(document.url!)}
                        >
                          Voir {document.label.toLowerCase()}
                        </Button>
                      ))
                    ) : (
                      <span className="text-xs text-muted-foreground">
                        Aucun document transmis dans cette candidature.
                      </span>
                    )}
                  </div>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}

      {/* Stock summary */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardContent className="flex items-center gap-3 p-5">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-amber-50 text-amber-600">
              <Package className="h-5 w-5" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stock.pending_origin}</div>
              <div className="text-xs text-muted-foreground">En attente (origine)</div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="flex items-center gap-3 p-5">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-blue-50 text-blue-600">
              <Package className="h-5 w-5" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stock.incoming}</div>
              <div className="text-xs text-muted-foreground">En route</div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="flex items-center gap-3 p-5">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-green-50 text-green-600">
              <Package className="h-5 w-5" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stock.available}</div>
              <div className="text-xs text-muted-foreground">Disponibles</div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="flex items-center gap-3 p-5">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-muted text-foreground">
              <Package className="h-5 w-5" />
            </div>
            <div>
              <div className="text-2xl font-bold">{stock.delivered_total}</div>
              <div className="text-xs text-muted-foreground">Livrés (total)</div>
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        {/* Wallet */}
        {wallet && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Wallet className="h-4 w-4" />
                Portefeuille relais
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Solde</span>
                <span className="font-bold">{xof.format(wallet.balance ?? 0)} XOF</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">En attente</span>
                <span>{xof.format(wallet.pending ?? 0)} XOF</span>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Agents */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Users className="h-4 w-4" />
              Agents ({data.agents?.length ?? 0})
            </CardTitle>
          </CardHeader>
          <CardContent>
            {data.agents && data.agents.length > 0 ? (
              <div className="space-y-2">
                {data.agents.map((agent: any) => {
                  const documents: ApplicationDocument[] = [
                    { label: "Pièce d'identité", url: agent.kyc_id_card_url },
                    { label: "Permis de conduire", url: agent.kyc_license_url },
                  ].filter((document) => document.url);

                  return (
                    <div key={agent.user_id} className="rounded-md border p-3 text-sm">
                      <div className="flex items-center justify-between gap-3">
                        <Link
                          href={`/dashboard/users/${agent.user_id}`}
                          className="hover:underline"
                        >
                          <div className="font-medium">{agent.name ?? "—"}</div>
                          <div className="text-xs text-muted-foreground">{agent.phone}</div>
                        </Link>
                        <Badge tone="warning">Agent</Badge>
                      </div>
                      {documents.length > 0 && (
                        <div className="mt-2 flex flex-wrap gap-2">
                          {documents.map((document) => (
                            <Button
                              key={document.label}
                              size="sm"
                              variant="outline"
                              onClick={() => openSecureDocument(document.url!)}
                            >
                              Voir {document.label.toLowerCase()}
                            </Button>
                          ))}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            ) : (
              <div className="text-sm text-muted-foreground">Aucun agent lié.</div>
            )}
          </CardContent>
        </Card>

        {/* Owner */}
        {data.owner && (
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Propriétaire</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm">
              <Link
                href={`/dashboard/users/${data.owner.user_id}`}
                className="text-primary underline"
              >
                {data.owner.name ?? data.owner.phone ?? data.owner.user_id}
              </Link>
              {[
                { label: "Pièce d'identité", url: data.owner.kyc_id_card_url },
                { label: "Permis de conduire", url: data.owner.kyc_license_url },
              ].some((document) => document.url) && (
                <div className="flex flex-wrap gap-2">
                  {[
                    { label: "Pièce d'identité", url: data.owner.kyc_id_card_url },
                    { label: "Permis de conduire", url: data.owner.kyc_license_url },
                  ]
                    .filter((document) => document.url)
                    .map((document) => (
                      <Button
                        key={document.label}
                        size="sm"
                        variant="outline"
                        onClick={() => openSecureDocument(document.url!)}
                      >
                        Voir {document.label.toLowerCase()}
                      </Button>
                    ))}
                </div>
              )}
            </CardContent>
          </Card>
        )}

        {/* Capacity */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Capacité</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Max</span>
              <span className="font-bold">{relay.max_capacity ?? "∞"}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Charge actuelle</span>
              <span>{relay.current_load ?? 0}</span>
            </div>
            {relay.max_capacity && relay.current_load != null && (
              <div className="h-2 w-full overflow-hidden rounded-full bg-muted">
                <div
                  className="h-full rounded-full bg-primary"
                  style={{
                    width: `${Math.min(100, (relay.current_load / relay.max_capacity) * 100)}%`,
                  }}
                />
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Recent parcels */}
      {data.recent_parcels && data.recent_parcels.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Colis récents</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {data.recent_parcels.map((p: any) => (
                <Link
                  key={p.parcel_id}
                  href={`/dashboard/parcels/${p.parcel_id}`}
                  className="flex items-center justify-between rounded-md border p-3 text-sm hover:bg-accent"
                >
                  <div>
                    <span className="font-mono font-semibold">{p.tracking_code}</span>
                    <span className="ml-2 text-muted-foreground">
                      {p.sender_name ?? "—"} → {p.recipient_name ?? "—"}
                    </span>
                  </div>
                  <Badge tone={p.status === "delivered" ? "success" : "info"}>
                    {p.status?.replace(/_/g, " ")}
                  </Badge>
                </Link>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
