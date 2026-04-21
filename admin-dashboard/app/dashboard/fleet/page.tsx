"use client";

import { useMemo } from "react";
import { useSearchParams } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { fetchFleetLive } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Loader2, MapPin, Navigation, RadioTower } from "lucide-react";

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
  driver_id?: string;
  driver_name?: string;
  driver_phone?: string;
  driver_location?: GeoPoint | null;
  location_updated_at?: string;
  is_stale?: boolean;
  eta_text?: string;
  distance_text?: string;
  recipient_name?: string;
  route_summary?: {
    speed_kmh?: number;
  };
};

const FILTERS = [
  { value: "all", label: "Toutes les missions" },
  { value: "live", label: "Positions live" },
  { value: "signal_lost", label: "Signal perdu" },
] as const;

function fmtTime(iso?: string) {
  if (!iso) return "—";
  const date = new Date(iso);
  return `${date.getHours().toString().padStart(2, "0")}:${date
    .getMinutes()
    .toString()
    .padStart(2, "0")}`;
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

export default function FleetPage() {
  const searchParams = useSearchParams();
  const selectedFilter = searchParams.get("filter") ?? "all";

  const { data, isLoading, isError } = useQuery({
    queryKey: ["fleet-live"],
    queryFn: fetchFleetLive,
    refetchInterval: 15_000,
  });

  const missions: FleetMission[] = data?.fleet ?? [];
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
    return missions;
  }, [missions, selectedFilter]);

  const activeFilter =
    FILTERS.find((filter) => filter.value === selectedFilter) ?? FILTERS[0];

  return (
    <div className="space-y-5 p-8">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold">Flotte live</h1>
          <p className="text-sm text-muted-foreground">
            Positions GPS temps réel des livreurs en mission. Les filtres reprennent
            les mêmes critères que les cartes du tableau de bord.
          </p>
        </div>
        <div className="text-sm text-muted-foreground">
          {filteredMissions.length} résultat{filteredMissions.length > 1 ? "s" : ""}
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        {FILTERS.map((filter) => (
          <a
            key={filter.value}
            href={`/dashboard/fleet${filter.value === "all" ? "" : `?filter=${filter.value}`}`}
            className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
              activeFilter.value === filter.value
                ? "border-primary bg-primary text-primary-foreground"
                : "border-input bg-background hover:bg-accent"
            }`}
          >
            {filter.label}
          </a>
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

      {filteredMissions.length === 0 && !isLoading && (
        <Card>
          <CardContent className="p-10 text-center text-sm text-muted-foreground">
            Aucun résultat pour ce filtre.
          </CardContent>
        </Card>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {filteredMissions.map((mission) => {
          const location = readLatLng(mission.driver_location);
          return (
            <Card key={mission.mission_id}>
              <CardContent className="p-5">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <div className="font-medium">{mission.driver_name ?? "—"}</div>
                    <div className="text-xs text-muted-foreground">
                      {mission.driver_id ?? "Livreur non renseigné"}
                    </div>
                  </div>
                  <Badge tone={statusTone(mission.status)}>
                    {mission.status ?? "—"}
                  </Badge>
                </div>

                {mission.tracking_code && (
                  <div className="mt-2 text-xs text-muted-foreground">
                    Mission :{" "}
                    <span className="font-mono">{mission.tracking_code}</span>
                  </div>
                )}

                {mission.recipient_name && (
                  <div className="mt-1 text-xs text-muted-foreground">
                    Destinataire : {mission.recipient_name}
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
                  Dernière mise à jour : {fmtTime(mission.location_updated_at)}
                  {mission.is_stale ? " · signal perdu" : ""}
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>
    </div>
  );
}
