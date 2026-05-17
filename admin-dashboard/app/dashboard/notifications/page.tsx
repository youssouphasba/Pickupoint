"use client";

import * as React from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import { Bell, Loader2, Send } from "lucide-react";
import {
  AdminUser,
  fetchNotificationBroadcasts,
  fetchUsers,
  sendTargetedNotification,
} from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { DataTable } from "@/components/data-table";
import { SecureProfileImage } from "@/components/secure-profile-image";
import { useToast } from "@/components/ui/toaster";

const ROLE_LABELS: Record<string, string> = {
  client: "Client",
  driver: "Livreur",
  relay_agent: "Agent relais",
  admin: "Admin",
  superadmin: "Super admin",
};

const ROLE_FILTERS = [
  { value: "all", label: "Tous les rôles" },
  { value: "client", label: "Clients" },
  { value: "driver", label: "Livreurs" },
  { value: "relay_agent", label: "Agents relais" },
  { value: "admin", label: "Admins" },
];

const CATEGORY_OPTIONS = [
  { value: "admin", label: "Information importante" },
  { value: "messages", label: "Message" },
  { value: "promotions", label: "Promotion" },
  { value: "parcel_updates", label: "Colis" },
] as const;

function userDisplayName(user: AdminUser) {
  return user.name ?? user.full_name ?? "Sans nom";
}

export default function TargetedNotificationsPage() {
  const { toast } = useToast();
  const [role, setRole] = React.useState("all");
  const [selectedIds, setSelectedIds] = React.useState<Set<string>>(new Set());
  const [title, setTitle] = React.useState("");
  const [body, setBody] = React.useState("");
  const [category, setCategory] = React.useState<
    "admin" | "messages" | "promotions" | "parcel_updates"
  >("admin");

  const { data, isLoading, isError } = useQuery({
    queryKey: ["notification-users", role],
    queryFn: () =>
      fetchUsers({ limit: 500, role: role === "all" ? undefined : role }),
  });
  const historyQuery = useQuery({
    queryKey: ["notification-broadcasts"],
    queryFn: () => fetchNotificationBroadcasts(50),
  });

  const users = data?.users ?? [];
  const selectedUsers = React.useMemo(
    () => users.filter((user) => selectedIds.has(user.user_id)),
    [selectedIds, users],
  );
  const allLoadedSelected =
    users.length > 0 && users.every((user) => selectedIds.has(user.user_id));

  const sendMut = useMutation({
    mutationFn: () =>
      sendTargetedNotification({
        title: title.trim(),
        body: body.trim(),
        category,
        user_ids: Array.from(selectedIds),
      }),
    onSuccess: (result) => {
      toast(
        `${result.sent} notification${result.sent > 1 ? "s" : ""} envoyée${result.sent > 1 ? "s" : ""}.`,
      );
      historyQuery.refetch();
      setSelectedIds(new Set());
      setTitle("");
      setBody("");
    },
  });

  const toggleUser = React.useCallback((userId: string) => {
    setSelectedIds((current) => {
      const next = new Set(current);
      if (next.has(userId)) {
        next.delete(userId);
      } else {
        next.add(userId);
      }
      return next;
    });
  }, []);

  const toggleAllLoaded = React.useCallback(() => {
    setSelectedIds((current) => {
      const next = new Set(current);
      if (allLoadedSelected) {
        users.forEach((user) => next.delete(user.user_id));
      } else {
        users.forEach((user) => next.add(user.user_id));
      }
      return next;
    });
  }, [allLoadedSelected, users]);

  const columns = React.useMemo<ColumnDef<AdminUser, any>[]>(
    () => [
      {
        id: "select",
        header: () => (
          <input
            type="checkbox"
            className="h-4 w-4 rounded border-input"
            checked={allLoadedSelected}
            onChange={toggleAllLoaded}
            aria-label="Sélectionner les utilisateurs chargés"
          />
        ),
        enableSorting: false,
        cell: ({ row }) => (
          <input
            type="checkbox"
            className="h-4 w-4 rounded border-input"
            checked={selectedIds.has(row.original.user_id)}
            onChange={() => toggleUser(row.original.user_id)}
            aria-label={`Sélectionner ${userDisplayName(row.original)}`}
          />
        ),
      },
      {
        id: "name",
        header: "Utilisateur",
        accessorFn: userDisplayName,
        cell: ({ row }) => {
          const user = row.original;
          const displayName = userDisplayName(user);
          return (
            <div className="flex items-center gap-3">
              <SecureProfileImage
                src={user.profile_picture_url}
                alt={`Photo de ${displayName}`}
                className="h-10 w-10 shrink-0"
              />
              <span className="flex min-w-0 flex-col">
                <span className="font-medium">{displayName}</span>
                <span className="text-xs text-muted-foreground">{user.phone}</span>
              </span>
            </div>
          );
        },
      },
      {
        id: "role",
        header: "Rôle",
        accessorKey: "role",
        cell: ({ getValue }) => {
          const roleValue = (getValue() as string) ?? "client";
          return <Badge>{ROLE_LABELS[roleValue] ?? roleValue}</Badge>;
        },
      },
      {
        id: "status",
        header: "Statut",
        accessorFn: (user) =>
          user.is_banned ? "banned" : user.is_active ? "active" : "inactive",
        cell: ({ row }) => {
          const user = row.original;
          if (user.is_banned) return <Badge tone="danger">Suspendu</Badge>;
          if (!user.is_active) return <Badge tone="default">Inactif</Badge>;
          return <Badge tone="success">Actif</Badge>;
        },
      },
    ],
    [allLoadedSelected, selectedIds, toggleAllLoaded, toggleUser],
  );

  const canSend =
    selectedIds.size > 0 &&
    title.trim().length >= 2 &&
    body.trim().length >= 3 &&
    !sendMut.isPending;

  return (
    <div className="space-y-6 p-8">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold">
            <Bell className="h-6 w-6 text-primary" />
            Notifications ciblées
          </h1>
          <p className="text-sm text-muted-foreground">
            Envoyer une notification in-app et push à un ou plusieurs utilisateurs.
          </p>
        </div>
        <Badge tone="info">
          {selectedIds.size} sélectionné{selectedIds.size > 1 ? "s" : ""}
        </Badge>
      </div>

      <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_380px]">
        <Card>
          <CardHeader>
            <CardTitle>Destinataires</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex max-w-xs flex-col gap-2">
              <label className="text-sm font-medium">Filtrer par rôle</label>
              <Select value={role} onValueChange={setRole}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {ROLE_FILTERS.map((filter) => (
                    <SelectItem key={filter.value} value={filter.value}>
                      {filter.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {isLoading && (
              <div className="flex h-40 items-center justify-center">
                <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              </div>
            )}
            {isError && (
              <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
                Impossible de charger les utilisateurs.
              </div>
            )}
            {data && (
              <DataTable
                columns={columns}
                data={users}
                pageSize={10}
                searchPlaceholder="Nom, téléphone, e-mail, ID..."
                toolbar={
                  <div className="flex flex-wrap gap-2">
                    <Button variant="outline" size="sm" onClick={toggleAllLoaded}>
                      {allLoadedSelected ? "Désélectionner" : "Sélectionner"} les résultats
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setSelectedIds(new Set())}
                      disabled={selectedIds.size === 0}
                    >
                      Vider
                    </Button>
                  </div>
                }
                globalFilterFn={(user, query) =>
                  userDisplayName(user).toLowerCase().includes(query) ||
                  (user.phone ?? "").toLowerCase().includes(query) ||
                  (user.email ?? "").toLowerCase().includes(query) ||
                  (user.user_id ?? "").toLowerCase().includes(query)
                }
              />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Message</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <label className="text-sm font-medium">Type</label>
              <Select value={category} onValueChange={(value) => setCategory(value as typeof category)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {CATEGORY_OPTIONS.map((option) => (
                    <SelectItem key={option.value} value={option.value}>
                      {option.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium">Titre</label>
              <Input
                value={title}
                maxLength={90}
                onChange={(event) => setTitle(event.target.value)}
                placeholder="Ex : Information importante"
              />
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium">Message</label>
              <Textarea
                value={body}
                maxLength={600}
                onChange={(event) => setBody(event.target.value)}
                placeholder="Écrivez le message à envoyer aux utilisateurs sélectionnés."
                className="min-h-36"
              />
              <p className="text-xs text-muted-foreground">
                {body.length}/600 caractères
              </p>
            </div>

            <div className="rounded-lg border bg-muted/30 p-3 text-sm">
              <div className="font-medium">Aperçu</div>
              <div className="mt-2 rounded-lg border bg-background p-3">
                <div className="font-semibold">{title || "Titre de la notification"}</div>
                <div className="mt-1 text-sm text-muted-foreground">
                  {body || "Votre message apparaîtra ici."}
                </div>
              </div>
            </div>

            <div className="rounded-lg border bg-background p-3 text-sm">
              <div className="font-medium">Destinataires sélectionnés</div>
              <div className="mt-2 max-h-32 space-y-1 overflow-y-auto text-muted-foreground">
                {selectedUsers.length === 0
                  ? "Aucun utilisateur sélectionné."
                  : selectedUsers.map((user) => (
                      <div key={user.user_id}>
                        {userDisplayName(user)} · {ROLE_LABELS[user.role] ?? user.role}
                      </div>
                    ))}
              </div>
            </div>

            <Button className="w-full" disabled={!canSend} onClick={() => sendMut.mutate()}>
              {sendMut.isPending ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Send className="h-4 w-4" />
              )}
              Envoyer la notification
            </Button>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Historique des envois</CardTitle>
        </CardHeader>
        <CardContent>
          {historyQuery.isLoading ? (
            <div className="flex h-24 items-center justify-center">
              <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
            </div>
          ) : historyQuery.isError ? (
            <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
              Impossible de charger l’historique.
            </div>
          ) : (historyQuery.data?.broadcasts.length ?? 0) === 0 ? (
            <div className="rounded-lg border bg-muted/30 p-4 text-sm text-muted-foreground">
              Aucun envoi manuel pour le moment.
            </div>
          ) : (
            <div className="overflow-hidden rounded-lg border">
              <table className="w-full text-sm">
                <thead className="bg-muted/40">
                  <tr>
                    <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                      Message
                    </th>
                    <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                      Cible
                    </th>
                    <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                      Envoyées
                    </th>
                    <th className="px-4 py-2.5 text-left text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                      Date
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {historyQuery.data?.broadcasts.map((broadcast) => (
                    <tr key={broadcast.broadcast_id} className="border-t">
                      <td className="max-w-xl px-4 py-3">
                        <div className="font-medium">{broadcast.title}</div>
                        <div className="mt-1 line-clamp-2 text-xs text-muted-foreground">
                          {broadcast.body}
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        {broadcast.target_role
                          ? ROLE_LABELS[broadcast.target_role] ?? broadcast.target_role
                          : "Sélection manuelle"}
                      </td>
                      <td className="px-4 py-3">
                        {broadcast.sent_count}/{broadcast.matched_count}
                      </td>
                      <td className="px-4 py-3 text-muted-foreground">
                        {broadcast.created_at
                          ? new Date(broadcast.created_at).toLocaleString("fr-FR")
                          : "—"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
