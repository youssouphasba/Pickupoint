import type { ReferralRoleConfig } from "./api";

export function referralConfigErrors(
  config: ReferralRoleConfig,
  metricOptions: { value: string; label: string }[] | undefined,
): string[] {
  const options = metricOptions ?? [];
  const errors: string[] = [];
  if (options.length === 0) {
    errors.push("Les activités autorisées ne sont pas chargées. Réessayez avant de sauvegarder.");
  } else {
    if (!options.some((option) => option.value === config.apply_metric)) {
      errors.push("Choisissez une activité autorisée pour ajouter le code.");
    }
    if (!options.some((option) => option.value === config.reward_metric)) {
      errors.push("Choisissez une activité autorisée pour débloquer les primes.");
    }
  }
  for (const [value, label, minimum] of [
    [config.sponsor_bonus_xof, "La prime du parrain", 0],
    [config.referred_bonus_xof, "La prime du filleul", 0],
    [config.apply_max_count, "Le maximum avant ajout du code", 0],
    [config.reward_count, "L’objectif du parrainage", 1],
    [config.max_referrals_per_sponsor, "La limite de filleuls", 0],
  ] as const) {
    if (!Number.isSafeInteger(value) || value < minimum) {
      errors.push(`${label} doit être un nombre entier supérieur ou égal à ${minimum}.`);
    }
  }
  return errors;
}
