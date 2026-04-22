"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Loader2, Save } from "lucide-react";
import {
  fetchSettings,
  updateOperationalSettings,
  type OperationalSettingsPayload,
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

  React.useEffect(() => {
    if (data) setForm(buildInitialPayload(data));
  }, [data]);

  const mutation = useMutation({
    mutationFn: () => updateOperationalSettings(form!),
    onSuccess: (updated) => {
      qc.invalidateQueries({ queryKey: ["settings"] });
      setForm(buildInitialPayload(updated));
      toast("Configuration opérationnelle sauvegardée.");
    },
  });

  function setField(key: keyof OperationalSettingsPayload, value: number) {
    setForm((current) => (current ? { ...current, [key]: value } : current));
  }

  if (isLoading || !form) {
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
