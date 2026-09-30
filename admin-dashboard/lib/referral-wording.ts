import type { ReferralRoleConfig } from "./api";

const units: Record<string, readonly [string, string]> = {
  sent_parcels: ["colis créé", "colis créés"],
  delivered_sender_parcels: ["colis envoyé puis livré", "colis envoyés puis livrés"],
  completed_driver_deliveries: ["mission terminée", "missions terminées"],
};

export function referralMetricCount(metric: string, count: number): string {
  const labels = units[metric];
  return `${count} ${labels ? labels[count === 1 ? 0 : 1] : metric}`;
}

export function referralConditions(config: ReferralRoleConfig) {
  return {
    application: `Le filleul peut ajouter le code tant que son compte ne dépasse pas ${referralMetricCount(config.apply_metric, config.apply_max_count)}. À partir de ${referralMetricCount(config.apply_metric, config.apply_max_count + 1)}, il ne peut plus l’ajouter.`,
    reward: `Le parrainage est validé dès que le filleul atteint au moins ${referralMetricCount(config.reward_metric, config.reward_count)}.`,
    limit: config.max_referrals_per_sponsor === 0
      ? "Aucune limite de filleuls de ce type par parrain."
      : `Chaque parrain peut avoir au maximum ${config.max_referrals_per_sponsor} filleul${config.max_referrals_per_sponsor === 1 ? "" : "s"} de ce type.`,
  };
}
