import { formatRoundingAmount } from "@/lib/delivery-rounding";

export function DenkmaRoundingOffer({ amount, includedInGain = false }: {
  amount?: number;
  includedInGain?: boolean;
}) {
  if (amount == null || !Number.isFinite(amount) || amount <= 0) return null;
  return <p className="text-xs font-semibold text-green-800">
    {formatRoundingAmount(amount)} offerts par Denkma{includedInGain ? " · inclus dans le gain" : ""}
  </p>;
}
