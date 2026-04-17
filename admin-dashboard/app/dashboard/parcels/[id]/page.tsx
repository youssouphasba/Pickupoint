"use client";

import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  api,
  confirmPayment,
  fetchDrivers,
  fetchParcelAudit,
  overrideParcelStatus,
  paymentOverride,
  reassignMission,
  resolveIncident,
  suspendParcel,
  unsuspendParcel,
} from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ActionModal, ConfirmModal } from "@/components/action-modal";
import { useToast } from "@/components/ui/toaster";
import { formatDate } from "@/lib/utils";
import {
  ArrowLeft,
  Ban,
  CheckCircle2,
  CreditCard,
  History,
  Loader2,
  Play,
  RefreshCw,
  ShieldAlert,
  Zap,
} from "lucide-react";
import Link from "next/link";

export const runtime = "edge";

const xof = new Intl.NumberFormat("fr-FR");

const STATUS_LABELS: Record<string, string> = {
  created: "Créé",
  dropped_at_origin_relay: "Déposé relais origine",
  in_transit: "En transit",
  at_destination_relay: "Au relais destination",
  available_at_relay: "Dispo relais",
  out_for_delivery: "En livraison",
  redirected_to_relay: "Redirigé relais",
  delivery_failed: "Échec livraison",
  delivered: "Livré",
  cancelled: "Annulé",
  returned: "Retourné",
  disputed: "Litige",
  expired: "Expiré",
  incident_reported: "Incident",
  suspended: "Suspendu",
};

const STATUS_TONE: Record<string, "default" | "info" | "success" | "warning" | "danger"> = {
  delivered: "success",
  in_transit: "info",
  out_for_delivery: "info",
  available_at_relay: "info",
  delivery_failed: "danger",
  disputed: "danger",
  incident_reported: "danger",
  suspended: "danger",
  cancelled: "default",
  returned: "default",
  created: "default",
  redirected_to_relay: "warning",
};

const MODE_LABELS: Record<string, string> = {
  relay_to_relay: "Relais → Relais",
  relay_to_home: "Relais → Domicile",
  home_to_relay: "Domicile → Relais",
  home_to_home: "Domicile → Domicile",
};

const OVERRIDE_STATUSES = [
  "created",
  "dropped_at_origin_relay",
  "in_transit",
  "at_destination_relay",
  "available_at_relay",
  "out_for_delivery",
  "delivered",
  "delivery_failed",
  "cancelled",
  "returned",
];

async function fetchParcelDetail(parcelId: string) {
  const { data } = await api.get(`/api/parcels/${parcelId}`);
  return data;
}

export default function ParcelDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const qc = useQueryClient();
  const { toast } = useToast();

  const { data, isLoading, isError } = useQuery({
    queryKey: ["parcel-detail", id],
    queryFn: () => fetchParcelDetail(id),
    enabled: !!id,
  });

  const audit = useQuery({
    queryKey: ["parcel-audit", id],
    queryFn: () => fetchParcelAudit(id),
    enabled: !!id,
  });

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ["parcel-detail", id] });
    qc.invalidateQueries({ queryKey: ["parcel-audit", id] });
    qc.invalidateQueries({ queryKey: ["parcels"], exact: false });
  };

  // ── Modals ──
  const [confirmPayOpen, setConfirmPayOpen] = React.useState(false);
  const [overridePayOpen, setOverridePayOpen] = React.useState(false);
  const [suspendOpen, setSuspendOpen] = React.useState(false);
  const [unsuspendOpen, setUnsuspendOpen] = React.useState(false);
  const [overrideOpen, setOverrideOpen] = React.useState(false);
  const [incidentOpen, setIncidentOpen] = React.useState(false);
  const [selectedStatus, setSelectedStatus] = React.useState("created");
  const [incidentAction, setIncidentAction] = React.useState<"reassign" | "return" | "cancel">("reassign");
  const [reassignOpen, setReassignOpen] = React.useState(false);
  const [reassignDriverId, setReassignDriverId] = React.useState("");

  const driversForReassign = useQuery({
    queryKey: ["drivers-list"],
    queryFn: fetchDrivers,
    enabled: reassignOpen,
  });

  const confirmPayMut = useMutation({
    mutationFn: () => confirmPayment(id),
    onSuccess: () => { invalidate(); toast("Paiement confirmé."); },
  });

  const overridePayMut = useMutation({
    mutationFn: (reason: string) => paymentOverride(id, reason),
    onSuccess: () => { invalidate(); toast("Blocage paiement levé."); },
  });

  const suspendMut = useMutation({
    mutationFn: () => suspendParcel(id),
    onSuccess: () => { invalidate(); toast("Colis suspendu."); },
  });

  const unsuspendMut = useMutation({
    mutationFn: (toStatus: string) => unsuspendParcel(id, toStatus),
    onSuccess: () => { invalidate(); toast("Suspension levée."); },
  });

  const overrideMut = useMutation({
    mutationFn: ({ status, notes }: { status: string; notes: string }) =>
      overrideParcelStatus(id, status, notes),
    onSuccess: () => { invalidate(); toast("Statut forcé."); },
  });

  const incidentMut = useMutation({
    mutationFn: ({ action, notes }: { action: "reassign" | "return" | "cancel"; notes: string }) =>
      resolveIncident(id, action, notes),
    onSuccess: () => { invalidate(); toast("Incident résolu."); },
  });

  const reassignMut = useMutation({
    mutationFn: ({ missionId, driverId }: { missionId: string; driverId: string }) =>
      reassignMission(missionId, driverId),
    onSuccess: () => {
      invalidate();
      toast("Mission r��assignée.");
      setReassignOpen(false);
      setReassignDriverId("");
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
          Colis introuvable.
        </div>
      </div>
    );
  }

  const parcel = data.parcel ?? data;
  const timeline = data.timeline ?? [];

  return (
    <div className="space-y-6 p-8">
      {/* Header */}
      <div className="flex items-start gap-4">
        <Button variant="ghost" size="icon" onClick={() => router.back()}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="flex-1">
          <div className="flex items-center gap-3">
            <h1 className="font-mono text-2xl font-bold">
              {parcel.tracking_code}
            </h1>
            <Badge tone={STATUS_TONE[parcel.status] ?? "default"}>
              {STATUS_LABELS[parcel.status] ?? parcel.status}
            </Badge>
          </div>
          <div className="mt-1 text-sm text-muted-foreground">
            {MODE_LABELS[parcel.delivery_mode] ?? parcel.delivery_mode} •
            Créé le {formatDate(parcel.created_at)} • ID: {parcel.parcel_id}
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="flex flex-wrap gap-2">
        <Button variant="outline" size="sm" onClick={() => setConfirmPayOpen(true)}>
          <CreditCard className="h-4 w-4" />
          Confirmer paiement
        </Button>
        <Button variant="outline" size="sm" onClick={() => setOverridePayOpen(true)}>
          <CheckCircle2 className="h-4 w-4" />
          Lever blocage paiement
        </Button>
        {parcel.status !== "suspended" ? (
          <Button variant="destructive" size="sm" onClick={() => setSuspendOpen(true)}>
            <Ban className="h-4 w-4" />
            Suspendre
          </Button>
        ) : (
          <Button variant="outline" size="sm" onClick={() => setUnsuspendOpen(true)}>
            <Play className="h-4 w-4" />
            Lever suspension
          </Button>
        )}
        {parcel.status === "incident_reported" && (
          <Button variant="outline" size="sm" onClick={() => setIncidentOpen(true)}>
            <ShieldAlert className="h-4 w-4" />
            Résoudre incident
          </Button>
        )}
        {parcel.assigned_driver_id && (
          <Button variant="outline" size="sm" onClick={() => setReassignOpen(true)}>
            <RefreshCw className="h-4 w-4" />
            Réassigner mission
          </Button>
        )}
        <Button variant="outline" size="sm" onClick={() => setOverrideOpen(true)}>
          <Zap className="h-4 w-4" />
          Forcer statut
        </Button>
      </div>

      {/* Info grid */}
      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Informations</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row label="Expéditeur" value={parcel.sender_name ?? "—"} />
            <Row label="Destinataire" value={parcel.recipient_name ?? parcel.recipient_phone ?? "—"} />
            <Row label="Tél. destinataire" value={parcel.recipient_phone ?? "—"} />
            <Row label="Mode" value={MODE_LABELS[parcel.delivery_mode] ?? "—"} />
            {parcel.is_express && <Row label="Express" value="Oui" />}
            {parcel.weight_kg != null && <Row label="Poids" value={`${parcel.weight_kg} kg`} />}
            {parcel.description && <Row label="Description" value={parcel.description} />}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Paiement</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row
              label="Prix devis"
              value={parcel.quoted_price ? `${xof.format(parcel.quoted_price)} XOF` : "—"}
            />
            <Row
              label="Prix payé"
              value={parcel.paid_price ? `${xof.format(parcel.paid_price)} XOF` : "—"}
            />
            <Row label="Statut paiement" value={parcel.payment_status ?? "—"} />
            <Row
              label="Override paiement"
              value={parcel.payment_override ? "Oui" : "Non"}
            />
            <Row label="Qui paie" value={parcel.who_pays ?? "—"} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Relais</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row label="Relais origine" value={parcel.origin_relay_id ?? "—"} />
            <Row label="Relais destination" value={parcel.destination_relay_id ?? "—"} />
            {parcel.relay_pin && <Row label="PIN relais" value={parcel.relay_pin} />}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Livreur</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row
              label="Livreur assigné"
              value={
                parcel.assigned_driver_id ? (
                  <Link
                    href={`/dashboard/users/${parcel.assigned_driver_id}`}
                    className="text-primary underline"
                  >
                    {parcel.driver_name ?? parcel.assigned_driver_id}
                  </Link>
                ) : (
                  "—"
                )
              }
            />
            <Row label="Revenus livreur" value={parcel.earn_amount ? `${xof.format(parcel.earn_amount)} XOF` : "—"} />
          </CardContent>
        </Card>
      </div>

      {/* Timeline */}
      {timeline.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <History className="h-4 w-4" />
              Timeline
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {timeline.map((ev: any, i: number) => (
                <div key={i} className="flex items-start gap-3 text-sm">
                  <div className="mt-1 h-2 w-2 shrink-0 rounded-full bg-primary" />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <Badge tone={STATUS_TONE[ev.new_status ?? ev.status] ?? "default"}>
                        {(ev.event_type ?? ev.new_status ?? "").replace(/_/g, " ")}
                      </Badge>
                      <span className="text-xs text-muted-foreground">
                        {formatDate(ev.created_at)}
                      </span>
                    </div>
                    {ev.notes && (
                      <div className="mt-0.5 text-xs text-muted-foreground">{ev.notes}</div>
                    )}
                    {ev.actor_name && (
                      <div className="text-xs text-muted-foreground">
                        Par: {ev.actor_name} ({ev.actor_role})
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Audit trail */}
      {audit.data?.events && audit.data.events.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Audit trail complet</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="max-h-96 space-y-2 overflow-y-auto">
              {audit.data.events.map((ev: any, i: number) => (
                <div
                  key={i}
                  className="rounded-md border p-3 text-sm"
                >
                  <div className="flex items-center justify-between">
                    <Badge tone="info">{ev.event_type?.replace(/_/g, " ")}</Badge>
                    <span className="text-xs text-muted-foreground">
                      {formatDate(ev.created_at)}
                    </span>
                  </div>
                  {ev.actor_name && (
                    <div className="mt-1 text-xs text-muted-foreground">
                      Acteur: {ev.actor_name} ({ev.actor_role})
                    </div>
                  )}
                  {ev.notes && (
                    <div className="mt-1 text-xs text-muted-foreground">{ev.notes}</div>
                  )}
                  {ev.metadata && (
                    <details className="mt-1">
                      <summary className="cursor-pointer text-xs text-muted-foreground">
                        Détails
                      </summary>
                      <pre className="mt-1 max-h-32 overflow-auto rounded bg-muted/50 p-2 text-[11px]">
                        {JSON.stringify(ev.metadata, null, 2)}
                      </pre>
                    </details>
                  )}
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* ── Modals ── */}
      <ConfirmModal
        open={confirmPayOpen}
        onOpenChange={setConfirmPayOpen}
        title="Confirmer le paiement manuellement"
        description={`Le statut paiement sera forcé à "paid" pour le colis ${parcel.tracking_code}.`}
        confirmLabel="Confirmer paiement"
        onConfirm={async () => { await confirmPayMut.mutateAsync(); }}
      />

      <ActionModal
        open={overridePayOpen}
        onOpenChange={setOverridePayOpen}
        title="Lever le blocage paiement"
        description="Le colis pourra continuer son parcours même sans paiement confirmé."
        inputLabel="Motif"
        inputPlaceholder="Ex: paiement reçu hors-ligne, webhook échoué…"
        inputType="textarea"
        confirmLabel="Lever blocage"
        onConfirm={async (reason) => { await overridePayMut.mutateAsync(reason); }}
      />

      <ConfirmModal
        open={suspendOpen}
        onOpenChange={setSuspendOpen}
        title="Suspendre ce colis"
        description="Toutes les actions (collecte, livraison) seront bloquées."
        confirmLabel="Suspendre"
        confirmVariant="destructive"
        onConfirm={async () => { await suspendMut.mutateAsync(); }}
      />

      {unsuspendOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="w-full max-w-sm rounded-lg border bg-background p-6 shadow-lg">
            <h3 className="mb-2 text-lg font-semibold">Lever la suspension</h3>
            <p className="mb-4 text-sm text-muted-foreground">Choisir le statut de destination :</p>
            <div className="mb-4 flex flex-wrap gap-2">
              {["created", "out_for_delivery", "in_transit"].map((s) => (
                <button
                  key={s}
                  onClick={() => setSelectedStatus(s)}
                  className={`rounded-full border px-3 py-1.5 text-sm ${
                    selectedStatus === s
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-input bg-background hover:bg-accent"
                  }`}
                >
                  {STATUS_LABELS[s] ?? s}
                </button>
              ))}
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" size="sm" onClick={() => setUnsuspendOpen(false)}>
                Annuler
              </Button>
              <Button
                size="sm"
                disabled={unsuspendMut.isPending}
                onClick={async () => {
                  await unsuspendMut.mutateAsync(selectedStatus);
                  setUnsuspendOpen(false);
                }}
              >
                {unsuspendMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
                Confirmer
              </Button>
            </div>
          </div>
        </div>
      )}

      {overrideOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="w-full max-w-md rounded-lg border bg-background p-6 shadow-lg">
            <h3 className="mb-2 text-lg font-semibold">Forcer un changement de statut</h3>
            <p className="mb-3 text-sm text-muted-foreground">
              Action SuperAdmin. Choisir le nouveau statut :
            </p>
            <div className="mb-3 flex flex-wrap gap-2">
              {OVERRIDE_STATUSES.map((s) => (
                <button
                  key={s}
                  onClick={() => setSelectedStatus(s)}
                  className={`rounded-full border px-2.5 py-1 text-xs ${
                    selectedStatus === s
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-input bg-background hover:bg-accent"
                  }`}
                >
                  {STATUS_LABELS[s] ?? s}
                </button>
              ))}
            </div>
            <textarea
              id="override-notes"
              className="mb-3 w-full rounded-md border p-2 text-sm"
              rows={2}
              placeholder="Motif de l'intervention…"
            />
            <div className="flex justify-end gap-2">
              <Button variant="outline" size="sm" onClick={() => setOverrideOpen(false)}>
                Annuler
              </Button>
              <Button
                size="sm"
                variant="destructive"
                disabled={overrideMut.isPending}
                onClick={async () => {
                  const notes = (document.getElementById("override-notes") as HTMLTextAreaElement)?.value ?? "";
                  if (notes.trim().length < 3) return;
                  await overrideMut.mutateAsync({ status: selectedStatus, notes: notes.trim() });
                  setOverrideOpen(false);
                }}
              >
                {overrideMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
                Forcer
              </Button>
            </div>
          </div>
        </div>
      )}

      {reassignOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="w-full max-w-md rounded-lg border bg-background p-6 shadow-lg">
            <h3 className="mb-2 text-lg font-semibold">Réassigner la mission</h3>
            <p className="mb-3 text-sm text-muted-foreground">
              Choisir un nouveau livreur pour ce colis.
            </p>
            <select
              value={reassignDriverId}
              onChange={(e) => setReassignDriverId(e.target.value)}
              className="mb-3 flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            >
              <option value="">Sélectionner un livreur…</option>
              {(driversForReassign.data?.drivers ?? [])
                .filter((d: any) => d.user_id !== parcel.assigned_driver_id)
                .map((d: any) => (
                  <option key={d.user_id} value={d.user_id}>
                    {d.name ?? d.full_name ?? d.phone} — {d.missions_count ?? 0} missions
                  </option>
                ))}
            </select>
            <div className="flex justify-end gap-2">
              <Button variant="outline" size="sm" onClick={() => setReassignOpen(false)}>
                Annuler
              </Button>
              <Button
                size="sm"
                disabled={!reassignDriverId || reassignMut.isPending}
                onClick={async () => {
                  const activeMission = audit.data?.missions?.find(
                    (m: any) => m.status === "assigned" || m.status === "in_progress"
                  );
                  if (!activeMission) {
                    toast("Aucune mission active trouvée.", "error");
                    return;
                  }
                  await reassignMut.mutateAsync({
                    missionId: activeMission.mission_id,
                    driverId: reassignDriverId,
                  });
                }}
              >
                {reassignMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
                Réassigner
              </Button>
            </div>
            {reassignMut.isError && (
              <div className="mt-3 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
                {(reassignMut.error as any)?.response?.data?.detail ?? "Erreur lors de la réassignation."}
              </div>
            )}
          </div>
        </div>
      )}

      {incidentOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="w-full max-w-sm rounded-lg border bg-background p-6 shadow-lg">
            <h3 className="mb-2 text-lg font-semibold">Résoudre l'incident</h3>
            <div className="mb-3 flex flex-wrap gap-2">
              {(["reassign", "return", "cancel"] as const).map((a) => (
                <button
                  key={a}
                  onClick={() => setIncidentAction(a)}
                  className={`rounded-full border px-3 py-1.5 text-sm ${
                    incidentAction === a
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-input bg-background hover:bg-accent"
                  }`}
                >
                  {a === "reassign" ? "Réassigner" : a === "return" ? "Retour envoyeur" : "Annuler"}
                </button>
              ))}
            </div>
            <textarea
              id="incident-notes"
              className="mb-3 w-full rounded-md border p-2 text-sm"
              rows={2}
              placeholder="Notes…"
            />
            <div className="flex justify-end gap-2">
              <Button variant="outline" size="sm" onClick={() => setIncidentOpen(false)}>
                Annuler
              </Button>
              <Button
                size="sm"
                disabled={incidentMut.isPending}
                onClick={async () => {
                  const notes = (document.getElementById("incident-notes") as HTMLTextAreaElement)?.value ?? "";
                  await incidentMut.mutateAsync({ action: incidentAction, notes: notes.trim() });
                  setIncidentOpen(false);
                }}
              >
                {incidentMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
                Résoudre
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-4">
      <span className="shrink-0 text-muted-foreground">{label}</span>
      <span className="text-right font-medium">{value}</span>
    </div>
  );
}
