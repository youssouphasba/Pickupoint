"use client";

import * as React from "react";
import Link from "next/link";
import {
  AlertTriangle,
  Bell,
  CheckCheck,
  FileText,
  Info,
  Package,
  RotateCcw,
  Scale,
  Settings,
  Truck,
  Undo2,
  Wallet,
  XCircle,
} from "lucide-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  markAdminEventRead,
  markAllAdminEventsRead,
  type AdminEvent,
} from "@/lib/api";
import { useAdminEvents } from "@/lib/use-admin-events";
import { useAdminAlertNotifications } from "@/lib/use-admin-alert-notifications";
import { cn } from "@/lib/utils";

const ICON_BY_TYPE: Record<string, React.ComponentType<{ className?: string }>> = {
  payout_requested: Wallet,
  payout_approved: Wallet,
  payout_rejected: Wallet,
  incident_reported: AlertTriangle,
  parcel_disputed: Scale,
  application_submitted: FileText,
  mission_critical_delay: Truck,
  signal_lost: Truck,
  parcel_stale: Package,
  parcel_redirected: RotateCcw,
  parcel_cancelled: XCircle,
  mission_released: Undo2,
};

function eventIcon(type: string) {
  return ICON_BY_TYPE[type] ?? Info;
}

function severityClasses(sev: AdminEvent["severity"]): {
  dot: string;
  chip: string;
} {
  if (sev === "critical")
    return { dot: "bg-red-500", chip: "bg-red-50 text-red-700" };
  if (sev === "warning")
    return { dot: "bg-amber-500", chip: "bg-amber-50 text-amber-700" };
  return { dot: "bg-muted-foreground/40", chip: "bg-muted text-foreground" };
}

function formatRelative(iso: string): string {
  const d = new Date(iso);
  const diff = Date.now() - d.getTime();
  const sec = Math.round(diff / 1000);
  if (sec < 60) return "à l'instant";
  const min = Math.round(sec / 60);
  if (min < 60) return `il y a ${min} min`;
  const h = Math.round(min / 60);
  if (h < 24) return `il y a ${h} h`;
  const j = Math.round(h / 24);
  return `il y a ${j} j`;
}

const absoluteFormatter = new Intl.DateTimeFormat("fr-FR", {
  dateStyle: "medium",
  timeStyle: "short",
});

function formatAbsolute(iso: string): string {
  try {
    return absoluteFormatter.format(new Date(iso));
  } catch {
    return iso;
  }
}

export function NotificationBell() {
  const [open, setOpen] = React.useState(false);
  const panelRef = React.useRef<HTMLDivElement | null>(null);
  const btnRef = React.useRef<HTMLButtonElement | null>(null);
  const qc = useQueryClient();
  const { data, isLoading } = useAdminEvents(30);

  useAdminAlertNotifications(data?.events);

  const unread = data?.unread_count ?? 0;
  const events = data?.events ?? [];

  React.useEffect(() => {
    if (!open) return;
    function onClick(e: MouseEvent) {
      const target = e.target as Node;
      if (
        panelRef.current &&
        !panelRef.current.contains(target) &&
        btnRef.current &&
        !btnRef.current.contains(target)
      ) {
        setOpen(false);
      }
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onClick);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onClick);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const markOne = useMutation({
    mutationFn: (eventId: string) => markAdminEventRead(eventId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["admin-events"] });
    },
  });

  const markAll = useMutation({
    mutationFn: () => markAllAdminEventsRead(),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["admin-events"] });
    },
  });

  function handleItemClick(ev: AdminEvent) {
    if (!ev.is_read) markOne.mutate(ev.event_id);
    setOpen(false);
  }

  return (
    <div className="relative">
      <button
        ref={btnRef}
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-label={
          unread > 0
            ? `Notifications (${unread} non lue${unread > 1 ? "s" : ""})`
            : "Notifications"
        }
        className={cn(
          "relative inline-flex h-9 w-9 items-center justify-center rounded-full border bg-background text-muted-foreground transition-colors hover:bg-accent hover:text-foreground",
          unread > 0 && "text-foreground"
        )}
      >
        <Bell className="h-[18px] w-[18px]" />
        {unread > 0 && (
          <span
            className={cn(
              "absolute -right-1 -top-1 inline-flex min-w-[18px] items-center justify-center rounded-full px-1 text-[10px] font-semibold leading-[18px] text-white",
              events[0]?.severity === "critical"
                ? "bg-red-600"
                : "bg-amber-500"
            )}
          >
            {unread > 99 ? "99+" : unread}
          </span>
        )}
      </button>

      {open && (
        <div
          ref={panelRef}
          className="absolute right-0 top-[calc(100%+8px)] z-50 w-[380px] overflow-hidden rounded-xl border bg-background shadow-lg"
        >
          <div className="flex items-center justify-between border-b px-4 py-3">
            <div>
              <div className="text-sm font-semibold">Notifications</div>
              <div className="text-xs text-muted-foreground">
                {unread > 0
                  ? `${unread} non lue${unread > 1 ? "s" : ""}`
                  : "Tout est à jour"}
              </div>
            </div>
            <div className="flex items-center gap-1">
              <button
                type="button"
                disabled={unread === 0 || markAll.isPending}
                onClick={() => markAll.mutate()}
                className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-muted-foreground hover:bg-accent hover:text-foreground disabled:opacity-40"
              >
                <CheckCheck className="h-3.5 w-3.5" />
                Tout lire
              </button>
              <Link
                href="/dashboard/settings/alerts"
                onClick={() => setOpen(false)}
                className="inline-flex h-7 w-7 items-center justify-center rounded-md text-muted-foreground hover:bg-accent hover:text-foreground"
                aria-label="Préférences d'alertes"
              >
                <Settings className="h-3.5 w-3.5" />
              </Link>
            </div>
          </div>

          <div className="max-h-[420px] overflow-y-auto">
            {isLoading && (
              <div className="p-6 text-center text-sm text-muted-foreground">
                Chargement…
              </div>
            )}
            {!isLoading && events.length === 0 && (
              <div className="p-6 text-center text-sm text-muted-foreground">
                Aucune notification récente.
              </div>
            )}
            {!isLoading &&
              events.map((ev) => {
                const Icon = eventIcon(ev.event_type);
                const sev = severityClasses(ev.severity);
                const content = (
                  <div
                    className={cn(
                      "flex gap-3 border-b px-4 py-3 last:border-b-0 transition-colors",
                      ev.is_read ? "bg-background" : "bg-emerald-50/40",
                      "hover:bg-accent"
                    )}
                  >
                    <div
                      className={cn(
                        "flex h-8 w-8 shrink-0 items-center justify-center rounded-md",
                        sev.chip
                      )}
                    >
                      <Icon className="h-4 w-4" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-start gap-2">
                        <div className="min-w-0 flex-1 text-sm font-medium leading-tight">
                          {ev.title}
                        </div>
                        {!ev.is_read && (
                          <span
                            className={cn(
                              "mt-1 inline-block h-2 w-2 shrink-0 rounded-full",
                              sev.dot
                            )}
                          />
                        )}
                      </div>
                      {ev.message && (
                        <div className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">
                          {ev.message}
                        </div>
                      )}
                      <div
                        className="mt-1 text-[11px] text-muted-foreground"
                        title={formatAbsolute(ev.created_at)}
                      >
                        {formatRelative(ev.created_at)}
                      </div>
                    </div>
                  </div>
                );
                return ev.href ? (
                  <Link
                    key={ev.event_id}
                    href={ev.href}
                    onClick={() => handleItemClick(ev)}
                  >
                    {content}
                  </Link>
                ) : (
                  <button
                    key={ev.event_id}
                    type="button"
                    onClick={() => handleItemClick(ev)}
                    className="w-full text-left"
                  >
                    {content}
                  </button>
                );
              })}
          </div>
        </div>
      )}
    </div>
  );
}
