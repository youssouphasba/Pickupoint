"use client";

import * as React from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchReferralStats,
  fetchPromotions,
  createPromotion,
  deletePromotion,
  updatePromotion,
  fetchPromotionStats,
  AdminPromotionPayload,
  fetchInAppCampaigns,
  createInAppCampaign,
  uploadInAppCampaignImage,
  uploadInAppCampaignVideo,
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
import { Loader2, Pencil, Plus, Save, Trash2, Upload, X } from "lucide-react";

const xof = new Intl.NumberFormat("fr-FR");

const PROMO_TYPES = [
  { value: "percentage", label: "Pourcentage" },
  { value: "fixed_amount", label: "Montant fixe" },
  { value: "free_delivery", label: "Livraison gratuite" },
  { value: "express_upgrade", label: "Express offert" },
] as const;

const PROMO_TARGETS = [
  { value: "all", label: "Tous les clients" },
  { value: "first_delivery", label: "Première livraison" },
  { value: "tier_silver", label: "Fidélité Silver+" },
  { value: "tier_gold", label: "Fidélité Gold" },
  { value: "delivery_mode", label: "Mode de livraison" },
] as const;

function PromotionManager() {
  const qc = useQueryClient();
  const { toast } = useToast();
  const promotions = useQuery({ queryKey: ["admin-promotions"], queryFn: () => fetchPromotions(false) });
  const [selectedId, setSelectedId] = React.useState<string | null>(null);
  const stats = useQuery({ queryKey: ["admin-promotion-stats", selectedId], queryFn: () => fetchPromotionStats(selectedId!), enabled: Boolean(selectedId) });
  const [editingId, setEditingId] = React.useState<string | null>(null);
  const now = React.useMemo(() => new Date(), []);
  const [editingCampaignId, setEditingCampaignId] = React.useState<string | null>(null);
  const [form, setForm] = React.useState<AdminPromotionPayload>({
    title: "",
    description: "",
    promo_type: "percentage",
    value: 10,
    target: "all",
    delivery_mode: null,
    target_user_ids: null,
    min_amount: null,
    max_uses_total: null,
    max_uses_per_user: 1,
    promo_code: "",
    start_date: toDateTimeLocal(now),
    end_date: toDateTimeLocal(new Date(now.getTime() + 7 * 24 * 60 * 60_000)),
    is_active: true,
  });
  const createMut = useMutation({ mutationFn: () => createPromotion({ ...form, promo_code: form.promo_code?.trim() || null, delivery_mode: form.target === "delivery_mode" ? form.delivery_mode : null, start_date: fromDateTimeLocal(form.start_date), end_date: fromDateTimeLocal(form.end_date) }), onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-promotions"] }); toast("Promotion créée."); setForm((current) => ({ ...current, title: "", description: "", promo_code: "" })); } });
  const updateMut = useMutation({ mutationFn: () => updatePromotion(editingId!, { title: form.title, description: form.description, value: form.value, min_amount: form.min_amount, max_uses_total: form.max_uses_total, max_uses_per_user: form.max_uses_per_user, end_date: fromDateTimeLocal(form.end_date) }), onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-promotions"] }); toast("Promotion modifiée."); setEditingId(null); } });
  const toggleMut = useMutation({ mutationFn: ({ id, active }: { id: string; active: boolean }) => updatePromotion(id, { is_active: active }), onSuccess: () => { qc.invalidateQueries({ queryKey: ["admin-promotions"] }); toast("Promotion mise à jour."); } });
  const deleteMut = useMutation({ mutationFn: deletePromotion, onSuccess: (data) => { qc.invalidateQueries({ queryKey: ["admin-promotions"] }); toast(data.message); } });
  const canCreate = form.title.trim().length >= 2 && new Date(form.end_date).getTime() > new Date(form.start_date).getTime() && (form.target !== "delivery_mode" || Boolean(form.delivery_mode));

  return <section className="space-y-4">
    <div><h2 className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">Promotions commerciales</h2><p className="mt-1 text-sm text-muted-foreground">Réductions appliquées au prix de livraison, avec quotas et historique.</p></div>
    <Card><CardHeader><CardTitle className="text-base">Créer une promotion</CardTitle></CardHeader><CardContent className="grid gap-4 lg:grid-cols-3">
      <Input placeholder="Titre de la promotion" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
      <Input placeholder="Code promo optionnel" value={form.promo_code ?? ""} onChange={(e) => setForm({ ...form, promo_code: e.target.value.toUpperCase() })} />
      <select value={form.promo_type} onChange={(e) => setForm({ ...form, promo_type: e.target.value as AdminPromotionPayload["promo_type"], value: e.target.value === "percentage" ? 10 : 0 })} className="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm">{PROMO_TYPES.map((type) => <option key={type.value} value={type.value}>{type.label}</option>)}</select>
      <textarea className="min-h-20 rounded-md border border-input bg-background px-3 py-2 text-sm lg:col-span-3" placeholder="Description" value={form.description ?? ""} onChange={(e) => setForm({ ...form, description: e.target.value })} />
      {form.promo_type === "percentage" || form.promo_type === "fixed_amount" ? <Input type="number" min={0} max={form.promo_type === "percentage" ? 100 : 1000000} placeholder={form.promo_type === "percentage" ? "Pourcentage" : "Montant XOF"} value={form.value} onChange={(e) => setForm({ ...form, value: Number(e.target.value) })} /> : <div className="flex items-center rounded-md border border-dashed px-3 text-sm text-muted-foreground">Aucune réduction monétaire</div>}
      <select value={form.target} onChange={(e) => setForm({ ...form, target: e.target.value, delivery_mode: e.target.value === "delivery_mode" ? "home_to_home" : null })} className="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm">{PROMO_TARGETS.map((target) => <option key={target.value} value={target.value}>{target.label}</option>)}</select>
      {form.target === "delivery_mode" ? <select value={form.delivery_mode ?? "home_to_home"} onChange={(e) => setForm({ ...form, delivery_mode: e.target.value })} className="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"><option value="home_to_home">Domicile → domicile</option><option value="home_to_relay">Domicile → relais</option><option value="relay_to_home">Relais → domicile</option><option value="relay_to_relay">Relais → relais</option></select> : <div />}
      <Input type="number" min={0} placeholder="Montant minimum XOF" value={form.min_amount ?? ""} onChange={(e) => setForm({ ...form, min_amount: e.target.value ? Number(e.target.value) : null })} />
      <Input type="number" min={1} placeholder="Quota total" value={form.max_uses_total ?? ""} onChange={(e) => setForm({ ...form, max_uses_total: e.target.value ? Number(e.target.value) : null })} />
      <Input type="number" min={1} placeholder="Quota par client" value={form.max_uses_per_user} onChange={(e) => setForm({ ...form, max_uses_per_user: Math.max(1, Number(e.target.value)) })} />
      <Input type="datetime-local" value={form.start_date.slice(0, 16)} onChange={(e) => setForm({ ...form, start_date: e.target.value })} />
      <Input type="datetime-local" value={form.end_date.slice(0, 16)} onChange={(e) => setForm({ ...form, end_date: e.target.value })} />
      <div className="flex gap-2"><Button disabled={!canCreate || createMut.isPending || updateMut.isPending} onClick={() => editingId ? updateMut.mutate() : createMut.mutate()}>{createMut.isPending || updateMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : editingId ? <Save className="h-4 w-4" /> : <Plus className="h-4 w-4" />}{editingId ? "Enregistrer" : "Créer"}</Button>{editingId ? <Button variant="outline" onClick={() => setEditingId(null)}>Annuler</Button> : null}</div>
    </CardContent></Card>
    <div className="grid gap-4 lg:grid-cols-2">{promotions.data?.promotions.map((promo) => { const expired = new Date(promo.end_date).getTime() < Date.now(); return <Card key={promo.promo_id}><CardContent className="space-y-3 p-5"><div className="flex items-start justify-between gap-3"><div><div className="font-semibold">{promo.title}</div><div className="text-sm text-muted-foreground">{promo.description || "Sans description"}</div></div><Badge tone={promo.is_active && !expired ? "success" : "default"}>{expired ? "Expirée" : promo.is_active ? "Active" : "Inactive"}</Badge></div><div className="grid grid-cols-2 gap-3 text-sm"><div><div className="text-xs text-muted-foreground">Avantage</div><div className="font-medium">{promo.promo_type === "percentage" ? `${promo.value}%` : promo.promo_type === "fixed_amount" ? `${xof.format(promo.value)} XOF` : PROMO_TYPES.find((type) => type.value === promo.promo_type)?.label}</div></div><div><div className="text-xs text-muted-foreground">Utilisations</div><div className="font-medium">{promo.uses_count}{promo.max_uses_total ? ` / ${promo.max_uses_total}` : ""}</div></div></div><div className="flex flex-wrap gap-2 text-xs"><Badge>{promo.promo_code || "Automatique"}</Badge><Badge>{PROMO_TARGETS.find((target) => target.value === promo.target)?.label ?? promo.target}</Badge><Badge>Jusqu’au {new Date(promo.end_date).toLocaleDateString("fr-FR")}</Badge></div><div className="flex flex-wrap justify-end gap-2"><Button size="sm" variant="outline" onClick={() => { setEditingId(promo.promo_id); setForm({ ...promo, start_date: toDateTimeLocal(new Date(promo.start_date)), end_date: toDateTimeLocal(new Date(promo.end_date)) }); }}>Modifier</Button><Button size="sm" variant="outline" onClick={() => setSelectedId(selectedId === promo.promo_id ? null : promo.promo_id)}>Statistiques</Button><Button size="sm" variant="outline" onClick={() => toggleMut.mutate({ id: promo.promo_id, active: !promo.is_active })}>{promo.is_active ? "Désactiver" : "Activer"}</Button><Button size="sm" variant="outline" onClick={() => { if (window.confirm("Supprimer ou désactiver cette promotion ?")) deleteMut.mutate(promo.promo_id); }}><Trash2 className="h-4 w-4" />Supprimer</Button></div>{selectedId === promo.promo_id && stats.data ? <div className="rounded-md bg-muted/50 p-3 text-sm"><div className="grid grid-cols-2 gap-2"><span>Utilisations : <strong>{stats.data.uses}</strong></span><span>Clients uniques : <strong>{stats.data.unique_users}</strong></span><span>Remises : <strong>{xof.format(stats.data.discount_total_xof)} XOF</strong></span><span>CA associé : <strong>{xof.format(stats.data.revenue_total_xof)} XOF</strong></span></div><div className="mt-3 max-h-40 overflow-y-auto border-t pt-2">{stats.data.history?.map((item: any) => <div key={item.use_id} className="flex justify-between border-b py-1 text-xs"><span>{item.tracking_code || item.parcel_id}</span><span>{xof.format(item.discount_xof)} XOF</span></div>)}</div></div> : null}</CardContent></Card>; })}</div>
  </section>;
}

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
  { value: "/client/create", label: "Cr?er un colis" },
  { value: "/client/profile", label: "Profil client" },
  { value: "/client/profile?section=stats", label: "Profil client - KPIs" },
  { value: "/client/profile?section=loyalty", label: "Profil client - fid?lit?" },
  { value: "/client/profile?section=settings", label: "Profil client - pr?f?rences" },
  { value: "/client/profile?section=referral", label: "Profil client - parrainage" },
  { value: "/client/profile?section=support", label: "Profil client - support" },
  { value: "/client/loyalty-history", label: "Historique fid?lit? client" },
  { value: "/client/partnership", label: "Devenir partenaire" },
  { value: "/driver/performance", label: "Performance livreur" },
  { value: "/driver/wallet", label: "Solde livreur" },
  { value: "/driver/profile", label: "Profil livreur" },
  { value: "/driver/profile?section=identity", label: "Profil livreur - identit?" },
  { value: "/driver/profile?section=referral", label: "Profil livreur - parrainage" },
  { value: "/driver/profile?section=kyc", label: "Profil livreur - documents" },
  { value: "/driver/profile?section=notifications", label: "Profil livreur - notifications" },
  { value: "/driver/profile?section=support", label: "Profil livreur - support" },
  { value: "/relay/profile", label: "Profil relais" },
  { value: "/relay/wallet", label: "Solde relais" },
  { value: "/relay/profile?section=identity", label: "Profil relais - compte agent" },
  { value: "/relay/profile?section=info", label: "Profil relais - fiche publique" },
  { value: "/relay/profile?section=operations", label: "Profil relais - op?rationnel" },
  { value: "/relay/profile?section=support", label: "Profil relais - support" },
];

function toDateTimeLocal(value: Date) {
  const offset = value.getTimezoneOffset();
  const local = new Date(value.getTime() - offset * 60_000);
  return local.toISOString().slice(0, 16);
}

function fromDateTimeLocal(value: string) {
  return new Date(value).toISOString();
}

function clampPriority(value: number) {
  if (!Number.isFinite(value)) return 0;
  return Math.min(10, Math.max(0, Math.round(value)));
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
    video_url: "",
    target_roles: ["all"],
    placements: ["home"],
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
        video_url: form.video_url?.trim() || null,
        start_date: fromDateTimeLocal(form.start_date),
        end_date: fromDateTimeLocal(form.end_date),
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["in-app-campaigns"] });
      setForm((current) => ({ ...current, title: "", body: "", image_url: "", video_url: "" }));
      toast("Campagne in-app créée.");
    },
  });

  const imageMut = useMutation({
    mutationFn: uploadInAppCampaignImage,
    onSuccess: (data) => {
      setForm((current) => ({ ...current, image_url: data.image_url, video_url: "" }));
      toast("Image importée.");
    },
  });

  const videoMut = useMutation({
    mutationFn: uploadInAppCampaignVideo,
    onSuccess: (data) => {
      setForm((current) => ({ ...current, video_url: data.video_url, image_url: "" }));
      toast("Vidéo importée.");
    },
  });

  const updateMut = useMutation({
    mutationFn: ({ id, body }: { id: string; body: Partial<InAppCampaignPayload> }) =>
      updateInAppCampaign(id, body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["in-app-campaigns"] });
      toast("Campagne mise à jour.");
      setEditingCampaignId(null);
    },
  });

  const deleteMut = useMutation({
    mutationFn: deleteInAppCampaign,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["in-app-campaigns"] });
      toast("Campagne supprimée.");
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
          Messages affichés dans l'app avec redirection vers une page.
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
          <div className="space-y-2">
            <Input placeholder="Image URL optionnelle" value={form.image_url ?? ""} onChange={(e) => setForm({ ...form, image_url: e.target.value, video_url: "" })} />
            <label className="inline-flex">
              <input
                type="file"
                accept="image/jpeg,image/png,image/webp"
                className="sr-only"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  e.currentTarget.value = "";
                  if (file) imageMut.mutate(file);
                }}
              />
              <Button type="button" variant="outline" disabled={imageMut.isPending} asChild>
                <span>
                  {imageMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
                  Importer une image
                </span>
              </Button>
            </label>
            <Input placeholder="URL vidéo optionnelle" value={form.video_url ?? ""} onChange={(e) => setForm({ ...form, video_url: e.target.value, image_url: "" })} />
            <label className="inline-flex">
              <input
                type="file"
                accept="video/mp4,video/webm"
                className="sr-only"
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  e.currentTarget.value = "";
                  if (file) videoMut.mutate(file);
                }}
              />
              <Button type="button" variant="outline" disabled={videoMut.isPending} asChild>
                <span>
                  {videoMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
                  Importer une vidéo
                </span>
              </Button>
            </label>
            <p className="text-xs text-muted-foreground">MP4 ou WebM, 12 Mo maximum. La vidéo sera chargée uniquement après appui dans l’application.</p>
          </div>
      <select value={form.target_roles[0] ?? "all"} onChange={(e) => setRole(e.target.value)} className="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm">
            {campaignRoleOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
      </select>
      <select
        value={form.placements[0] ?? "home"}
        onChange={(e) => setForm({ ...form, placements: [e.target.value] })}
        className="flex h-10 rounded-md border border-input bg-background px-3 py-2 text-sm"
      >
        <option value="home">Accueil</option>
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
          <div>
            <label className="mb-1 block text-xs font-medium text-muted-foreground">
              Priorité d'affichage
            </label>
            <Input
              type="number"
              min={0}
              max={10}
              step={1}
              value={form.priority}
              onChange={(e) =>
                setForm({
                  ...form,
                  priority: clampPriority(Number(e.target.value)),
                })
              }
            />
            <p className="mt-1 text-xs text-muted-foreground">
              De 0 à 10. Plus le chiffre est élevé, plus la campagne passe devant.
            </p>
          </div>
          <Button
            disabled={!canCreate || createMut.isPending || updateMut.isPending}
            onClick={() => {
              if (editingCampaignId) {
                updateMut.mutate({
                  id: editingCampaignId,
                  body: {
                    ...form,
                    image_url: form.image_url?.trim() || null,
                    video_url: form.video_url?.trim() || null,
                    start_date: fromDateTimeLocal(form.start_date),
                    end_date: fromDateTimeLocal(form.end_date),
                  },
                });
              } else {
                createMut.mutate();
              }
            }}
          >
            {createMut.isPending || updateMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : editingCampaignId ? <Save className="h-4 w-4" /> : <Plus className="h-4 w-4" />}
            {editingCampaignId ? "Enregistrer" : "Créer la campagne"}
          </Button>
          {editingCampaignId ? <Button variant="outline" onClick={() => setEditingCampaignId(null)}>Annuler</Button> : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Prévisualisation mobile</CardTitle>
        </CardHeader>
        <CardContent>
          <CampaignPreview form={form} />
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
            onEdit={() => {
              setEditingCampaignId(campaign.campaign_id);
              setForm({
                title: campaign.title,
                body: campaign.body,
                cta_label: campaign.cta_label,
                image_url: campaign.image_url ?? "",
                video_url: campaign.video_url ?? "",
                target_roles: campaign.target_roles,
                placements: campaign.placements ?? ["home"],
                action_type: campaign.action_type,
                action_value: campaign.action_value,
                start_date: toDateTimeLocal(new Date(campaign.start_date)),
                end_date: toDateTimeLocal(new Date(campaign.end_date)),
                priority: campaign.priority,
                is_active: campaign.is_active,
              });
              window.scrollTo({ top: 0, behavior: "smooth" });
            }}
          />
        ))}
      </div>
    </section>
  );
}

function CampaignPreview({ form }: { form: InAppCampaignPayload }) {
  return (
    <div className="mx-auto max-w-md rounded-[22px] border bg-muted/30 p-4 shadow-sm">
      <div className="mb-3 text-xs font-medium text-muted-foreground">Accueil client</div>
      <div className="flex min-h-24 items-start gap-3 rounded-2xl bg-blue-700 p-4 text-white shadow-md">
        {form.video_url ? (
          <video src={form.video_url} controls className="h-14 w-14 shrink-0 rounded-xl object-cover" />
        ) : form.image_url ? (
          <img src={form.image_url} alt="" className="h-14 w-14 rounded-xl object-cover" />
        ) : (
          <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-xl bg-white/20 text-xl">📣</div>
        )}
        <div className="min-w-0 flex-1">
          <div className="line-clamp-1 font-bold">{form.title || "Titre de la campagne"}</div>
          <div className="mt-1 line-clamp-2 text-xs">{form.body || "Le message de la campagne apparaîtra ici."}</div>
          <div className="mt-3 inline-flex rounded-lg bg-white px-3 py-2 text-xs font-semibold text-blue-700">
            {form.cta_label || "Voir"}
          </div>
        </div>
        <span className="text-lg leading-none">⌄</span>
      </div>
    </div>
  );
}

function CampaignCard({ campaign, onToggle, onDelete, onEdit }: { campaign: InAppCampaign; onToggle: () => void; onDelete: () => void; onEdit: () => void }) {
  const ctr = campaign.impressions_count > 0 ? Math.round((campaign.clicks_count / campaign.impressions_count) * 100) : 0;
  const now = Date.now();
  const start = new Date(campaign.start_date).getTime();
  const expired = new Date(campaign.end_date).getTime() < now;
  const scheduled = start > now;
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
          <Badge tone={campaign.is_active && !expired && !scheduled ? "success" : "default"}>
            {scheduled ? "Programmée" : expired ? "Expirée" : campaign.is_active ? "Active" : "Inactive"}
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
          <Badge>Priorité {campaign.priority}</Badge>
        </div>
        <div className="flex justify-end gap-2">
          <Button size="sm" variant="outline" onClick={onEdit}>Modifier</Button>
          <Button size="sm" variant="outline" onClick={onToggle}>{campaign.is_active ? "Désactiver" : "Activer"}</Button>
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
    <div className="space-y-6 p-4 sm:p-6 lg:p-8">
      <div>
        <h1 className="text-2xl font-bold">Promotions & paramètres</h1>
        <p className="text-sm text-muted-foreground">
          Contrôler la livraison express et les programmes de parrainage.
        </p>
      </div>

      <PromotionManager />

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
