"use client";

import * as React from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ColumnDef } from "@tanstack/react-table";
import {
  AdminApplication,
  approveApplication,
  fetchApplications,
  moderateProfilePhoto,
  rejectApplication,
} from "@/lib/api";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/toaster";
import { formatDate } from "@/lib/utils";
import { CheckCircle2, Eye, Loader2, XCircle } from "lucide-react";

const STATUS_LABELS: Record<string, string> = {
  pending: "En attente",
  approved: "Approuvée",
  rejected: "Rejetée",
};

const STATUS_TONES: Record<string, "success" | "warning" | "danger" | "default"> = {
  pending: "warning",
  approved: "success",
  rejected: "danger",
};

const PHOTO_LABELS: Record<string, string> = {
  approved: "Photo approuvée",
  pending: "Photo à vérifier",
  rejected: "Photo refusée",
  missing: "Photo absente",
};

const PHOTO_TONES: Record<string, "success" | "warning" | "danger" | "default"> = {
  approved: "success",
  pending: "warning",
  rejected: "danger",
  missing: "default",
};

function applicationName(application: AdminApplication) {
  return (
    application.user?.name ||
    application.user?.full_name ||
    application.user_name ||
    application.data?.full_name ||
    application.data?.business_name ||
    application.user_phone ||
    "Candidat"
  );
}

function applicationPhone(application: AdminApplication) {
  return application.user?.phone || application.user_phone || "—";
}

function photoStatus(application: AdminApplication) {
  return (
    application.user?.profile_picture_status ||
    application.profile_picture_status ||
    "missing"
  );
}

export default function ApplicationsPage() {
  const qc = useQueryClient();
  const { toast } = useToast();
  const [status, setStatus] = React.useState("pending");

  const query = useQuery({
    queryKey: ["applications", status],
    queryFn: () =>
      fetchApplications({
        status: status === "all" ? undefined : status,
      }),
  });

  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["applications"] });
    qc.invalidateQueries({ queryKey: ["users"], exact: false });
  };

  const approveMut = useMutation({
    mutationFn: ({ id, notes }: { id: string; notes?: string }) =>
      approveApplication(id, notes),
    onSuccess: () => {
      refresh();
      toast("Candidature approuvée.");
    },
    onError: (error) => toast(error instanceof Error ? error.message : "Validation impossible."),
  });

  const rejectMut = useMutation({
    mutationFn: ({ id, notes }: { id: string; notes?: string }) =>
      rejectApplication(id, notes),
    onSuccess: () => {
      refresh();
      toast("Candidature rejetée.");
    },
    onError: (error) => toast(error instanceof Error ? error.message : "Rejet impossible."),
  });

  const photoMut = useMutation({
    mutationFn: ({
      userId,
      nextStatus,
      reason,
    }: {
      userId: string;
      nextStatus: "approved" | "rejected";
      reason?: string;
    }) => moderateProfilePhoto(userId, nextStatus, reason),
    onSuccess: () => {
      refresh();
      toast("Photo de profil mise à jour.");
    },
    onError: (error) => toast(error instanceof Error ? error.message : "Modération photo impossible."),
  });

  const columns = React.useMemo<ColumnDef<AdminApplication, any>[]>(
    () => [
      {
        id: "candidate",
        header: "Candidat",
        accessorFn: applicationName,
        cell: ({ row }) => (
          <div className="flex flex-col">
            <span className="font-medium">{applicationName(row.original)}</span>
            <span className="text-xs text-muted-foreground">
              {applicationPhone(row.original)}
            </span>
          </div>
        ),
      },
      {
        id: "type",
        header: "Type",
        accessorKey: "type",
        cell: ({ row }) => (
          <Badge tone={row.original.type === "driver" ? "info" : "warning"}>
            {row.original.type === "driver" ? "Livreur" : "Point relais"}
          </Badge>
        ),
      },
      {
        id: "status",
        header: "Statut",
        accessorKey: "status",
        cell: ({ row }) => (
          <Badge tone={STATUS_TONES[row.original.status] ?? "default"}>
            {STATUS_LABELS[row.original.status] ?? row.original.status}
          </Badge>
        ),
      },
      {
        id: "photo",
        header: "Photo",
        accessorFn: photoStatus,
        cell: ({ row }) => {
          const value = photoStatus(row.original);
          const hasPhoto = Boolean(row.original.user?.profile_picture_url || row.original.profile_picture_url);
          return (
            <div className="flex flex-col gap-2">
              <Badge tone={PHOTO_TONES[value] ?? "default"}>
                {PHOTO_LABELS[value] ?? value}
              </Badge>
              {row.original.type === "driver" && hasPhoto && value !== "approved" && (
                <div className="flex gap-2">
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={photoMut.isPending}
                    onClick={() =>
                      photoMut.mutate({
                        userId: row.original.user_id,
                        nextStatus: "approved",
                      })
                    }
                  >
                    Approuver
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={photoMut.isPending}
                    onClick={() => {
                      const reason = window.prompt("Motif du refus de photo");
                      if (!reason) return;
                      photoMut.mutate({
                        userId: row.original.user_id,
                        nextStatus: "rejected",
                        reason,
                      });
                    }}
                  >
                    Refuser
                  </Button>
                </div>
              )}
            </div>
          );
        },
      },
      {
        id: "created",
        header: "Soumise le",
        accessorKey: "created_at",
        cell: ({ row }) => (
          <span className="text-xs text-muted-foreground">
            {formatDate(row.original.created_at)}
          </span>
        ),
      },
      {
        id: "actions",
        header: "Actions",
        enableSorting: false,
        cell: ({ row }) => {
          const application = row.original;
          const pending = application.status === "pending";
          return (
            <div className="flex flex-wrap gap-2">
              <Button asChild size="sm" variant="outline">
                <Link href={`/dashboard/users/${application.user_id}`}>
                  <Eye className="h-4 w-4" />
                  Dossier
                </Link>
              </Button>
              {pending && (
                <Button
                  size="sm"
                  disabled={approveMut.isPending}
                  onClick={() => {
                    const notes = window.prompt("Note interne optionnelle") ?? undefined;
                    approveMut.mutate({ id: application.application_id, notes });
                  }}
                >
                  <CheckCircle2 className="h-4 w-4" />
                  Approuver
                </Button>
              )}
              {pending && (
                <Button
                  size="sm"
                  variant="destructive"
                  disabled={rejectMut.isPending}
                  onClick={() => {
                    const notes = window.prompt("Raison du rejet");
                    if (!notes) return;
                    rejectMut.mutate({ id: application.application_id, notes });
                  }}
                >
                  <XCircle className="h-4 w-4" />
                  Rejeter
                </Button>
              )}
            </div>
          );
        },
      },
    ],
    [approveMut, rejectMut, photoMut],
  );

  const applications = query.data?.applications ?? [];

  return (
    <div className="space-y-5 p-8">
      <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 className="text-2xl font-bold">Candidatures</h1>
          <p className="text-sm text-muted-foreground">
            Dossiers livreurs et relais avec documents, photo de profil et validation.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {["pending", "approved", "rejected", "all"].map((value) => (
            <Button
              key={value}
              size="sm"
              variant={status === value ? "default" : "outline"}
              onClick={() => setStatus(value)}
            >
              {value === "all" ? "Toutes" : STATUS_LABELS[value]}
            </Button>
          ))}
        </div>
      </div>

      {query.isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {query.isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement des candidatures.
        </div>
      )}
      {!query.isLoading && !query.isError && (
        <DataTable
          columns={columns}
          data={applications}
          searchPlaceholder="Nom, téléphone, dossier..."
          globalFilterFn={(application, q) => {
            const haystack = [
              applicationName(application),
              applicationPhone(application),
              application.application_id,
              application.data?.full_name,
              application.data?.business_name,
            ]
              .join(" ")
              .toLowerCase();
            return haystack.includes(q);
          }}
          emptyLabel="Aucune candidature pour ce filtre."
        />
      )}
    </div>
  );
}
