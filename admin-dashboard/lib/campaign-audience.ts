import type { CampaignAudienceOption, CampaignTargeting } from "./api";

export function audiencesForRecipients(
  roles: string[],
  byRole?: Record<string, CampaignAudienceOption[]>,
): CampaignAudienceOption[] {
  return roles.length === 1 ? byRole?.[roles[0]] ?? [] : [];
}

export function resetRecipientAudience(
  current: CampaignTargeting | undefined,
  defaults: CampaignTargeting | undefined,
): CampaignTargeting | undefined {
  if (!current && !defaults) return undefined;
  return { ...defaults, ...current, audience: "all" } as CampaignTargeting;
}
