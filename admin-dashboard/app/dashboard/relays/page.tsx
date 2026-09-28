"use client";

import * as React from "react";
import { useSearchParams } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { APIProvider, AdvancedMarker, InfoWindow, Map as GoogleMap, Pin } from "@vis.gl/react-google-maps";
import { ColumnDef } from "@tanstack/react-table";
import {
  AdminRelay,
  createRelayPoint,
  fetchAddressSuggestions,
  fetchRelays,
  fetchRelayStats,
  getRelayAddressLabel,
  getRelayCoordinates,
  geocodeMissingRelays,
  reverseGeocodeAddress,
  verifyRelay,
} from "@/lib/api";
import { DataTable, ServerPagination } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { CheckCircle2, Eye, Loader2, Map as MapIcon, RefreshCw, Search } from "lucide-react";
import Link from "next/link";
import { useToast } from "@/components/ui/toaster";
import { RelayOpeningHoursEditor, formatRelayOpeningHours, type RelayOpeningHours } from "@/components/relay-opening-hours-editor";

type RelayRow = AdminRelay & {
  rank?: number | null;
  parcels_processed?: number;
  parcels_delivered?: number;
  projected_bonus_xof?: number;
  next_bonus_threshold?: number | null;
};

type SelectedRelay = { relay: AdminRelay; latitude: number; longitude: number } | null;
type RelayLocation = { lat: number; lng: number } | null;

const xof = new Intl.NumberFormat("fr-FR");
const RELAY_MAP_ID = process.env.NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID ?? "denkma-relay-create-map";

function RelayLocationPicker({
  location,
  onChange,
}: {
  location: RelayLocation;
  onChange: (location: { lat: number; lng: number }) => void;
}) {
  const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY ?? "";
  if (!location) {
    return (
      <div className="flex min-h-28 items-center justify-center rounded-lg border border-dashed bg-muted/20 p-4 text-center text-sm text-muted-foreground">
        Choisis une adresse pour afficher sa position sur la carte.
      </div>
    );
  }
  if (!apiKey) {
    return <div className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">Carte indisponible : clé Google Maps absente.</div>;
  }
  return (
    <div className="overflow-hidden rounded-lg border">
      <APIProvider apiKey={apiKey}>
        <GoogleMap
          mapId={RELAY_MAP_ID}
          center={location}
          zoom={16}
          gestureHandling="greedy"
          className="h-64"
          disableDefaultUI
          zoomControl
        >
          <AdvancedMarker
            position={location}
            draggable
            title="Déplacer pour corriger la position"
            onDragEnd={(event) => {
              const lat = event.latLng?.lat();
              const lng = event.latLng?.lng();
              if (lat !== undefined && lng !== undefined) onChange({ lat, lng });
            }}
          >
            <Pin background="#2563eb" borderColor="#1d4ed8" glyphColor="#ffffff" />
          </AdvancedMarker>
        </GoogleMap>
      </APIProvider>
    </div>
  );
}

function currentPeriod() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

export default function RelaysPage() {
  const qc = useQueryClient();
  const { toast } = useToast();
  const [createOpen, setCreateOpen] = React.useState(false);
  const [createForm, setCreateForm] = React.useState({
    name: "",
    phone: "",
    label: "",
    city: "",
    district: "",
    lat: "",
    lng: "",
    maxCapacity: "20",
    openingHours: {} as RelayOpeningHours,
  });
  const [addressSuggestions, setAddressSuggestions] = React.useState<Awaited<ReturnType<typeof fetchAddressSuggestions>>>([]);
  const [suggestionsLoading, setSuggestionsLoading] = React.useState(false);
  const [locationSource, setLocationSource] = React.useState<"address" | "manual" | null>(null);
  const location = React.useMemo<RelayLocation>(() => {
    const lat = Number(createForm.lat);
    const lng = Number(createForm.lng);
    return Number.isFinite(lat) && Number.isFinite(lng) ? { lat, lng } : null;
  }, [createForm.lat, createForm.lng]);
  const searchParams = useSearchParams();
  const activeOnly = searchParams.get("active") === "true";
  const [period, setPeriod] = React.useState(currentPeriod);
  const [serverSearch, setServerSearch] = React.useState("");
  const [page, setPage] = React.useState(0);
  const { data, isLoading, isError } = useQuery({
    queryKey: ["relays", activeOnly, serverSearch, page],
    queryFn: () => fetchRelays({
      ...(activeOnly ? { active: true } : {}),
      ...(serverSearch.trim() ? { search: serverSearch.trim() } : {}),
      skip: page * 100,
      limit: 100,
    }),
    refetchInterval: 60_000,
  });
  const { data: mapData } = useQuery({
    queryKey: ["relays-map", activeOnly, serverSearch],
    queryFn: () => fetchRelays({
      ...(activeOnly ? { active: true } : {}),
      ...(serverSearch.trim() ? { search: serverSearch.trim() } : {}),
      limit: 1000,
    }),
    refetchInterval: 60_000,
  });
  const { data: relayStatsData } = useQuery({
    queryKey: ["relays-performance", period],
    queryFn: () => fetchRelayStats(period),
  });

  const relays = React.useMemo<RelayRow[]>(() => {
    const stats = relayStatsData?.stats ?? [];
    const statsByRelay = new Map(stats.map((stat: any) => [stat.relay_id, stat]));
    return (data?.relay_points ?? []).map((relay) => ({
      ...relay,
      ...(statsByRelay.get(relay.relay_id) ?? {}),
    }));
  }, [data, relayStatsData]);

  const verifyMut = useMutation({
    mutationFn: (id: string) => verifyRelay(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["relays"] }),
  });
  const geocodeMut = useMutation({
    mutationFn: () => geocodeMissingRelays(100),
    onSuccess: (result) => {
      qc.invalidateQueries({ queryKey: ["relays"] });
      qc.invalidateQueries({ queryKey: ["relays-map"] });
      toast(`${result.geocoded} relais géocodé(s). ${result.remaining} restant(s).`);
    },
    onError: () => toast("Impossible de géocoder les relais incomplets."),
  });
  const createMut = useMutation({
    mutationFn: () => createRelayPoint({
      name: createForm.name.trim(),
      phone: createForm.phone.trim(),
      max_capacity: Number(createForm.maxCapacity),
      opening_hours: createForm.openingHours,
      address: {
        label: createForm.label.trim() || undefined,
        city: createForm.city.trim() || undefined,
        district: createForm.district.trim() || undefined,
        ...(createForm.lat.trim() && createForm.lng.trim()
          ? { geopin: { lat: Number(createForm.lat), lng: Number(createForm.lng) } }
          : {}),
      },
    }),
    onSuccess: () => {
      setCreateOpen(false);
      setCreateForm({ name: "", phone: "", label: "", city: "", district: "", lat: "", lng: "", maxCapacity: "20", openingHours: {} as RelayOpeningHours });
      setLocationSource(null);
      setAddressSuggestions([]);
      qc.invalidateQueries({ queryKey: ["relays"] });
      qc.invalidateQueries({ queryKey: ["relays-map"] });
      toast("Relais créé. L’adresse a été géocodée si nécessaire.");
    },
    onError: () => toast("Impossible de créer le relais."),
  });

  React.useEffect(() => {
    const query = createForm.label.trim();
    if (query.length < 3 || locationSource === "address") {
      if (locationSource !== "address") setAddressSuggestions([]);
      return;
    }
    const timer = window.setTimeout(async () => {
      setSuggestionsLoading(true);
      try {
        setAddressSuggestions(await fetchAddressSuggestions(query));
      } catch {
        setAddressSuggestions([]);
      } finally {
        setSuggestionsLoading(false);
      }
    }, 350);
    return () => window.clearTimeout(timer);
  }, [createForm.label, locationSource]);

  const selectAddressSuggestion = (suggestion: Awaited<ReturnType<typeof fetchAddressSuggestions>>[number]) => {
    const city = suggestion.subtitle?.split(",", 1)[0]?.trim();
    setCreateForm((current) => ({
      ...current,
      label: suggestion.label,
      ...(city && !current.city.trim() ? { city } : {}),
      lat: String(suggestion.lat),
      lng: String(suggestion.lng),
    }));
    setLocationSource("address");
    setAddressSuggestions([]);
  };

  const moveRelayLocation = async ({ lat, lng }: { lat: number; lng: number }) => {
    setCreateForm((current) => ({ ...current, lat: String(lat), lng: String(lng) }));
    setLocationSource("manual");
    try {
      const address = await reverseGeocodeAddress(lat, lng);
      if (address) {
        setCreateForm((current) => ({
          ...current,
          label: address.formatted_address ?? current.label,
          city: address.city ?? current.city,
          district: address.district ?? current.district,
          lat: String(lat),
          lng: String(lng),
        }));
      }
    } catch {
      toast("La position est enregistrée, mais l’adresse n’a pas pu être actualisée.");
    }
  };

  React.useEffect(() => setPage(0), [activeOnly, serverSearch]);

  const columns = React.useMemo<ColumnDef<RelayRow, any>[]>(
    () => [
      {
        id: "name",
        header: "Nom",
        accessorKey: "name",
        cell: ({ row }) => (
          <Link
            href={`/dashboard/relays/${row.original.relay_id}`}
            className="group flex flex-col"
          >
            <span className="font-medium group-hover:text-primary group-hover:underline">
              {row.original.name}
            </span>
            <span className="text-xs text-muted-foreground">
              {row.original.city ?? "—"}
            </span>
          </Link>
        ),
      },
      {
        id: "address",
        header: "Adresse",
        cell: ({ row }) => {
          return <span className="text-xs">{getRelayAddressLabel(row.original) ?? "—"}</span>;
        },
      },
      {
        id: "location",
        header: "Localisation",
        cell: ({ row }) => {
          const coordinates = getRelayCoordinates(row.original);
          if (!coordinates) return <span className="text-xs">Non renseignée</span>;
          const mapsUrl = `https://www.google.com/maps?q=${coordinates.latitude},${coordinates.longitude}`;
          return (
            <a
              href={mapsUrl}
              target="_blank"
              rel="noreferrer"
              className="text-xs text-primary underline-offset-4 hover:underline"
            >
              {coordinates.latitude.toFixed(5)}, {coordinates.longitude.toFixed(5)}
            </a>
          );
        },
      },
      {
        id: "active",
        header: "Actif",
        accessorKey: "is_active",
        cell: ({ getValue }) =>
          getValue() ? (
            <Badge tone="success">Actif</Badge>
          ) : (
            <Badge tone="default">Inactif</Badge>
          ),
      },
      {
        id: "opening_hours",
        header: "Horaires",
        cell: ({ row }) => (
          <div className="flex flex-col gap-1 text-xs">
            <Badge tone={row.original.is_open === false ? "danger" : "success"}>
              {row.original.is_open === false ? "Fermé" : "Ouvert"}
            </Badge>
            <span className="max-w-56 text-muted-foreground">
              {formatRelayOpeningHours(row.original.opening_hours)}
            </span>
          </div>
        ),
      },
      {
        id: "verified",
        header: "Vérifié",
        accessorKey: "is_verified",
        cell: ({ getValue }) =>
          getValue() ? (
            <Badge tone="success">Vérifié</Badge>
          ) : (
            <Badge tone="warning">Non vérifié</Badge>
          ),
      },
      {
        id: "capacity",
        header: "Charge",
        cell: ({ row }) => {
          const r = row.original;
          const load = r.current_load ?? 0;
          const max = r.max_capacity ?? 0;
          return (
            <span className="text-xs">
              {load}/{max || "∞"}
            </span>
          );
        },
      },
      {
        id: "rank",
        header: "Rang mois",
        accessorFn: (relay) => relay.rank ?? 999999,
        cell: ({ row }) => (
          <span className="font-medium">#{row.original.rank ?? "-"}</span>
        ),
      },
      {
        id: "processed",
        header: "Traites",
        accessorFn: (relay) => relay.parcels_processed ?? 0,
        cell: ({ row }) => (
          <div className="flex flex-col">
            <span className="font-medium">
              {row.original.parcels_processed ?? 0} colis
            </span>
            <span className="text-xs text-muted-foreground">
              {row.original.parcels_delivered ?? 0} livres
            </span>
          </div>
        ),
      },
      {
        id: "bonus",
        header: "Bonus",
        accessorFn: (relay) => relay.projected_bonus_xof ?? 0,
        cell: ({ row }) => (
          <div className="flex flex-col">
            <span className="font-medium">
              {xof.format(row.original.projected_bonus_xof ?? 0)} XOF
            </span>
            <span className="text-xs text-muted-foreground">
              Palier {row.original.next_bonus_threshold ?? "-"}
            </span>
          </div>
        ),
      },
      {
        id: "actions",
        header: "",
        enableSorting: false,
        cell: ({ row }) => {
          const r = row.original;
          return (
            <div className="flex gap-2">
              <Link href={`/dashboard/relays/${r.relay_id}`}>
                <Button size="sm" variant="outline">
                  <Eye className="h-3.5 w-3.5" />
                  Fiche
                </Button>
              </Link>
              {!r.is_verified && (
                <Button
                  size="sm"
                  variant="outline"
                  disabled={verifyMut.isPending}
                  onClick={() => verifyMut.mutate(r.relay_id)}
                >
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  Vérifier
                </Button>
              )}
            </div>
          );
        },
      },
    ],
    [verifyMut]
  );

  return (
    <div className="space-y-5 p-4 sm:p-6 lg:p-8">
      <div>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold">Points relais</h1>
            <p className="text-sm text-muted-foreground">
              Réseau complet des relais Denkma. Vérifiez les nouveaux.
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" onClick={() => setCreateOpen((open) => !open)}>
              Nouveau relais
            </Button>
            <Button
              variant="outline"
              disabled={geocodeMut.isPending}
              onClick={() => geocodeMut.mutate()}
            >
              {geocodeMut.isPending ? <Loader2 className="animate-spin" /> : <RefreshCw />}
              Géocoder les incomplets
            </Button>
          </div>
        </div>
      </div>

      {createOpen && (
        <section className="rounded-xl border bg-card p-4">
          <h2 className="mb-4 font-semibold">Créer un point relais</h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {([
              ["name", "Nom du relais"],
              ["phone", "Téléphone"],
              ["city", "Ville"],
              ["district", "Quartier"],
              ["maxCapacity", "Capacité maximale"],
            ] as const).map(([field, label]) => (
              <label key={field} className="space-y-1 text-sm">
                <span className="font-medium">{label}</span>
                <Input
                  value={createForm[field]}
                  inputMode={field === "maxCapacity" ? "decimal" : undefined}
                  onChange={(event) => setCreateForm((current) => ({ ...current, [field]: event.target.value }))}
                />
              </label>
            ))}
          </div>
          <div className="relative mt-4">
            <label className="space-y-1 text-sm">
              <span className="font-medium">Adresse du relais</span>
              <div className="relative">
                <Search className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" />
                <Input
                  value={createForm.label}
                  placeholder="Commence à saisir une adresse complète…"
                  className="pl-9"
                  onChange={(event) => {
                    const label = event.target.value;
                    setCreateForm((current) => ({ ...current, label, lat: "", lng: "" }));
                    setLocationSource(null);
                  }}
                />
              </div>
            </label>
            {(suggestionsLoading || addressSuggestions.length > 0) && (
              <div className="absolute z-10 mt-1 w-full overflow-hidden rounded-lg border bg-background shadow-lg">
                {suggestionsLoading && <div className="p-3 text-sm text-muted-foreground">Recherche d’adresses…</div>}
                {!suggestionsLoading && addressSuggestions.map((suggestion) => (
                  <button
                    key={suggestion.place_id ?? `${suggestion.lat}-${suggestion.lng}`}
                    type="button"
                    className="block w-full border-b px-3 py-2 text-left text-sm last:border-0 hover:bg-muted"
                    onClick={() => selectAddressSuggestion(suggestion)}
                  >
                    <div className="font-medium">{suggestion.label}</div>
                    {suggestion.subtitle && <div className="text-xs text-muted-foreground">{suggestion.subtitle}</div>}
                  </button>
                ))}
              </div>
            )}
          </div>
          <div className="mt-4 space-y-2">
            <RelayLocationPicker location={location} onChange={moveRelayLocation} />
            {location ? (
              <div className="rounded-md bg-blue-50 p-3 text-xs text-blue-900">
                {locationSource === "manual"
                  ? "Position corrigée manuellement. L’adresse a été actualisée si Google a trouvé une correspondance."
                  : "Position trouvée automatiquement. Déplace le marqueur si nécessaire pour la corriger."}
                <div className="mt-1 font-mono">{location.lat.toFixed(6)}, {location.lng.toFixed(6)}</div>
              </div>
            ) : (
              <p className="text-xs text-amber-700">Sélectionne une suggestion pour éviter une position approximative.</p>
            )}
          </div>
          <div className="mt-4">
            <RelayOpeningHoursEditor
              value={createForm.openingHours}
              onChange={(openingHours) => setCreateForm((current) => ({ ...current, openingHours }))}
            />
          </div>
          <div className="mt-4 flex gap-2">
            <Button disabled={createMut.isPending || !location} onClick={() => createMut.mutate()}>
              {createMut.isPending && <Loader2 className="animate-spin" />}
              Créer le relais
            </Button>
            <Button variant="outline" onClick={() => setCreateOpen(false)}>Annuler</Button>
          </div>
        </section>
      )}

      <div className="flex flex-wrap gap-4">
        <label className="min-w-60 flex-1 space-y-1 text-sm">
          <span className="font-medium">Rechercher côté serveur</span>
          <Input
            value={serverSearch}
            onChange={(e) => setServerSearch(e.target.value)}
            placeholder="Nom, ville, téléphone, adresse…"
          />
        </label>
        <label className="w-40 space-y-1 text-sm">
          <span className="font-medium">Période</span>
          <Input value={period} onChange={(e) => setPeriod(e.target.value)} />
        </label>
      </div>

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      )}
      {isError && (
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          Erreur de chargement des relais.
        </div>
      )}
      {data && (
        <>
          <RelayMap relays={mapData?.relay_points ?? relays} />
          <DataTable
            columns={columns}
            data={relays}
            searchPlaceholder="Nom, ville, adresse…"
            globalFilterFn={(r, q) =>
              (r.name ?? "").toLowerCase().includes(q) ||
              (r.city ?? "").toLowerCase().includes(q) ||
              (getRelayAddressLabel(r) ?? "").toLowerCase().includes(q) ||
              (r.relay_id ?? "").toLowerCase().includes(q)
            }
          />
          <ServerPagination
            page={page}
            total={data.total}
            pageSize={100}
            onPageChange={setPage}
          />
        </>
      )}
    </div>
  );
}

function RelayMap({ relays }: { relays: AdminRelay[] }) {
  const [selected, setSelected] = React.useState<SelectedRelay>(null);
  const points = React.useMemo(
    () => relays.flatMap((relay) => {
      const coordinates = getRelayCoordinates(relay);
      return coordinates ? [{ relay, ...coordinates }] : [];
    }),
    [relays],
  );
  const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY ?? "";
  const mapId = process.env.NEXT_PUBLIC_GOOGLE_MAPS_MAP_ID ?? "denkma-relays-map";
  const center = points[0] ?? {
    latitude: Number(process.env.NEXT_PUBLIC_DEFAULT_MAP_LAT ?? "14.7167"),
    longitude: Number(process.env.NEXT_PUBLIC_DEFAULT_MAP_LNG ?? "-17.4677"),
  };

  return (
    <section className="space-y-3 rounded-xl border bg-card p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h2 className="flex items-center gap-2 font-semibold">
            <MapIcon className="h-4 w-4" /> Carte des relais
          </h2>
          <p className="text-xs text-muted-foreground">
            {points.length} relais géolocalisé(s) · {relays.length - points.length} sans coordonnées
          </p>
        </div>
      </div>
      {apiKey ? (
        <div className="h-[420px] overflow-hidden rounded-lg border">
          <APIProvider apiKey={apiKey}>
            <GoogleMap
              mapId={mapId}
              defaultCenter={{ lat: center.latitude, lng: center.longitude }}
              defaultZoom={11}
              gestureHandling="greedy"
              onClick={() => setSelected(null)}
            >
              {points.map(({ relay, latitude, longitude }) => (
                <AdvancedMarker
                  key={relay.relay_id}
                  position={{ lat: latitude, lng: longitude }}
                  title={relay.name}
                  onClick={() => setSelected({ relay, latitude, longitude })}
                >
                  <Pin
                    background={relay.is_active ? "#16a34a" : "#6b7280"}
                    borderColor={relay.is_verified ? "#1d4ed8" : "#f59e0b"}
                    glyphColor="#ffffff"
                  />
                </AdvancedMarker>
              ))}
              {selected && (
                <InfoWindow
                  position={{ lat: selected.latitude, lng: selected.longitude }}
                  onCloseClick={() => setSelected(null)}
                >
                  <div className="min-w-[190px] space-y-1 text-sm">
                    <div className="font-semibold">{selected.relay.name}</div>
                    <div>{getRelayAddressLabel(selected.relay) ?? selected.relay.city ?? "Adresse indisponible"}</div>
                    <div className="text-xs text-muted-foreground">
                      {selected.relay.is_active ? "Actif" : "Inactif"} · {selected.relay.is_verified ? "Vérifié" : "À vérifier"}
                    </div>
                    <Link className="text-xs text-primary underline" href={`/dashboard/relays/${selected.relay.relay_id}`}>
                      Ouvrir la fiche
                    </Link>
                  </div>
                </InfoWindow>
              )}
            </GoogleMap>
          </APIProvider>
        </div>
      ) : (
        <div className="flex h-32 items-center justify-center rounded-lg border border-dashed text-sm text-muted-foreground">
          Clé Google Maps absente. La liste reste disponible.
        </div>
      )}
    </section>
  );
}
