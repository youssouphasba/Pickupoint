"use client";

import * as React from "react";
import type { AdminEvent } from "@/lib/api";

const STORAGE_KEY = "denkma_admin_alerts_prefs";
const LAST_SEEN_KEY = "denkma_admin_alerts_last_seen";

export type AlertPrefs = {
  // Permission utilisateur pour les notifications navigateur.
  desktop: boolean;
  // Severities qu'on veut afficher en desktop (toujours sauvegarde un doc json
  // pour pouvoir l'éditer depuis la page réglages).
  severities: {
    critical: boolean;
    warning: boolean;
    info: boolean;
  };
  // Types d'événements désactivés individuellement.
  mutedTypes: string[];
};

export const DEFAULT_PREFS: AlertPrefs = {
  desktop: false,
  severities: { critical: true, warning: true, info: false },
  mutedTypes: [],
};

export function loadPrefs(): AlertPrefs {
  if (typeof window === "undefined") return DEFAULT_PREFS;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_PREFS;
    const parsed = JSON.parse(raw) as Partial<AlertPrefs>;
    return {
      desktop: Boolean(parsed.desktop),
      severities: {
        critical: parsed.severities?.critical ?? true,
        warning: parsed.severities?.warning ?? true,
        info: parsed.severities?.info ?? false,
      },
      mutedTypes: Array.isArray(parsed.mutedTypes) ? parsed.mutedTypes : [],
    };
  } catch {
    return DEFAULT_PREFS;
  }
}

export function savePrefs(prefs: AlertPrefs) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs));
}

/**
 * Met à jour le favicon dynamiquement avec une pastille + compteur.
 * On conserve l'URL d'origine pour pouvoir la restaurer quand unread passe à 0.
 */
function setFaviconBadge(count: number) {
  if (typeof document === "undefined") return;
  const link =
    (document.querySelector("link[rel='icon']") as HTMLLinkElement | null) ??
    (() => {
      const l = document.createElement("link");
      l.rel = "icon";
      document.head.appendChild(l);
      return l;
    })();

  if (!link.dataset.original) {
    link.dataset.original = link.href || "";
  }

  if (count <= 0) {
    if (link.dataset.original) {
      link.href = link.dataset.original;
    } else {
      link.removeAttribute("href");
    }
    return;
  }

  const size = 32;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  // Fond arrondi vert Denkma.
  ctx.fillStyle = "#0b8a5f";
  ctx.beginPath();
  const r = 7;
  ctx.moveTo(r, 0);
  ctx.arcTo(size, 0, size, size, r);
  ctx.arcTo(size, size, 0, size, r);
  ctx.arcTo(0, size, 0, 0, r);
  ctx.arcTo(0, 0, size, 0, r);
  ctx.closePath();
  ctx.fill();

  // Lettre D centrale.
  ctx.fillStyle = "#ffffff";
  ctx.font = "bold 18px -apple-system, BlinkMacSystemFont, sans-serif";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText("D", size / 2, size / 2 + 1);

  // Pastille rouge avec compteur.
  const badgeSize = 16;
  const cx = size - badgeSize / 2;
  const cy = badgeSize / 2;
  ctx.fillStyle = "#dc2626";
  ctx.beginPath();
  ctx.arc(cx, cy, badgeSize / 2, 0, Math.PI * 2);
  ctx.fill();

  ctx.fillStyle = "#ffffff";
  ctx.font = "bold 10px -apple-system, BlinkMacSystemFont, sans-serif";
  ctx.fillText(count > 9 ? "9+" : String(count), cx, cy + 1);

  link.href = canvas.toDataURL("image/png");
}

/**
 * Hook branché sur le feed d'événements admin.
 * - Met à jour le favicon avec le compteur non-lus.
 * - Joue une notification navigateur pour les nouveaux events critiques/warning
 *   (selon préférences), sans jamais renotifier un event déjà vu.
 */
export function useAdminAlertNotifications(events: AdminEvent[] | undefined) {
  const initializedRef = React.useRef(false);

  React.useEffect(() => {
    if (!events) return;
    const unread = events.filter((e) => !e.is_read).length;
    setFaviconBadge(unread);
  }, [events]);

  React.useEffect(() => {
    if (!events || typeof window === "undefined") return;

    const prefs = loadPrefs();

    // Premier chargement : on enregistre les ids vus mais on ne notifie pas
    // (sinon on déclenche un son dès l'ouverture).
    const lastSeen = window.localStorage.getItem(LAST_SEEN_KEY);
    if (!initializedRef.current && !lastSeen && events[0]) {
      window.localStorage.setItem(LAST_SEEN_KEY, events[0].created_at);
      initializedRef.current = true;
      return;
    }
    initializedRef.current = true;

    if (!prefs.desktop) {
      // On avance quand même le curseur "dernière vue" pour éviter un rattrapage
      // massif si l'utilisateur réactive plus tard.
      if (events[0]) {
        window.localStorage.setItem(LAST_SEEN_KEY, events[0].created_at);
      }
      return;
    }

    if (
      typeof Notification === "undefined" ||
      Notification.permission !== "granted"
    ) {
      return;
    }

    const cutoff = lastSeen ? new Date(lastSeen).getTime() : 0;
    const fresh = events
      .filter((e) => new Date(e.created_at).getTime() > cutoff)
      .filter((e) => prefs.severities[e.severity])
      .filter((e) => !prefs.mutedTypes.includes(e.event_type));

    // Plus ancien d'abord pour que la plus récente reste en haut.
    fresh.reverse().forEach((ev) => {
      try {
        const notif = new Notification(ev.title, {
          body: ev.message || undefined,
          icon: "/favicon.ico",
          tag: ev.event_id,
          requireInteraction: ev.severity === "critical",
        });
        if (ev.href) {
          notif.onclick = () => {
            window.focus();
            window.location.href = ev.href as string;
            notif.close();
          };
        }
      } catch {
        // Safari peut lever si la permission est encore "default".
      }
    });

    if (events[0]) {
      window.localStorage.setItem(LAST_SEEN_KEY, events[0].created_at);
    }
  }, [events]);
}
