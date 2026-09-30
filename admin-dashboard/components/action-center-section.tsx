"use client";

import * as React from "react";
import Link from "next/link";
import { useQueryClient } from "@tanstack/react-query";
import {
  AlertTriangle,
  ArrowRight,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  Clock,
  ExternalLink,
  FileText,
  Loader2,
  MessageCircle,
  Package,
  Scale,
  Truck,
  Wallet,
  XCircle,
} from "lucide-react";

import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ActionModal } from "@/components/action-modal";
import { useToast } from "@/components/ui/toaster";
import {
  approvePayout,
  rejectPayout,
  type ActionCategory,
  type ActionCenter,
  type ActionItem,
  type ActionUrgency,
} from "@/lib/api";
import { useActionCenter } from "@/lib/use-action-center";
import { cn } from "@/lib/utils";
import { adminActionHref, paymentStatusLabel, parcelStatusLabel, payoutMethodLabel } from "@/lib/admin-display";

const xof = new Intl.NumberFormat("fr-FR");

type CategoryKey = keyof ActionCenter["categories"];

type Descriptor = {
  key: CategoryKey;
  label: string;
  Icon: React.ComponentType<{ className?: string }>;
  tone: "danger" | "warning" | "info" | "neutral";
};

const CATEGORIES: Descriptor[] = [
  { key: "security", label: "Sécurité des livreurs", Icon: AlertTriangle, tone: "danger" },
  { key: "incidents", label: "Incidents signalés", Icon: AlertTriangle, tone: "danger" },
  { key: "disputes", label: "Litiges ouverts", Icon: Scale, tone: "danger" },
  { key: "payouts", label: "Retraits à valider", Icon: Wallet, tone: "warning" },
  { key: "applications", label: "Candidatures à traiter", Icon: FileText, tone: "info" },
  { key: "anomalies", label: "Anomalies flotte", Icon: Truck, tone: "warning" },
  { key: "payment_blocked", label: "Paiements bloqués", Icon: Package, tone: "warning" },
  { key: "stale_parcels", label: "Colis en attente prolongée", Icon: Clock, tone: "neutral" },
  { key: "support", label: "Support WhatsApp", Icon: MessageCircle, tone: "info" },
];

function urgencyTone(urgency: ActionUrgency): "danger" | "warning" | "default" {
  if (urgency === "critical") return "danger";
  if (urgency === "warning") return "warning";
  return "default";
}

function urgencyLabel(urgency: ActionUrgency): string {
  if (urgency === "critical") return "Urgent";
  if (urgency === "warning") return "Attention";
  return "Normal";
}

function formatAge(hours: number): string {
  if (hours < 1) return `${Math.max(1, Math.round(hours * 60))} min`;
  if (hours < 48) return `${hours.toFixed(1)} h`;
  return `${Math.round(hours / 24)} j`;
}

function asText(value: unknown, fallback = "-"): string {
  if (typeof value !== "string") return fallback;
  const trimmed = value.trim();
  return trimmed.length ? trimmed : fallback;
}

function asNumber(value: unknown): number {
  return typeof value === "number" ? value : 0;
}

export function ActionCenterSection() {
  const { data, isLoading, isError, refetch } = useActionCenter();
  const [urgentOnly, setUrgentOnly] = React.useState(false);

  if (isLoading) {
    return (
      <Card>
        <CardContent className="flex h-24 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </CardContent>
      </Card>
    );
  }

  if (isError || !data) {
    return (
      <Card>
        <CardContent className="flex items-center gap-3 p-5 text-sm text-red-700">
          <AlertTriangle className="h-4 w-4" />
          Impossible de charger les actions à traiter.
          <Button size="sm" variant="outline" onClick={() => refetch()}>
            Réessayer
          </Button>
        </CardContent>
      </Card>
    );
  }

  if (data.total === 0) {
    return (
      <Card className="border-emerald-200 bg-emerald-50/60">
        <CardContent className="flex items-center gap-3 p-5">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700">
            <CheckCircle2 className="h-5 w-5" />
          </div>
          <div>
            <div className="font-semibold text-emerald-900">Tout est à jour.</div>
            <div className="text-sm text-emerald-800/80">Aucune action admin en attente.</div>
          </div>
        </CardContent>
      </Card>
    );
  }

  const visible = CATEGORIES.map((descriptor) => ({
    ...descriptor,
    category: data.categories[descriptor.key],
  }))
    .filter((entry) => entry.category.count > 0)
    .sort((a, b) => {
      const score = (category: ActionCategory) =>
        category.urgent_count * 1000 + category.warning_count * 10 + category.count;
      return score(b.category) - score(a.category);
    });

  return (
    <section className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold">À traiter</h2>
          <p className="text-sm text-muted-foreground">
            {data.total} action{data.total > 1 ? "s" : ""} en attente
            {data.total_urgent > 0 && (
              <>
                {" · "}
                <span className="font-semibold text-red-700">
                  {data.total_urgent} urgent{data.total_urgent > 1 ? "s" : ""}
                </span>
              </>
            )}
            {data.total_warning > 0 && (
              <>
                {" · "}
                <span className="font-semibold text-amber-700">
                  {data.total_warning} attention
                </span>
              </>
            )}
          </p>
        </div>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={urgentOnly}
            onChange={(e) => setUrgentOnly(e.target.checked)}
            className="h-4 w-4 rounded border-muted-foreground/30"
          />
          Urgents uniquement
        </label>
      </div>

      {urgentOnly && data.total_urgent === 0 && <p className="rounded-lg border bg-background p-4 text-sm text-muted-foreground">Aucune action urgente signalée. Décochez le filtre pour consulter les autres éléments.</p>}
      <div className="grid gap-3">
        {visible.map((entry) => (
          <CategoryBlock
            key={entry.key}
            descriptor={entry}
            category={entry.category}
            urgentOnly={urgentOnly}
          />
        ))}
      </div>
    </section>
  );
}

function CategoryBlock({
  descriptor,
  category,
  urgentOnly,
}: {
  descriptor: Descriptor;
  category: ActionCategory;
  urgentOnly: boolean;
}) {
  const [open, setOpen] = React.useState(category.urgent_count > 0);
  const panelId = React.useId();
  const filtered = urgentOnly
    ? category.items.filter((item) => item.urgency === "critical")
    : category.items;

  if (urgentOnly && filtered.length === 0) return null;

  const toneBg: Record<Descriptor["tone"], string> = {
    danger: "bg-red-50 text-red-700",
    warning: "bg-amber-50 text-amber-700",
    info: "bg-blue-50 text-blue-700",
    neutral: "bg-muted text-foreground",
  };

  return (
    <Card>
      <div className="flex items-center gap-3 p-4 sm:p-5">
        <button type="button" onClick={() => setOpen((value) => !value)} aria-expanded={open} aria-controls={panelId}
          className="flex min-w-0 flex-1 items-center gap-3 rounded-md text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
          <div className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-lg", toneBg[descriptor.tone])}>
            <descriptor.Icon className="h-5 w-5" aria-hidden="true" />
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <span className="font-semibold">{descriptor.label}</span>
              {category.urgent_count > 0 && <Badge tone="danger">{category.urgent_count} urgent{category.urgent_count > 1 ? "s" : ""}</Badge>}
              {category.warning_count > 0 && <Badge tone="warning">{category.warning_count} à surveiller</Badge>}
            </div>
            <div className="text-sm text-muted-foreground">{category.count} au total</div>
          </div>
          {open ? <ChevronDown className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden="true" /> : <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden="true" />}
        </button>
        <Link href={category.href} className="inline-flex shrink-0 items-center gap-1 rounded-md px-2 py-2 text-xs font-medium text-primary hover:bg-accent hover:underline" aria-label={`Voir la liste : ${descriptor.label}`}>
          Voir tout <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
        </Link>
      </div>
      {open && (
        <div id={panelId} className="border-t">
          <ul>
            {filtered.map((item) => (
              <li key={String(item.id)} className="border-b last:border-b-0">
                <ItemRow categoryKey={descriptor.key} item={item} fallbackHref={category.href} />
              </li>
            ))}
          </ul>
        </div>
      )}
    </Card>
  );
}

function ItemRow({
  categoryKey,
  item,
  fallbackHref,
}: {
  categoryKey: CategoryKey;
  item: ActionItem;
  fallbackHref: string;
}) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 px-5 py-3">
      <div className="min-w-0 flex-1">
        <RowPrimary categoryKey={categoryKey} item={item} />
      </div>
      <div className="flex items-center gap-2">
        <Badge tone={urgencyTone(item.urgency)}>{urgencyLabel(item.urgency)}</Badge>
        <span className="whitespace-nowrap text-xs text-muted-foreground">{formatAge(item.age_hours)}</span>
        <RowActions categoryKey={categoryKey} item={item} fallbackHref={fallbackHref} />
      </div>
    </div>
  );
}

function RowPrimary({
  categoryKey,
  item,
}: {
  categoryKey: CategoryKey;
  item: ActionItem;
}) {
  switch (categoryKey) {
    case "security":
      return <div><div className="font-medium">{asText(item.driver_name, "Livreur")} · Vérification de sécurité</div><div className="text-xs text-muted-foreground">{asText(item.message, "Consultez l’événement et le dossier avant toute intervention.")}</div></div>;
    case "payouts":
      return (
        <div>
          <div className="font-medium">
            {xof.format(asNumber(item.amount))} XOF - {asText(item.owner_name, "Utilisateur inconnu")}
          </div>
          <div className="text-xs text-muted-foreground">
            {payoutMethodLabel(item.method)} · {asText(item.phone)}
          </div>
        </div>
      );
    case "applications":
      return (
        <div>
          <div className="font-medium">{asText(item.full_name, "Candidat")}</div>
          <div className="text-xs text-muted-foreground">
            {asText(item.phone)} · KYC {asText(item.kyc_status, "inconnu")}
          </div>
        </div>
      );
    case "incidents":
      return (
        <div>
          <div className="font-medium">Colis {asText(item.tracking_code, String(item.parcel_id ?? "-"))}</div>
          <div className="text-xs text-muted-foreground">Livreur {asText(item.driver_name, "non assigné")}</div>
        </div>
      );
    case "disputes":
      return (
        <div>
          <div className="font-medium">Litige colis {asText(item.tracking_code, String(item.parcel_id ?? "-"))}</div>
        </div>
      );
    case "anomalies":
      return (
        <div>
          <div className="font-medium">
            {item.type === "signal_lost" ? "Signal GPS perdu" : "Retard critique"} · {asText(item.driver_name, "Livreur")}
          </div>
          <div className="text-xs text-muted-foreground">Mission {String(item.mission_id ?? "-")}</div>
        </div>
      );
    case "stale_parcels":
      return (
        <div>
          <div className="font-medium">Colis {asText(item.tracking_code, String(item.parcel_id ?? "-"))}</div>
          <div className="text-xs text-muted-foreground">
            {parcelStatusLabel(item.parcel_status)} · {asNumber(item.age_days)} j en relais
          </div>
        </div>
      );
    case "payment_blocked":
      return (
        <div>
          <div className="font-medium">
            Colis {asText(item.tracking_code, String(item.parcel_id ?? "-"))} - {xof.format(asNumber(item.amount))} XOF
          </div>
          <div className="text-xs text-muted-foreground">Paiement {paymentStatusLabel(item.payment_status)}</div>
        </div>
      );
    case "support":
      return (
        <div>
          <div className="font-medium">{asText(item.full_name, asText(item.phone, "Conversation"))}</div>
          <div className="line-clamp-1 text-xs text-muted-foreground">{asText(item.preview)}</div>
        </div>
      );
  }
}

function RowActions({
  categoryKey,
  item,
  fallbackHref,
}: {
  categoryKey: CategoryKey;
  item: ActionItem;
  fallbackHref: string;
}) {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const [approveOpen, setApproveOpen] = React.useState(false);
  const [rejectOpen, setRejectOpen] = React.useState(false);

  function invalidate() {
    queryClient.invalidateQueries({ queryKey: ["action-center"] });
    queryClient.invalidateQueries({ queryKey: ["payouts"], exact: false });
    queryClient.invalidateQueries({ queryKey: ["users"], exact: false });
  }


  if (categoryKey === "payouts") {
    return (
      <>
        <Button size="sm" variant="outline" onClick={() => setRejectOpen(true)}>
          <XCircle className="h-4 w-4" /> Rejeter
        </Button>
        <Button size="sm" onClick={() => setApproveOpen(true)}>
          <CheckCircle2 className="h-4 w-4" /> Valider
        </Button>
        <ActionModal
          open={approveOpen}
          onOpenChange={setApproveOpen}
          title={`Confirmer le versement de ${xof.format(asNumber(item.amount))} XOF`}
          description={`Effectuez le versement hors plateforme (${payoutMethodLabel(item.method)}), puis saisissez sa référence ou celle du justificatif.`}
          inputLabel="Référence du versement ou du justificatif"
          inputPlaceholder="Ex: TX-20260620-001"
          confirmLabel="Confirmer l’envoi"
          required
          onConfirm={async (reference) => {
            await approvePayout(String(item.payout_id), reference);
            invalidate();
            toast("Versement enregistré.");
          }}
        />
        <ActionModal
          open={rejectOpen}
          onOpenChange={setRejectOpen}
          title={`Rejeter le retrait de ${xof.format(asNumber(item.amount))} XOF`}
          description="Indiquez le motif. Le solde sera restauré."
          inputLabel="Motif du rejet"
          inputPlaceholder="Ex: numéro invalide"
          confirmLabel="Rejeter"
          confirmVariant="destructive"
          onConfirm={async (reason) => {
            await rejectPayout(String(item.payout_id), reason);
            invalidate();
            toast("Retrait rejeté.");
          }}
        />
      </>
    );
  }

  const href = adminActionHref(item, fallbackHref);
  if (!href) return <span className="text-xs text-muted-foreground">Dossier indisponible</span>;
  return (
    <Link
      href={href}
      className="inline-flex items-center gap-1 rounded-md border px-3 py-1.5 text-xs font-medium hover:bg-accent"
    >
      {categoryKey === "applications" ? "Vérifier le dossier" : "Ouvrir"} <ExternalLink className="h-3 w-3" />
    </Link>
  );
}
