export type RoundingBenefits = {
  version?: string;
  customer_discount_xof?: number;
  driver_bonus_xof?: number;
  denkma_contribution_xof?: number;
};

export type FinancialRounding = { rounding?: RoundingBenefits };

export type RoundingSource = {
  financial_rounding?: FinancialRounding | null;
  financial_contract?: { breakdown?: FinancialRounding } | null;
  quote_breakdown?: { financial_rounding?: FinancialRounding } | null;
};

export function roundingBenefits(source: RoundingSource): RoundingBenefits {
  const snapshot = source.financial_contract?.breakdown
    ?? source.financial_rounding
    ?? source.quote_breakdown?.financial_rounding;
  return snapshot?.rounding?.version ? snapshot.rounding : {};
}

export function formatRoundingAmount(value: number) {
  return `${new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2 }).format(value)} FCFA`;
}
