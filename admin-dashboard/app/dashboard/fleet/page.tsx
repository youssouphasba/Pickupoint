"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchFleetLive } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Loader2, MapPin, Navigation } from "lucide-react";

type FleetDriver = {
  driver_id: string;
  driver_name?: string;
  phone?: string;
  latitude?: number;
  longitude?: number;
  status?: string;
  mission_id?: string;
  parcel_tracking_code?: string;
  location_updated_at?: string;
  speed_kmh?: number;
};

function fmtTime(iso?: string) {
  if (!iso) return "—";
  const d = new Date(iso);
  return `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
}

export default function FleetPage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["fleet-live"],
    queryFn: fetchFleetLive,
    refetchInterval: 15_000,
  });

  const drivers: FleetDriver[] = data?.drivers ?? [];

  return (
    <div className="space-y-5 p-8">
      <div>
        <h1 className="text-2xl font-bold">Flotte live</h1>
        <p className="text-sm text-muted-foreground">
          Positions GPS temps réel des livreurs en mission. Rafraîchissement
          toutes les 15 secondes.
        </p>
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

      {drivers.length === 0 && !isLoading && (
        <Card>
          <CardContent className="p-10 text-center text-sm text-muted-foreground">
            Aucun livreur en ligne actuellement.
          </CardContent>
        </Card>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {drivers.map((d) => (
          <Card key={d.driver_id}>
            <CardContent className="p-5">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <div className="font-medium">{d.driver_name ?? "—"}</div>
                  <div className="text-xs text-muted-foreground">
                    {d.phone ?? d.driver_id}
                  </div>
                </div>
                <Badge
                  tone={
                    d.status === "in_progress"
                      ? "success"
                      : d.status === "assigned"
                        ? "info"
                        : "default"
                  }
                >
                  {d.status ?? "idle"}
                </Badge>
              </div>

              {d.parcel_tracking_code && (
                <div className="mt-2 text-xs text-muted-foreground">
                  Mission: <span className="font-mono">{d.parcel_tracking_code}</span>
                </div>
              )}

              <div className="mt-3 flex items-center gap-4 text-xs text-muted-foreground">
                <span className="inline-flex items-center gap-1">
                  <MapPin className="h-3.5 w-3.5" />
                  {d.latitude?.toFixed(4)}, {d.longitude?.toFixed(4)}
                </span>
                {d.speed_kmh != null && (
                  <span className="inline-flex items-center gap-1">
                    <Navigation className="h-3.5 w-3.5" />
                    {d.speed_kmh} km/h
                  </span>
                )}
              </div>

              <div className="mt-1 text-[11px] text-muted-foreground">
                Dernière MAJ: {fmtTime(d.location_updated_at)}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
