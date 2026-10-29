import { useEffect, useState } from "react";

/**
 * V700: a JSON read a screen keeps current — fetched when its address (or the tick, bumped after a change) moves, the answer kept
 * with the address it answers, so the screen knows it is loading without setting state in the effect itself, and keeps showing the
 * last answer while the next one comes.
 */
export function useJson<T>(url: string | null, tick = 0): { data: T | null; failed: string | null; loading: boolean } {
  const [res, setRes] = useState<{ url: string; tick: number; data: T | null; failed: string | null } | null>(null);
  useEffect(() => {
    if (!url) return;
    let live = true;
    fetch(url, { cache: "no-store" })
      .then(async (r) => {
        const j = await r.json().catch(() => null);
        if (!live) return;
        setRes({ url, tick, data: r.ok ? (j as T) : null, failed: r.ok ? null : (j?.detail ?? j?.title ?? "Unable to load.") });
      })
      .catch(() => { if (live) setRes({ url, tick, data: null, failed: "Unable to load." }); });
    return () => { live = false; };
  }, [url, tick]);
  const loading = !!url && (res?.url !== url || res?.tick !== tick);
  return { data: res?.data ?? null, failed: res && !loading ? res.failed : null, loading };
}
