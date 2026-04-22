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
  Flame,
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
  changeUserRole,
  rejectPayout,
  type ActionCategory,
  type ActionCenter,
  type ActionItem,
  type ActionUrgency,
} from "@/lib/api";
import { useActionCenter } from "@/lib/use-action-center";
import { cn } from "@/lib/utils";

const xof = new Intl.NumberFormat("fr-FR");

type CategoryKey = keyof ActionCenter["categories"];

type Descriptor = {
  key: CategoryKey;
  label: string;
  Icon: React.ComponentType<{ className?: string }>;
  tone: "danger" | "warning" | "info" | "neutral";
};

const CATEGORIES: Descriptor[] = [
  { key: "incidents", label: "Incidents signalés", Icon: AlertTriangle, tone: "danger" },
  { key: "disputes", label: "Litiges ouverts", Icon: Scale, tone: "danger" },
  { key: "payouts", label: "Retraits à valider", Icon: Wallet, tone: "warning" },
  { key: "applications", label: "Candidatures à traiter", Icon: FileText, tone: "info" },
  { key: "anomalies", label: "Anomalies flotte", Icon: Truck, tone: "warning" },
  { key: "payment_blocked", label: "Paiements bloqués", Icon: Package, tone: "warning" },
  { key: "stale_parcels", label: "Colis stagnants", Icon: Clock, tone: "neutral" },
  { key: "support", label: "Support WhatsApp", Icon: MessageCircle, tone: "info" },
];

function urgencyTone(u: ActionUrgency): "danger" | "warning" | "default" {
  if (u === "critical") return "danger";
  if (u === "warning") return "warning";
  return "default";
}

function urgencyLabel(u: ActionUrgency): string {
  if (u === "critical") return "Urgent";
  if (u === "warning") return "Attention";
  return "Normal";
}

function formatAge(hours: number): string {
  if (hours < 1) return `${Math.round(hours * 60)} min`;
  if (hours < 48) return `${hours.toFixed(1)} h`;
  return `${Math.round(hours / 24)} j`;
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
          Impossible de charger le centre d'action.
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
            <div className="font-semibold text-emerald-900">
              Tout est à jour.
            </div>
            <div className="text-sm text-emerald-800/80">
              Aucune action admin en attente.
            </div>
          </div>
        </CardContent>
      </Card>
    );
  }

  // Tri : critique d'abord, puis le reste, puis masquer les vides.
  const visible = CATEGORIES.map((d) => ({ ...d, category: data.categories[d.key] }))
    .filter((c) => c.category.count > 0)
    .sort((a, b) => {
      const score = (c: ActionCategory) =>
        c.urgent_count * 1000 + c.warning_count * 10 + c.count;
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

      <div className="grid gap-3">
        {visible.map((desc) => (
          <CategoryBlock
            key={desc.key}
            descriptor={desc}
            category={desc.category}
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
  const filtered = urgentOnly
    ? category.items.filter((it) => it.urgency === "critical")
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
      <button
        onClick={() => setOpen((v) => !v)}
        className="flex w-full items-center gap-3 p-5 text-left"
        aria-expanded={open}
      >
        <div
          className={cn(
            "flex h-10 w-10 items-center justify-center rounded-lg",
            toneBg[descriptor.tone]
          )}
        >
          <descriptor.Icon className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="font-semibold">{descriptor.label}</span>
            {category.urgent_count > 0 && (
              <Badge tone="danger">
                {category.urgent_count} urgent
                {category.urgent_count > 1 ? "s" : ""}
              </Badge>
            )}
            {category.warning_count > 0 && (
              <Badge tone="warning">{category.warning_count} attention</Badge>
            )}
          </div>
          <div className="text-sm text-muted-foreground">
            {category.count} au total
          </div>
        </div>
        <Link
          href={category.href}
          onClick={(e) => e.stopPropagation()}
          className="hidden items-center gap-1 text-xs font-medium text-emerald-700 hover:underline sm:inline-flex"
        >
          Voir tout <ArrowRight className="h-3.5 w-3.5" />
        </Link>
        {open ? (
          <ChevronDown className="h-4 w-4 text-muted-foreground" />
        ) : (
          <ChevronRight className="h-4 w-4 text-muted-foreground" />
        )}
      </button>
      {open && (
        <div className="border-t">
          <ul>
            {filtered.map((item) => (
              <li key={String(item.id)} className="border-b last:border-b-0">
                <ItemRow categoryKey={descriptor.key} item={item} />
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
}: {
  categoryKey: CategoryKey;
  item: ActionItem;
}) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 px-5 py-3">
      <div className="min-w-0 flex-1">
        <RowPrimary categoryKey={categoryKey} item={item} />
      </div>
      <div className="flex items-center gap-2">
        <Badge tone={urgencyTone(item.urgency)}>
          {urgencyLabel(item.urgency)}
        </Badge>
        <span className="whitespace-nowrap text-xs text-muted-foreground">
          {formatAge(item.age_hours)}
        </span>
        <RowActions categoryKey={categoryKey} item={item} />
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
    case "payouts":
      return (
        <div>
          <div className="font-medium">
            {xof.format((item.amount as number) ?? 0)} XOF —{" "}
            {(item.owner_name as string) ?? "—"}
          </div>
          <div className="text-xs text-muted-foreground">
            {(item.method as string) ?? "—"} · {(item.phone as string) ?? "—"}
          </div>
        </div>
      );
    case "applications":
      return (
        <div>
          <div className="font-medium">
            {(item.full_name as string) ?? "—"}
          </div>
          <div className="text-xs text-muted-foreground">
            {(item.phone as string) ?? "—"} · KYC{" "}
            {(item.kyc_status as string) ?? "—"}
          </div>
        </div>
      );
    case "incidents":
      return (
        <div>
          <div className="font-medium">
            Colis {(item.tracking_code as string) ?? item.parcel_id}
          </div>
          <div className="text-xs text-muted-foreground">
            Livreur {(item.driver_name as string) ?? "—"}
          </div>
        </div>
      );
    case "disputes":
      return (
        <div>
          <div className="font-medium">
            Litige colis {(item.tracking_code as string) ?? item.parcel_id}
          </div>
        </div>
      );
    case "anomalies":
      return (
        <div>
          <div className="font-medium">
            {item.type === "signal_lost" ? "Signal GPS perdu" : "Retard critique"}
            {" · "}
            {(item.driver_name as string) ?? "—"}
          </div>
          <div className="text-xs text-muted-foreground">
            Mission {item.mission_id as string}
          </div>
        </div>
      );
    case "stale_parcels":
      return (
        <div>
          <div className="font-medium">
            Colis {(item.tracking_code as string) ?? item.parcel_id}
          </div>
          <div className="text-xs text-muted-foreground">
            {(item.parcel_status as string) ?? ""} ·{" "}
            {item.age_days as number} j en relais
          </div>
        </div>
      );
    case "payment_blocked":
      return (
        <div>
          <div className="font-medium">
            Colis {(item.tracking_code as string) ?? item.parcel_id}
            {" — "}
            {xof.format((item.amount as number) ?? 0)} XOF
          </div>
          <div className="text-xs text-muted-foreground">
            Paiement {(item.payment_status as string) ?? "—"}
          </div>
        </div>
      );
    case "support":
      return (
        <div>
          <div className="font-medium">
            {(item.full_name as string) ?? (item.phone as string) ?? "—"}
          </div>
          <div className="line-clamp-1 text-xs text-muted-foreground">
            {(item.preview as string) ?? "—"}
          </div>
        </div>
      );
  }
}

function RowActions({
  categoryKey,
  item,
}: {
  categoryKey: CategoryKey;
  item: ActionItem;
}) {
  const qc = useQueryClient();
  const { toast } = useToast();
  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ["action-center"] });
    qc.invalidateQueries({ queryKey: ["payouts"], exact: false });
    qc.invalidateQueries({ queryKey: ["users"], exact: false });
  };

  const [approveOpen, setApproveOpen] = React.useState(false);
  const [rejectOpen, setRejectOpen] = React.useState(false);
  const [promoteLoading, setPromoteLoading] = React.useState<string | null>(null);

  async function promote(role: "driver" | "relay_agent") {
    setPromoteLoading(role);
    try {
      await changeUserRole(item.user_id as string, role);
      invalidate();
      toast(
        role === "driver" ? "Promu en livreur." : "Promu en agent relais."
      );
    } catch (e: any) {
      toast(e?.response?.data?.detail ?? "Erreur lors de la promotion.");
    } finally {
      setPromoteLoading(null);
    }
  }

  if (categoryKey === "payouts") {
    return (
      <>
        <Button
          size="sm"
          variant="outline"
          onClick={() => setRejectOpen(true)}
        >
          <XCircle className="h-4 w-4" /> Rejeter
        </Button>
        <Button size="sm" onClick={() => setApproveOpen(true)}>
          <CheckCircle2 className="h-4 w-4" /> Valider
        </Button>
        <ActionModal
          open={approveOpen}
          onOpenChange={setApproveOpen}
          title={`Valider le retrait de ${xof.format((item.amount as number) ?? 0)} XOF`}
          description="Note optionnelle (référence de transaction…)"
          inputLabel="Note (optionnel)"
          inputPlaceholder="Ex: TX-20260417-001"
          confirmLabel="Valider le retrait"
          required={false}
          onConfirm={async (note) => {
            await approvePayout(item.payout_id as string, note || undefined);
            invalidate();
            toast("Retrait validé.");
          }}
        />
        <ActionModal
          open={rejectOpen}
          onOpenChange={setRejectOpen}
          title={`Rejeter le retrait de ${xof.format((item.amount as number) ?? 0)} XOF`}
          description="Indiquez le motif. Le solde sera restauré."
          inputLabel="Motif du rejet"
          inputPlaceholder="Ex: numéro invalide"
          confirmLabel="Rejeter"
          confirmVariant="destructive"
          onConfirm={async (reason) => {
            await rejectPayout(item.payout_id as string, reason);
            invalidate();
            toast("Retrait rejeté.");
          }}
        />
      </>
    );
  }

  if (categoryKey === "applications") {
    return (
      <>
        <Button
          size="sm"
          variant="outline"
          disabled={promoteLoading !== null}
          onClick={() => {
            if (confirm("Promouvoir en livreur ?")) promote("driver");
          }}
        >
          {promoteLoading === "driver" && (
            <Loader2 className="h-4 w-4 animate-spin" />
          )}
          Livreur
        </Button>
        <Button
          size="sm"
          variant="outline"
          disabled={promoteLoading !== null}
          onClick={() => {
            if (confirm("Promouvoir en agent relais ?")) promote("relay_agent");
          }}
        >
          {promoteLoading === "relay_agent" && (
            <Loader2 className="h-4 w-4 animate-spin" />
          )}
          Agent relais
        </Button>
      </>
    );
  }

  const href = (item.href as string) ?? "#";
  return (
    <Link
      href={href}
      className="inline-flex items-center gap-1 rounded-md border px-3 py-1.5 text-xs font-medium hover:bg-accent"
    >
      Ouvrir <ExternalLink className="h-3 w-3" />
    </Link>
  );
}
