"use client";

import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  assignRelayPoint,
  banUser,
  changeUserRole,
  fetchRelays,
  fetchUserDetail,
  fetchUserHistory,
  setReferralAccess,
  unbanUser,
} from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ActionModal, ConfirmModal } from "@/components/action-modal";
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
  Users,
} from "lucide-react";
import Link from "next/link";

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
    queryFn: fetchRelays,
  });

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ["user-detail", id] });
    qc.invalidateQueries({ queryKey: ["users"], exact: false });
  };

  // ── Modals state ──
  const [banOpen, setBanOpen] = React.useState(false);
  const [unbanOpen, setUnbanOpen] = React.useState(false);
  const [roleOpen, setRoleOpen] = React.useState(false);
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
  const wallet = data.wallet;
  const referral = data.referral;

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

      <div className="grid gap-6 lg:grid-cols-2">
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
              <div className="flex justify-between">
                <span className="text-muted-foreground">Filleuls</span>
                <span>{referral.referrals_count}</span>
              </div>
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
              <div className="flex gap-2 pt-2">
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
