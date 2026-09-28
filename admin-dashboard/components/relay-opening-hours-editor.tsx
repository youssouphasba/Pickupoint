"use client";

import * as React from "react";
import { Input } from "@/components/ui/input";

export const RELAY_DAYS = [
  ["monday", "Lundi"],
  ["tuesday", "Mardi"],
  ["wednesday", "Mercredi"],
  ["thursday", "Jeudi"],
  ["friday", "Vendredi"],
  ["saturday", "Samedi"],
  ["sunday", "Dimanche"],
] as const;

export type RelayOpeningHours = Record<string, {
  enabled: boolean;
  open: string;
  close: string;
}>;

function emptyHours(): RelayOpeningHours {
  return Object.fromEntries(
    RELAY_DAYS.map(([day]) => [day, { enabled: false, open: "08:00", close: "20:00" }]),
  );
}

function parseLegacy(value: string): RelayOpeningHours {
  const result = emptyHours();
  const range = value.match(/(\d{1,2}(?::\d{2})?|\d{1,2}h)\s*[-–]\s*(\d{1,2}(?::\d{2})?|\d{1,2}h)/i);
  if (!range) return result;
  const open = range[1].replace("h", ":").replace(/:$/, ":00");
  const close = range[2].replace("h", ":").replace(/:$/, ":00");
  const normalized = value.toLowerCase();
  const count = normalized.includes("lun-sam") || normalized.includes("lun–sam")
    ? 6
    : normalized.includes("lun-ven") || normalized.includes("lun–ven") ? 5 : 7;
  RELAY_DAYS.slice(0, count).forEach(([day]) => {
    result[day] = { enabled: true, open, close };
  });
  return result;
}

export function normalizeRelayOpeningHours(value: unknown): RelayOpeningHours {
  if (typeof value === "string") return parseLegacy(value);
  const result = emptyHours();
  if (!value || typeof value !== "object") return result;
  const source = value as Record<string, unknown>;
  RELAY_DAYS.forEach(([day]) => {
    const raw = source[day];
    if (!raw || typeof raw !== "object") return;
    const entry = raw as Record<string, unknown>;
    result[day] = {
      enabled: entry.enabled !== false && Boolean(entry.open) && Boolean(entry.close),
      open: String(entry.open ?? "08:00"),
      close: String(entry.close ?? "20:00"),
    };
  });
  return result;
}

export function formatRelayOpeningHours(value: unknown): string {
  const hours = normalizeRelayOpeningHours(value);
  return RELAY_DAYS
    .filter(([day]) => hours[day]?.enabled)
    .map(([day, label]) => `${label.slice(0, 3)} ${hours[day].open}–${hours[day].close}`)
    .join(" · ") || "Fermé tous les jours";
}

export function RelayOpeningHoursEditor({
  value,
  onChange,
}: {
  value: unknown;
  onChange: (value: RelayOpeningHours) => void;
}) {
  const hours = normalizeRelayOpeningHours(value);
  return (
    <div className="space-y-2 rounded-lg border p-3">
      <div>
        <div className="text-sm font-medium">Jours et horaires d’ouverture</div>
        <div className="text-xs text-muted-foreground">Un jour non sélectionné sera affiché comme fermé.</div>
      </div>
      <div className="space-y-2">
        {RELAY_DAYS.map(([day, label]) => {
          const entry = hours[day];
          return (
            <div key={day} className="grid items-center gap-2 sm:grid-cols-[7rem_auto_1fr_1fr]">
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={entry.enabled}
                  onChange={(event) => onChange({ ...hours, [day]: { ...entry, enabled: event.target.checked } })}
                />
                {label}
              </label>
              <span className="text-xs text-muted-foreground">{entry.enabled ? "Ouvert" : "Fermé"}</span>
              <Input
                type="time"
                value={entry.open}
                disabled={!entry.enabled}
                onChange={(event) => onChange({ ...hours, [day]: { ...entry, open: event.target.value } })}
              />
              <Input
                type="time"
                value={entry.close}
                disabled={!entry.enabled}
                onChange={(event) => onChange({ ...hours, [day]: { ...entry, close: event.target.value } })}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
}
