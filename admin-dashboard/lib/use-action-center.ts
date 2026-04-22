"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchActionCenter, type ActionCenter } from "@/lib/api";

/**
 * Hook partagé par la sidebar, le home "À traiter" et la cloche.
 * Un seul polling 30s → tout reste synchro sans multiplier les requêtes.
 */
export function useActionCenter() {
  return useQuery<ActionCenter>({
    queryKey: ["action-center"],
    queryFn: fetchActionCenter,
    refetchInterval: 30_000,
    staleTime: 15_000,
  });
}
