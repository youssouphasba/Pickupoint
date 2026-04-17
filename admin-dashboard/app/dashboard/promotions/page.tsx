"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchReferralStats,
  fetchSettings,
  toggleExpress,
  updateReferralSettings,
  ReferralRoleConfig,
} from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { useToast } from "@/components/ui/toaster";
import { Loader2, Pencil, Save, X } from "lucide-react";

const xof = new Intl.NumberFormat("fr-FR");

const METRIC_LABELS: Record<string, string> = {
  sent_parcels: "Colis envoyés",
  delivered_sender_parcels: "Colis livrés (expéditeur)",
  completed_driver_deliveries: "Livraisons effectuées (driver)",
};

function RoleConfigCard({
  role,
  config,
  metricOptions,
  editing,
  onChange,
}: {
  role: string;
  config: ReferralRoleConfig;
  metricOptions?: { value: string; label: string }[];
  editing: boolean;
  onChange: (c: ReferralRoleConfig) => void;
}) {
  const label = role === "client" ? "Client" : role === "driver" ? "Livreur" : role;

  return (
    <Card>
      <CardContent className="p-5 space-y-3">
        <div className="flex items-center justify-between">
          <span className="font-semibold">{label}</span>
          {editing ? (
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={config.enabled}
                onChange={(e) => onChange({ ...config, enabled: e.target.checked })}
                className="h-4 w-4 rounded border-gray-300"
              />
              Activé
            </label>
          ) : (
            <Badge tone={config.enabled ? "success" : "default"}>
              {config.enabled ? "Activé" : "Désactivé"}
            </Badge>
          )}
        </div>

        <div className="grid grid-cols-2 gap-3 text-sm">
          <div>
            <label className="block text-xs text-muted-foreground mb-1">Bonus parrain (XOF)</label>
            {editing ? (
              <Input
                type="number"
                value={config.sponsor_bonus_xof}
                onChange={(e) => onChange({ ...config, sponsor_bonus_xof: parseInt(e.target.value) || 0 })}
              />
            ) : (
              <div className="font-medium">{xof.format(config.sponsor_bonus_xof)} XOF</div>
            )}
          </div>
          <div>
            <label className="block text-xs text-muted-foreground mb-1">Bonus filleul (XOF)</label>
            {editing ? (
              <Input
                type="number"
                value={config.referred_bonus_xof}
                onChange={(e) => onChange({ ...config, referred_bonus_xof: parseInt(e.target.value) || 0 })}
              />
            ) : (
              <div className="font-medium">{xof.format(config.referred_bonus_xof)} XOF</div>
            )}
          </div>
          <div>
            <label className="block text-xs text-muted-foreground mb-1">Métrique d'application</label>
            {editing ? (
              <select
                value={config.apply_metric}
                onChange={(e) => onChange({ ...config, apply_metric: e.target.value })}
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
              >
                {(metricOptions ?? Object.entries(METRIC_LABELS).map(([v, l]) => ({ value: v, label: l }))).map((o) => (
                  <option key={o.value} value={o.value}>{o.label}</option>
                ))}
              </select>
            ) : (
              <div className="font-medium">{METRIC_LABELS[config.apply_metric] ?? config.apply_metric}</div>
            )}
          </div>
          <div>
            <label className="block text-xs text-muted-foreground mb-1">Seuil application (0 = illimité)</label>
            {editing ? (
              <Input
                type="number"
                value={config.apply_max_count}
                onChange={(e) => onChange({ ...config, apply_max_count: parseInt(e.target.value) || 0 })}
              />
            ) : (
              <div className="font-medium">{config.apply_max_count === 0 ? "Illimité" : config.apply_max_count}</div>
            )}
          </div>
          <div>
            <label className="block text-xs text-muted-foreground mb-1">Métrique récompense</label>
            {editing ? (
              <select
                value={config.reward_metric}
                onChange={(e) => onChange({ ...config, reward_metric: e.target.value })}
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
              >
                {(metricOptions ?? Object.entries(METRIC_LABELS).map(([v, l]) => ({ value: v, label: l }))).map((o) => (
                  <option key={o.value} value={o.value}>{o.label}</option>
                ))}
              </select>
            ) : (
              <div className="font-medium">{METRIC_LABELS[config.reward_metric] ?? config.reward_metric}</div>
            )}
          </div>
          <div>
            <label className="block text-xs text-muted-foreground mb-1">Nb requis pour récompense</label>
            {editing ? (
              <Input
                type="number"
                value={config.reward_count}
                onChange={(e) => onChange({ ...config, reward_count: parseInt(e.target.value) || 1 })}
                min={1}
              />
            ) : (
              <div className="font-medium">{config.reward_count}</div>
            )}
          </div>
          <div className="col-span-2">
            <label className="block text-xs text-muted-foreground mb-1">Max parrainages/parrain (0 = illimité)</label>
            {editing ? (
              <Input
                type="number"
                value={config.max_referrals_per_sponsor}
                onChange={(e) => onChange({ ...config, max_referrals_per_sponsor: parseInt(e.target.value) || 0 })}
              />
            ) : (
              <div className="font-medium">{config.max_referrals_per_sponsor === 0 ? "Illimité" : config.max_referrals_per_sponsor}</div>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

export default function PromotionsPage() {
  const qc = useQueryClient();
  const { toast } = useToast();

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
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["settings"] });
      toast("Mode express mis à jour.");
    },
  });

  // Referral editing state
  const [editing, setEditing] = React.useState(false);
  const [clientConfig, setClientConfig] = React.useState<ReferralRoleConfig | null>(null);
  const [driverConfig, setDriverConfig] = React.useState<ReferralRoleConfig | null>(null);

  const s = settings.data;

  React.useEffect(() => {
    if (s?.referral_roles) {
      setClientConfig(s.referral_roles.client);
      setDriverConfig(s.referral_roles.driver);
    }
  }, [s]);

  const referralMut = useMutation({
    mutationFn: () =>
      updateReferralSettings({
        client: clientConfig!,
        driver: driverConfig!,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["settings"] });
      qc.invalidateQueries({ queryKey: ["referral-stats"] });
      setEditing(false);
      toast("Paramètres parrainage sauvegardés.");
    },
  });

  const loading = settings.isLoading;

  // Metric options from stats response
  const clientMetrics = referralStats.data?.referral_roles?.client?.metric_options;
  const driverMetrics = referralStats.data?.referral_roles?.driver?.metric_options;

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

      {clientConfig && driverConfig && (
        <section>
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
              Parrainage par rôle
            </h2>
            {!editing ? (
              <Button size="sm" variant="outline" onClick={() => setEditing(true)}>
                <Pencil className="h-4 w-4" />
                Modifier
              </Button>
            ) : (
              <div className="flex gap-2">
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    setEditing(false);
                    if (s?.referral_roles) {
                      setClientConfig(s.referral_roles.client);
                      setDriverConfig(s.referral_roles.driver);
                    }
                  }}
                >
                  <X className="h-4 w-4" />
                  Annuler
                </Button>
                <Button
                  size="sm"
                  onClick={() => referralMut.mutate()}
                  disabled={referralMut.isPending}
                >
                  {referralMut.isPending ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    <Save className="h-4 w-4" />
                  )}
                  Sauvegarder
                </Button>
              </div>
            )}
          </div>
          {referralMut.isError && (
            <div className="mb-3 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
              {(referralMut.error as any)?.response?.data?.detail ?? "Erreur de sauvegarde."}
            </div>
          )}
          <div className="grid gap-4 sm:grid-cols-2">
            <RoleConfigCard
              role="client"
              config={clientConfig}
              metricOptions={clientMetrics}
              editing={editing}
              onChange={setClientConfig}
            />
            <RoleConfigCard
              role="driver"
              config={driverConfig}
              metricOptions={driverMetrics}
              editing={editing}
              onChange={setDriverConfig}
            />
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
