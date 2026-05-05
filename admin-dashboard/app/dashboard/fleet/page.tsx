"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import {
  APIProvider,
  AdvancedMarker,
  InfoWindow,
  Map,
  Pin,
} from "@vis.gl/react-google-maps";
import { fetchFleetLive } from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Loader2, MapPin, Navigation, Phone, RadioTower } from "lucide-react";

type GeoPoint = {
  lat?: number;
  lng?: number;
  latitude?: number;
  longitude?: number;
};

type FleetMission = {
  mission_id: string;
  parcel_id?: string;
  tracking_code?: string;
  status?: string;
  parcel_status?: string;
  delivery_mode?: string;
  driver_id?: string;
  driver_name?: string;
  driver_phone?: string;
  driver_photo_url?: string;
  driver_location?: GeoPoint | null;
  location_updated_at?: string;
  location_source?: string | null;
  is_stale?: boolean;
  eta_text?: string;
  distance_text?: string;
  recipient_name?: string;
  recipient_phone?: string;
  pickup?: { label?: string | null };
  delivery?: { label?: string | null };
  route_summary?: {
    speed_kmh?: number;
    gps_points_count?: number;
  };
};

type IdleDriver = {
  driver_id: string;
  driver_name?: string;
  driver_phone?: string;
  driver_photo_url?: string;
  driver_location?: GeoPoint | null;
  location_updated_at?: string;
};

type SelectedPin =
  | { kind: "mission"; data: FleetMission }
  | { kind: "idle"; data: IdleDriver }
  | null;

const FILTERS = [
  { value: "all", label: "Toutes les missions" },
  { value: "live", label: "Positions live" },
  { value: "signal_lost", label: "Signal perdu" },
  { value: "idle", label: "Hors course" },
] as const;

const DEFAULT_MAP_CENTER = {
  lat: Number(process.env.NEXT_PUBLIC_DEFAULT_MAP_LAT ?? "14.7167"),
  lng: Number(process.env.NEXT_PUBLIC_DEFAULT_MAP_LNG ?? "-17.4677"),
};
const MAP_ID = process.env.NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID ?? "denkma-fleet-map";

function fmtTime(iso?: string) {
  if (!iso) return "—";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "—";
  return `${date.getHours().toString().padStart(2, "0")}:${date
    .getMinutes()
    .toString()
    .padStart(2, "0")}`;
}

function relativeTime(iso?: string) {
  if (!iso) return "aucune position";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "date invalide";
  const minutes = Math.max(0, Math.round((Date.now() - date.getTime()) / 60000));
  if (minutes < 1) return "à l’instant";
  if (minutes < 60) return `il y a ${minutes} min`;
  return `il y a ${Math.round(minutes / 60)} h`;
}

function readLatLng(point?: GeoPoint | null) {
  if (!point) return null;
  const lat = point.lat ?? point.latitude;
  const lng = point.lng ?? point.longitude;
  if (lat == null || lng == null) return null;
  return { lat, lng };
}

function statusTone(status?: string) {
  if (status === "in_progress") return "success";
  if (status === "assigned") return "info";
  if (status === "incident_reported") return "danger";
  return "default";
}

function statusLabel(mission: FleetMission) {
  if (mission.is_stale) return "Signal perdu";
  if (mission.status === "in_progress") return "En course";
  if (mission.status === "assigned") return "Assignée";
  if (mission.status === "incident_reported") return "Incident";
  return mission.status ?? "—";
}

function pinColors(mission: FleetMission) {
  if (mission.is_stale) {
    return { background: "#f59e0b", border: "#b45309", glyph: "#fff" };
  }
  if (mission.status === "in_progress") {
    return { background: "#16a34a", border: "#15803d", glyph: "#fff" };
  }
  if (mission.status === "incident_reported") {
    return { background: "#dc2626", border: "#991b1b", glyph: "#fff" };
  }
  return { background: "#2563eb", border: "#1d4ed8", glyph: "#fff" };
}

export default function FleetPage() {
  const searchParams = useSearchParams();
  const selectedFilter = searchParams.get("filter") ?? "all";
  const [selectedPin, setSelectedPin] = useState<SelectedPin>(null);

  const { data, isLoading, isError } = useQuery({
    queryKey: ["fleet-live"],
    queryFn: fetchFleetLive,
    refetchInterval: 15_000,
  });

  const missions: FleetMission[] = data?.fleet ?? [];
  const idleDrivers: IdleDriver[] = data?.idle_drivers ?? [];
  const summary = data?.summary ?? {};
  const mapsApiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY ?? "";

  const filteredMissions = useMemo(() => {
    if (selectedFilter === "live") {
      return missions.filter((mission) => {
        const location = readLatLng(mission.driver_location);
        return Boolean(location && !mission.is_stale);
      });
    }
    if (selectedFilter === "signal_lost") {
      return missions.filter(
        (mission) =>
          mission.is_stale &&
          ["assigned", "in_progress"].includes(mission.status ?? "")
      );
    }
    if (selectedFilter === "idle") return [];
    return missions;
  }, [missions, selectedFilter]);

  const filteredIdle = useMemo(() => {
    if (selectedFilter === "idle" || selectedFilter === "all") return idleDrivers;
    return [];
  }, [idleDrivers, selectedFilter]);

  const activeFilter =
    FILTERS.find((filter) => filter.value === selectedFilter) ?? FILTERS[0];

  const mapCenter = useMemo(() => {
    const first = filteredMissions
      .map((mission) => readLatLng(mission.driver_location))
      .find((point): point is { lat: number; lng: number } => point !== null);
    if (first) return first;
    const firstIdle = filteredIdle
      .map((driver) => readLatLng(driver.driver_location))
      .find((point): point is { lat: number; lng: number } => point !== null);
    return firstIdle ?? DEFAULT_MAP_CENTER;
  }, [filteredMissions, filteredIdle]);

  const totalVisible = filteredMissions.length + filteredIdle.length;

  return (
    <div className="space-y-5 p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Flotte live</h1>
          <p className="text-sm text-muted-foreground">
            Positions GPS temps réel des livreurs en mission et hors mission.
            Cliquez sur un marqueur pour voir le livreur, la course et l’état du signal.
          </p>
        </div>
        <div className="text-sm text-muted-foreground">
          {totalVisible} résultat{totalVisible > 1 ? "s" : ""}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
        <KpiTile label="Actives" value={summary.total_active ?? 0} color="blue" />
        <KpiTile label="Avec GPS" value={summary.with_live_location ?? 0} color="green" />
        <KpiTile label="Signal faible" value={summary.stale_locations ?? 0} color="orange" />
        <KpiTile label="Sans position" value={summary.missing_locations ?? 0} color="red" />
        <KpiTile label="Hors course" value={summary.idle_drivers ?? 0} color="purple" />
      </div>

      <div className="flex flex-wrap gap-2">
        {FILTERS.map((filter) => (
          <Link
            key={filter.value}
            href={`/dashboard/fleet${filter.value === "all" ? "" : `?filter=${filter.value}`}`}
            className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
              activeFilter.value === filter.value
                ? "border-primary bg-primary text-primary-foreground"
                : "border-input bg-background hover:bg-accent"
            }`}
          >
            {filter.label}
          </Link>
        ))}
      </div>

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement de la flotte.
        </div>
      )}

      {!mapsApiKey ? (
        <Card>
          <CardContent className="p-6 text-sm text-amber-700">
            Clé Google Maps manquante : définissez{" "}
            <code className="rounded bg-amber-100 px-1 py-0.5 text-xs">
              NEXT_PUBLIC_GOOGLE_MAPS_KEY
            </code>{" "}
            dans l’environnement du dashboard pour afficher la carte.
          </CardContent>
        </Card>
      ) : (
        <div className="overflow-hidden rounded-xl border bg-white">
          <div className="h-[520px] w-full">
            <APIProvider apiKey={mapsApiKey}>
              <Map
                mapId={MAP_ID}
                defaultCenter={mapCenter}
                defaultZoom={12}
                gestureHandling="greedy"
                disableDefaultUI={false}
              >
                {filteredMissions.map((mission) => {
                  const location = readLatLng(mission.driver_location);
                  if (!location) return null;
                  const colors = pinColors(mission);
                  return (
                    <AdvancedMarker
                      key={`mission:${mission.mission_id}`}
                      position={location}
                      onClick={() => setSelectedPin({ kind: "mission", data: mission })}
                    >
                      <Pin
                        background={colors.background}
                        borderColor={colors.border}
                        glyphColor={colors.glyph}
                      />
                    </AdvancedMarker>
                  );
                })}

                {filteredIdle.map((driver) => {
                  const location = readLatLng(driver.driver_location);
                  if (!location) return null;
                  return (
                    <AdvancedMarker
                      key={`idle:${driver.driver_id}`}
                      position={location}
                      onClick={() => setSelectedPin({ kind: "idle", data: driver })}
                    >
                      <Pin background="#8b5cf6" borderColor="#6d28d9" glyphColor="#fff" />
                    </AdvancedMarker>
                  );
                })}

                {selectedPin && (
                  <InfoWindow
                    position={readLatLng(selectedPin.data.driver_location) ?? undefined}
                    onCloseClick={() => setSelectedPin(null)}
                  >
                    {selectedPin.kind === "mission" ? (
                      <MissionPopup mission={selectedPin.data} />
                    ) : (
                      <IdlePopup driver={selectedPin.data} />
                    )}
                  </InfoWindow>
                )}
              </Map>
            </APIProvider>
          </div>
        </div>
      )}

      {totalVisible === 0 && !isLoading && (
        <Card>
          <CardContent className="p-10 text-center text-sm text-muted-foreground">
            Aucun résultat pour ce filtre.
          </CardContent>
        </Card>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {filteredMissions.map((mission) => (
          <MissionCard key={mission.mission_id} mission={mission} />
        ))}
        {filteredIdle.map((driver) => (
          <IdleDriverCard key={`idle-${driver.driver_id}`} driver={driver} />
        ))}
      </div>
    </div>
  );
}

function KpiTile({
  label,
  value,
  color,
}: {
  label: string;
  value: number | string;
  color: "blue" | "green" | "orange" | "red" | "purple";
}) {
  const palette: Record<typeof color, string> = {
    blue: "bg-blue-50 border-blue-200 text-blue-700",
    green: "bg-green-50 border-green-200 text-green-700",
    orange: "bg-orange-50 border-orange-200 text-orange-700",
    red: "bg-red-50 border-red-200 text-red-700",
    purple: "bg-purple-50 border-purple-200 text-purple-700",
  };
  return (
    <div className={`rounded-xl border p-3 ${palette[color]}`}>
      <div className="text-xs font-semibold">{label}</div>
      <div className="mt-1 text-2xl font-bold text-foreground">{value}</div>
    </div>
  );
}

function MissionCard({ mission }: { mission: FleetMission }) {
  const location = readLatLng(mission.driver_location);
  return (
    <Card>
      <CardContent className="p-5">
        <div className="flex items-start justify-between gap-2">
          <div>
            <div className="font-medium">{mission.driver_name ?? "—"}</div>
            <div className="text-xs text-muted-foreground">
              {mission.driver_id ?? "Livreur non renseigné"}
            </div>
          </div>
          <Badge tone={statusTone(mission.status)}>{statusLabel(mission)}</Badge>
        </div>

        {mission.tracking_code && (
          <div className="mt-2 text-xs text-muted-foreground">
            Colis : <span className="font-mono">{mission.tracking_code}</span>
          </div>
        )}

        {mission.recipient_name && (
          <div className="mt-1 text-xs text-muted-foreground">
            Destinataire : {mission.recipient_name}
          </div>
        )}

        {(mission.pickup?.label || mission.delivery?.label) && (
          <div className="mt-2 space-y-1 text-xs text-muted-foreground">
            {mission.pickup?.label && <div>Départ : {mission.pickup.label}</div>}
            {mission.delivery?.label && <div>Arrivée : {mission.delivery.label}</div>}
          </div>
        )}

        <div className="mt-3 flex flex-wrap items-center gap-4 text-xs text-muted-foreground">
          {location ? (
            <span className="inline-flex items-center gap-1">
              <MapPin className="h-3.5 w-3.5" />
              {location.lat.toFixed(4)}, {location.lng.toFixed(4)}
            </span>
          ) : (
            <span className="inline-flex items-center gap-1 text-amber-700">
              <RadioTower className="h-3.5 w-3.5" />
              Aucune position
            </span>
          )}
          {mission.route_summary?.speed_kmh != null && (
            <span className="inline-flex items-center gap-1">
              <Navigation className="h-3.5 w-3.5" />
              {mission.route_summary.speed_kmh} km/h
            </span>
          )}
        </div>

        {(mission.eta_text || mission.distance_text) && (
          <div className="mt-2 text-xs text-muted-foreground">
            {mission.distance_text ? `${mission.distance_text} · ` : ""}
            {mission.eta_text}
          </div>
        )}

        <div
          className={`mt-1 text-[11px] ${
            mission.is_stale ? "text-red-700" : "text-muted-foreground"
          }`}
        >
          Dernière mise à jour : {fmtTime(mission.location_updated_at)} ·{" "}
          {relativeTime(mission.location_updated_at)}
          {mission.is_stale ? " · signal perdu" : ""}
        </div>

        <div className="mt-3 flex flex-wrap gap-2 text-xs">
          {mission.driver_phone && (
            <a
              href={`tel:${mission.driver_phone}`}
              className="inline-flex items-center gap-1 rounded-md border px-2 py-1 hover:bg-accent"
            >
              <Phone className="h-3 w-3" /> Appeler
            </a>
          )}
          {mission.driver_id && (
            <Link
              href={`/dashboard/users/${mission.driver_id}`}
              className="rounded-md border px-2 py-1 hover:bg-accent"
            >
              Fiche livreur
            </Link>
          )}
          {mission.parcel_id && (
            <Link
              href={`/dashboard/parcels/${mission.parcel_id}`}
              className="rounded-md border px-2 py-1 hover:bg-accent"
            >
              Fiche colis
            </Link>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

function IdleDriverCard({ driver }: { driver: IdleDriver }) {
  const location = readLatLng(driver.driver_location);
  return (
    <Card className="border-purple-200 bg-purple-50/40">
      <CardContent className="p-5">
        <div className="flex items-start justify-between gap-2">
          <div>
            <div className="font-medium">{driver.driver_name ?? "—"}</div>
            <div className="text-xs text-muted-foreground">{driver.driver_id}</div>
          </div>
          <Badge tone="default">Hors course</Badge>
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-4 text-xs text-muted-foreground">
          {location ? (
            <span className="inline-flex items-center gap-1">
              <MapPin className="h-3.5 w-3.5" />
              {location.lat.toFixed(4)}, {location.lng.toFixed(4)}
            </span>
          ) : (
            <span className="inline-flex items-center gap-1 text-amber-700">
              <RadioTower className="h-3.5 w-3.5" />
              Aucune position
            </span>
          )}
        </div>

        <div className="mt-1 text-[11px] text-muted-foreground">
          Dernière mise à jour : {fmtTime(driver.location_updated_at)} ·{" "}
          {relativeTime(driver.location_updated_at)}
        </div>

        <div className="mt-3 flex flex-wrap gap-2 text-xs">
          {driver.driver_phone && (
            <a
              href={`tel:${driver.driver_phone}`}
              className="inline-flex items-center gap-1 rounded-md border px-2 py-1 hover:bg-accent"
            >
              <Phone className="h-3 w-3" /> Appeler
            </a>
          )}
          <Link
            href={`/dashboard/users/${driver.driver_id}`}
            className="rounded-md border px-2 py-1 hover:bg-accent"
          >
            Fiche livreur
          </Link>
        </div>
      </CardContent>
    </Card>
  );
}

function MissionPopup({ mission }: { mission: FleetMission }) {
  return (
    <div className="min-w-[240px] space-y-2 p-1 text-sm">
      <div className="font-semibold">{mission.driver_name ?? "Livreur"}</div>
      <div className="inline-block rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-700">
        {statusLabel(mission)}
      </div>
      {mission.driver_phone && (
        <div className="flex items-center gap-2">
          <Phone className="h-3.5 w-3.5 text-slate-500" />
          <a
            href={`tel:${mission.driver_phone}`}
            className="text-blue-600 underline-offset-2 hover:underline"
          >
            {mission.driver_phone}
          </a>
        </div>
      )}
      {mission.tracking_code && (
        <div className="text-xs text-slate-600">
          Colis : <span className="font-mono">{mission.tracking_code}</span>
        </div>
      )}
      {mission.recipient_name && (
        <div className="text-xs text-slate-600">
          Destinataire : {mission.recipient_name}
        </div>
      )}
      {mission.delivery?.label && (
        <div className="text-xs text-slate-600">Arrivée : {mission.delivery.label}</div>
      )}
      {(mission.eta_text || mission.distance_text) && (
        <div className="text-xs text-slate-600">
          {mission.distance_text ? `${mission.distance_text} · ` : ""}
          {mission.eta_text ?? ""}
        </div>
      )}
      <div className="text-xs text-slate-500">
        Dernière MAJ : {fmtTime(mission.location_updated_at)} ·{" "}
        {relativeTime(mission.location_updated_at)}
      </div>
      <div className="flex flex-wrap gap-2 pt-1">
        {mission.driver_id && (
          <Link
            href={`/dashboard/users/${mission.driver_id}`}
            className="rounded-md border px-2 py-1 text-xs hover:bg-accent"
          >
            Fiche livreur
          </Link>
        )}
        {mission.parcel_id && (
          <Link
            href={`/dashboard/parcels/${mission.parcel_id}`}
            className="rounded-md border px-2 py-1 text-xs hover:bg-accent"
          >
            Fiche colis
          </Link>
        )}
      </div>
    </div>
  );
}

function IdlePopup({ driver }: { driver: IdleDriver }) {
  return (
    <div className="min-w-[220px] space-y-2 p-1 text-sm">
      <div className="font-semibold">{driver.driver_name ?? "Livreur"}</div>
      <div className="inline-block rounded-full bg-purple-100 px-2 py-0.5 text-xs font-medium text-purple-700">
        Hors course
      </div>
      {driver.driver_phone && (
        <div className="flex items-center gap-2">
          <Phone className="h-3.5 w-3.5 text-slate-500" />
          <a
            href={`tel:${driver.driver_phone}`}
            className="text-blue-600 underline-offset-2 hover:underline"
          >
            {driver.driver_phone}
          </a>
        </div>
      )}
      <div className="text-xs text-slate-500">
        Dernière position : {fmtTime(driver.location_updated_at)} ·{" "}
        {relativeTime(driver.location_updated_at)}
      </div>
      <div className="flex flex-wrap gap-2 pt-1">
        <Link
          href={`/dashboard/users/${driver.driver_id}`}
          className="rounded-md border px-2 py-1 text-xs hover:bg-accent"
        >
          Fiche livreur
        </Link>
      </div>
    </div>
  );
}
