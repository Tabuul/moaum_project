"use client";
/** Words that depend on the clock — "3 min ago", "Due in 2 h" — rendered on the browser only: the server gives the plain
 *  date, so the two never disagree at a minute boundary, and the words are refreshed every half minute while the page
 *  is open. A client-only module, because it reads the clock through a store hook. */
import { useSyncExternalStore } from "react";
import { ago, dueWords, when } from "@/lib/helpdesk";

const tickers = new Set<() => void>();
let ticker: number | null = null;
function subscribeClock(cb: () => void) {
  tickers.add(cb);
  if (ticker === null) ticker = window.setInterval(() => tickers.forEach((f) => f()), 30_000);
  return () => { tickers.delete(cb); if (!tickers.size && ticker !== null) { window.clearInterval(ticker); ticker = null; } };
}

/** "3 min ago" on the browser; the date on the server */
export function Ago({ iso }: { iso: string | null | undefined }) {
  const text = useSyncExternalStore(subscribeClock, () => ago(iso), () => when(iso));
  return <>{text}</>;
}

/** "Due in 3 h" / "Overdue by 2 d" on the browser; the due date on the server */
export function Due({ iso, settled }: { iso: string | null | undefined; settled: boolean }) {
  const text = useSyncExternalStore(subscribeClock, () => dueWords(iso, settled), () => (settled || !iso ? "—" : when(iso)));
  return <>{text}</>;
}
