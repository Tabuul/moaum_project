"use client";

import { useRouter } from "next/navigation";
import { useCallback } from "react";

/**
 * Navigate to the same page with new search parameters — a session, a semester, a filter, a page
 * number — and have the server render it again. A plain router.push is liable to be served from the
 * client router's cache when only the query changed, so the address moves and the figures do not;
 * the refresh after the push makes the server re-read the page for the new parameters.
 */
export function useQueryNav(): (url: string) => void {
  const router = useRouter();
  return useCallback((url: string) => { router.push(url); router.refresh(); }, [router]);
}
