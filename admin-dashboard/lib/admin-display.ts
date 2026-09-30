import { adminPageForPath } from "@/lib/admin-navigation";
import type { ActionItem } from "@/lib/api";

const PAYMENT_LABELS: Record<string, string> = {
  pending: "En attente", unpaid: "Non réglé", paid: "Réglé", failed: "Échec",
  refunded: "Remboursé", cancelled: "Annulé", authorized: "Autorisé",
};
const PARCEL_LABELS: Record<string, string> = {
  created: "Créé", dropped_at_origin_relay: "Déposé au relais de départ",
  in_transit: "En transit", at_destination_relay: "Au relais d’arrivée",
  available_at_relay: "Disponible au relais", out_for_delivery: "En livraison",
  redirected_to_relay: "Redirigé vers un relais", delivery_failed: "Échec de livraison",
  delivered: "Livré", cancelled: "Annulé", returned: "Retourné", disputed: "Litige",
  expired: "Expiré", incident_reported: "Incident signalé", suspended: "Suspendu",
};
const SETTLEMENT_LABELS: Record<string, string> = {
  pending: "À effectuer", declared: "Déclaré, à vérifier",
  validated: "Validé", rejected: "Rejeté",
};
export const RELAY_SETTLEMENT_LABELS: Record<string, string> = {
  driver_payment_status: "Versement au livreur",
  denkma_payment_status: "Versement du relais à Denkma",
  origin_relay_payment_status: "Versement au relais de départ",
  destination_relay_payment_status: "Versement au relais d’arrivée",
};
const PAYOUT_METHOD_LABELS: Record<string, string> = {
  wave: "Wave", orange_money: "Orange Money", free_money: "Free Money",
  bank: "Virement bancaire", cash: "Espèces",
};

function translated(value: unknown, labels: Record<string, string>, fallback: string) {
  if (typeof value !== "string" || !value.trim()) return fallback;
  return labels[value] ?? "Statut à vérifier";
}

export function paymentStatusLabel(value: unknown) {
  return translated(value, PAYMENT_LABELS, "Paiement non renseigné");
}
export function parcelStatusLabel(value: unknown) {
  return translated(value, PARCEL_LABELS, "Statut non renseigné");
}
export function settlementStatusLabel(value: unknown) {
  return translated(value, SETTLEMENT_LABELS, "Non renseigné");
}
export function payerLabel(value: unknown) {
  if (value === "sender") return "Expéditeur";
  if (value === "recipient") return "Destinataire";
  return "Payeur non renseigné";
}
export function payoutMethodLabel(value: unknown) {
  if (typeof value !== "string" || !value.trim()) return "Mode non renseigné";
  return PAYOUT_METHOD_LABELS[value] ?? "Mode à vérifier";
}

export function adminActionHref(item: ActionItem, fallback?: string): string | undefined {
  if (item.href && item.href.startsWith("/dashboard") && adminPageForPath(item.href)) return item.href;
  if (typeof item.parcel_id === "string" && item.parcel_id.trim()) return `/dashboard/parcels/${encodeURIComponent(item.parcel_id)}`;
  if (typeof item.user_id === "string" && item.user_id.trim()) return `/dashboard/users/${encodeURIComponent(item.user_id)}`;
  return fallback && adminPageForPath(fallback) ? fallback : undefined;
}
