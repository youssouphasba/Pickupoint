"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { fetchHeatmap } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Loader2 } from "lucide-react";

type RawPoint = { lat: number; lng: number };
type Zone = { lat: number; lng: number; count: number; label: string };

/** Group raw GPS points into zones by rounding to ~1 km grid */
function clusterPoints(points: RawPoint[]): Zone[] {
  const buckets = new Map<string, { lat: number; lng: number; count: number }>();
  for (const p of points) {
    // Round to 2 decimals ≈ ~1km grid
    const keyLat = Math.round(p.lat * 100) / 100;
    const keyLng = Math.round(p.lng * 100) / 100;
    const key = `${keyLat},${keyLng}`;
    const existing = buckets.get(key);
    if (existing) {
      existing.count++;
      existing.lat = (existing.lat + p.lat) / 2;
      existing.lng = (existing.lng + p.lng) / 2;
    } else {
      buckets.set(key, { lat: p.lat, lng: p.lng, count: 1 });
    }
  }
  return Array.from(buckets.entries()).map(([, v], i) => ({
    ...v,
    label: `Zone ${i + 1}`,
  }));
}

export default function HeatmapPage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["heatmap"],
    queryFn: fetchHeatmap,
  });

  const zones = React.useMemo(() => {
    const raw: RawPoint[] = data?.points ?? [];
    return clusterPoints(raw).sort((a, b) => b.count - a.count);
  }, [data]);

  const totalPoints = data?.points?.length ?? 0;

  return (
    <div className="space-y-5 p-8">
      <div>
        <h1 className="text-2xl font-bold">Heatmap des demandes</h1>
        <p className="text-sm text-muted-foreground">
          Densité géographique des demandes de livraison pour optimiser le réseau
          de relais.
        </p>
      </div>

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

      {zones.length === 0 && !isLoading && !isError && (
        <Card>
          <CardContent className="p-10 text-center text-sm text-muted-foreground">
            Pas assez de données pour générer la heatmap.
          </CardContent>
        </Card>
      )}

      {zones.length > 0 && (
        <>
          <p className="text-sm text-muted-foreground">
            {totalPoints} point{totalPoints > 1 ? "s" : ""} GPS regroupés en{" "}
            {zones.length} zone{zones.length > 1 ? "s" : ""}. Top zones par
            volume :
          </p>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {zones.slice(0, 20).map((z, i) => (
              <Card key={i}>
                <CardContent className="p-5">
                  <div className="flex items-start justify-between">
                    <div>
                      <div className="font-medium">{z.label}</div>
                      <div className="mt-1 text-xs text-muted-foreground">
                        {z.lat.toFixed(4)}, {z.lng.toFixed(4)}
                      </div>
                    </div>
                    <div className="text-2xl font-bold text-primary">
                      {z.count}
                    </div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
