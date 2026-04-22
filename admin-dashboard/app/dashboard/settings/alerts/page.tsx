"use client";

import * as React from "react";
import {
  Bell,
  BellOff,
  Check,
  Info,
  ShieldAlert,
  TriangleAlert,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/toaster";
import {
  DEFAULT_PREFS,
  loadPrefs,
  savePrefs,
  type AlertPrefs,
} from "@/lib/use-admin-alert-notifications";
import { cn } from "@/lib/utils";

export const runtime = "edge";

type EventTypeDescriptor = {
  key: string;
  label: string;
  description: string;
  severity: "critical" | "warning" | "info";
};

const EVENT_TYPES: EventTypeDescriptor[] = [
  {
    key: "incident_reported",
    label: "Incidents livreur",
    description: "Un livreur signale un incident sur une mission.",
    severity: "critical",
  },
  {
    key: "parcel_disputed",
    label: "Litiges colis",
    description: "Un colis passe en statut litige.",
    severity: "critical",
  },
  {
    key: "payout_requested",
    label: "Demandes de retrait",
    description: "Un livreur ou relais demande un retrait.",
    severity: "warning",
  },
  {
    key: "mission_critical_delay",
    label: "Retards critiques",
    description: "Une mission en cours dépasse le SLA.",
    severity: "warning",
  },
  {
    key: "signal_lost",
    label: "Perte de signal GPS",
    description: "Un livreur n'émet plus sa position pendant >20 min.",
    severity: "warning",
  },
  {
    key: "application_submitted",
    label: "Candidatures",
    description: "Un utilisateur dépose une candidature livreur ou relais.",
    severity: "info",
  },
  {
    key: "parcel_redirected",
    label: "Colis redirigés",
    description: "Livraison échouée, colis routé vers un relais de repli.",
    severity: "warning",
  },
  {
    key: "parcel_stale",
    label: "Colis stagnants",
    description: "Un colis stagne sur le réseau au-delà du SLA.",
    severity: "info",
  },
  {
    key: "mission_released",
    label: "Missions relâchées",
    description: "Un livreur a libéré une mission acceptée.",
    severity: "info",
  },
  {
    key: "parcel_cancelled",
    label: "Colis annulés",
    description: "Un colis est passé en statut annulé.",
    severity: "info",
  },
  {
    key: "payout_approved",
    label: "Retraits validés",
    description: "Un admin valide une demande de retrait.",
    severity: "info",
  },
  {
    key: "payout_rejected",
    label: "Retraits rejetés",
    description: "Un admin rejette une demande de retrait.",
    severity: "info",
  },
];

const SEVERITY_DESCRIPTORS = {
  critical: {
    label: "Critique",
    description:
      "Incidents, litiges — événements qui réclament une action immédiate.",
    Icon: ShieldAlert,
    chip: "bg-red-50 text-red-700",
  },
  warning: {
    label: "Attention",
    description: "Demandes de retrait, retards, perte de signal.",
    Icon: TriangleAlert,
    chip: "bg-amber-50 text-amber-700",
  },
  info: {
    label: "Info",
    description: "Notifications de suivi sans urgence particulière.",
    Icon: Info,
    chip: "bg-muted text-foreground",
  },
} as const;

function useBrowserPermission() {
  const [permission, setPermission] = React.useState<NotificationPermission | "unsupported">(
    () => {
      if (typeof window === "undefined") return "default";
      if (typeof Notification === "undefined") return "unsupported";
      return Notification.permission;
    }
  );

  const request = React.useCallback(async () => {
    if (typeof Notification === "undefined") return "unsupported" as const;
    try {
      const p = await Notification.requestPermission();
      setPermission(p);
      return p;
    } catch {
      return Notification.permission;
    }
  }, []);

  return { permission, request };
}

export default function AdminAlertsPage() {
  const { toast } = useToast();
  const [prefs, setPrefs] = React.useState<AlertPrefs>(DEFAULT_PREFS);
  const [hydrated, setHydrated] = React.useState(false);
  const { permission, request } = useBrowserPermission();

  React.useEffect(() => {
    setPrefs(loadPrefs());
    setHydrated(true);
  }, []);

  function update(next: AlertPrefs) {
    setPrefs(next);
    savePrefs(next);
  }

  async function toggleDesktop(enabled: boolean) {
    if (enabled && permission !== "granted") {
      const p = await request();
      if (p === "denied") {
        toast(
          "Autorisation refusée. Ouvrez les réglages navigateur pour l'activer.",
          "error"
        );
        return;
      }
      if (p !== "granted") return;
    }
    update({ ...prefs, desktop: enabled });
    toast(
      enabled
        ? "Notifications navigateur activées."
        : "Notifications navigateur désactivées."
    );
  }

  function toggleSeverity(sev: keyof AlertPrefs["severities"], value: boolean) {
    update({
      ...prefs,
      severities: { ...prefs.severities, [sev]: value },
    });
  }

  function toggleType(typeKey: string, muted: boolean) {
    const next = muted
      ? [...new Set([...prefs.mutedTypes, typeKey])]
      : prefs.mutedTypes.filter((k) => k !== typeKey);
    update({ ...prefs, mutedTypes: next });
  }

  if (!hydrated) {
    return null;
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6 p-6">
      <div>
        <h1 className="text-2xl font-semibold">Alertes admin</h1>
        <p className="text-sm text-muted-foreground">
          Choisissez les événements qui déclenchent une notification navigateur.
          La cloche du dashboard reste toujours active.
        </p>
      </div>

      <Card>
        <CardContent className="space-y-4 p-5">
          <div className="flex items-start gap-3">
            <div
              className={cn(
                "flex h-10 w-10 shrink-0 items-center justify-center rounded-lg",
                prefs.desktop && permission === "granted"
                  ? "bg-emerald-50 text-emerald-700"
                  : "bg-muted text-muted-foreground"
              )}
            >
              {prefs.desktop && permission === "granted" ? (
                <Bell className="h-5 w-5" />
              ) : (
                <BellOff className="h-5 w-5" />
              )}
            </div>
            <div className="flex-1">
              <div className="font-medium">Notifications navigateur</div>
              <p className="text-sm text-muted-foreground">
                {permission === "unsupported"
                  ? "Ce navigateur ne supporte pas les notifications."
                  : permission === "denied"
                    ? "Autorisation bloquée dans ce navigateur. Déverrouillez-la depuis les réglages du site."
                    : permission === "granted"
                      ? "Autorisation accordée. Les events critiques resteront affichés jusqu'à clic."
                      : "Vous serez invité à autoriser les notifications à l'activation."}
              </p>
            </div>
            <Toggle
              checked={prefs.desktop && permission === "granted"}
              disabled={permission === "unsupported" || permission === "denied"}
              onChange={toggleDesktop}
            />
          </div>
        </CardContent>
      </Card>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
          Sévérités
        </h2>
        <Card>
          <CardContent className="divide-y p-0">
            {(Object.keys(SEVERITY_DESCRIPTORS) as Array<
              keyof typeof SEVERITY_DESCRIPTORS
            >).map((key) => {
              const { label, description, Icon, chip } =
                SEVERITY_DESCRIPTORS[key];
              return (
                <div key={key} className="flex items-center gap-3 p-4">
                  <div
                    className={cn(
                      "flex h-9 w-9 items-center justify-center rounded-md",
                      chip
                    )}
                  >
                    <Icon className="h-4 w-4" />
                  </div>
                  <div className="flex-1">
                    <div className="font-medium">{label}</div>
                    <div className="text-xs text-muted-foreground">
                      {description}
                    </div>
                  </div>
                  <Toggle
                    checked={prefs.severities[key]}
                    onChange={(v) => toggleSeverity(key, v)}
                  />
                </div>
              );
            })}
          </CardContent>
        </Card>
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
          Types d'événements
        </h2>
        <Card>
          <CardContent className="divide-y p-0">
            {EVENT_TYPES.map((t) => {
              const muted = prefs.mutedTypes.includes(t.key);
              const severityMuted = !prefs.severities[t.severity];
              return (
                <div key={t.key} className="flex items-center gap-3 p-4">
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{t.label}</span>
                      <span
                        className={cn(
                          "rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase",
                          SEVERITY_DESCRIPTORS[t.severity].chip
                        )}
                      >
                        {SEVERITY_DESCRIPTORS[t.severity].label}
                      </span>
                    </div>
                    <div className="mt-0.5 text-xs text-muted-foreground">
                      {t.description}
                      {severityMuted && !muted && (
                        <span className="ml-1 font-medium text-amber-600">
                          · sévérité coupée globalement
                        </span>
                      )}
                    </div>
                  </div>
                  <Toggle
                    checked={!muted}
                    onChange={(v) => toggleType(t.key, !v)}
                  />
                </div>
              );
            })}
          </CardContent>
        </Card>
      </section>

      <div className="flex items-center justify-between rounded-lg border bg-muted/40 px-4 py-3 text-sm">
        <div>
          <div className="font-medium">Tester une notification</div>
          <div className="text-xs text-muted-foreground">
            Déclenche une notification locale pour vérifier l'autorisation.
          </div>
        </div>
        <Button
          variant="outline"
          size="sm"
          onClick={() => {
            if (typeof Notification === "undefined") {
              toast("Ce navigateur ne supporte pas les notifications.", "error");
              return;
            }
            if (Notification.permission !== "granted") {
              toast("Activez d'abord les notifications navigateur.", "error");
              return;
            }
            new Notification("Denkma Admin", {
              body: "Test de notification — tout est opérationnel.",
              icon: "/favicon.ico",
            });
          }}
        >
          <Check className="h-4 w-4" /> Tester
        </Button>
      </div>
    </div>
  );
}

function Toggle({
  checked,
  disabled,
  onChange,
}: {
  checked: boolean;
  disabled?: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={cn(
        "relative inline-flex h-6 w-11 shrink-0 cursor-pointer items-center rounded-full border transition-colors",
        checked ? "border-emerald-600 bg-emerald-600" : "border-input bg-muted",
        disabled && "cursor-not-allowed opacity-50"
      )}
    >
      <span
        className={cn(
          "inline-block h-5 w-5 transform rounded-full bg-white shadow-sm transition-transform",
          checked ? "translate-x-5" : "translate-x-0.5"
        )}
      />
    </button>
  );
}
