export type LocationSignalState =
  | "live"
  | "last_known"
  | "signal_lost"
  | "unavailable";

export type LocationSignalTone =
  | "default"
  | "info"
  | "success"
  | "warning"
  | "danger";

export type LocationSignal = {
  state: LocationSignalState;
  label: string;
  tone: LocationSignalTone;
  ageMinutes: number | null;
};

const LIVE_MAX_AGE_MS = 2 * 60 * 1000;
const SIGNAL_LOST_MIN_AGE_MS = 10 * 60 * 1000;

export function parseLocationTimestamp(value?: string | null): number | null {
  if (!value) return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function resolveLocationSignal({
  hasLocation,
  updatedAt,
}: {
  hasLocation: boolean;
  updatedAt?: string | null;
}): LocationSignal {
  if (!hasLocation) {
    return {
      state: "unavailable",
      label: "Localisation indisponible",
      tone: "default",
      ageMinutes: null,
    };
  }

  const timestamp = parseLocationTimestamp(updatedAt);
  if (timestamp == null) {
    return {
      state: "last_known",
      label: "Dernière position connue",
      tone: "warning",
      ageMinutes: null,
    };
  }

  const ageMs = Math.max(0, Date.now() - timestamp);
  const ageMinutes = Math.round(ageMs / 60000);

  if (ageMs < LIVE_MAX_AGE_MS) {
    return {
      state: "live",
      label: "Position live",
      tone: "success",
      ageMinutes,
    };
  }

  if (ageMs >= SIGNAL_LOST_MIN_AGE_MS) {
    return {
      state: "signal_lost",
      label: "Signal perdu",
      tone: "danger",
      ageMinutes,
    };
  }

  return {
    state: "last_known",
    label: "Dernière position connue",
    tone: "warning",
    ageMinutes,
  };
}

export function formatLocationClock(iso?: string | null) {
  const timestamp = parseLocationTimestamp(iso);
  if (timestamp == null) return "—";
  const date = new Date(timestamp);
  return `${date.getHours().toString().padStart(2, "0")}:${date
    .getMinutes()
    .toString()
    .padStart(2, "0")}`;
}

export function formatLocationRelativeTime(iso?: string | null) {
  const timestamp = parseLocationTimestamp(iso);
  if (timestamp == null) return "horodatage indisponible";
  const minutes = Math.max(0, Math.round((Date.now() - timestamp) / 60000));
  if (minutes < 1) return "à l'instant";
  if (minutes < 60) return `il y a ${minutes} min`;
  return `il y a ${Math.round(minutes / 60)} h`;
}
