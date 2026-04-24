"use client";

type GeoPoint = {
  lat?: number | null;
  lng?: number | null;
  latitude?: number | null;
  longitude?: number | null;
};

type LocationPreviewMapProps = {
  point?: GeoPoint | null;
  title?: string;
  heightClassName?: string;
};

const MAP_DELTA = 0.01;

function resolvePoint(point?: GeoPoint | null) {
  if (!point) return null;
  const lat = point.lat ?? point.latitude;
  const lng = point.lng ?? point.longitude;
  if (lat == null || lng == null) return null;
  return { lat, lng };
}

export function LocationPreviewMap({
  point,
  title = "Position sur la carte",
  heightClassName = "h-64",
}: LocationPreviewMapProps) {
  const resolved = resolvePoint(point);

  if (!resolved) {
    return (
      <div
        className={`flex items-center justify-center rounded-xl border border-dashed bg-muted/20 text-sm text-muted-foreground ${heightClassName}`}
      >
        Aucune position GPS disponible.
      </div>
    );
  }

  const { lat, lng } = resolved;
  const bbox = [
    lng - MAP_DELTA,
    lat - MAP_DELTA,
    lng + MAP_DELTA,
    lat + MAP_DELTA,
  ].join(",");
  const embedUrl = `https://www.openstreetmap.org/export/embed.html?bbox=${bbox}&layer=mapnik&marker=${lat},${lng}`;
  const openStreetMapUrl = `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=15/${lat}/${lng}`;

  return (
    <div className="space-y-3">
      <iframe
        title={title}
        src={embedUrl}
        className={`w-full rounded-xl border ${heightClassName}`}
        loading="lazy"
        referrerPolicy="no-referrer-when-downgrade"
      />
      <div className="flex flex-wrap items-center justify-between gap-3 text-xs text-muted-foreground">
        <span>
          {lat.toFixed(5)}, {lng.toFixed(5)}
        </span>
        <a
          href={openStreetMapUrl}
          target="_blank"
          rel="noreferrer"
          className="font-medium text-primary underline"
        >
          Ouvrir dans la carte
        </a>
      </div>
    </div>
  );
}
