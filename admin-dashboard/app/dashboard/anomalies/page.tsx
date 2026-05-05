"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { fetchActionCenter } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { AlertTriangle, ExternalLink, Loader2 } from "lucide-react";

type Anomaly = {
  id: string;
  type: string;
  parcel_id?: string;
  parcel_status?: string;
  mission_id?: string;
  mission_status?: string;
  tracking_code?: string;
  status?: string;
  driver_name?: string;
  relay_name?: string;
  age_hours?: number;
  message?: string;
  href?: string;
};

const TYPE_LABELS: Record<string, string> = {
  stalled_mission: "Mission bloquée",
  signal_lost: "Signal GPS perdu",
  long_transit: "Transit trop long",
  capacity_overflow: "Relais plein",
  critical_delay: "Mission trop longue",
};

function anomalyMessage(anomaly: Anomaly) {
  if (anomaly.message) return anomaly.message;
  if (anomaly.type === "signal_lost") {
    return "Le livreur n'a pas transmis de position GPS depuis plus de 20 minutes.";
  }
  if (anomaly.type === "critical_delay") {
    return "La mission dépasse le délai opérationnel attendu et doit être contrôlée.";
  }
  return "Une anomalie opérationnelle demande un contrôle admin.";
}

export default function AnomaliesPage() {
  const { data, isLoading, isError } = useQuery({
    queryKey: ["action-center", "anomalies"],
    queryFn: fetchActionCenter,
    refetchInterval: 60_000,
  });

  const alerts = (data?.categories.anomalies.items ?? []) as unknown as Anomaly[];

  return (
    <div className="space-y-5 p-8">
      <div>
        <h1 className="text-2xl font-bold">Anomalies</h1>
        <p className="text-sm text-muted-foreground">
          Détection automatique : signal GPS perdu, missions trop longues et
          incidents qui demandent un contrôle.
        </p>
      </div>

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement des anomalies.
        </div>
      )}

      {alerts.length === 0 && !isLoading && (
        <Card>
          <CardContent className="p-10 text-center text-sm text-muted-foreground">
            Aucune anomalie détectée. Tout est normal.
          </CardContent>
        </Card>
      )}

      <div className="grid gap-3">
        {alerts.map((a, i) => (
          <Card key={a.id ?? i}>
            <CardContent className="flex items-start gap-4 p-5">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-red-50 text-red-600">
                <AlertTriangle className="h-5 w-5" />
              </div>
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-medium">
                    {TYPE_LABELS[a.type] ?? a.type}
                  </span>
                  {a.tracking_code && (
                    <Badge tone="info">
                      <span className="font-mono">{a.tracking_code}</span>
                    </Badge>
                  )}
                </div>
                <div className="mt-1 text-sm text-muted-foreground">
                  {anomalyMessage(a)}
                </div>
                <div className="mt-1 flex flex-wrap gap-3 text-xs text-muted-foreground">
                  {a.driver_name && <span>Livreur : {a.driver_name}</span>}
                  {a.relay_name && <span>Relais : {a.relay_name}</span>}
                  {a.mission_id && <span>Mission : {a.mission_id}</span>}
                  {a.age_hours != null && <span>{a.age_hours.toFixed(1)} h</span>}
                  {(a.parcel_status || a.mission_status || a.status) && (
                    <span>
                      Statut : {a.parcel_status || a.mission_status || a.status}
                    </span>
                  )}
                </div>
                {a.href && (
                  <Link
                    href={a.href}
                    className="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
                  >
                    Ouvrir le contrôle
                    <ExternalLink className="h-3 w-3" />
                  </Link>
                )}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
