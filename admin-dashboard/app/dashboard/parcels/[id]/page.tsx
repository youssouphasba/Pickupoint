"use client";

import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  APIProvider,
  AdvancedMarker,
  Map,
  Pin,
  Polyline,
} from "@vis.gl/react-google-maps";
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
import { SecureProfileImage } from "@/components/secure-profile-image";
import { useToast } from "@/components/ui/toaster";
import {
  formatLocationRelativeTime,
  resolveLocationSignal,
} from "@/lib/location-signal";
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
  Route,
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

const STATUS_TONE: Record<
  string,
  "default" | "info" | "success" | "warning" | "danger"
> = {
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

const DEFAULT_MAP_CENTER = {
  lat: Number(process.env.NEXT_PUBLIC_DEFAULT_MAP_LAT ?? "14.7167"),
  lng: Number(process.env.NEXT_PUBLIC_DEFAULT_MAP_LNG ?? "-17.4677"),
};
const MAP_ID =
  process.env.NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID ?? "denkma-parcel-route-map";

async function fetchParcelDetail(parcelId: string) {
  const { data } = await api.get(`/api/parcels/${parcelId}`);
  return data;
}

type GeoPoint = {
  lat?: number;
  lng?: number;
  latitude?: number;
  longitude?: number;
  ts?: string;
  accuracy?: number;
};

type ParcelMission = {
  mission_id?: string;
  status?: string;
  driver_name?: string;
  driver_location?: GeoPoint | null;
  assigned_at?: string;
  started_at?: string;
  completed_at?: string;
  encoded_polyline?: string;
  gps_trail?: GeoPoint[];
  pickup?: { label?: string | null; geopin?: GeoPoint | null };
  delivery?: { label?: string | null; geopin?: GeoPoint | null };
  route_summary?: {
    gps_points_count?: number;
    distance_text?: string;
    eta_text?: string;
    last_seen_at?: string;
  };
};

function readLatLng(point?: GeoPoint | null) {
  if (!point) return null;
  const lat = point.lat ?? point.latitude;
  const lng = point.lng ?? point.longitude;
  if (typeof lat !== "number" || typeof lng !== "number") return null;
  return { lat, lng };
}

function missionRouteLabel(mission: ParcelMission, index: number) {
  const driver = mission.driver_name ? ` - ${mission.driver_name}` : "";
  return `Mission ${index + 1}${driver}`;
}

function distanceBetweenMeters(
  from?: { lat: number; lng: number } | null,
  to?: { lat: number; lng: number } | null,
) {
  if (!from || !to) return null;
  const toRad = (value: number) => (value * Math.PI) / 180;
  const earthRadiusMeters = 6371000;
  const dLat = toRad(to.lat - from.lat);
  const dLng = toRad(to.lng - from.lng);
  const lat1 = toRad(from.lat);
  const lat2 = toRad(to.lat);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) *
      Math.cos(lat2) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

function formatDistanceMeters(distanceMeters?: number | null) {
  if (distanceMeters == null || !Number.isFinite(distanceMeters)) return "—";
  if (distanceMeters < 1000) {
    return `${Math.round(distanceMeters)} m`;
  }
  return `${(distanceMeters / 1000).toFixed(1)} km`;
}

function formatAddress(address: any): string | null {
  if (!address || typeof address !== "object") return null;
  const seen = new Set<string>();
  const richKeys = [
    "label",
    "formatted_address",
    "address",
    "address_line",
    "full_address",
    "place_name",
    "display_name",
    "street",
    "district",
    "notes",
  ];
  const parts = richKeys
    .map((key) => address[key])
    .filter((value) => typeof value === "string" && value.trim())
    .map((value) => value.trim())
    .filter((value) => {
      if (seen.has(value)) return false;
      seen.add(value);
      return true;
    });
  const city = address.city;
  if (parts.length && typeof city === "string" && city.trim()) {
    const value = city.trim();
    if (!seen.has(value)) parts.push(value);
  }
  if (parts.length) return parts.join(", ");
  const lat = address.geopin?.lat;
  const lng = address.geopin?.lng;
  if (typeof lat === "number" && typeof lng === "number") {
    return `Position GPS confirmée (${lat.toFixed(5)}, ${lng.toFixed(5)})`;
  }
  return null;
}

function formatAddressSummary(address: any): string | null {
  if (!address || typeof address !== "object") return null;
  const seen = new Set<string>();
  const keys = [
    "formatted_address",
    "address",
    "address_line",
    "full_address",
    "place_name",
    "display_name",
    "label",
    "street",
    "district",
    "city",
    "country",
  ];
  const parts = keys
    .map((key) => address[key])
    .filter((value) => typeof value === "string" && value.trim())
    .map((value) => value.trim())
    .filter((value) => {
      const lower = value.toLowerCase();
      if (seen.has(lower)) return false;
      seen.add(lower);
      return true;
    });
  if (parts.length === 1 && parts[0] === address.city && address.geopin) {
    return null;
  }
  return parts.length ? parts.join(", ") : null;
}

function formatGeoPin(geopin: any): string | null {
  if (!geopin || typeof geopin !== "object") return null;
  const lat = geopin.lat;
  const lng = geopin.lng;
  if (typeof lat !== "number" || typeof lng !== "number") return null;
  return `${lat.toFixed(6)}, ${lng.toFixed(6)}`;
}

function formatAddressLabel(label: any, address: any): string | null {
  if (typeof label !== "string" || !label.trim()) return null;
  const value = label.trim();
  const city = typeof address?.city === "string" ? address.city.trim() : "";
  const hasPreciseAddress = Boolean(formatAddressSummary(address));
  if (
    !hasPreciseAddress &&
    city &&
    value.toLowerCase() === city.toLowerCase()
  ) {
    return null;
  }
  return value;
}

function formatRelay(relay: any): string | null {
  if (!relay || typeof relay !== "object") return null;
  const name = typeof relay.name === "string" ? relay.name.trim() : "";
  const address = relay.address_label ?? formatAddress(relay.address);
  if (name && address) return `${name} - ${address}`;
  return name || address || null;
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
  const [overrideNotes, setOverrideNotes] = React.useState("");
  const [overrideError, setOverrideError] = React.useState<string | null>(null);
  const [incidentOpen, setIncidentOpen] = React.useState(false);
  const [selectedStatus, setSelectedStatus] = React.useState("created");
  const [incidentAction, setIncidentAction] = React.useState<
    "reassign" | "return" | "cancel"
  >("reassign");
  const [photoOpen, setPhotoOpen] = React.useState(false);
  const [reassignOpen, setReassignOpen] = React.useState(false);
  const [reassignDriverId, setReassignDriverId] = React.useState("");
  const [reassignMode, setReassignMode] = React.useState<
    "normal" | "driver_debt" | "platform_sponsored"
  >("normal");
  const [selectedRouteMissionId, setSelectedRouteMissionId] = React.useState<
    string | null
  >(null);

  const driversForReassign = useQuery({
    queryKey: ["drivers-list"],
    queryFn: () => fetchDrivers(),
    enabled: reassignOpen,
  });

  const confirmPayMut = useMutation({
    mutationFn: () => confirmPayment(id),
    onSuccess: () => {
      invalidate();
      toast("Paiement confirmé.");
    },
  });

  const overridePayMut = useMutation({
    mutationFn: (reason: string) => paymentOverride(id, reason),
    onSuccess: () => {
      invalidate();
      toast("Blocage paiement levé.");
    },
  });

  const suspendMut = useMutation({
    mutationFn: () => suspendParcel(id),
    onSuccess: () => {
      invalidate();
      toast("Colis suspendu.");
    },
  });

  const unsuspendMut = useMutation({
    mutationFn: (toStatus: string) => unsuspendParcel(id, toStatus),
    onSuccess: () => {
      invalidate();
      toast("Suspension levée.");
    },
  });

  const overrideMut = useMutation({
    mutationFn: ({ status, notes }: { status: string; notes: string }) =>
      overrideParcelStatus(id, status, notes),
    onSuccess: () => {
      invalidate();
      toast("Statut forcé.");
    },
  });

  const incidentMut = useMutation({
    mutationFn: ({
      action,
      notes,
    }: {
      action: "reassign" | "return" | "cancel";
      notes: string;
    }) => resolveIncident(id, action, notes),
    onSuccess: () => {
      invalidate();
      toast("Incident résolu.");
    },
  });

  const reassignMut = useMutation({
    mutationFn: ({
      missionId,
      driverId,
      assignmentMode,
    }: {
      missionId: string;
      driverId: string;
      assignmentMode: "normal" | "driver_debt" | "platform_sponsored";
    }) => reassignMission(missionId, driverId, assignmentMode),
    onSuccess: () => {
      invalidate();
      toast("Mission reaffectee.");
      setReassignOpen(false);
      setReassignDriverId("");
      setReassignMode("normal");
    },
  });

  const routeMissions = React.useMemo<ParcelMission[]>(() => {
    const missions = Array.isArray(audit.data?.missions)
      ? audit.data.missions
      : [];
    return missions.filter((mission: ParcelMission) => {
      const trail = Array.isArray(mission.gps_trail) ? mission.gps_trail : [];
      return (
        trail.some((point) => readLatLng(point)) ||
        Boolean(mission.encoded_polyline) ||
        Boolean(readLatLng(mission.pickup?.geopin)) ||
        Boolean(readLatLng(mission.delivery?.geopin))
      );
    });
  }, [audit.data?.missions]);

  const selectedRouteMission =
    routeMissions.find(
      (mission) =>
        mission.mission_id &&
        selectedRouteMissionId &&
        mission.mission_id === selectedRouteMissionId,
    ) ??
    routeMissions[0] ??
    null;
  const assignableMission = React.useMemo(() => {
    const missions = Array.isArray(audit.data?.missions) ? audit.data.missions : [];
    const statuses = ["assigned", "pending", "incident_reported"];
    for (const status of statuses) {
      const mission = missions.find((item: any) => item.status === status);
      if (mission) return mission;
    }
    return null;
  }, [audit.data?.missions]);

  const selectedTrail =
    selectedRouteMission?.gps_trail
      ?.map(readLatLng)
      .filter((point): point is { lat: number; lng: number } => point !== null) ??
    [];
  const selectedDriver = readLatLng(selectedRouteMission?.driver_location);
  const selectedPickup = readLatLng(selectedRouteMission?.pickup?.geopin);
  const selectedDelivery = readLatLng(selectedRouteMission?.delivery?.geopin);
  const driverToPickupDistance = distanceBetweenMeters(
    selectedDriver,
    selectedPickup,
  );
  const driverToDeliveryDistance = distanceBetweenMeters(
    selectedDriver,
    selectedDelivery,
  );
  const selectedRouteLocationUpdatedAt =
    selectedRouteMission?.route_summary?.last_seen_at ??
    selectedRouteMission?.driver_location?.ts ??
    null;
  const selectedRouteSignal = resolveLocationSignal({
    hasLocation: selectedDriver != null,
    updatedAt: selectedRouteLocationUpdatedAt,
  });
  const selectedMapCenter =
    selectedDriver ??
    selectedTrail[0] ??
    selectedPickup ??
    selectedDelivery ??
    DEFAULT_MAP_CENTER;
  const mapsApiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY ?? "";

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
  const parcelPhotoUrl = parcel.parcel_photo_url?.trim();

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
            {MODE_LABELS[parcel.delivery_mode] ?? parcel.delivery_mode} • Créé
            le {formatDate(parcel.created_at)} • ID: {parcel.parcel_id}
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="flex flex-wrap gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={() => setConfirmPayOpen(true)}
        >
          <CreditCard className="h-4 w-4" />
          Confirmer paiement
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={() => setOverridePayOpen(true)}
        >
          <CheckCircle2 className="h-4 w-4" />
          Lever blocage paiement
        </Button>
        {parcel.status !== "suspended" ? (
          <Button
            variant="destructive"
            size="sm"
            onClick={() => setSuspendOpen(true)}
          >
            <Ban className="h-4 w-4" />
            Suspendre
          </Button>
        ) : (
          <Button
            variant="outline"
            size="sm"
            onClick={() => setUnsuspendOpen(true)}
          >
            <Play className="h-4 w-4" />
            Lever suspension
          </Button>
        )}
        {parcel.status === "incident_reported" && (
          <Button
            variant="outline"
            size="sm"
            onClick={() => setIncidentOpen(true)}
          >
            <ShieldAlert className="h-4 w-4" />
            Résoudre incident
          </Button>
        )}
        {assignableMission && (
          <Button
            variant="outline"
            size="sm"
            onClick={() => setReassignOpen(true)}
          >
            <RefreshCw className="h-4 w-4" />
            {parcel.assigned_driver_id
              ? "Reassigner mission"
              : "Assigner un livreur"}
          </Button>
        )}
        <Button
          variant="outline"
          size="sm"
          onClick={() => setOverrideOpen(true)}
        >
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
            <Row
              label="Destinataire"
              value={parcel.recipient_name ?? parcel.recipient_phone ?? "—"}
            />
            <Row
              label="Tél. destinataire"
              value={parcel.recipient_phone ?? "—"}
            />
            <Row label="Créé le" value={formatDate(parcel.created_at)} />
            <Row
              label="Mode"
              value={MODE_LABELS[parcel.delivery_mode] ?? "—"}
            />
            {parcel.is_express && <Row label="Express" value="Oui" />}
            {parcel.weight_kg != null && (
              <Row label="Poids" value={`${parcel.weight_kg} kg`} />
            )}
            {parcel.description && (
              <Row label="Description" value={parcel.description} />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Photo du colis</CardTitle>
          </CardHeader>
          <CardContent>
            {parcelPhotoUrl ? (
              <button
                type="button"
                onClick={() => setPhotoOpen(true)}
                className="group flex w-full items-center gap-4 rounded-md border bg-muted/30 p-3 text-left transition hover:bg-muted"
              >
                <SecureProfileImage
                  src={parcelPhotoUrl}
                  alt="Photo du colis"
                  className="h-24 w-24 rounded-md"
                  fallbackClassName="rounded-md"
                />
                <div className="min-w-0">
                  <div className="font-medium">Photo de sécurité</div>
                  <div className="mt-1 text-sm text-muted-foreground">
                    Cliquer pour agrandir
                  </div>
                </div>
              </button>
            ) : (
              <div className="rounded-md border border-dashed p-4 text-sm text-muted-foreground">
                Aucune photo disponible.
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Paiement</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row
              label="Prix devis"
              value={
                parcel.quoted_price
                  ? `${xof.format(parcel.quoted_price)} XOF`
                  : "—"
              }
            />
            <Row
              label="Prix payé"
              value={
                parcel.paid_price ? `${xof.format(parcel.paid_price)} XOF` : "—"
              }
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
            <Row
              label="Relais origine"
              value={
                formatRelay(parcel.origin_relay) ??
                parcel.origin_relay_id ??
                "—"
              }
            />
            <Row
              label="Relais destination"
              value={
                formatRelay(parcel.destination_relay) ??
                parcel.destination_relay_id ??
                "—"
              }
            />
            <Row
              label="Relais de repli"
              value={
                formatRelay(parcel.redirect_relay) ??
                parcel.redirect_relay_id ??
                "—"
              }
            />
            <Row
              label="Relais de transit"
              value={
                formatRelay(parcel.transit_relay) ??
                parcel.transit_relay_id ??
                "—"
              }
            />
            {parcel.relay_pin && (
              <Row label="PIN relais" value={parcel.relay_pin} />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Adresses</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row
              label="Adresse expéditeur"
              value={
                formatAddressSummary(parcel.origin_location) ??
                formatAddressLabel(
                  parcel.origin_address_label,
                  parcel.origin_location,
                ) ??
                parcel.active_pickup_label ??
                "—"
              }
            />
            <Row
              label="Adresse destinataire"
              value={
                formatAddressSummary(parcel.delivery_address) ??
                formatAddressLabel(
                  parcel.destination_address_label,
                  parcel.delivery_address,
                ) ??
                parcel.active_delivery_label ??
                "—"
              }
            />
            <Row
              label="Point de collecte actif"
              value={
                formatGeoPin(parcel.active_pickup_geopin) ??
                formatGeoPin(parcel.origin_location?.geopin) ??
                "—"
              }
            />
            <Row
              label="Point de livraison actif"
              value={
                formatGeoPin(parcel.active_delivery_geopin) ??
                formatGeoPin(parcel.delivery_address?.geopin) ??
                "—"
              }
            />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Codes et accès</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row label="Code de collecte" value={parcel.pickup_code ?? "—"} />
            <Row
              label="Code de livraison"
              value={parcel.delivery_code ?? "—"}
            />
            <Row label="Code retrait relais" value={parcel.relay_pin ?? "—"} />
            <Row
              label="Code de retour expéditeur"
              value={parcel.return_code ?? "—"}
            />
            <Row
              label="Lien destinataire"
              value={parcel.recipient_confirm_url ?? "—"}
            />
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
            <Row
              label="Revenus livreur"
              value={
                parcel.earn_amount
                  ? `${xof.format(parcel.earn_amount)} XOF`
                  : "—"
              }
            />
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Route className="h-4 w-4" />
            Tracé du parcours
          </CardTitle>
        </CardHeader>
        <CardContent>
          {audit.isLoading ? (
            <div className="flex h-32 items-center justify-center">
              <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
            </div>
          ) : routeMissions.length === 0 ? (
            <div className="rounded-md border border-dashed p-4 text-sm text-muted-foreground">
              Aucun tracé GPS enregistré pour ce colis.
            </div>
          ) : !mapsApiKey ? (
            <div className="rounded-md border border-amber-200 bg-amber-50 p-4 text-sm text-amber-700">
              Clé Google Maps manquante pour afficher le tracé.
            </div>
          ) : (
            <div className="space-y-3">
              {routeMissions.length > 1 && (
                <div className="flex flex-wrap gap-2">
                  {routeMissions.map((mission, index) => (
                    <Button
                      key={mission.mission_id ?? index}
                      type="button"
                      variant={
                        selectedRouteMission?.mission_id === mission.mission_id
                          ? "default"
                          : "outline"
                      }
                      size="sm"
                      onClick={() =>
                        setSelectedRouteMissionId(mission.mission_id ?? null)
                      }
                    >
                      {missionRouteLabel(mission, index)}
                    </Button>
                  ))}
                </div>
              )}
              <div className="overflow-hidden rounded-md border">
                <div className="h-[420px] w-full">
                  <APIProvider apiKey={mapsApiKey}>
                    <Map
                      key={selectedRouteMission?.mission_id ?? "parcel-route"}
                      mapId={MAP_ID}
                      defaultCenter={selectedMapCenter}
                      defaultZoom={13}
                      gestureHandling="greedy"
                      disableDefaultUI={false}
                    >
                      {selectedRouteMission?.encoded_polyline && (
                        <Polyline
                          encodedPath={selectedRouteMission.encoded_polyline}
                          strokeColor="#64748b"
                          strokeOpacity={0.45}
                          strokeWeight={4}
                          zIndex={10}
                        />
                      )}
                      {selectedTrail.length > 1 && (
                        <Polyline
                          path={selectedTrail}
                          strokeColor="#0f766e"
                          strokeOpacity={0.95}
                          strokeWeight={5}
                          zIndex={20}
                        />
                      )}
                      {selectedPickup && (
                        <AdvancedMarker position={selectedPickup}>
                          <Pin
                            background="#f97316"
                            borderColor="#c2410c"
                            glyphColor="#fff"
                          />
                        </AdvancedMarker>
                      )}
                      {selectedDelivery && (
                        <AdvancedMarker position={selectedDelivery}>
                          <Pin
                            background="#10b981"
                            borderColor="#047857"
                            glyphColor="#fff"
                          />
                        </AdvancedMarker>
                      )}
                      {selectedDriver && (
                        <AdvancedMarker position={selectedDriver}>
                          <Pin
                            background="#2563eb"
                            borderColor="#1d4ed8"
                            glyphColor="#fff"
                          />
                        </AdvancedMarker>
                      )}
                    </Map>
                  </APIProvider>
                </div>
              </div>
              <div className="grid gap-2 text-sm sm:grid-cols-2 lg:grid-cols-4">
                <Row
                  label="Livreur"
                  value={selectedRouteMission?.driver_name ?? "—"}
                />
                <Row label="Etat GPS" value={selectedRouteSignal.label} />
                <Row
                  label="Position live"
                  value={
                    selectedDriver
                      ? `${selectedDriver.lat.toFixed(5)}, ${selectedDriver.lng.toFixed(5)}`
                      : "—"
                  }
                />
                <Row
                  label="Vers l'expéditeur"
                  value={formatDistanceMeters(driverToPickupDistance)}
                />
                <Row
                  label="Vers le destinataire"
                  value={formatDistanceMeters(driverToDeliveryDistance)}
                />
                <Row
                  label="Fraicheur signal"
                  value={formatLocationRelativeTime(selectedRouteLocationUpdatedAt)}
                />
                <Row
                  label="Points GPS"
                  value={
                    selectedRouteMission?.route_summary?.gps_points_count ??
                    selectedTrail.length
                  }
                />
                <Row
                  label="Début"
                  value={formatDate(
                    selectedRouteMission?.started_at ??
                      selectedRouteMission?.assigned_at,
                  )}
                />
                <Row
                  label="Fin"
                  value={formatDate(selectedRouteMission?.completed_at)}
                />
              </div>
            </div>
          )}
        </CardContent>
      </Card>

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
                      <Badge
                        tone={
                          STATUS_TONE[ev.new_status ?? ev.status] ?? "default"
                        }
                      >
                        {(ev.event_type ?? ev.new_status ?? "").replace(
                          /_/g,
                          " ",
                        )}
                      </Badge>
                      <span className="text-xs text-muted-foreground">
                        {formatDate(ev.created_at)}
                      </span>
                    </div>
                    {ev.notes && (
                      <div className="mt-0.5 text-xs text-muted-foreground">
                        {ev.notes}
                      </div>
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
                <div key={i} className="rounded-md border p-3 text-sm">
                  <div className="flex items-center justify-between">
                    <Badge tone="info">
                      {ev.event_type?.replace(/_/g, " ")}
                    </Badge>
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
                    <div className="mt-1 text-xs text-muted-foreground">
                      {ev.notes}
                    </div>
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
        onConfirm={async () => {
          await confirmPayMut.mutateAsync();
        }}
      />

      {photoOpen && parcelPhotoUrl && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-6">
          <div className="w-full max-w-4xl rounded-lg bg-background p-4 shadow-xl">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-base font-semibold">Photo du colis</h2>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setPhotoOpen(false)}
              >
                Fermer
              </Button>
            </div>
            <SecureProfileImage
              src={parcelPhotoUrl}
              alt="Photo du colis"
              className="max-h-[72vh] w-full rounded-md object-contain"
              fallbackClassName="h-[50vh] rounded-md"
            />
          </div>
        </div>
      )}

      <ActionModal
        open={overridePayOpen}
        onOpenChange={setOverridePayOpen}
        title="Lever le blocage paiement"
        description="Le colis pourra continuer son parcours même sans paiement confirmé."
        inputLabel="Motif"
        inputPlaceholder="Ex: paiement reçu hors-ligne, webhook échoué…"
        inputType="textarea"
        confirmLabel="Lever blocage"
        onConfirm={async (reason) => {
          await overridePayMut.mutateAsync(reason);
        }}
      />

      <ConfirmModal
        open={suspendOpen}
        onOpenChange={setSuspendOpen}
        title="Suspendre ce colis"
        description="Toutes les actions (collecte, livraison) seront bloquées."
        confirmLabel="Suspendre"
        confirmVariant="destructive"
        onConfirm={async () => {
          await suspendMut.mutateAsync();
        }}
      />

      {unsuspendOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="w-full max-w-sm rounded-lg border bg-background p-6 shadow-lg">
            <h3 className="mb-2 text-lg font-semibold">Lever la suspension</h3>
            <p className="mb-4 text-sm text-muted-foreground">
              Choisir le statut de destination :
            </p>
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
              <Button
                variant="outline"
                size="sm"
                onClick={() => setUnsuspendOpen(false)}
              >
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
                {unsuspendMut.isPending && (
                  <Loader2 className="h-4 w-4 animate-spin" />
                )}
                Confirmer
              </Button>
            </div>
          </div>
        </div>
      )}

      {overrideOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="w-full max-w-md rounded-lg border bg-background p-6 shadow-lg">
            <h3 className="mb-2 text-lg font-semibold">
              Forcer un changement de statut
            </h3>
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
              value={overrideNotes}
              onChange={(e) => {
                setOverrideNotes(e.target.value);
                if (overrideError) setOverrideError(null);
              }}
              className="mb-2 w-full rounded-md border p-2 text-sm"
              rows={2}
              placeholder="Motif de l'intervention (3 caractères minimum)…"
            />
            {overrideError && (
              <div className="mb-3 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
                {overrideError}
              </div>
            )}
            <div className="flex justify-end gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={() => {
                  setOverrideOpen(false);
                  setOverrideError(null);
                  setOverrideNotes("");
                }}
              >
                Annuler
              </Button>
              <Button
                size="sm"
                variant="destructive"
                disabled={overrideMut.isPending}
                onClick={async () => {
                  const notes = overrideNotes.trim();
                  if (notes.length < 3) {
                    setOverrideError(
                      "Le motif doit contenir au moins 3 caractères.",
                    );
                    return;
                  }
                  try {
                    await overrideMut.mutateAsync({
                      status: selectedStatus,
                      notes,
                    });
                    setOverrideOpen(false);
                    setOverrideError(null);
                    setOverrideNotes("");
                  } catch (err: any) {
                    setOverrideError(
                      err?.response?.data?.detail ??
                        "Erreur lors du forçage du statut.",
                    );
                  }
                }}
              >
                {overrideMut.isPending && (
                  <Loader2 className="h-4 w-4 animate-spin" />
                )}
                Forcer
              </Button>
            </div>
          </div>
        </div>
      )}

      {reassignOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="w-full max-w-md rounded-lg border bg-background p-6 shadow-lg">
            <h3 className="mb-2 text-lg font-semibold">
              {parcel.assigned_driver_id
                ? "Reassigner la mission"
                : "Assigner un livreur"}
            </h3>
            <p className="mb-3 text-sm text-muted-foreground">
              {parcel.assigned_driver_id ? "Choisir un nouveau livreur pour ce colis." : "Choisir un livreur pour attribuer ce colis."}
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
                    {d.name ?? d.full_name ?? d.phone} — {d.missions_count ?? 0}{" "}
                    missions
                  </option>
                ))}
            </select>
            <select
              value={reassignMode}
              onChange={(e) =>
                setReassignMode(
                  e.target.value as
                    | "normal"
                    | "driver_debt"
                    | "platform_sponsored",
                )
              }
              className="mb-3 flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            >
              <option value="normal">Flux normal (solde requis)</option>
              <option value="driver_debt">Forcer avec dette livreur</option>
              <option value="platform_sponsored">
                Commission offerte par Denkma
              </option>
            </select>
            <p className="mb-4 text-sm text-muted-foreground">
              En mode normal, le livreur reçoit la mission, peut l'accepter ou
              la refuser, et doit recharger si son solde est insuffisant.
            </p>
            <div className="flex justify-end gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={() => {
                  setReassignOpen(false);
                  setReassignMode("normal");
                }}
              >
                Annuler
              </Button>
              <Button
                size="sm"
                disabled={!reassignDriverId || reassignMut.isPending}
                onClick={async () => {
                  const activeMission = assignableMission;
                  if (!activeMission) {
                    toast("Aucune mission eligible trouvee.", "error");
                    return;
                  }
                  await reassignMut.mutateAsync({
                    missionId: activeMission.mission_id,
                    driverId: reassignDriverId,
                    assignmentMode: reassignMode,
                  });
                }}
              >
                {reassignMut.isPending && (
                  <Loader2 className="h-4 w-4 animate-spin" />
                )}
                {parcel.assigned_driver_id ? "Reassigner" : "Assigner"}
              </Button>
            </div>
            {reassignMut.isError && (
              <div className="mt-3 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
                {(reassignMut.error as any)?.response?.data?.detail ??
                  "Erreur lors de l'assignation."}
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
                  {a === "reassign"
                    ? "Réassigner"
                    : a === "return"
                      ? "Retour envoyeur"
                      : "Annuler"}
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
              <Button
                variant="outline"
                size="sm"
                onClick={() => setIncidentOpen(false)}
              >
                Annuler
              </Button>
              <Button
                size="sm"
                disabled={incidentMut.isPending}
                onClick={async () => {
                  const notes =
                    (
                      document.getElementById(
                        "incident-notes",
                      ) as HTMLTextAreaElement
                    )?.value ?? "";
                  await incidentMut.mutateAsync({
                    action: incidentAction,
                    notes: notes.trim(),
                  });
                  setIncidentOpen(false);
                }}
              >
                {incidentMut.isPending && (
                  <Loader2 className="h-4 w-4 animate-spin" />
                )}
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
