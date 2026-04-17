"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchHeatmap } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Loader2 } from "lucide-react";

type HeatmapPoint = {
  latitude: number;
  longitude: number;
  count: number;
  zone_label?: string;
};

export default function HeatmapPage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["heatmap"],
    queryFn: fetchHeatmap,
  });

  const points: HeatmapPoint[] = data?.points ?? [];

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

      {points.length === 0 && !isLoading && (
        <Card>
          <CardContent className="p-10 text-center text-sm text-muted-foreground">
            Pas assez de données pour générer la heatmap.
          </CardContent>
        </Card>
      )}

      {points.length > 0 && (
        <>
          <p className="text-sm text-muted-foreground">
            {points.length} zone{points.length > 1 ? "s" : ""} identifiée
            {points.length > 1 ? "s" : ""}. Top zones par volume de demandes :
          </p>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {points
              .sort((a, b) => b.count - a.count)
              .slice(0, 20)
              .map((p, i) => (
                <Card key={i}>
                  <CardContent className="p-5">
                    <div className="flex items-start justify-between">
                      <div>
                        <div className="font-medium">
                          {p.zone_label ?? `Zone ${i + 1}`}
                        </div>
                        <div className="mt-1 text-xs text-muted-foreground">
                          {p.latitude.toFixed(4)}, {p.longitude.toFixed(4)}
                        </div>
                      </div>
                      <div className="text-2xl font-bold text-primary">
                        {p.count}
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
