export type SettlementDirection = "to_relay" | "to_denkma" | "to_driver";
export type SettlementStatus = "pending" | "declared" | "validated" | "rejected";
export type SettlementFilter = SettlementStatus | "all" | "outstanding" | "upcoming" | "issues";

export type RelaySettlementAction = {
  action: string;
  relay_id: string;
  relay_name?: string;
  direction: SettlementDirection;
  label: string;
  amount_xof: number;
  status: SettlementStatus;
  stage: "due" | "upcoming";
  can_validate: boolean;
  can_reject: boolean;
  parcel_id: string;
  tracking_code: string;
  beneficiary_name?: string;
  driver_id?: string | null;
  updated_at?: string | null;
  declared_at?: string | null;
  reviewed_at?: string | null;
  reviewed_by?: string | null;
  note?: string | null;
};

export type SettlementIssue = { parcel_id: string; tracking_code: string; issue: string };
export type SettlementTotals = Record<`${SettlementDirection}_xof` | `${SettlementDirection}_declared_xof` | `${SettlementDirection}_validated_xof`, number> & {
  upcoming_to_relay_xof: number;
  pending_count: number;
  declared_count: number;
  rejected_count: number;
  outstanding_count: number;
  unavailable_count: number;
};
export type RelaySettlementRow = SettlementTotals & { relay_id: string; name: string; is_active: boolean | null; missing_relay: boolean };
export type RelaySettlementOverview = { totals: SettlementTotals; relays: RelaySettlementRow[]; total: number; has_more: boolean };
export type RelaySettlementActions = { actions: (RelaySettlementAction | SettlementIssue)[]; total: number; unavailable_count: number; has_more: boolean };

export const SETTLEMENT_DIRECTIONS: Record<SettlementDirection, string> = {
  to_relay: "Denkma doit au relais",
  to_denkma: "Le relais doit à Denkma",
  to_driver: "Le relais doit au livreur",
};

export function formatSettlementAmount(amount: number) {
  return `${new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2 }).format(amount)} FCFA`;
}
