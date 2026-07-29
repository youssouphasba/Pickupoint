const hotelKeywords = [
  "hotel",
  "auberge",
  "residence",
  "nuit",
  "sejour",
  "etoiles",
];

const realEstateKeywords = [
  "appartement",
  "maison",
  "villa",
  "terrain",
  "studio",
  "chambre",
  "louer",
  "location",
  "vendre",
  "vente",
  "achat",
  "acheter",
  "meuble",
];

const vehicleKeywords = [
  "voiture",
  "auto",
  "vehicule",
  "toyota",
  "prado",
  "hyundai",
  "kia",
  "peugeot",
  "renault",
  "mercedes",
  "4x4",
  "chauffeur",
];

const tripKeywords = [
  "voyage",
  "trajet",
  "bus",
  "car",
  "minibus",
  "7 places",
  "dakar touba",
  "dakar thies",
  "dakar saint-louis",
  "dakar mbour",
  "dakar kaolack",
  "dakar ziguinchor",
];

const cityNames = [
  "dakar",
  "touba",
  "thies",
  "saint-louis",
  "mbour",
  "kaolack",
  "ziguinchor",
  "saly",
];

function normalizeQuery(query: string) {
  return query
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[’']/g, " ")
    .replace(/\ba\b/g, " ")
    .replace(/\s+/g, " ");
}

function hasKeyword(query: string, keywords: string[]) {
  return keywords.some((keyword) => query.includes(keyword));
}

function createDestination(path: string, params: Record<string, string | number | undefined>) {
  const searchParams = new URLSearchParams();

  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && `${value}`.trim()) {
      searchParams.set(key, `${value}`);
    }
  });

  const queryString = searchParams.toString();
  return queryString ? `${path}?${queryString}` : path;
}

function cleanQuery(query: string, wordsToRemove: string[]) {
  return query
    .split(" ")
    .filter((word) => !wordsToRemove.includes(word))
    .join(" ");
}

function detectTripCities(query: string) {
  const matches = cityNames.filter((city) => query.includes(city));

  if (matches.length >= 2 && !query.includes("voyage") && !query.includes("trajet")) {
    return { depart: matches[0], arrivee: matches[1] };
  }

  return null;
}

export function getSearchDestination(query: string) {
  const normalizedQuery = normalizeQuery(query);

  if (!normalizedQuery) {
    return "/";
  }

  const tripCities = detectTripCities(normalizedQuery);

  if (tripCities) {
    return createDestination("/voyages", tripCities);
  }

  if (hasKeyword(normalizedQuery, hotelKeywords)) {
    const starMatch = normalizedQuery.match(/\b([1-5])\s*(etoile|etoiles)\b/);

    return createDestination("/hotels", {
      query: normalizedQuery,
      stars: starMatch?.[1],
    });
  }

  if (hasKeyword(normalizedQuery, vehicleKeywords)) {
    return createDestination("/voitures", {
      query: normalizedQuery,
      type: normalizedQuery.includes("location") || normalizedQuery.includes("louer") ? "location" : undefined,
    });
  }

  if (hasKeyword(normalizedQuery, realEstateKeywords)) {
    const isSale =
      normalizedQuery.includes("vendre") ||
      normalizedQuery.includes("vente") ||
      normalizedQuery.includes("achat") ||
      normalizedQuery.includes("acheter");

    return createDestination("/immobilier", {
      query: isSale ? cleanQuery(normalizedQuery, ["vendre", "vente", "achat", "acheter"]) : normalizedQuery,
      type: isSale ? "vente" : undefined,
    });
  }

  if (hasKeyword(normalizedQuery, tripKeywords)) {
    return createDestination("/voyages", {
      query: cleanQuery(normalizedQuery, ["voyage", "trajet"]),
    });
  }

  return createDestination("/search", { query: normalizedQuery });
}
