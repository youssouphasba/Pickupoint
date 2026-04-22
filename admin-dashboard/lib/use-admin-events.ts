"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchAdminEvents, type AdminEventsFeed } from "@/lib/api";

/**
 * Feed d'événements admin pour la cloche. Polling 20s (plus réactif que
 * l'action-center 30s) pour détecter les nouveaux events rapidement.
 */
export function useAdminEvents(limit = 50) {
  return useQuery<AdminEventsFeed>({
    queryKey: ["admin-events", limit],
    queryFn: () => fetchAdminEvents({ limit }),
    refetchInterval: 20_000,
    staleTime: 10_000,
  });
}
