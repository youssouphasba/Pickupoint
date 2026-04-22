"use client";

import * as React from "react";
import { Calendar, X } from "lucide-react";
import { cn } from "@/lib/utils";

export type DateRange = {
  /** ISO YYYY-MM-DD — inclus */
  from?: string;
  /** ISO YYYY-MM-DD — inclus */
  to?: string;
};

type Mode = "all" | "day" | "month" | "range";

type Props = {
  value: DateRange;
  onChange: (v: DateRange) => void;
  className?: string;
};

function todayIso(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const j = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${j}`;
}

function firstDayOfMonth(ym: string): string {
  return `${ym}-01`;
}

function lastDayOfMonth(ym: string): string {
  // ym = "YYYY-MM"
  const [yStr, mStr] = ym.split("-");
  const y = Number(yStr);
  const m = Number(mStr);
  // day 0 du mois suivant = dernier jour du mois courant
  const d = new Date(Date.UTC(y, m, 0));
  return d.toISOString().slice(0, 10);
}

function inferMode(value: DateRange): Mode {
  if (!value.from && !value.to) return "all";
  if (value.from && value.to) {
    if (value.from === value.to) return "day";
    const sameMonth =
      value.from.slice(0, 7) === value.to.slice(0, 7) &&
      value.from.endsWith("-01") &&
      value.to === lastDayOfMonth(value.from.slice(0, 7));
    if (sameMonth) return "month";
    return "range";
  }
  return "range";
}

function formatHuman(range: DateRange): string {
  if (!range.from && !range.to) return "Toutes les dates";
  const mode = inferMode(range);
  if (mode === "day") return `Le ${formatFr(range.from!)}`;
  if (mode === "month") {
    const [y, m] = range.from!.split("-");
    const name = new Date(Number(y), Number(m) - 1, 1).toLocaleDateString(
      "fr-FR",
      { month: "long", year: "numeric" }
    );
    return name.charAt(0).toUpperCase() + name.slice(1);
  }
  if (range.from && range.to) {
    return `Du ${formatFr(range.from)} au ${formatFr(range.to)}`;
  }
  if (range.from) return `Depuis le ${formatFr(range.from)}`;
  return `Jusqu'au ${formatFr(range.to!)}`;
}

function formatFr(iso: string): string {
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

export function DateRangeFilter({ value, onChange, className }: Props) {
  const [open, setOpen] = React.useState(false);
  const [mode, setMode] = React.useState<Mode>(() => inferMode(value));
  const wrapperRef = React.useRef<HTMLDivElement | null>(null);

  // États locaux pour chaque mode (évite qu'un switch de mode détruise la saisie).
  const [day, setDay] = React.useState<string>(value.from ?? "");
  const [month, setMonth] = React.useState<string>(
    value.from ? value.from.slice(0, 7) : ""
  );
  const [rangeFrom, setRangeFrom] = React.useState<string>(value.from ?? "");
  const [rangeTo, setRangeTo] = React.useState<string>(value.to ?? "");

  React.useEffect(() => {
    if (!open) return;
    function onClick(e: MouseEvent) {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
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

  const active = Boolean(value.from || value.to);

  function commit(next: DateRange) {
    onChange(next);
    setOpen(false);
  }

  function applyDay() {
    if (!day) return;
    commit({ from: day, to: day });
  }
  function applyMonth() {
    if (!month) return;
    commit({ from: firstDayOfMonth(month), to: lastDayOfMonth(month) });
  }
  function applyRange() {
    if (!rangeFrom && !rangeTo) {
      commit({});
      return;
    }
    commit({ from: rangeFrom || undefined, to: rangeTo || undefined });
  }
  function applyPreset(preset: "today" | "7d" | "30d" | "this_month") {
    const today = new Date();
    const todayStr = todayIso();
    if (preset === "today") {
      commit({ from: todayStr, to: todayStr });
      return;
    }
    if (preset === "7d") {
      const d = new Date(today);
      d.setDate(d.getDate() - 6);
      commit({ from: d.toISOString().slice(0, 10), to: todayStr });
      return;
    }
    if (preset === "30d") {
      const d = new Date(today);
      d.setDate(d.getDate() - 29);
      commit({ from: d.toISOString().slice(0, 10), to: todayStr });
      return;
    }
    // this_month
    const ym = todayStr.slice(0, 7);
    commit({ from: firstDayOfMonth(ym), to: lastDayOfMonth(ym) });
  }

  return (
    <div ref={wrapperRef} className={cn("relative inline-block", className)}>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className={cn(
          "inline-flex h-9 items-center gap-2 rounded-md border px-3 text-sm font-medium transition-colors",
          active
            ? "border-emerald-600 bg-emerald-50 text-emerald-800 hover:bg-emerald-100"
            : "bg-background text-muted-foreground hover:bg-accent hover:text-foreground"
        )}
      >
        <Calendar className="h-4 w-4" />
        <span className="max-w-[220px] truncate">{formatHuman(value)}</span>
        {active && (
          <span
            role="button"
            aria-label="Effacer le filtre de date"
            onClick={(e) => {
              e.stopPropagation();
              commit({});
            }}
            className="ml-1 inline-flex h-4 w-4 items-center justify-center rounded-full text-emerald-700 hover:bg-emerald-200"
          >
            <X className="h-3 w-3" />
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 top-[calc(100%+6px)] z-50 w-[320px] rounded-xl border bg-background p-3 shadow-lg">
          <div className="mb-3 flex flex-wrap gap-1.5">
            {(
              [
                { key: "today", label: "Aujourd'hui" },
                { key: "7d", label: "7 j" },
                { key: "30d", label: "30 j" },
                { key: "this_month", label: "Ce mois" },
              ] as const
            ).map((p) => (
              <button
                key={p.key}
                type="button"
                onClick={() => applyPreset(p.key)}
                className="rounded-full border px-2.5 py-0.5 text-xs font-medium text-muted-foreground hover:border-emerald-600 hover:bg-emerald-50 hover:text-emerald-700"
              >
                {p.label}
              </button>
            ))}
          </div>

          <div className="mb-3 flex rounded-md border p-0.5 text-xs">
            {(
              [
                { key: "day", label: "Jour" },
                { key: "month", label: "Mois" },
                { key: "range", label: "Période" },
              ] as const
            ).map((t) => (
              <button
                key={t.key}
                type="button"
                onClick={() => setMode(t.key)}
                className={cn(
                  "flex-1 rounded px-2 py-1 font-medium transition-colors",
                  mode === t.key
                    ? "bg-primary text-primary-foreground"
                    : "text-muted-foreground hover:bg-accent"
                )}
              >
                {t.label}
              </button>
            ))}
          </div>

          {mode === "day" && (
            <div className="space-y-2">
              <label className="block text-xs font-medium text-muted-foreground">
                Jour
              </label>
              <input
                type="date"
                value={day}
                onChange={(e) => setDay(e.target.value)}
                className="h-9 w-full rounded-md border bg-background px-3 text-sm"
              />
              <ApplyRow
                onApply={applyDay}
                disabled={!day}
                onClear={() => commit({})}
                clearActive={active}
              />
            </div>
          )}

          {mode === "month" && (
            <div className="space-y-2">
              <label className="block text-xs font-medium text-muted-foreground">
                Mois
              </label>
              <input
                type="month"
                value={month}
                onChange={(e) => setMonth(e.target.value)}
                className="h-9 w-full rounded-md border bg-background px-3 text-sm"
              />
              <ApplyRow
                onApply={applyMonth}
                disabled={!month}
                onClear={() => commit({})}
                clearActive={active}
              />
            </div>
          )}

          {mode === "range" && (
            <div className="space-y-2">
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="block text-xs font-medium text-muted-foreground">
                    Du
                  </label>
                  <input
                    type="date"
                    value={rangeFrom}
                    onChange={(e) => setRangeFrom(e.target.value)}
                    className="h-9 w-full rounded-md border bg-background px-2 text-sm"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-muted-foreground">
                    Au
                  </label>
                  <input
                    type="date"
                    value={rangeTo}
                    onChange={(e) => setRangeTo(e.target.value)}
                    min={rangeFrom || undefined}
                    className="h-9 w-full rounded-md border bg-background px-2 text-sm"
                  />
                </div>
              </div>
              <ApplyRow
                onApply={applyRange}
                disabled={!rangeFrom && !rangeTo}
                onClear={() => commit({})}
                clearActive={active}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function ApplyRow({
  onApply,
  disabled,
  onClear,
  clearActive,
}: {
  onApply: () => void;
  disabled: boolean;
  onClear: () => void;
  clearActive: boolean;
}) {
  return (
    <div className="flex items-center justify-between pt-1">
      <button
        type="button"
        onClick={onClear}
        disabled={!clearActive}
        className="text-xs font-medium text-muted-foreground hover:text-foreground disabled:opacity-40"
      >
        Effacer
      </button>
      <button
        type="button"
        onClick={onApply}
        disabled={disabled}
        className="inline-flex h-8 items-center rounded-md bg-primary px-3 text-xs font-semibold text-primary-foreground hover:bg-primary/90 disabled:opacity-40"
      >
        Appliquer
      </button>
    </div>
  );
}
