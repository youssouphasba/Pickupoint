"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchReferralStats,
  fetchInAppCampaigns,
  createInAppCampaign,
  updateInAppCampaign,
  deleteInAppCampaign,
  fetchSettings,
  toggleExpress,
  updateLogisticsSettings,
  updateReferralSettings,
  ReferralRoleConfig,
  InAppCampaign,
  InAppCampaignPayload,
} from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { useToast } from "@/components/ui/toaster";
import { Loader2, Pencil, Plus, Save, Trash2, X } from "lucide-react";

const xof = new Intl.NumberFormat("fr-FR");

const METRIC_LABELS: Record<string, string> = {
  sent_parcels: "Colis créés",
  delivered_sender_parcels: "Colis livrés par le client",
  completed_driver_deliveries: "Missions terminées par le livreur",
};

const campaignRoleOptions = [
  { value: "all", label: "Tous" },
  { value: "client", label: "Clients" },
  { value: "driver", label: "Livreurs" },
  { value: "relay_agent", label: "Relais" },
];

const internalRoutes = [
  { value: "/client/create", label: "Creer un colis" },
  { value: "/client/profile", label: "Profil client" },
  { value: "/client/loyalty-history", label: "Fidelite client" },
  { value: "/client/partnership", label: "Devenir partenaire" },
  { value: "/driver/performance", label: "Performance livreur" },
  { value: "/driver/wallet", label: "Solde livreur" },
  { value: "/relay/profile", label: "Profil relais" },
  { value: "/relay/wallet", label: "Solde relais" },
];

function toDateTimeLocal(value: Date) {
  const offset = value.getTimezoneOffset();
  const local = new Date(value.getTime() - offset * 60_000);
  return local.toISOString().slice(0, 16);
}

function fromDateTimeLocal(value: string) {
  return new Date(value).toISOString();
}

function CampaignsSection() {
  const qc = useQueryClient();
  const { toast } = useToast();
  const campaigns = useQuery({
    queryKey: ["in-app-campaigns"],
    queryFn: () => fetchInAppCampaigns(false),
  });
  const now = React.useMemo(() => new Date(), []);
  const [form, setForm] = React.useState<InAppCampaignPayload>({
    title: "",
    body: "",
    cta_label: "Voir",
    image_url: "",
    target_roles: ["all"],
    action_type: "internal_route",
    action_value: "/client/create",
    start_date: toDateTimeLocal(now),
    end_date: toDateTimeLocal(new Date(now.getTime() + 7 * 24 * 60 * 60_000)),
    priority: 0,
    is_active: true,
  });

  const createMut = useMutation({
    mutationFn: () =>
      createInAppCampaign({
        ...form,
        image_url: form.image_url?.trim() || null,
        start_date: fromDateTimeLocal(form.start_date),
        end_date: fromDateTimeLocal(form.end_date),
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["in-app-campaigns"] });
      setForm((current) => ({ ...current, title: "", body: "", image_url: "" }));
      toast("Campagne in-app creee.");
    },
  });

  const updateMut = useMutation({
    mutationFn: ({ id, body }: { id: string; body: Partial<InAppCampaignPayload> }) =>
      updateInAppCampaign(id, body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["in-app-campaigns"] });
      toast("Campagne mise a jour.");
    },
  });

  const deleteMut = useMutation({
    mutationFn: deleteInAppCampaign,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["in-app-campaigns"] });
      toast("Campagne supprimee.");
    },
  });

  function setRole(role: string) {
    setForm((current) => ({
      ...current,
      target_roles: role === "all" ? ["all"] : [role],
    }));
  }

  const canCreate =
    form.title.trim().length > 0 &&
    form.body.trim().length > 0 &&
    form.cta_label.trim().length > 0 &&
    form.action_value.trim().length > 0 &&
    new Date(form.end_date).getTime() > new Date(form.start_date).getTime();

  return (
    <section className="space-y-4">
      <div>
        <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
          Campagnes in-app
        </h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Messages affiches dans l'app avec redirection vers une page.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Nouvelle campagne</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 lg:grid-cols-2">
          <Input placeholder="Titre" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
          <Input placeholder="Bouton" value={form.cta_label} onChange={(e) => setForm({ ...form, cta_label: e.target.value })} />
          <textarea
            className="min-h-24 rounded-md border border-input bg-background px-3 py-2 text-sm lg:col-span-2"
            placeholder="Message court"
            value={form.body}
            onChange={(e) => setForm({ ...form, body: e.target.value })}
          />
          <Input placeholder="Image URL optionnelle" value={form.image_url ?? ""} onChange={(e) => setForm({ ...form, image_url: e.target.value })} />
          <select value={form.target_roles[0] ?? "all"} onChange={(e) => setRole(e.target.value)} className="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm">
            {campaignRoleOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
          <select
            value={form.action_type}
            onChange={(e) => setForm({ ...form, action_type: e.target.value as "internal_route" | "external_url", action_value: e.target.value === "external_url" ? "https://" : "/client/create" })}
            className="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
          >
            <option value="internal_route">Page de l'app</option>
            <option value="external_url">Lien externe</option>
          </select>
          {form.action_type === "internal_route" ? (
            <select value={form.action_value} onChange={(e) => setForm({ ...form, action_value: e.target.value })} className="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm">
              {internalRoutes.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </select>
          ) : (
            <Input placeholder="https://..." value={form.action_value} onChange={(e) => setForm({ ...form, action_value: e.target.value })} />
          )}
          <Input type="datetime-local" value={form.start_date} onChange={(e) => setForm({ ...form, start_date: e.target.value })} />
          <Input type="datetime-local" value={form.end_date} onChange={(e) => setForm({ ...form, end_date: e.target.value })} />
          <Input type="number" placeholder="Priorite" value={form.priority} onChange={(e) => setForm({ ...form, priority: Number(e.target.value) || 0 })} />
          <Button disabled={!canCreate || createMut.isPending} onClick={() => createMut.mutate()}>
            {createMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
            Creer la campagne
          </Button>
        </CardContent>
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        {campaigns.isLoading && (
          <Card>
            <CardContent className="flex h-28 items-center justify-center">
              <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
            </CardContent>
          </Card>
        )}
        {(campaigns.data?.campaigns ?? []).map((campaign) => (
          <CampaignCard
            key={campaign.campaign_id}
            campaign={campaign}
            onToggle={() => updateMut.mutate({ id: campaign.campaign_id, body: { is_active: !campaign.is_active } })}
            onDelete={() => deleteMut.mutate(campaign.campaign_id)}
          />
        ))}
      </div>
    </section>
  );
}

function CampaignCard({ campaign, onToggle, onDelete }: { campaign: InAppCampaign; onToggle: () => void; onDelete: () => void }) {
  const ctr = campaign.impressions_count > 0 ? Math.round((campaign.clicks_count / campaign.impressions_count) * 100) : 0;
  const expired = new Date(campaign.end_date).getTime() < Date.now();
  const roleLabel = campaign.target_roles.includes("all")
    ? "Tous"
    : campaign.target_roles.map((role) => campaignRoleOptions.find((o) => o.value === role)?.label ?? role).join(", ");

  return (
    <Card>
      <CardContent className="space-y-4 p-5">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="font-semibold">{campaign.title}</div>
            <div className="mt-1 line-clamp-2 text-sm text-muted-foreground">{campaign.body}</div>
          </div>
          <Badge tone={campaign.is_active && !expired ? "success" : "default"}>
            {campaign.is_active && !expired ? "Active" : expired ? "Expiree" : "Inactive"}
          </Badge>
        </div>
        <div className="grid grid-cols-3 gap-3 text-sm">
          <div><div className="text-xs text-muted-foreground">Vues</div><div className="font-semibold">{campaign.impressions_count}</div></div>
          <div><div className="text-xs text-muted-foreground">Clics</div><div className="font-semibold">{campaign.clicks_count}</div></div>
          <div><div className="text-xs text-muted-foreground">CTR</div><div className="font-semibold">{ctr}%</div></div>
        </div>
        <div className="flex flex-wrap gap-2 text-xs">
          <Badge>{roleLabel}</Badge>
          <Badge>{campaign.action_type === "external_url" ? "Lien externe" : campaign.action_value}</Badge>
          <Badge>Priorite {campaign.priority}</Badge>
        </div>
        <div className="flex justify-end gap-2">
          <Button size="sm" variant="outline" onClick={onToggle}>{campaign.is_active ? "Desactiver" : "Activer"}</Button>
          <Button size="sm" variant="outline" onClick={onDelete}>
            <Trash2 className="h-4 w-4" />
            Supprimer
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}

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
            <label className="block text-xs text-muted-foreground mb-1">Quand le code peut être saisi</label>
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
            <label className="block text-xs text-muted-foreground mb-1">Maximum avant saisie du code</label>
            {editing ? (
              <Input
                type="number"
                value={config.apply_max_count}
                onChange={(e) => onChange({ ...config, apply_max_count: parseInt(e.target.value) || 0 })}
              />
            ) : (
              <div className="font-medium">{config.apply_max_count === 0 ? "Aucune action réalisée" : config.apply_max_count}</div>
            )}
          </div>
          <div>
            <label className="block text-xs text-muted-foreground mb-1">Quand payer le bonus</label>
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
            <label className="block text-xs text-muted-foreground mb-1">Objectif à atteindre</label>
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
            <label className="block text-xs text-muted-foreground mb-1">Limite de filleuls par parrain</label>
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
  const [redirectRelayDistance, setRedirectRelayDistance] = React.useState("1");

  const s = settings.data;

  React.useEffect(() => {
    if (s?.referral_roles) {
      setClientConfig(s.referral_roles.client);
      setDriverConfig(s.referral_roles.driver);
    }
    if (s?.redirect_relay_max_distance_km != null) {
      setRedirectRelayDistance(String(s.redirect_relay_max_distance_km));
    }
  }, [s]);

  const logisticsMut = useMutation({
    mutationFn: () =>
      updateLogisticsSettings({
        redirect_relay_max_distance_km: Number(redirectRelayDistance),
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["settings"] });
      toast("Règles logistiques mises à jour.");
    },
  });

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

      <CampaignsSection />

      {loading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}

      {s && (
        <>
          <section>
            <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
              Livraison express
            </h2>
            <Card>
              <CardContent className="flex items-center justify-between p-5">
                <div>
                  <div className="font-medium">Mode express</div>
                  <div className="text-sm text-muted-foreground">
                    Coefficient x1.30 sur les tarifs.
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

          <section>
            <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
              Règles logistiques
            </h2>
            <Card>
              <CardContent className="grid gap-4 p-5 md:grid-cols-[1fr_auto] md:items-end">
                <div>
                  <div className="font-medium">Rayon maximum relais de repli</div>
                  <div className="mt-1 text-sm text-muted-foreground">
                    Si aucun relais actif, ouvert et disponible n'est trouvé dans ce rayon autour du destinataire,
                    Denkma déclenche un retour à l'expéditeur au lieu d'envoyer le colis trop loin.
                  </div>
                  <div className="mt-3 max-w-xs">
                    <label className="mb-1 block text-xs text-muted-foreground">
                      Distance maximale autour du destinataire
                    </label>
                    <div className="flex items-center gap-2">
                      <Input
                        type="number"
                        min="0.1"
                        max="10"
                        step="0.1"
                        value={redirectRelayDistance}
                        onChange={(e) => setRedirectRelayDistance(e.target.value)}
                      />
                      <span className="text-sm text-muted-foreground">km</span>
                    </div>
                  </div>
                </div>
                <Button
                  className="w-full md:w-auto"
                  variant="outline"
                  disabled={logisticsMut.isPending || Number(redirectRelayDistance) < 0.1}
                  onClick={() => logisticsMut.mutate()}
                >
                  {logisticsMut.isPending ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    <Save className="h-4 w-4" />
                  )}
                  Sauvegarder
                </Button>
              </CardContent>
            </Card>
          </section>
        </>
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
        const moneyKeys = [
          { key: "referral_bonus_paid_total_xof", label: "Bonus versés (total)" },
          { key: "referral_bonus_paid_last_30_days_xof", label: "Bonus versés (30 jours)" },
        ];
        const txKeys = [
          { key: "referral_bonus_transactions_total", label: "Transactions bonus (total)" },
          { key: "referral_bonus_transactions_last_30_days", label: "Transactions bonus (30 jours)" },
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
            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              {moneyKeys.map(({ key, label }) => (
                <Card key={key}>
                  <CardContent className="p-5">
                    <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                      {label}
                    </div>
                    <div className="mt-1 text-xl font-bold">
                      {xof.format(Number(rs[key] ?? 0))} XOF
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              {txKeys.map(({ key, label }) => (
                <Card key={key}>
                  <CardContent className="p-5">
                    <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                      {label}
                    </div>
                    <div className="mt-1 text-xl font-bold">{Number(rs[key] ?? 0)}</div>
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
