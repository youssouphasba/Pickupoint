"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Loader2, Save } from "lucide-react";
import {
  fetchSettings,
  updateAppUpdateSettings,
  updateOperationalSettings,
  updatePerformanceRewardsSettings,
  type AppUpdateSettingsPayload,
  type OperationalSettingsPayload,
  type PerformanceRewardsPayload,
} from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { useToast } from "@/components/ui/toaster";

export const runtime = "edge";

type Field = {
  key: keyof OperationalSettingsPayload;
  label: string;
  help: string;
  suffix?: string;
  min?: number;
  step?: string;
};

const PRICING_FIELDS: Field[] = [
  {
    key: "base_relay_to_relay",
    label: "Relais vers relais",
    help: "Base avant distance, poids et promotions.",
    suffix: "XOF",
  },
  {
    key: "base_relay_to_home",
    label: "Relais vers domicile",
    help: "Base pour une livraison finale au destinataire.",
    suffix: "XOF",
  },
  {
    key: "base_home_to_relay",
    label: "Domicile vers relais",
    help: "Base lorsque le livreur collecte chez l'expéditeur.",
    suffix: "XOF",
  },
  {
    key: "base_home_to_home",
    label: "Domicile vers domicile",
    help: "Base du flux complet avec collecte et livraison.",
    suffix: "XOF",
  },
  {
    key: "price_per_km",
    label: "Prix par kilomètre",
    help: "Coût ajouté selon la distance estimée.",
    suffix: "XOF/km",
  },
  {
    key: "price_per_kg",
    label: "Prix par kilo supplémentaire",
    help: "Appliqué au-delà du poids gratuit.",
    suffix: "XOF/kg",
  },
  {
    key: "free_weight_kg",
    label: "Poids gratuit inclus",
    help: "Seul le poids au-dessus de ce seuil est facturé.",
    suffix: "kg",
    step: "0.1",
  },
  {
    key: "min_price",
    label: "Prix minimum",
    help: "Prix plancher après remises et arrondis.",
    suffix: "XOF",
    min: 100,
  },
];

const DELIVERY_FIELDS: Field[] = [
  {
    key: "redirect_relay_max_distance_km",
    label: "Rayon maximum relais de repli",
    help: "Si aucun relais proche/ouvert n'est trouvé autour du destinataire, retour à l'expéditeur.",
    suffix: "km",
    min: 0.1,
    step: "0.1",
  },
  {
    key: "default_distance_km",
    label: "Distance par défaut",
    help: "Utilisée seulement quand les GPS nécessaires ne sont pas encore connus.",
    suffix: "km",
    min: 0.1,
    step: "0.1",
  },
  {
    key: "express_multiplier",
    label: "Coefficient Express",
    help: "1.30 signifie +30 %. Le bouton d'activation reste séparé.",
    suffix: "x",
    min: 1,
    step: "0.01",
  },
  {
    key: "night_multiplier",
    label: "Coefficient nuit/dimanche",
    help: "Réservé aux règles horaires et aux évolutions tarifaires.",
    suffix: "x",
    min: 1,
    step: "0.01",
  },
];

function numberValue(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function buildInitialPayload(settings: any): OperationalSettingsPayload {
  const pricing = settings?.pricing ?? {};
  return {
    express_enabled: Boolean(settings?.express_enabled),
    base_relay_to_relay: numberValue(pricing.base_relay_to_relay),
    base_relay_to_home: numberValue(pricing.base_relay_to_home),
    base_home_to_relay: numberValue(pricing.base_home_to_relay),
    base_home_to_home: numberValue(pricing.base_home_to_home),
    price_per_km: numberValue(pricing.price_per_km),
    price_per_kg: numberValue(pricing.price_per_kg),
    free_weight_kg: numberValue(pricing.free_weight_kg),
    min_price: numberValue(pricing.min_price),
    express_multiplier: numberValue(pricing.express_multiplier, 1.3),
    night_multiplier: numberValue(pricing.night_multiplier, 1.2),
    default_distance_km: numberValue(pricing.default_distance_km),
    redirect_relay_max_distance_km: numberValue(
      settings?.redirect_relay_max_distance_km,
      1
    ),
  };
}

function buildInitialAppUpdatePayload(settings: any): AppUpdateSettingsPayload {
  const update = settings?.app_update ?? {};
  return {
    enabled: update.enabled ?? true,
    message: update.message ?? "Une nouvelle version de Denkma est disponible.",
    android_latest_version: update.android_latest_version ?? "",
    android_min_version: update.android_min_version ?? "",
    android_store_url: update.android_store_url ?? "",
    ios_latest_version: update.ios_latest_version ?? "",
    ios_min_version: update.ios_min_version ?? "",
    ios_store_url: update.ios_store_url ?? "",
  };
}

function buildInitialPerformanceRewardsPayload(settings: any): PerformanceRewardsPayload {
  const rewards = settings?.performance_rewards ?? {};
  return {
    driver: {
      monthly_goal_deliveries: numberValue(
        rewards?.driver?.monthly_goal_deliveries,
        20,
      ),
      success_bonus: {
        enabled: Boolean(rewards?.driver?.success_bonus?.enabled ?? true),
        min_success_rate: numberValue(
          rewards?.driver?.success_bonus?.min_success_rate,
          95,
        ),
        min_deliveries: numberValue(
          rewards?.driver?.success_bonus?.min_deliveries,
          20,
        ),
        amount_xof: numberValue(rewards?.driver?.success_bonus?.amount_xof, 5000),
      },
      volume_bonuses: rewards?.driver?.volume_bonuses ?? [
        { min_deliveries: 50, amount_xof: 2500 },
        { min_deliveries: 100, amount_xof: 5000 },
        { min_deliveries: 200, amount_xof: 10000 },
      ],
    },
    relay: {
      volume_bonuses: rewards?.relay?.volume_bonuses ?? [
        { min_parcels: 20, amount_xof: 1000 },
        { min_parcels: 50, amount_xof: 2000 },
      ],
    },
    client: {
      loyalty_points_per_delivered_parcel: numberValue(
        rewards?.client?.loyalty_points_per_delivered_parcel,
        10,
      ),
      monthly_goal_sent_parcels: numberValue(
        rewards?.client?.monthly_goal_sent_parcels,
        5,
      ),
    },
  };
}

export default function ConfigurationPage() {
  const qc = useQueryClient();
  const { toast } = useToast();
  const { data, isLoading } = useQuery({
    queryKey: ["settings"],
    queryFn: fetchSettings,
  });

  const [form, setForm] = React.useState<OperationalSettingsPayload | null>(
    null
  );
  const [appUpdateForm, setAppUpdateForm] =
    React.useState<AppUpdateSettingsPayload | null>(null);
  const [performanceRewardsForm, setPerformanceRewardsForm] =
    React.useState<PerformanceRewardsPayload | null>(null);

  React.useEffect(() => {
    if (data) {
      setForm(buildInitialPayload(data));
      setAppUpdateForm(buildInitialAppUpdatePayload(data));
      setPerformanceRewardsForm(buildInitialPerformanceRewardsPayload(data));
    }
  }, [data]);

  const mutation = useMutation({
    mutationFn: () => updateOperationalSettings(form!),
    onSuccess: (updated) => {
      qc.invalidateQueries({ queryKey: ["settings"] });
      setForm(buildInitialPayload(updated));
      toast("Configuration opérationnelle sauvegardée.");
    },
  });

  const appUpdateMutation = useMutation({
    mutationFn: () => updateAppUpdateSettings(appUpdateForm!),
    onSuccess: (updated) => {
      qc.invalidateQueries({ queryKey: ["settings"] });
      setAppUpdateForm(updated.app_update);
      toast("Règles de mise à jour sauvegardées.");
    },
  });

  const performanceRewardsMutation = useMutation({
    mutationFn: () => updatePerformanceRewardsSettings(performanceRewardsForm!),
    onSuccess: (updated) => {
      qc.invalidateQueries({ queryKey: ["settings"] });
      setPerformanceRewardsForm(updated.performance_rewards);
      toast("Récompenses de performance sauvegardées.");
    },
  });

  function setField(key: keyof OperationalSettingsPayload, value: number) {
    setForm((current) => (current ? { ...current, [key]: value } : current));
  }

  function updateDriverSuccessBonus(
    key: keyof PerformanceRewardsPayload["driver"]["success_bonus"],
    value: number,
  ) {
    setPerformanceRewardsForm((current) =>
      current
        ? {
            ...current,
            driver: {
              ...current.driver,
              success_bonus: {
                ...current.driver.success_bonus,
                [key]: value,
              },
            },
          }
        : current,
    );
  }

  if (isLoading || !form || !appUpdateForm || !performanceRewardsForm) {
    return (
      <div className="flex h-80 items-center justify-center">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-6 p-8">
      <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
        <div>
          <h1 className="text-2xl font-bold">Configuration opérationnelle</h1>
          <p className="text-sm text-muted-foreground">
            Pilotez les règles métier sans redéployer : tarifs, express et relais
            de repli. Les secrets restent dans Railway.
          </p>
        </div>
        <Button
          onClick={() => mutation.mutate()}
          disabled={mutation.isPending}
          className="w-full md:w-auto"
        >
          {mutation.isPending ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Save className="h-4 w-4" />
          )}
          Sauvegarder
        </Button>
      </div>

      {mutation.isError && (
        <div className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
          {(mutation.error as any)?.response?.data?.detail ??
            "Erreur de sauvegarde."}
        </div>
      )}

      {appUpdateMutation.isError && (
        <div className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
          {(appUpdateMutation.error as any)?.response?.data?.detail ??
            "Erreur de sauvegarde des mises à jour."}
        </div>
      )}

      {performanceRewardsMutation.isError && (
        <div className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
          {(performanceRewardsMutation.error as any)?.response?.data?.detail ??
            "Erreur de sauvegarde des r?compenses."}
        </div>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Tarifs</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {PRICING_FIELDS.map((field) => (
            <NumberField
              key={field.key}
              field={field}
              value={Number(form[field.key])}
              onChange={(value) => setField(field.key, value)}
            />
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Mises à jour mobiles</CardTitle>
        </CardHeader>
        <CardContent className="space-y-5">
          <div className="flex flex-col gap-3 rounded-lg border p-4 md:flex-row md:items-center md:justify-between">
            <div>
              <div className="font-medium">Contrôle de version</div>
              <div className="text-sm text-muted-foreground">
                Force ou recommande une mise à jour sans republier l'application.
              </div>
            </div>
            <button
              type="button"
              role="switch"
              aria-checked={appUpdateForm.enabled}
              onClick={() =>
                setAppUpdateForm((current) =>
                  current ? { ...current, enabled: !current.enabled } : current
                )
              }
              className={`inline-flex h-6 w-11 items-center rounded-full border transition-colors ${
                appUpdateForm.enabled
                  ? "border-emerald-600 bg-emerald-600"
                  : "border-input bg-muted"
              }`}
            >
              <span
                className={`inline-block h-5 w-5 rounded-full bg-white shadow-sm transition-transform ${
                  appUpdateForm.enabled ? "translate-x-5" : "translate-x-0.5"
                }`}
              />
            </button>
          </div>

          <div className="grid gap-4 md:grid-cols-2">
            <TextField
              label="Message"
              value={appUpdateForm.message}
              onChange={(value) =>
                setAppUpdateForm((current) =>
                  current ? { ...current, message: value } : current
                )
              }
            />
            <div className="hidden md:block" />
            <TextField
              label="Android dernière version"
              value={appUpdateForm.android_latest_version}
              onChange={(value) =>
                setAppUpdateForm((current) =>
                  current
                    ? { ...current, android_latest_version: value }
                    : current
                )
              }
            />
            <TextField
              label="Android version minimale"
              value={appUpdateForm.android_min_version}
              onChange={(value) =>
                setAppUpdateForm((current) =>
                  current ? { ...current, android_min_version: value } : current
                )
              }
            />
            <TextField
              label="Lien Play Store"
              value={appUpdateForm.android_store_url}
              onChange={(value) =>
                setAppUpdateForm((current) =>
                  current ? { ...current, android_store_url: value } : current
                )
              }
            />
            <div className="hidden md:block" />
            <TextField
              label="iOS dernière version"
              value={appUpdateForm.ios_latest_version}
              onChange={(value) =>
                setAppUpdateForm((current) =>
                  current ? { ...current, ios_latest_version: value } : current
                )
              }
            />
            <TextField
              label="iOS version minimale"
              value={appUpdateForm.ios_min_version}
              onChange={(value) =>
                setAppUpdateForm((current) =>
                  current ? { ...current, ios_min_version: value } : current
                )
              }
            />
            <TextField
              label="Lien App Store"
              value={appUpdateForm.ios_store_url}
              onChange={(value) =>
                setAppUpdateForm((current) =>
                  current ? { ...current, ios_store_url: value } : current
                )
              }
            />
          </div>

          <div className="flex justify-end">
            <Button
              onClick={() => appUpdateMutation.mutate()}
              disabled={appUpdateMutation.isPending}
            >
              {appUpdateMutation.isPending ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Save className="h-4 w-4" />
              )}
              Sauvegarder les mises à jour
            </Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Livraison et relais</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 md:grid-cols-2">
          {DELIVERY_FIELDS.map((field) => (
            <NumberField
              key={field.key}
              field={field}
              value={Number(form[field.key])}
              onChange={(value) => setField(field.key, value)}
            />
          ))}

          <div className="rounded-lg border p-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <div className="font-medium">Mode Express</div>
                <div className="text-sm text-muted-foreground">
                  Active ou désactive la facturation Express dans l'application.
                </div>
              </div>
              <Badge tone={form.express_enabled ? "success" : "default"}>
                {form.express_enabled ? "Activé" : "Désactivé"}
              </Badge>
            </div>
            <button
              type="button"
              role="switch"
              aria-checked={form.express_enabled}
              onClick={() =>
                setForm((current) =>
                  current
                    ? { ...current, express_enabled: !current.express_enabled }
                    : current
                )
              }
              className={`mt-4 inline-flex h-6 w-11 items-center rounded-full border transition-colors ${
                form.express_enabled
                  ? "border-emerald-600 bg-emerald-600"
                  : "border-input bg-muted"
              }`}
            >
              <span
                className={`inline-block h-5 w-5 rounded-full bg-white shadow-sm transition-transform ${
                  form.express_enabled ? "translate-x-5" : "translate-x-0.5"
                }`}
              />
            </button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div>
            <CardTitle>Récompenses de performance</CardTitle>
            <p className="mt-1 text-sm text-muted-foreground">
              Ces règles alimentent les bonus mensuels, objectifs, points client
              et tableaux de monitoring.
            </p>
          </div>
          <Button
            onClick={() => performanceRewardsMutation.mutate()}
            disabled={performanceRewardsMutation.isPending}
            className="w-full md:w-auto"
          >
            {performanceRewardsMutation.isPending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Save className="h-4 w-4" />
            )}
            Sauvegarder les récompenses
          </Button>
        </CardHeader>
        <CardContent className="space-y-5">
          <div className="grid gap-4 md:grid-cols-3">
            <SimpleNumberCard
              label="Objectif livreur mensuel"
              help="Utilisé dans la progression et le message de motivation."
              value={performanceRewardsForm.driver.monthly_goal_deliveries}
              suffix="courses"
              onChange={(value) =>
                setPerformanceRewardsForm((current) =>
                  current
                    ? {
                        ...current,
                        driver: {
                          ...current.driver,
                          monthly_goal_deliveries: value,
                        },
                      }
                    : current
                )
              }
            />
            <SimpleNumberCard
              label="Points client par colis livré"
              help="Crédités quand un colis client est livré."
              value={
                performanceRewardsForm.client.loyalty_points_per_delivered_parcel
              }
              suffix="points"
              onChange={(value) =>
                setPerformanceRewardsForm((current) =>
                  current
                    ? {
                        ...current,
                        client: {
                          ...current.client,
                          loyalty_points_per_delivered_parcel: value,
                        },
                      }
                    : current
                )
              }
            />
            <SimpleNumberCard
              label="Objectif client mensuel"
              help="Base pour les futures cartes client et le monitoring."
              value={performanceRewardsForm.client.monthly_goal_sent_parcels}
              suffix="colis"
              onChange={(value) =>
                setPerformanceRewardsForm((current) =>
                  current
                    ? {
                        ...current,
                        client: {
                          ...current.client,
                          monthly_goal_sent_parcels: value,
                        },
                      }
                    : current
                )
              }
            />
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <div className="rounded-lg border p-4">
              <div className="mb-3 font-medium">Bonus fiabilité livreur</div>
              <div className="grid gap-3 md:grid-cols-4">
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={performanceRewardsForm.driver.success_bonus.enabled}
                    onChange={(e) =>
                      setPerformanceRewardsForm((current) =>
                        current
                          ? {
                              ...current,
                              driver: {
                                ...current.driver,
                                success_bonus: {
                                  ...current.driver.success_bonus,
                                  enabled: e.target.checked,
                                },
                              },
                            }
                          : current
                      )
                    }
                  />
                  Actif
                </label>
                <MiniNumber
                  label="Réussite min."
                  suffix="%"
                  value={
                    performanceRewardsForm.driver.success_bonus.min_success_rate
                  }
                  onChange={(value) =>
                    updateDriverSuccessBonus("min_success_rate", value)
                  }
                />
                <MiniNumber
                  label="Courses min."
                  value={performanceRewardsForm.driver.success_bonus.min_deliveries}
                  onChange={(value) =>
                    updateDriverSuccessBonus("min_deliveries", value)
                  }
                />
                <MiniNumber
                  label="Montant"
                  suffix="XOF"
                  value={performanceRewardsForm.driver.success_bonus.amount_xof}
                  onChange={(value) =>
                    updateDriverSuccessBonus("amount_xof", value)
                  }
                />
              </div>
            </div>

            <RewardRulesEditor
              title="Bonus volume livreur"
              rows={performanceRewardsForm.driver.volume_bonuses}
              thresholdKey="min_deliveries"
              thresholdLabel="Courses min."
              onChange={(rows) =>
                setPerformanceRewardsForm((current) =>
                  current
                    ? {
                        ...current,
                        driver: { ...current.driver, volume_bonuses: rows },
                      }
                    : current
                )
              }
            />

            <RewardRulesEditor
              title="Bonus volume relais"
              rows={performanceRewardsForm.relay.volume_bonuses}
              thresholdKey="min_parcels"
              thresholdLabel="Colis min."
              onChange={(rows) =>
                setPerformanceRewardsForm((current) =>
                  current
                    ? {
                        ...current,
                        relay: { ...current.relay, volume_bonuses: rows },
                      }
                    : current
                )
              }
            />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-5 text-sm text-muted-foreground">
          Règle clé : un relais de repli n'est choisi que s'il est actif, ouvert,
          disponible et dans le rayon configuré autour du destinataire. Sinon,
          Denkma déclenche le retour à l'expéditeur.
        </CardContent>
      </Card>
    </div>
  );
}

function NumberField({
  field,
  value,
  onChange,
}: {
  field: Field;
  value: number;
  onChange: (value: number) => void;
}) {
  return (
    <div className="rounded-lg border p-4">
      <label className="block text-sm font-medium">{field.label}</label>
      <p className="mt-1 min-h-10 text-xs text-muted-foreground">
        {field.help}
      </p>
      <div className="mt-3 flex items-center gap-2">
        <Input
          type="number"
          min={field.min ?? 0}
          step={field.step ?? "1"}
          value={value}
          onChange={(e) => onChange(Number(e.target.value))}
        />
        {field.suffix && (
          <span className="min-w-fit text-sm text-muted-foreground">
            {field.suffix}
          </span>
        )}
      </div>
    </div>
  );
}

function TextField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <div className="rounded-lg border p-4">
      <label className="block text-sm font-medium">{label}</label>
      <Input
        className="mt-3"
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
    </div>
  );
}

function SimpleNumberCard({
  label,
  help,
  value,
  suffix,
  onChange,
}: {
  label: string;
  help: string;
  value: number;
  suffix?: string;
  onChange: (value: number) => void;
}) {
  return (
    <div className="rounded-lg border p-4">
      <label className="block text-sm font-medium">{label}</label>
      <p className="mt-1 min-h-10 text-xs text-muted-foreground">{help}</p>
      <div className="mt-3 flex items-center gap-2">
        <Input
          type="number"
          min={0}
          value={value}
          onChange={(e) => onChange(Number(e.target.value))}
        />
        {suffix && <span className="text-sm text-muted-foreground">{suffix}</span>}
      </div>
    </div>
  );
}

function MiniNumber({
  label,
  value,
  suffix,
  onChange,
}: {
  label: string;
  value: number;
  suffix?: string;
  onChange: (value: number) => void;
}) {
  return (
    <label className="block text-xs text-muted-foreground">
      {label}
      <div className="mt-1 flex items-center gap-1">
        <Input
          type="number"
          min={0}
          value={value}
          onChange={(e) => onChange(Number(e.target.value))}
        />
        {suffix && <span>{suffix}</span>}
      </div>
    </label>
  );
}

function RewardRulesEditor<T extends "min_deliveries" | "min_parcels">({
  title,
  rows,
  thresholdKey,
  thresholdLabel,
  onChange,
}: {
  title: string;
  rows: Array<Record<T, number> & { amount_xof: number }>;
  thresholdKey: T;
  thresholdLabel: string;
  onChange: (rows: Array<Record<T, number> & { amount_xof: number }>) => void;
}) {
  function updateRow(index: number, key: T | "amount_xof", value: number) {
    onChange(
      rows.map((row, rowIndex) =>
        rowIndex === index ? { ...row, [key]: value } : row,
      ),
    );
  }

  return (
    <div className="rounded-lg border p-4">
      <div className="mb-3 flex items-center justify-between gap-3">
        <div className="font-medium">{title}</div>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={() =>
            onChange([...rows, { [thresholdKey]: 1, amount_xof: 0 } as Record<T, number> & { amount_xof: number }])
          }
        >
          Ajouter
        </Button>
      </div>
      <div className="space-y-2">
        {rows.map((row, index) => (
          <div key={index} className="grid gap-2 md:grid-cols-[1fr_1fr_auto]">
            <MiniNumber
              label={thresholdLabel}
              value={row[thresholdKey]}
              onChange={(value) => updateRow(index, thresholdKey, value)}
            />
            <MiniNumber
              label="Montant"
              suffix="XOF"
              value={row.amount_xof}
              onChange={(value) => updateRow(index, "amount_xof", value)}
            />
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="self-end"
              onClick={() => onChange(rows.filter((_, rowIndex) => rowIndex !== index))}
            >
              Retirer
            </Button>
          </div>
        ))}
      </div>
    </div>
  );
}
