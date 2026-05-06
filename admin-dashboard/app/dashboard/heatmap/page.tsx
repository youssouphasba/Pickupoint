"use client";

import * as React from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import {
  APIProvider,
  AdvancedMarker,
  InfoWindow,
  Map,
} from "@vis.gl/react-google-maps";
import { fetchHeatmap } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Loader2,
  MapPin,
  PackageSearch,
  RadioTower,
  Route,
} from "lucide-react";
import { formatDate } from "@/lib/utils";

type HeatmapPointType =
  | "home_pickups"
  | "home_deliveries"
  | "relay_points"
  | "redirect_points"
  | "transit_points";

type HeatmapPointFilter = HeatmapPointType | "all";

type HeatmapParcel = {
  parcel_id?: string;
  tracking_code?: string;
  delivery_mode?: string;
  created_at?: string;
};

type HeatmapHotspot = {
  lat: number;
  lng: number;
  label?: string;
  count: number;
  type_counts?: Partial<Record<HeatmapPointType, number>>;
  parcels?: HeatmapParcel[];
  latest_created_at?: string;
};

type HeatmapSummary = {
  parcels_considered?: number;
  total_points?: number;
  home_pickups?: number;
  home_deliveries?: number;
  relay_points?: number;
  redirect_points?: number;
  transit_points?: number;
  days?: number;
  point_type?: HeatmapPointFilter;
};

const POINT_LABELS: Record<HeatmapPointType, string> = {
  home_pickups: "Collectes domicile",
  home_deliveries: "Livraisons domicile",
  relay_points: "Relais",
  redirect_points: "Redirections relais",
  transit_points: "Transit relais",
};

const POINT_FILTER_OPTIONS: { value: HeatmapPointFilter; label: string }[] = [
  { value: "all", label: "Tous les points" },
  { value: "home_pickups", label: POINT_LABELS.home_pickups },
  { value: "home_deliveries", label: POINT_LABELS.home_deliveries },
  { value: "relay_points", label: POINT_LABELS.relay_points },
  { value: "redirect_points", label: POINT_LABELS.redirect_points },
  { value: "transit_points", label: POINT_LABELS.transit_points },
];

const PERIOD_OPTIONS = [
  { value: 7, label: "7 derniers jours" },
  { value: 30, label: "30 derniers jours" },
  { value: 90, label: "90 derniers jours" },
  { value: 365, label: "12 derniers mois" },
  { value: 0, label: "Tout l’historique" },
];

const LIMIT_OPTIONS = [10, 20, 50, 100];
const DEFAULT_MAP_CENTER = {
  lat: Number(process.env.NEXT_PUBLIC_DEFAULT_MAP_LAT ?? "14.7167"),
  lng: Number(process.env.NEXT_PUBLIC_DEFAULT_MAP_LNG ?? "-17.4677"),
};
const MAP_ID = process.env.NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID ?? "denkma-heatmap";

const MODE_LABELS: Record<string, string> = {
  relay_to_relay: "Relais → Relais",
  relay_to_home: "Relais → Domicile",
  home_to_relay: "Domicile → Relais",
  home_to_home: "Domicile → Domicile",
};

function plural(value: number, singular: string, pluralLabel: string) {
  return `${value} ${value > 1 ? pluralLabel : singular}`;
}

function formatCoordinate(value?: number) {
  return typeof value === "number" ? value.toFixed(4) : "—";
}

function dominantType(hotspot: HeatmapHotspot) {
  const entries = Object.entries(hotspot.type_counts ?? {}) as [
    HeatmapPointType,
    number,
  ][];
  if (!entries.length) return null;
  return entries.sort((a, b) => b[1] - a[1])[0][0];
}

function summaryCards(summary: HeatmapSummary) {
  return [
    {
      label: "Colis pris en compte",
      value: summary.parcels_considered ?? 0,
      icon: PackageSearch,
      tone: "text-blue-700",
    },
    {
      label: "Points exploitables",
      value: summary.total_points ?? 0,
      icon: MapPin,
      tone: "text-emerald-700",
    },
    {
      label: "Points domicile",
      value: (summary.home_pickups ?? 0) + (summary.home_deliveries ?? 0),
      icon: Route,
      tone: "text-amber-700",
    },
    {
      label: "Points relais",
      value:
        (summary.relay_points ?? 0) +
        (summary.redirect_points ?? 0) +
        (summary.transit_points ?? 0),
      icon: RadioTower,
      tone: "text-purple-700",
    },
  ];
}

function periodLabel(days: number) {
  return (
    PERIOD_OPTIONS.find((option) => option.value === days)?.label ??
    `${days} jours`
  );
}

function HeatmapPopup({ hotspot }: { hotspot: HeatmapHotspot }) {
  const type = dominantType(hotspot);
  const label =
    hotspot.label ||
    `${formatCoordinate(hotspot.lat)}, ${formatCoordinate(hotspot.lng)}`;

  return (
    <div className="min-w-[260px] space-y-3 p-1 text-sm">
      <div>
        <div className="font-semibold text-slate-950">{label}</div>
        <div className="mt-1 text-xs text-slate-500">
          {formatCoordinate(hotspot.lat)}, {formatCoordinate(hotspot.lng)}
        </div>
      </div>
      <div className="flex flex-wrap gap-2">
        {type && (
          <span className="rounded-full bg-blue-100 px-2 py-0.5 text-xs font-medium text-blue-700">
            {POINT_LABELS[type]}
          </span>
        )}
        <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-700">
          {plural(hotspot.count, "point", "points")}
        </span>
      </div>
      {(hotspot.parcels?.length ?? 0) > 0 && (
        <div className="space-y-2">
          <div className="text-xs font-medium uppercase tracking-wide text-slate-500">
            Colis liés
          </div>
          <div className="space-y-1">
            {hotspot.parcels!.slice(0, 3).map((parcel) =>
              parcel.parcel_id ? (
                <Link
                  key={parcel.parcel_id}
                  href={`/dashboard/parcels/${parcel.parcel_id}`}
                  className="block rounded-md border border-slate-200 px-2 py-1 font-mono text-xs font-semibold text-blue-700 underline"
                >
                  {parcel.tracking_code ?? parcel.parcel_id}
                </Link>
              ) : (
                <div
                  key={parcel.tracking_code}
                  className="rounded-md border border-slate-200 px-2 py-1 font-mono text-xs font-semibold text-slate-700"
                >
                  {parcel.tracking_code ?? "Colis"}
                </div>
              ),
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export default function HeatmapPage() {
  const [days, setDays] = React.useState(30);
  const [pointType, setPointType] = React.useState<HeatmapPointFilter>("all");
  const [limit, setLimit] = React.useState(20);
  const [selectedHotspot, setSelectedHotspot] =
    React.useState<HeatmapHotspot | null>(null);

  const { data, isLoading, isError } = useQuery({
    queryKey: ["heatmap-rich", days, pointType, limit],
    queryFn: () =>
      fetchHeatmap({
        days,
        limit,
        point_type: pointType === "all" ? undefined : pointType,
      }),
  });

  const summary: HeatmapSummary = data?.summary ?? {};
  const hotspots: HeatmapHotspot[] = React.useMemo(
    () =>
      (data?.top_hotspots ?? [])
        .slice()
        .sort((a: HeatmapHotspot, b: HeatmapHotspot) => b.count - a.count),
    [data],
  );
  const selectedPointLabel =
    POINT_FILTER_OPTIONS.find((option) => option.value === pointType)?.label ??
    "Tous les points";
  const mapsApiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY ?? "";
  const mapCenter = hotspots[0]
    ? { lat: hotspots[0].lat, lng: hotspots[0].lng }
    : DEFAULT_MAP_CENTER;

  return (
    <div className="space-y-6 p-8">
      <div className="space-y-1">
        <h1 className="text-2xl font-bold">Heatmap des demandes</h1>
        <p className="text-sm text-muted-foreground">
          Vue des secteurs où les collectes, livraisons et relais concentrent le
          plus d’activité. Filtre actif : {periodLabel(days).toLowerCase()},
          {` ${selectedPointLabel.toLowerCase()}`}.
        </p>
      </div>

      <Card>
        <CardContent className="grid gap-4 p-5 md:grid-cols-3">
          <label className="space-y-2 text-sm">
            <span className="font-medium">Période</span>
            <select
              value={days}
              onChange={(event) => setDays(Number(event.target.value))}
              className="h-10 w-full rounded-md border bg-background px-3 text-sm"
            >
              {PERIOD_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>
          <label className="space-y-2 text-sm">
            <span className="font-medium">Type de point</span>
            <select
              value={pointType}
              onChange={(event) =>
                setPointType(event.target.value as HeatmapPointFilter)
              }
              className="h-10 w-full rounded-md border bg-background px-3 text-sm"
            >
              {POINT_FILTER_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>
          <label className="space-y-2 text-sm">
            <span className="font-medium">Secteurs affichés</span>
            <select
              value={limit}
              onChange={(event) => setLimit(Number(event.target.value))}
              className="h-10 w-full rounded-md border bg-background px-3 text-sm"
            >
              {LIMIT_OPTIONS.map((option) => (
                <option key={option} value={option}>
                  Top {option}
                </option>
              ))}
            </select>
          </label>
        </CardContent>
      </Card>

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}

      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement de la heatmap.
        </div>
      )}

      {!isLoading && !isError && (
        <>
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
              <div className="h-[540px] w-full">
                <APIProvider apiKey={mapsApiKey}>
                  <Map
                    key={`heatmap:${days}:${pointType}:${limit}:${mapCenter.lat}:${mapCenter.lng}`}
                    mapId={MAP_ID}
                    defaultCenter={mapCenter}
                    defaultZoom={hotspots.length ? 11 : 6}
                    gestureHandling="greedy"
                    disableDefaultUI={false}
                  >
                    {hotspots.map((hotspot, index) => {
                      const type = dominantType(hotspot);
                      return (
                        <AdvancedMarker
                          key={`hotspot:${hotspot.lat}:${hotspot.lng}:${index}`}
                          position={{ lat: hotspot.lat, lng: hotspot.lng }}
                          onClick={() => setSelectedHotspot(hotspot)}
                        >
                          <div className="flex h-12 min-w-12 items-center justify-center rounded-full border-2 border-white bg-primary px-3 text-sm font-bold text-primary-foreground shadow-lg">
                            {hotspot.count}
                          </div>
                          {type && (
                            <div className="mt-1 rounded-full bg-white px-2 py-0.5 text-[10px] font-medium shadow">
                              {POINT_LABELS[type]}
                            </div>
                          )}
                        </AdvancedMarker>
                      );
                    })}

                    {selectedHotspot && (
                      <InfoWindow
                        position={{
                          lat: selectedHotspot.lat,
                          lng: selectedHotspot.lng,
                        }}
                        onCloseClick={() => setSelectedHotspot(null)}
                      >
                        <HeatmapPopup hotspot={selectedHotspot} />
                      </InfoWindow>
                    )}
                  </Map>
                </APIProvider>
              </div>
            </div>
          )}

          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            {summaryCards(summary).map(({ label, value, icon: Icon, tone }) => (
              <Card key={label}>
                <CardContent className="flex items-center justify-between p-5">
                  <div>
                    <div className="text-sm text-muted-foreground">{label}</div>
                    <div className="mt-1 text-2xl font-bold">{value}</div>
                  </div>
                  <Icon className={`h-8 w-8 ${tone}`} />
                </CardContent>
              </Card>
            ))}
          </div>

          <Card>
            <CardHeader>
              <CardTitle className="text-base">
                Répartition par type de point
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid gap-3 md:grid-cols-5">
                {(Object.keys(POINT_LABELS) as HeatmapPointType[]).map(
                  (key) => (
                    <div
                      key={key}
                      className="rounded-xl border bg-muted/20 p-4"
                    >
                      <div className="text-xs text-muted-foreground">
                        {POINT_LABELS[key]}
                      </div>
                      <div className="mt-1 text-xl font-semibold">
                        {summary[key] ?? 0}
                      </div>
                    </div>
                  ),
                )}
              </div>
            </CardContent>
          </Card>

          {hotspots.length === 0 ? (
            <Card>
              <CardContent className="p-10 text-center text-sm text-muted-foreground">
                Aucune donnée GPS exploitable pour les filtres sélectionnés.
              </CardContent>
            </Card>
          ) : (
            <div className="space-y-3">
              <div>
                <h2 className="text-lg font-semibold">
                  Secteurs les plus actifs
                </h2>
                <p className="text-sm text-muted-foreground">
                  Les secteurs sont nommés à partir des adresses ou relais
                  connus. Quand aucun nom n’est disponible, les coordonnées
                  servent de repère.
                </p>
              </div>
              <div className="grid gap-4 lg:grid-cols-2">
                {hotspots.map((hotspot, index) => {
                  const type = dominantType(hotspot);
                  const label =
                    hotspot.label ||
                    `${formatCoordinate(hotspot.lat)}, ${formatCoordinate(hotspot.lng)}`;
                  return (
                    <Card key={`${hotspot.lat}-${hotspot.lng}-${index}`}>
                      <CardContent className="space-y-4 p-5">
                        <div className="flex items-start justify-between gap-4">
                          <div>
                            <div className="flex items-center gap-2">
                              <Badge tone="info">Secteur {index + 1}</Badge>
                              {type && (
                                <Badge tone="default">
                                  {POINT_LABELS[type]}
                                </Badge>
                              )}
                            </div>
                            <h3 className="mt-2 text-base font-semibold">
                              {label}
                            </h3>
                            <div className="mt-1 text-xs text-muted-foreground">
                              {formatCoordinate(hotspot.lat)},{" "}
                              {formatCoordinate(hotspot.lng)}
                            </div>
                          </div>
                          <div className="text-right">
                            <div className="text-3xl font-bold text-primary">
                              {hotspot.count}
                            </div>
                            <div className="text-xs text-muted-foreground">
                              {plural(hotspot.count, "point", "points")}
                            </div>
                          </div>
                        </div>

                        <div className="flex flex-wrap gap-2">
                          {(
                            Object.entries(hotspot.type_counts ?? {}) as [
                              HeatmapPointType,
                              number,
                            ][]
                          ).map(([key, value]) => (
                            <span
                              key={key}
                              className="rounded-full bg-muted px-3 py-1 text-xs"
                            >
                              {POINT_LABELS[key]} : {value}
                            </span>
                          ))}
                        </div>

                        {(hotspot.parcels?.length ?? 0) > 0 && (
                          <div className="space-y-2">
                            <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                              Colis récents liés
                            </div>
                            <div className="space-y-2">
                              {hotspot.parcels!.map((parcel) => (
                                <div
                                  key={parcel.parcel_id ?? parcel.tracking_code}
                                  className="flex items-center justify-between gap-3 rounded-lg border px-3 py-2 text-sm"
                                >
                                  <div>
                                    {parcel.parcel_id ? (
                                      <Link
                                        href={`/dashboard/parcels/${parcel.parcel_id}`}
                                        className="font-mono font-semibold text-primary underline"
                                      >
                                        {parcel.tracking_code ??
                                          parcel.parcel_id}
                                      </Link>
                                    ) : (
                                      <span className="font-mono font-semibold">
                                        {parcel.tracking_code ?? "Colis"}
                                      </span>
                                    )}
                                    <div className="text-xs text-muted-foreground">
                                      {MODE_LABELS[
                                        parcel.delivery_mode ?? ""
                                      ] ??
                                        parcel.delivery_mode ??
                                        "Mode inconnu"}
                                    </div>
                                  </div>
                                  <div className="text-right text-xs text-muted-foreground">
                                    {parcel.created_at
                                      ? formatDate(parcel.created_at)
                                      : "—"}
                                  </div>
                                </div>
                              ))}
                            </div>
                          </div>
                        )}
                      </CardContent>
                    </Card>
                  );
                })}
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
