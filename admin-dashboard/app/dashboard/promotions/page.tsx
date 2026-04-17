"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchReferralStats,
  fetchSettings,
  toggleExpress,
} from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Loader2 } from "lucide-react";

const xof = new Intl.NumberFormat("fr-FR");

function RoleCard({ role, config }: { role: string; config: any }) {
  const label = role === "client" ? "Client" : role === "driver" ? "Livreur" : role;
  return (
    <Card>
      <CardContent className="p-5 space-y-3">
        <div className="flex items-center justify-between">
          <span className="font-medium">{label}</span>
          <Badge tone={config.enabled ? "success" : "default"}>
            {config.enabled ? "Activé" : "Désactivé"}
          </Badge>
        </div>
        <div className="grid grid-cols-2 gap-2 text-sm">
          <div>
            <div className="text-xs text-muted-foreground">Bonus parrain</div>
            <div className="font-medium">{xof.format(config.sponsor_bonus_xof ?? 0)} XOF</div>
          </div>
          <div>
            <div className="text-xs text-muted-foreground">Bonus filleul</div>
            <div className="font-medium">{xof.format(config.referred_bonus_xof ?? 0)} XOF</div>
          </div>
        </div>
        {config.apply_rule && (
          <div className="text-xs text-muted-foreground">{config.apply_rule}</div>
        )}
        {config.reward_rule && (
          <div className="text-xs text-muted-foreground">{config.reward_rule}</div>
        )}
        {config.max_referrals_per_sponsor > 0 && (
          <div className="text-xs text-muted-foreground">
            Max parrainages : {config.max_referrals_per_sponsor}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

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
                  {expressMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
                  {s.express_enabled ? "Désactiver" : "Activer"}
                </Button>
              </div>
            </CardContent>
          </Card>
        </section>
      )}

      {s?.referral_roles && (
        <section>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            Parrainage par rôle
          </h2>
          <div className="grid gap-4 sm:grid-cols-2">
            {Object.entries(s.referral_roles).map(([role, config]) => (
              <RoleCard key={role} role={role} config={config} />
            ))}
          </div>
        </section>
      )}

      {referralStats.data && (() => {
        const rs = referralStats.data;
        const statKeys = [
          { key: "users_with_code", label: "Utilisateurs avec code" },
          { key: "effective_enabled_users", label: "Parrainage actif" },
          { key: "referred_users", label: "Filleuls inscrits" },
          { key: "rewarded_users", label: "Récompensés" },
          { key: "pending_reward_users", label: "En attente de récompense" },
        ];
        return (
          <section>
            <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
              Statistiques parrainage
            </h2>
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {statKeys.map(({ key, label }) => (
                <Card key={key}>
                  <CardContent className="p-5">
                    <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                      {label}
                    </div>
                    <div className="mt-1 text-xl font-bold">
                      {rs[key] ?? 0}
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>

            {rs.stats_by_role && (
              <div className="mt-4 grid gap-4 sm:grid-cols-2">
                {Object.entries(rs.stats_by_role).map(([role, stats]: [string, any]) => (
                  <Card key={role}>
                    <CardContent className="p-5 space-y-2">
                      <div className="font-medium">
                        {role === "client" ? "Clients" : role === "driver" ? "Livreurs" : role}
                      </div>
                      <div className="grid grid-cols-2 gap-2 text-sm">
                        <div>
                          <div className="text-xs text-muted-foreground">Total</div>
                          <div className="font-medium">{stats.total_users ?? 0}</div>
                        </div>
                        <div>
                          <div className="text-xs text-muted-foreground">Avec code</div>
                          <div className="font-medium">{stats.with_code ?? 0}</div>
                        </div>
                        <div>
                          <div className="text-xs text-muted-foreground">Filleuls</div>
                          <div className="font-medium">{stats.referred_users ?? 0}</div>
                        </div>
                        <div>
                          <div className="text-xs text-muted-foreground">En attente</div>
                          <div className="font-medium">{stats.pending_rewards ?? 0}</div>
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </section>
        );
      })()}
    </div>
  );
}
