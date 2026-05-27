"use client";

import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  api,
  assignRelayPoint,
  banUser,
  changeUserRole,
  fetchRelays,
  fetchUserDetail,
  fetchUserHistory,
  moderateProfilePhoto,
  setReferralAccess,
  setUserPayoutBlock,
  startWhatsappSupport,
  unbanUser,
} from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ActionModal, ConfirmModal } from "@/components/action-modal";
import { LocationPreviewMap } from "@/components/location-preview-map";
import { SecureProfileImage } from "@/components/secure-profile-image";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useToast } from "@/components/ui/toaster";
import { formatDate } from "@/lib/utils";
import {
  ArrowLeft,
  Loader2,
  ShieldBan,
  ShieldCheck,
  UserCog,
  Wallet,
  Package,
  Truck,
  Link as LinkIcon,
  MapPin,
  Users,
  MessageCircle,
} from "lucide-react";
import Link from "next/link";

export const runtime = "edge";

const xof = new Intl.NumberFormat("fr-FR");

const ROLE_LABELS: Record<string, string> = {
  client: "Client",
  driver: "Livreur",
  relay_agent: "Agent relais",
  admin: "Admin",
  superadmin: "Super admin",
};

const ROLES = ["client", "driver", "relay_agent", "admin"] as const;

type BadgeTone = NonNullable<React.ComponentProps<typeof Badge>["tone"]>;

const ROLE_TONES: Record<string, BadgeTone> = {
  client: "default",
  driver: "info",
  relay_agent: "warning",
  admin: "success",
  superadmin: "danger",
};

const PROFILE_PHOTO_TONES: Record<string, BadgeTone> = {
  approved: "success",
  pending: "warning",
  rejected: "danger",
  missing: "default",
};

const PROFILE_PHOTO_LABELS: Record<string, string> = {
  approved: "Approuvée",
  pending: "À vérifier",
  rejected: "Refusée",
  missing: "Absente",
};

type ApplicationDocument = {
  label: string;
  url?: string | null;
};

const REFERRAL_STATUS_LABELS: Record<string, string> = {
  pending: "En cours",
  qualified: "Qualifie",
  rewarded: "Paye",
  qualified_no_bonus: "Qualifie sans bonus",
};

const REFERRAL_STATUS_TONES: Record<string, BadgeTone> = {
  pending: "warning",
  qualified: "info",
  rewarded: "success",
  qualified_no_bonus: "default",
};

function textOrDash(value: unknown) {
  const text = String(value ?? "").trim();
  return text || "—";
}

function applicationStatusLabel(status: unknown) {
  switch (String(status ?? "")) {
    case "approved":
      return "Approuvée";
    case "rejected":
      return "Refusée";
    case "pending":
      return "En attente";
    default:
      return textOrDash(status);
  }
}

function applicationStatusTone(status: unknown): BadgeTone {
  switch (String(status ?? "")) {
    case "approved":
      return "success";
    case "rejected":
      return "danger";
    case "pending":
      return "warning";
    default:
      return "default";
  }
}

async function openSecureDocument(url: string) {
  const popup = window.open("about:blank", "_blank");
  try {
    const response = await api.get(url, { responseType: "blob" });
    const objectUrl = URL.createObjectURL(response.data);
    if (popup) {
      popup.opener = null;
      popup.location.href = objectUrl;
    } else {
      window.open(objectUrl, "_blank", "noopener,noreferrer");
    }
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 60_000);
  } catch (error) {
    popup?.close();
    throw error;
  }
}

function InfoLine({
  label,
  value,
}: {
  label: string;
  value: unknown;
}) {
  return (
    <div className="flex justify-between gap-3">
      <span className="text-muted-foreground">{label}</span>
      <span className="max-w-[65%] text-right">{textOrDash(value)}</span>
    </div>
  );
}

function resolveGeoPoint(point?: {
  lat?: number | null;
  lng?: number | null;
  latitude?: number | null;
  longitude?: number | null;
} | null) {
  if (!point) return null;
  const lat = point.lat ?? point.latitude;
  const lng = point.lng ?? point.longitude;
  if (lat == null || lng == null) return null;
  return { lat, lng };
}

export default function UserDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const qc = useQueryClient();
  const { toast } = useToast();

  const { data, isLoading, isError } = useQuery({
    queryKey: ["user-detail", id],
    queryFn: () => fetchUserDetail(id),
    enabled: !!id,
  });

  const history = useQuery({
    queryKey: ["user-history", id],
    queryFn: () => fetchUserHistory(id),
    enabled: !!id,
  });

  const relays = useQuery({
    queryKey: ["relays"],
    queryFn: () => fetchRelays(),
  });

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ["user-detail", id] });
    qc.invalidateQueries({ queryKey: ["users"], exact: false });
  };

  // ── Modals state ──
  const [banOpen, setBanOpen] = React.useState(false);
  const [unbanOpen, setUnbanOpen] = React.useState(false);
  const [roleOpen, setRoleOpen] = React.useState(false);
  const [approvePhotoOpen, setApprovePhotoOpen] = React.useState(false);
  const [rejectPhotoOpen, setRejectPhotoOpen] = React.useState(false);
  const [payoutBlockOpen, setPayoutBlockOpen] = React.useState(false);
  const [payoutUnblockOpen, setPayoutUnblockOpen] = React.useState(false);
  const [selectedRole, setSelectedRole] = React.useState("");

  const banMut = useMutation({
    mutationFn: (reason: string) => banUser(id, reason),
    onSuccess: () => {
      invalidate();
      toast("Utilisateur banni.");
    },
  });

  const unbanMut = useMutation({
    mutationFn: (reason: string) => unbanUser(id, reason),
    onSuccess: () => {
      invalidate();
      toast("Utilisateur débanni.");
    },
  });

  const roleMut = useMutation({
    mutationFn: (role: string) => changeUserRole(id, role),
    onSuccess: () => {
      invalidate();
      toast("Rôle mis à jour.");
    },
  });

  const relayMut = useMutation({
    mutationFn: (relayId: string) => assignRelayPoint(id, relayId),
    onSuccess: () => {
      invalidate();
      toast("Point relais lié.");
    },
  });

  const referralMut = useMutation({
    mutationFn: (val: boolean | null) => setReferralAccess(id, val),
    onSuccess: () => {
      invalidate();
      toast("Accès parrainage mis à jour.");
    },
  });

  const photoModerationMut = useMutation({
    mutationFn: ({
      status,
      reason,
    }: {
      status: "approved" | "rejected" | "pending";
      reason?: string;
    }) => moderateProfilePhoto(id, status, reason),
    onSuccess: () => {
      invalidate();
      toast("Photo de profil mise à jour.");
    },
  });

  const supportMut = useMutation({
    mutationFn: () => startWhatsappSupport({ user_id: id }),
    onSuccess: (result) => {
      const conversationId = result.conversation?.conversation_id;
      router.push(
        `/dashboard/support${conversationId ? `?c=${encodeURIComponent(conversationId)}` : supportQuery ? `?q=${encodeURIComponent(supportQuery)}` : ""}`,
      );
      toast("Template WhatsApp envoyé.");
    },
    onError: (error) => toast(error instanceof Error ? error.message : "Impossible de démarrer le support WhatsApp."),
  });

  const payoutBlockMut = useMutation({
    mutationFn: ({ blocked, reason }: { blocked: boolean; reason?: string }) =>
      setUserPayoutBlock(id, blocked, reason),
    onSuccess: (_, vars) => {
      invalidate();
      toast(vars.blocked ? "Décaissements bloqués." : "Décaissements débloqués.");
    },
  });

  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="p-8">
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Utilisateur introuvable.
        </div>
      </div>
    );
  }

  const user = data.user;
  const summary = data.summary;
  const performance = data.performance ?? {};
  const wallet = data.wallet;
  const referral = data.referral;
  const sponsoredReferrals = referral?.sponsored_referrals;
  const sponsoredItems = Array.isArray(sponsoredReferrals?.items)
    ? sponsoredReferrals.items
    : [];
  const missionLocation = resolveGeoPoint(data.active_mission?.driver_location);
  const profileLocation = resolveGeoPoint(user.last_driver_location);
  const displayLocation = missionLocation ?? profileLocation;
  const displayLocationUpdatedAt =
    data.active_mission?.location_updated_at ?? user.last_driver_location_at;
  const displayLocationSource = missionLocation
    ? "Mission active"
    : profileLocation
      ? "Dernière position connue"
      : null;
  const referralUrl = referral?.referral_url ?? "";
  const referralShareMessage = referralUrl
    ? `Utilise mon code parrainage Denkma ${referral.code ?? ""} pour rejoindre l'app. Lien d'inscription : ${referralUrl}`
    : "";
  const supportQuery = String(user.phone ?? "").trim();
  const copyReferralLink = async () => {
    if (!referralUrl) {
      toast("Aucun lien de parrainage disponible.");
      return;
    }
    try {
      await navigator.clipboard.writeText(referralUrl);
      toast("Lien de parrainage copié.");
    } catch {
      toast("Impossible de copier le lien.");
    }
  };
  const copyReferralMessage = async () => {
    if (!referralShareMessage) {
      toast("Aucun message de parrainage disponible.");
      return;
    }
    try {
      await navigator.clipboard.writeText(referralShareMessage);
      toast("Message de parrainage copié.");
    } catch {
      toast("Impossible de copier le message.");
    }
  };

  return (
    <div className="space-y-6 p-8">
      {/* Header */}
      <div className="flex items-start gap-4">
        <Button variant="ghost" size="icon" onClick={() => router.back()}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="flex-1">
          <h1 className="text-2xl font-bold">{user.name ?? "Sans nom"}</h1>
          <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            <span>{user.phone}</span>
            {user.email && (
              <>
                <span>•</span>
                <span>{user.email}</span>
              </>
            )}
            <span>•</span>
            <Badge
              tone={
                user.is_banned
                  ? "danger"
                  : user.is_active
                    ? "success"
                    : "default"
              }
            >
              {user.is_banned ? "Suspendu" : user.is_active ? "Actif" : "Inactif"}
            </Badge>
            <Badge
              tone={ROLE_TONES[String(user.role)] ?? "default"}
            >
              {ROLE_LABELS[user.role] ?? user.role}
            </Badge>
          </div>
          <div className="mt-1 text-xs text-muted-foreground">
            Inscrit le {formatDate(user.created_at)} • ID: {user.user_id}
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="flex flex-wrap gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={() => {
            setSelectedRole(user.role);
            setRoleOpen(true);
          }}
        >
          <UserCog className="h-4 w-4" />
          Changer rôle
        </Button>
        <Button
          variant="outline"
          size="sm"
          disabled={!supportQuery}
          onClick={() => supportMut.mutate()}
        >
          {supportMut.isPending ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <MessageCircle className="h-4 w-4" />
          )}
          Support WhatsApp
        </Button>
        {user.is_banned ? (
          <Button variant="outline" size="sm" onClick={() => setUnbanOpen(true)}>
            <ShieldCheck className="h-4 w-4" />
            Débannir
          </Button>
        ) : (
          <Button
            variant="destructive"
            size="sm"
            onClick={() => setBanOpen(true)}
          >
            <ShieldBan className="h-4 w-4" />
            Bannir
          </Button>
        )}
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Photo de profil</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-5 md:flex-row md:items-start">
          <SecureProfileImage
            src={user.profile_picture_url}
            alt={`Photo de ${user.name ?? user.phone}`}
            className="h-36 w-36 shrink-0 rounded-2xl"
            fallbackClassName="rounded-2xl"
          />
          <div className="min-w-0 flex-1 space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              <Badge tone={PROFILE_PHOTO_TONES[user.profile_picture_status ?? "missing"] ?? "default"}>
                {PROFILE_PHOTO_LABELS[user.profile_picture_status ?? "missing"] ?? user.profile_picture_status}
              </Badge>
              {user.profile_picture_rejected_reason && (
                <span className="text-sm text-red-600">
                  Motif : {user.profile_picture_rejected_reason}
                </span>
              )}
            </div>
            <p className="text-sm text-muted-foreground">
              Cette photo est visible par les clients sur les colis et missions. Un livreur ne peut être disponible ou assigné que si sa photo est approuvée.
            </p>
            <div className="flex flex-wrap gap-2">
              <Button
                size="sm"
                disabled={!user.profile_picture_url || photoModerationMut.isPending}
                onClick={() => setApprovePhotoOpen(true)}
              >
                Approuver
              </Button>
              <Button
                size="sm"
                variant="destructive"
                disabled={!user.profile_picture_url || photoModerationMut.isPending}
                onClick={() => setRejectPhotoOpen(true)}
              >
                Désapprouver
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {data.applications && data.applications.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Candidatures et documents</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {data.applications.map((application: any) => {
              const applicationData = application.data ?? {};
              const isDriver = application.type === "driver";
              const documents: ApplicationDocument[] = isDriver
                ? [
                    { label: "Pièce d'identité", url: applicationData.id_card_url },
                    { label: "Permis de conduire", url: applicationData.license_url },
                  ]
                : [
                    { label: "Document commerce", url: applicationData.business_doc_url },
                    { label: "Registre commerce", url: applicationData.business_reg_url },
                    { label: "Pièce d'identité", url: applicationData.id_card_url },
                  ];
              const availableDocuments = documents.filter((doc) => doc.url);

              return (
                <div
                  key={application.application_id}
                  className="rounded-lg border bg-muted/20 p-4 text-sm"
                >
                  <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                    <div className="font-semibold">
                      {isDriver ? "Candidature livreur" : "Candidature point relais"}
                    </div>
                    <Badge tone={applicationStatusTone(application.status)}>
                      {applicationStatusLabel(application.status)}
                    </Badge>
                  </div>
                  <div className="grid gap-2 md:grid-cols-2">
                    <InfoLine label="ID candidature" value={application.application_id} />
                    <InfoLine label="Soumise le" value={formatDate(application.created_at)} />
                    <InfoLine label="Mise à jour" value={formatDate(application.updated_at)} />
                    {isDriver ? (
                      <>
                        <InfoLine label="Nom déclaré" value={applicationData.full_name} />
                        <InfoLine label="Numéro CNI" value={applicationData.id_card_number} />
                        <InfoLine label="Numéro permis" value={applicationData.license_number} />
                        <InfoLine label="Véhicule" value={applicationData.vehicle_type} />
                      </>
                    ) : (
                      <>
                        <InfoLine label="Nom du commerce" value={applicationData.business_name} />
                        <InfoLine label="Adresse" value={applicationData.address_label} />
                        <InfoLine label="Ville" value={applicationData.city} />
                        <InfoLine label="Registre commerce" value={applicationData.business_reg} />
                        <InfoLine label="Horaires" value={applicationData.opening_hours} />
                      </>
                    )}
                    <InfoLine label="Message candidat" value={applicationData.message} />
                    <InfoLine label="Note admin" value={application.admin_notes} />
                  </div>
                  <div className="mt-3 flex flex-wrap gap-2">
                    {availableDocuments.length > 0 ? (
                      availableDocuments.map((document) => (
                        <Button
                          key={document.label}
                          size="sm"
                          variant="outline"
                          onClick={() => {
                            void openSecureDocument(document.url!).catch(() => {
                              toast("Impossible d'ouvrir le document.");
                            });
                          }}
                        >
                          Voir {document.label.toLowerCase()}
                        </Button>
                      ))
                    ) : (
                      <span className="text-xs text-muted-foreground">
                        Aucun document transmis dans cette candidature.
                      </span>
                    )}
                  </div>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}

      {/* Summary KPIs */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardContent className="flex items-center gap-3 p-5">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-blue-50 text-blue-600">
              <Package className="h-5 w-5" />
            </div>
            <div>
              <div className="text-2xl font-bold">{summary.parcels_sent}</div>
              <div className="text-xs text-muted-foreground">Colis envoyés</div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="flex items-center gap-3 p-5">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-green-50 text-green-600">
              <Package className="h-5 w-5" />
            </div>
            <div>
              <div className="text-2xl font-bold">{summary.parcels_received}</div>
              <div className="text-xs text-muted-foreground">Colis reçus</div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="flex items-center gap-3 p-5">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-amber-50 text-amber-600">
              <Truck className="h-5 w-5" />
            </div>
            <div>
              <div className="text-2xl font-bold">{summary.missions_count}</div>
              <div className="text-xs text-muted-foreground">Missions</div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="flex items-center gap-3 p-5">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-purple-50 text-purple-600">
              <Users className="h-5 w-5" />
            </div>
            <div>
              <div className="text-2xl font-bold">{summary.active_sessions}</div>
              <div className="text-xs text-muted-foreground">Sessions actives</div>
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">
            Performance mensuelle {performance.period ? `(${performance.period})` : ""}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-5">
          <div className="grid gap-4 md:grid-cols-3">
            {performance.client && (
              <div className="rounded-lg border bg-muted/20 p-4">
                <div className="mb-3 flex items-center justify-between gap-2">
                  <div className="font-semibold">Client</div>
                  {performance.client.is_hybrid_client && (
                    <Badge tone="info">Compte hybride</Badge>
                  )}
                </div>
                <div className="grid gap-2 text-sm">
                  <InfoLine label="Colis crees" value={performance.client.sent_parcels ?? 0} />
                  <InfoLine label="Colis livres" value={performance.client.delivered_parcels ?? 0} />
                  <InfoLine label="Taux livre" value={`${performance.client.success_rate ?? 0}%`} />
                  <InfoLine
                    label="Objectif"
                    value={`${Math.round((performance.client.goal_progress ?? 0) * 100)}% (${performance.client.sent_parcels ?? 0}/${performance.client.monthly_goal ?? 0})`}
                  />
                  <InfoLine label="CA client" value={`${xof.format(performance.client.spent_xof ?? 0)} XOF`} />
                  <InfoLine
                    label="Fidelite"
                    value={`${performance.client.loyalty_points ?? 0} pts - ${performance.client.loyalty_tier ?? "bronze"}`}
                  />
                </div>
              </div>
            )}
            {performance.driver && (
              <div className="rounded-lg border bg-muted/20 p-4">
                <div className="mb-3 flex items-center justify-between gap-2">
                  <div className="font-semibold">Livreur</div>
                  <Badge tone="info">
                    {performance.driver.rank
                      ? `#${performance.driver.rank} / ${performance.driver.total_ranked_drivers ?? "-"}`
                      : "Non classe"}
                  </Badge>
                </div>
                <div className="grid gap-2 text-sm">
                  <InfoLine label="Courses reussies" value={performance.driver.deliveries_success ?? 0} />
                  <InfoLine label="Total missions" value={performance.driver.deliveries_total ?? 0} />
                  <InfoLine label="Taux reussite" value={`${performance.driver.success_rate ?? 0}%`} />
                  <InfoLine label="Gains mois" value={`${xof.format(performance.driver.total_earned_xof ?? 0)} XOF`} />
                  <InfoLine label="Bonus verse" value={`${xof.format(performance.driver.bonus_paid_xof ?? 0)} XOF`} />
                  <InfoLine
                    label="Niveau / note"
                    value={`Niv. ${performance.driver.level ?? 1} - ${Number(performance.driver.average_rating ?? 0).toFixed(1)}/5`}
                  />
                </div>
              </div>
            )}
            {performance.relay && (
              <div className="rounded-lg border bg-muted/20 p-4">
                <div className="mb-3 flex items-center justify-between gap-2">
                  <div className="font-semibold">Relais</div>
                  <Badge tone={(performance.relay.projected_bonus_xof ?? 0) > 0 ? "success" : "default"}>
                    {(performance.relay.projected_bonus_xof ?? 0) > 0 ? "Prime" : "Sans prime"}
                  </Badge>
                </div>
                <div className="grid gap-2 text-sm">
                  <InfoLine label="Colis traites" value={performance.relay.parcels_processed ?? 0} />
                  <InfoLine label="Colis livres" value={performance.relay.parcels_delivered ?? 0} />
                  <InfoLine label="Stock actuel" value={performance.relay.stock_count ?? 0} />
                  <InfoLine label="Bonus projete" value={`${xof.format(performance.relay.projected_bonus_xof ?? 0)} XOF`} />
                  <InfoLine
                    label="Prochain palier"
                    value={performance.relay.next_bonus_threshold ? `${performance.relay.next_bonus_threshold} colis` : "Palier maximum"}
                  />
                </div>
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        {(user.role === "driver" || displayLocation) && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <MapPin className="h-4 w-4" />
                Position du livreur
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="grid gap-2 text-sm">
                <InfoLine label="Source" value={displayLocationSource} />
                <InfoLine
                  label="Dernière remontée"
                  value={displayLocationUpdatedAt ? formatDate(displayLocationUpdatedAt) : "—"}
                />
              </div>
              <LocationPreviewMap
                point={displayLocation}
                title={`Position de ${user.name ?? user.phone}`}
                heightClassName="h-72"
              />
            </CardContent>
          </Card>
        )}

        {/* Wallet */}
        {wallet && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base">
                <Wallet className="h-4 w-4" />
                Portefeuille
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Solde disponible</span>
                <span className="font-bold">
                  {xof.format(wallet.balance ?? 0)} XOF
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">En attente</span>
                <span className="font-medium text-amber-600">
                  {xof.format(wallet.pending ?? 0)} XOF
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Devise</span>
                <span>{wallet.currency ?? "XOF"}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Décaissements</span>
                <Badge tone={wallet.payout_blocked ? "danger" : "success"}>
                  {wallet.payout_blocked ? "Bloqués" : "Autorisés"}
                </Badge>
              </div>
              {wallet.payout_blocked && (
                <div className="rounded-md border border-red-200 bg-red-50 p-3 text-xs text-red-700">
                  {wallet.payout_block_reason || "Blocage manuel admin"}
                </div>
              )}
              <div className="pt-2">
                {wallet.payout_blocked ? (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setPayoutUnblockOpen(true)}
                  >
                    Débloquer les décaissements
                  </Button>
                ) : (
                  <Button
                    variant="destructive"
                    size="sm"
                    onClick={() => setPayoutBlockOpen(true)}
                  >
                    Bloquer les décaissements
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>
        )}

        {/* Linked relay */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <LinkIcon className="h-4 w-4" />
              Point relais lié
            </CardTitle>
          </CardHeader>
          <CardContent>
            {data.linked_relay ? (
              <div className="space-y-1 text-sm">
                <div className="font-medium">{data.linked_relay.name}</div>
                <div className="text-muted-foreground">
                  {data.linked_relay.city} — {data.linked_relay.relay_id}
                </div>
              </div>
            ) : (
              <div className="text-sm text-muted-foreground">
                Aucun relais lié.
              </div>
            )}
            {user.role === "relay_agent" && relays.data && (
              <div className="mt-3">
                <Select
                  value={user.relay_point_id ?? ""}
                  onValueChange={(val) => relayMut.mutate(val)}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder="Choisir un relais…" />
                  </SelectTrigger>
                  <SelectContent>
                    {relays.data.relay_points.map((r: any) => (
                      <SelectItem key={r.relay_id} value={r.relay_id}>
                        {r.name} — {r.city}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Active mission */}
        {data.active_mission && (
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Mission active</CardTitle>
            </CardHeader>
            <CardContent className="space-y-1 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">ID Mission</span>
                <span className="font-mono text-xs">{data.active_mission.mission_id}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Statut</span>
                <Badge tone="info">{data.active_mission.status}</Badge>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Pickup</span>
                <span>{data.active_mission.pickup_label ?? "—"}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Livraison</span>
                <span>{data.active_mission.delivery_label ?? "—"}</span>
              </div>
            </CardContent>
          </Card>
        )}

        {/* Referral */}
        {referral && (
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Parrainage</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Code</span>
                <span className="font-mono font-bold">{referral.code ?? "—"}</span>
              </div>
              <div className="space-y-1">
                <span className="text-muted-foreground">Lien parrainage</span>
                <div className="break-all rounded-md border bg-muted/30 p-2 font-mono text-xs">
                  {referralUrl || "—"}
                </div>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Filleuls</span>
                <span>{referral.referrals_count}</span>
              </div>
              {sponsoredReferrals && (
                <div className="space-y-3 rounded-lg border bg-muted/20 p-3">
                  <div className="grid gap-2 sm:grid-cols-4">
                    <InfoLine label="Total filleuls" value={sponsoredReferrals.total ?? 0} />
                    <InfoLine label="En attente" value={sponsoredReferrals.pending_rewards ?? 0} />
                    <InfoLine label="Récompensés" value={sponsoredReferrals.rewarded ?? 0} />
                    <InfoLine
                      label="Bonus parrain"
                      value={`${xof.format(sponsoredReferrals.total_sponsor_bonus_xof ?? 0)} XOF`}
                    />
                  </div>
                  {sponsoredItems.length > 0 ? (
                    <div className="overflow-x-auto">
                      <table className="w-full text-left text-xs">
                        <thead className="text-muted-foreground">
                          <tr>
                            <th className="py-2 pr-3">Filleul</th>
                            <th className="py-2 pr-3">Rôle</th>
                            <th className="py-2 pr-3">Statut</th>
                            <th className="py-2 pr-3">Progression</th>
                            <th className="py-2 pr-3">Bonus</th>
                          </tr>
                        </thead>
                        <tbody>
                          {sponsoredItems.map((item: any) => {
                            const status = String(item.status ?? "pending");
                            return (
                              <tr key={item.referral_id ?? item.referred_user_id} className="border-t">
                                <td className="py-2 pr-3">
                                  {item.referred_user_id ? (
                                    <Link
                                      href={`/dashboard/users/${item.referred_user_id}`}
                                      className="font-medium text-primary underline"
                                    >
                                      {textOrDash(item.referred_name)}
                                    </Link>
                                  ) : (
                                    textOrDash(item.referred_name)
                                  )}
                                  {item.referred_phone && (
                                    <div className="text-muted-foreground">{item.referred_phone}</div>
                                  )}
                                </td>
                                <td className="py-2 pr-3">
                                  {ROLE_LABELS[item.referred_role] ?? textOrDash(item.referred_role)}
                                </td>
                                <td className="py-2 pr-3">
                                  <Badge tone={REFERRAL_STATUS_TONES[status] ?? "default"}>
                                    {REFERRAL_STATUS_LABELS[status] ?? status}
                                  </Badge>
                                </td>
                                <td className="py-2 pr-3">
                                  {item.reward_metric_count ?? 0} / {item.reward_count ?? 1}
                                </td>
                                <td className="py-2 pr-3">
                                  {xof.format(item.sponsor_bonus_xof ?? 0)} XOF
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>
                  ) : (
                    <div className="text-xs text-muted-foreground">
                      Aucun filleul inscrit pour cet utilisateur.
                    </div>
                  )}
                </div>
              )}
              <div className="flex justify-between">
                <span className="text-muted-foreground">Actif</span>
                <Badge tone={referral.effective_enabled ? "success" : "default"}>
                  {referral.effective_enabled ? "Oui" : "Non"}
                </Badge>
              </div>
              {referral.referred_by_user && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Parrainé par</span>
                  <Link
                    href={`/dashboard/users/${referral.referred_by_user.user_id}`}
                    className="text-primary underline"
                  >
                    {referral.referred_by_user.name}
                  </Link>
                </div>
              )}
              <div className="flex flex-wrap gap-2 pt-2">
                <Button
                  size="sm"
                  variant="outline"
                  disabled={!referralUrl}
                  onClick={copyReferralLink}
                >
                  Copier le lien
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={!referralShareMessage}
                  onClick={copyReferralMessage}
                >
                  Copier le message
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={referralMut.isPending}
                  onClick={() => referralMut.mutate(true)}
                >
                  Forcer activer
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={referralMut.isPending}
                  onClick={() => referralMut.mutate(false)}
                >
                  Forcer désactiver
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={referralMut.isPending}
                  onClick={() => referralMut.mutate(null)}
                >
                  Auto
                </Button>
              </div>
            </CardContent>
          </Card>
        )}
      </div>

      {/* Recent events */}
      {data.recent_events && data.recent_events.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Événements récents</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2">
              {data.recent_events.map((ev: any, i: number) => (
                <div
                  key={i}
                  className="flex items-start justify-between rounded-md border p-3 text-sm"
                >
                  <div>
                    <Badge tone="info">{ev.event_type?.replace(/_/g, " ")}</Badge>
                    {ev.notes && (
                      <div className="mt-1 text-xs text-muted-foreground">
                        {ev.notes}
                      </div>
                    )}
                  </div>
                  <span className="shrink-0 text-xs text-muted-foreground">
                    {formatDate(ev.created_at)}
                  </span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* User history */}
      {history.data?.events && history.data.events.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Historique complet</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="max-h-96 space-y-2 overflow-y-auto">
              {history.data.events.map((ev: any, i: number) => (
                <div
                  key={i}
                  className="flex items-start justify-between rounded-md border p-3 text-sm"
                >
                  <div className="min-w-0">
                    <Badge tone="default">{ev.event_type?.replace(/_/g, " ")}</Badge>
                    {ev.tracking_code && (
                      <span className="ml-2 font-mono text-xs">{ev.tracking_code}</span>
                    )}
                    {ev.notes && (
                      <div className="mt-1 truncate text-xs text-muted-foreground">
                        {ev.notes}
                      </div>
                    )}
                  </div>
                  <span className="shrink-0 text-xs text-muted-foreground">
                    {formatDate(ev.created_at)}
                  </span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* ── Modals ── */}
      <ActionModal
        open={banOpen}
        onOpenChange={setBanOpen}
        title={`Bannir ${user.name ?? user.phone}`}
        description="L'utilisateur ne pourra plus se connecter. Ses sessions seront révoquées."
        inputLabel="Motif du bannissement"
        inputPlaceholder="Ex: fraude, documents invalides…"
        inputType="textarea"
        confirmLabel="Bannir"
        confirmVariant="destructive"
        onConfirm={async (reason) => {
          await banMut.mutateAsync(reason);
        }}
      />

      <ActionModal
        open={unbanOpen}
        onOpenChange={setUnbanOpen}
        title={`Débannir ${user.name ?? user.phone}`}
        description="L'utilisateur pourra de nouveau se connecter."
        inputLabel="Motif du débannissement"
        inputPlaceholder="Ex: erreur, correction…"
        inputType="textarea"
        confirmLabel="Débannir"
        onConfirm={async (reason) => {
          await unbanMut.mutateAsync(reason);
        }}
      />

      <ConfirmModal
        open={approvePhotoOpen}
        onOpenChange={setApprovePhotoOpen}
        title="Approuver la photo de profil"
        description="La photo pourra être affichée aux clients et le livreur pourra être assigné aux missions."
        confirmLabel="Approuver"
        onConfirm={async () => {
          await photoModerationMut.mutateAsync({ status: "approved" });
        }}
      />

      <ActionModal
        open={rejectPhotoOpen}
        onOpenChange={setRejectPhotoOpen}
        title="Désapprouver la photo de profil"
        description="Le livreur devra envoyer une nouvelle photo avant de pouvoir être disponible ou assigné."
        inputLabel="Motif du refus"
        inputPlaceholder="Ex: visage non visible, photo floue, document à la place..."
        inputType="textarea"
        confirmLabel="Désapprouver"
        confirmVariant="destructive"
        onConfirm={async (reason) => {
          await photoModerationMut.mutateAsync({ status: "rejected", reason });
        }}
      />

      <ActionModal
        open={payoutBlockOpen}
        onOpenChange={setPayoutBlockOpen}
        title="Bloquer les décaissements"
        description="Le livreur ne pourra plus demander ni faire valider un décaissement tant que le blocage reste actif."
        inputLabel="Motif du blocage"
        inputPlaceholder="Ex: litige en cours, contrôle manuel, dette à clarifier..."
        inputType="textarea"
        confirmLabel="Bloquer"
        confirmVariant="destructive"
        onConfirm={async (reason) => {
          await payoutBlockMut.mutateAsync({ blocked: true, reason });
          setPayoutBlockOpen(false);
        }}
      />

      <ConfirmModal
        open={payoutUnblockOpen}
        onOpenChange={setPayoutUnblockOpen}
        title="Débloquer les décaissements"
        description="Les décaissements seront de nouveau autorisés si aucune règle automatique ne les bloque."
        confirmLabel="Débloquer"
        onConfirm={async () => {
          await payoutBlockMut.mutateAsync({ blocked: false });
          setPayoutUnblockOpen(false);
        }}
      />

      {roleOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="w-full max-w-sm rounded-lg border bg-background p-6 shadow-lg">
            <h3 className="mb-4 text-lg font-semibold">Changer le rôle</h3>
            <div className="mb-4 flex flex-wrap gap-2">
              {ROLES.map((r) => (
                <button
                  key={r}
                  onClick={() => setSelectedRole(r)}
                  className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
                    selectedRole === r
                      ? "border-primary bg-primary text-primary-foreground"
                      : "border-input bg-background hover:bg-accent"
                  }`}
                >
                  {ROLE_LABELS[r]}
                </button>
              ))}
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" size="sm" onClick={() => setRoleOpen(false)}>
                Annuler
              </Button>
              <Button
                size="sm"
                disabled={selectedRole === user.role || roleMut.isPending}
                onClick={async () => {
                  await roleMut.mutateAsync(selectedRole);
                  setRoleOpen(false);
                }}
              >
                {roleMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
                Confirmer
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
