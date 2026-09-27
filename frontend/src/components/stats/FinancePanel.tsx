"use client";

/** The financial figures on a dashboard (V279): revenue, transactions and unique payers for the current session
 *  within the acting office's scope, the top payment types, and the door to the full analytics. Asked after the
 *  page has painted; while the ledger is read it says so, and if it does not answer it says that instead. */
import { useEffect, useState } from "react";
import Link from "next/link";
import { LinkBtn, Note, Panel, PBody } from "@/components/proto/ui";
import { vzNum } from "@/components/proto/vz";
import { analyticsHeading, naira, type FinSummary } from "@/lib/analytics";

export function FinancePanel({ title = "Financial analytics" }: { title?: string }) {
  const [d, setD] = useState<FinSummary | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 90_000);
    fetch("/api/bff/api/v1/analytics/finance/summary?compare=false", { cache: "no-store", signal: ctl.signal })
      .then(async (r) => { if (!live) return; if (!r.ok) { setFailed(true); return; } setD((await r.json()) as FinSummary); })
      .catch(() => { if (live) setFailed(true); })
      .finally(() => clearTimeout(timer));
    return () => { live = false; ctl.abort(); };
  }, []);
  if (failed) return <Note kind="bad" title="Unable to load financial statistics" action={<LinkBtn href="/finance/analytics">Open Financial Analytics</LinkBtn>}>The figures could not be read just now. Please try again.</Note>;
  if (!d) return <Panel title={title} right={<span className="sub2">Reading the ledger…</span>}><PBody><div className="sub2">Revenue, transactions and unique payers are being counted for the current session.</div></PBody></Panel>;
  const t = d.totals;
  const session = d.filters.session || "all sessions";
  const top = d.byCategory.slice(0, 4);
  const tiles: [string, string, string | null, string][] = [
    ["Total revenue", naira(t.revenue), "var(--green-ink)", `Session ${session}`],
    ["Transactions", vzNum(t.transactions), null, "Confirmed payments"],
    ["Unique paying students", vzNum(t.payers), "var(--chrome)", "Distinct payers"],
    ["Pending references", vzNum(t.pending_count), t.pending_count ? "var(--amber-ink)" : null, naira(t.pending_amount) + " not yet confirmed"],
  ];
  return (
    <Panel title={title} right={<span className="row row--inline row--tight"><span className="sub2">{analyticsHeading(d.scope)}</span><LinkBtn kind="primary" size="sm" href="/finance/analytics">Open Financial Analytics</LinkBtn></span>}>
      <PBody>
        <div className="grid grid--4">
          {tiles.map(([label, v, colour, caption]) => (
            <Link key={label} href="/finance/analytics" className="tile stat-tile"><div className="eyebrow">{label}</div><div className="n" style={colour ? { color: colour } : undefined}>{v}</div><div className="c">{caption}</div></Link>
          ))}
        </div>
        {top.length ? (
          <div className="row mt-3" style={{ flexWrap: "wrap", gap: 14 }}>
            {top.map((c) => <Link key={c.code} className="lnk" href={`/finance/analytics?types=${encodeURIComponent(c.code)}`}>{c.label} · {naira(c.amount)}</Link>)}
            <Link className="lnk" href="/finance/analytics">By faculty, department, programme, level, gender and entry type</Link>
          </div>
        ) : <div className="sub2 mt-3">No confirmed payment this session within this scope yet.</div>}
      </PBody>
    </Panel>
  );
}
