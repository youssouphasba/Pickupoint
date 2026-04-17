"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchReferralStats,
  fetchSettings,
  toggleExpress,
} from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Loader2 } from "lucide-react";

const xof = new Intl.NumberFormat("fr-FR");

export default function PromotionsPage() {
  const qc = useQueryClient();

  const settings = useQuery({
    queryKey: ["settings"],
    queryFn: fetchSettings,
  });

  const referralStats = useQuery({
    queryKey: ["referral-stats"],
    queryFn: fetchReferralStats,
  });

  const expressMut = useMutation({
    mutationFn: (enabled: boolean) => toggleExpress(enabled),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["settings"] }),
  });

  const s = settings.data;
  const loading = settings.isLoading;

  return (
    <div className="space-y-6 p-8">
      <div>
        <h1 className="text-2xl font-bold">Promotions & paramètres</h1>
        <p className="text-sm text-muted-foreground">
          Contrôler la livraison express et les programmes de parrainage.
        </p>
      </div>

      {loading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}

      {s && (
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Livraison express
          </h2>
          <Card>
            <CardContent className="flex items-center justify-between p-5">
              <div>
                <div className="font-medium">Mode express</div>
                <div className="text-sm text-muted-foreground">
                  Coefficient x1.40 sur les tarifs
                </div>
              </div>
              <div className="flex items-center gap-3">
                <Badge tone={s.express_enabled ? "success" : "default"}>
                  {s.express_enabled ? "Activé" : "Désactivé"}
                </Badge>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={expressMut.isPending}
                  onClick={() => expressMut.mutate(!s.express_enabled)}
                >
                  {s.express_enabled ? "Désactiver" : "Activer"}
                </Button>
              </div>
            </CardContent>
          </Card>
        </section>
      )}

      {referralStats.data && (
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Programme de parrainage
          </h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {Object.entries(referralStats.data).map(([key, val]) => (
              <Card key={key}>
                <CardContent className="p-5">
                  <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    {key.replace(/_/g, " ")}
                  </div>
                  <div className="mt-1 text-xl font-bold">
                    {typeof val === "number" ? xof.format(val) : String(val)}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
