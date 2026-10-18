"use client";

/**
 * V546: the live database's own slowest statements (pg_stat_statements) — how often each ran and how long it took, the portal
 * functions it calls and the screens known to issue it. The live database's figures, not a copy's on another machine.
 * V555: over the last day, week or month by the daily snapshots; the statements ICT was told turned slow; a reset for ICT.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
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
  /** V555 */
  period?: "RESET" | "DAYS"; days?: number | null; reset_at?: string | null; snapshots?: number;
  resets: { reset_at: string; office: string | null; reason: string | null }[];
  alerts: { day: string; mean_ms: number; before_ms: number; calls: number; query: string | null }[];
}

const ms = (n: number) => (n >= 1000 ? `${(n / 1000).toLocaleString("en-NG", { maximumFractionDigits: 1 })} s` : `${Number(n).toLocaleString("en-NG", { maximumFractionDigits: 1 })} ms`);
const count = (n: number) => Number(n).toLocaleString("en-NG");
const day = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });
const ORDERS: [string, string][] = [["MEAN", "Slowest on average"], ["MAX", "Slowest once"], ["TOTAL", "Most time in all"], ["CALLS", "Most run"]];
const PERIODS: [number, string][] = [[0, "Since the statistics were reset"], [1, "The last day"], [7, "The last 7 days"], [30, "The last 30 days"]];

export function SlowStatements({ d, order, minCalls, days, may }: { d: SlowData; order: string; minCalls: number; days: number; may: boolean }) {
  const nav = useQueryNav();
  const router = useRouter();
  const [open, setOpen] = useState<number | null>(null);
  const [form, setForm] = useState({ fn: "", screens: "" });
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [resetting, setResetting] = useState(false);
  const [why, setWhy] = useState("");
  const go = (o: string, m: number, p = days) => nav(`/platform/slow-statements?order=${o}&minCalls=${m}${p ? `&days=${p}` : ""}`);
  const periodWords = PERIODS.find(([k]) => k === days)?.[1] ?? PERIODS[0][1];
  const head = ["Statement", "Screens", "Calls", "Mean (ms)", "Worst (ms)", "Total (ms)", "Share of all (%)"];
  const sheet = () => d.rows.map((r) => [r.query, (r.screens ?? []).join(" | "), r.calls, r.mean_ms, r.max_ms, r.total_ms, r.share_pct ?? ""]);

  async function reset() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/platform/slow-statements/reset", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Statement statistics reset: ${why.trim()}`) },
        body: JSON.stringify({ reason: why.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify("The statement statistics were reset");
      setResetting(false);
      setWhy("");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

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
            <Field id="ss-period" label="Period">
              <select id="ss-period" className="ctl" style={{ minWidth: 220 }} value={String(days)} onChange={(e) => go(order, minCalls, Number(e.target.value))}>
                {PERIODS.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
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
          {d.available && days > 0 && d.period !== "DAYS" ? <Note kind="info" title="No snapshot kept yet">The figures over a period come from the snapshot taken each night; until the first is kept, they are since the statistics were reset.</Note> : null}
          {d.available && d.period === "DAYS" ? <div className="sub2 mt-1">{periodWords}: what ran since {d.since ? day(d.since) : "the snapshot"}; the worst single run is since the statistics were reset.</div> : null}
          {may && d.available ? (
            <div className="row row--right mt-2">
              <span className="sub2 grow">{d.reset_at ? `Statistics kept since ${day(d.reset_at)}.` : null} {d.resets[0] ? `Last reset by ${d.resets[0].office ?? "the database"}: ${d.resets[0].reason ?? ""}` : null}</span>
              <Btn kind="ghost" onClick={() => setResetting(true)}>Reset the statistics</Btn>
            </div>
          ) : null}
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
      {d.alerts.length ? (
        <Panel title="Statements that turned slow" right="told to ICT after each night's snapshot">
          <DTable pageSize={10} cols={["Day", "Statement", "Average (ms)|num", "The week before (ms)|num", "Runs|num"]} rows={d.alerts.map((a) => [
            <span key="d" className="tnum">{a.day}</span>,
            <code key="q" className="sub2" style={{ whiteSpace: "pre-wrap", wordBreak: "break-word" }}>{a.query ?? "—"}</code>,
            <b key="m" className="tnum">{ms(a.mean_ms)}</b>,
            <span key="b" className="tnum">{ms(a.before_ms)}</span>,
            <span key="c" className="tnum">{count(a.calls)}</span>,
          ])} />
        </Panel>
      ) : null}
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
      {resetting ? (
        <Modal title="Reset the statement statistics" sub="This database only; the counts start again from now" onClose={() => setResetting(false)}
          foot={<><Btn kind="ghost" onClick={() => setResetting(false)}>Cancel</Btn><span className="grow" /><Btn kind="urgent" busy={busy} disabled={why.trim().length < 5} onClick={() => void reset()}>Reset</Btn></>}>
          <Note kind="info" title="What a reset does">Every statement&rsquo;s calls and times start again from nought. The nightly snapshots are kept, so the last day, week and month still read; the figures since the reset begin from now.</Note>
          <Field id="ss-why" label="Why"><input id="ss-why" className="ctl" style={{ minWidth: 360 }} value={why} onChange={(e) => setWhy(e.target.value)} placeholder="After the release of 20 October, to see the new figures alone" /></Field>
          {problem ? <ProblemNotice problem={problem} /> : null}
        </Modal>
      ) : null}
    </>
  );
}
