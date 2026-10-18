"use client";

/**
 * V546: the live database's own slowest statements (pg_stat_statements) — how often each ran and how long it took, the portal
 * functions it calls and the screens known to issue it. The live database's figures, not a copy's on another machine.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface SlowRow {
  query: string; calls: number; mean_ms: number; max_ms: number; total_ms: number; rows: number; share_pct: number | null;
  functions: string[] | null; screens: string[] | null;
}
export interface SlowData {
  available: boolean; reason?: string; order?: string; since?: string | null; total_ms?: number; hidden?: boolean; rows: SlowRow[];
  screens: { function_name: string; screens: string; note: string | null; set_at: string }[];
}

const ms = (n: number) => (n >= 1000 ? `${(n / 1000).toLocaleString("en-NG", { maximumFractionDigits: 1 })} s` : `${Number(n).toLocaleString("en-NG", { maximumFractionDigits: 1 })} ms`);
const count = (n: number) => Number(n).toLocaleString("en-NG");
const day = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });
const ORDERS: [string, string][] = [["MEAN", "Slowest on average"], ["MAX", "Slowest once"], ["TOTAL", "Most time in all"], ["CALLS", "Most run"]];

export function SlowStatements({ d, order, minCalls, may }: { d: SlowData; order: string; minCalls: number; may: boolean }) {
  const nav = useQueryNav();
  const router = useRouter();
  const [open, setOpen] = useState<number | null>(null);
  const [form, setForm] = useState({ fn: "", screens: "" });
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const go = (o: string, m: number) => nav(`/platform/slow-statements?order=${o}&minCalls=${m}`);
  const head = ["Statement", "Screens", "Calls", "Mean (ms)", "Worst (ms)", "Total (ms)", "Share of all (%)"];
  const sheet = () => d.rows.map((r) => [r.query, (r.screens ?? []).join(" | "), r.calls, r.mean_ms, r.max_ms, r.total_ms, r.share_pct ?? ""]);

  async function saveScreen() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/platform/slow-statements/screens/${encodeURIComponent(form.fn.trim())}`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Screens of ${form.fn.trim()} named`) },
        body: JSON.stringify({ screens: form.screens.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(`Screens of ${form.fn.trim()} named`);
      setForm({ fn: "", screens: "" });
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      {!d.available ? (
        <Note kind="info" title="This database keeps no statement statistics">
          {d.reason}. On the live portal&rsquo;s database (Railway, AWS RDS) pg_stat_statements is loaded; the figures appear there.
        </Note>
      ) : (
        <Tiles items={[
          ["Statements listed", count(d.rows.length), null, `run ${count(minCalls)} times or more`],
          ["Time in all statements", ms(d.total_ms ?? 0), null, d.since ? `since ${day(d.since)}` : "since the statistics were last reset"],
          ["Slowest on average", d.rows.length ? ms(Math.max(...d.rows.map((r) => Number(r.mean_ms)))) : "—", null, "of those listed"],
          ["Worst single run", d.rows.length ? ms(Math.max(...d.rows.map((r) => Number(r.max_ms)))) : "—", null, "of those listed"],
        ]} />
      )}
      {d.available && d.hidden ? <Note kind="info" title="Some statements are hidden">The portal&rsquo;s database role may not read the text of other roles&rsquo; statements; grant it pg_read_all_stats to see them.</Note> : null}
      <Panel title="The live database's slowest statements" right={d.available ? "pg_stat_statements" : "not available here"}>
        <PBody>
          <div className="row row--end">
            <Field id="ss-order" label="Order">
              <select id="ss-order" className="ctl" style={{ minWidth: 200 }} value={order} onChange={(e) => go(e.target.value, minCalls)}>
                {ORDERS.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </Field>
            <Field id="ss-min" label="Run at least">
              <select id="ss-min" className="ctl" value={String(minCalls)} onChange={(e) => go(order, Number(e.target.value))}>
                {[1, 5, 20, 100, 1000].map((n) => <option key={n} value={n}>{n} time{n === 1 ? "" : "s"}</option>)}
              </select>
            </Field>
            <span className="grow" />
            <Btn kind="ghost" disabled={!d.rows.length} onClick={async () => downloadBlob(await brandedXlsx("Slow Statements", head, sheet(), { sheetName: "Slow statements", serial: docSerial("SQL"), sub: ORDERS.find(([k]) => k === order)?.[1] ?? order, meta: [["Order", ORDERS.find(([k]) => k === order)?.[1] ?? order], ["Run at least", `${minCalls} times`]] }), "slow-statements.xlsx")}>Download Excel</Btn>
          </div>
          <div className="sub2 mt-2">A statement is shown as the database records it, its values replaced by $1, $2…; the functions it calls name the screens known to issue it. A screen that reads several statements takes their time together.</div>
        </PBody>
        {d.rows.length ? (
          <DTable pageSize={25} cols={["Statement", "Screens", "Calls|num", "Mean|num", "Worst|num", "Total|num", "Share|num"]}
            texts={d.rows.map((r) => `${r.query} ${(r.functions ?? []).join(" ")} ${(r.screens ?? []).join(" ")}`)}
            rows={d.rows.map((r, i) => [
              <span key="q"><code className="sub2" style={{ whiteSpace: "pre-wrap", wordBreak: "break-word" }}>{open === i || r.query.length <= 160 ? r.query : `${r.query.slice(0, 160)}…`}</code>
                {r.query.length > 160 ? <div><Btn kind="ghost" onClick={() => setOpen(open === i ? null : i)}>{open === i ? "Less" : "All of it"}</Btn></div> : null}
                {r.functions?.length ? <div className="sub2">{r.functions.join(", ")}</div> : null}</span>,
              <span key="s" className="sub2">{r.screens?.length ? r.screens.join(" · ") : "—"}</span>,
              <span key="c" className="tnum">{count(r.calls)}</span>,
              <b key="m" className="tnum">{ms(r.mean_ms)}</b>,
              <span key="x" className="tnum">{ms(r.max_ms)}</span>,
              <span key="t" className="tnum">{ms(r.total_ms)}</span>,
              <span key="p" className="tnum">{r.share_pct == null ? "—" : `${r.share_pct}%`}</span>,
            ])} />
        ) : d.available ? <PBody><div className="sub2">No statement has run {minCalls} times or more since the statistics were reset.</div></PBody> : null}
      </Panel>
      <Panel title="Screens of each function" right={`${d.screens.length}`}>
        <DTable pageSize={10} cols={["Function", "Screens", "Named"]} rows={d.screens.map((s) => [
          <code key="f" className="sub2">{s.function_name}</code>, <span key="s">{s.screens}</span>, <span key="d" className="sub2">{day(s.set_at)}</span>,
        ])} />
        {may ? (
          <PBody>
            <div className="row row--end">
              <Field id="ss-fn" label="Function"><input id="ss-fn" className="ctl" placeholder="finance.day_book" value={form.fn} onChange={(e) => setForm({ ...form, fn: e.target.value })} /></Field>
              <Field id="ss-sc" label="Screens"><input id="ss-sc" className="ctl" style={{ minWidth: 320 }} placeholder="Day Book (Ledger)" value={form.screens} onChange={(e) => setForm({ ...form, screens: e.target.value })} /></Field>
              <Btn kind="primary" busy={busy} disabled={!form.fn.trim() || !form.screens.trim()} onClick={() => saveScreen()}>Name its screens</Btn>
            </div>
            {problem ? <div className="mt-2"><ProblemNotice problem={problem} /></div> : null}
          </PBody>
        ) : null}
      </Panel>
    </>
  );
}
