"use client";

/**
 * Oct 2026: the summary's figures are kept a few minutes per scope and filters (the API's FinanceSummaryCache). This says
 * when they were worked out, offers Refresh to work them out again, and — while newer figures are being prepared behind the
 * ones shown — looks quietly for them (a background request, never counted as the person's activity) and offers to show
 * them once they are ready, instead of changing the figures under the reader's eyes.
 */
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { BACKGROUND_HEADER } from "@/lib/idle";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn } from "@/components/proto/ui";

/** the University's clock, the same on the server and in the browser */
const at = (iso: string) =>
  new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });

function ago(iso: string, now: number): string {
  const m = Math.floor((now - new Date(iso).getTime()) / 60000);
  return m < 1 ? "just now" : m === 1 ? "a minute ago" : m < 60 ? `${m} minutes ago` : m < 120 ? "an hour ago" : `${Math.floor(m / 60)} hours ago`;
}

export function FiguresAsOf({ asOf, computedMs, refreshing, query }: { asOf?: string; computedMs?: number; refreshing?: boolean; query: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState<number | null>(null);
  const [newer, setNewer] = useState(false);
  const looked = useRef(0);
  const url = `/api/bff/api/v1/analytics/finance/summary?${query}`;

  // the "minutes ago" is the browser's own reading, after the page is on screen
  useEffect(() => {
    const first = setTimeout(() => setNow(Date.now()), 0);
    const every = setInterval(() => setNow(Date.now()), 30000);
    return () => { clearTimeout(first); clearInterval(every); };
  }, [asOf]);

  // newer figures being prepared: look for them a few times, as long as they took last time
  useEffect(() => {
    looked.current = 0;
    if (!refreshing || !asOf) return;
    let live = true;
    let timer: ReturnType<typeof setTimeout>;
    const look = () => {
      timer = setTimeout(async () => {
        looked.current += 1;
        try {
          const r = await fetch(url, { cache: "no-store", headers: { [BACKGROUND_HEADER]: "1" } });
          const j = (await r.json().catch(() => null)) as { asOf?: string; refreshing?: boolean } | null;
          if (!live) return;
          if (r.ok && j?.asOf && j.asOf !== asOf) { setNewer(true); return; }
        } catch {
          /* offline for a moment: Refresh still works */
        }
        if (live && looked.current < 4) look();
      }, Math.min(Math.max((computedMs ?? 5000) + 1500, 3000), 60000));
    };
    look();
    return () => { live = false; clearTimeout(timer); };
  }, [refreshing, asOf, computedMs, url]);

  async function refresh() {
    setBusy(true);
    try {
      const r = await fetch(`${url}${query ? "&" : ""}fresh=true`, { cache: "no-store" });
      if (!r.ok) {
        notifyProblem(((await r.json().catch(() => null)) as Problem | null) ?? { status: r.status, title: r.statusText });
        return;
      }
      setNewer(false);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  if (!asOf) return null;
  return (
    <div className="row" style={{ gap: 8, flexWrap: "wrap", alignItems: "center", margin: "0 0 10px" }} aria-live="polite">
      <span className="sub2">
        Figures as of {at(asOf)}{now ? ` (${ago(asOf, now)})` : ""}
        {newer ? " · newer figures are ready" : refreshing ? " · newer figures are being prepared" : ""}
      </span>
      {newer ? <Btn kind="secondary" size="sm" onClick={() => { setNewer(false); router.refresh(); }}>Show them</Btn> : null}
      <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void refresh()}>{busy ? "Refreshing…" : "Refresh"}</Btn>
    </div>
  );
}
