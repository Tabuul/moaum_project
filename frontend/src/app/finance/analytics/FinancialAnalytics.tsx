"use client";

/** Financial analytics (V279): one filter bar over the one engine — date preset or range, granularity, payment types
 *  (several at once), gender, faculty, department, programme, level, session, entry type, channel, search — the
 *  figures as doors, the period before beside them, the charts, and the breakdown tables by payment type, faculty,
 *  department, programme, level, gender, entry type, session and channel, each row narrowing the filters or opening
 *  the transactions behind it. Every number is counted on the server within the acting office's scope. */
import { useState } from "react";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { Donut, HBars, Line, VBars, VZ, vzNum, type DonutItem } from "@/components/proto/vz";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import {
  PRESETS, analyticsHeading, bucketLabel, entryWord, finQuery, naira, presetGranularity, presetRange, sexWord,
  type FinCategory, type FinFigures, type FinFilters, type FinSummary,
} from "@/lib/analytics";

const PALETTE = [VZ.s1, VZ.s3, VZ.s4, VZ.s2, VZ.s5, VZ.good, VZ.warn, VZ.crit, "#6b5bd6", "#2aa7b7", "#8a939e", "#c47f2a"];
const SETTERS = new Set(["bursar", "ict", "admin", "super"]);
const pct = (a: number, b: number) => (b ? `${a >= b ? "+" : ""}${Math.round(((a - b) / b) * 100)}%` : a ? "new" : "—");

type BreakRow = FinFigures & { key: string; label: string; sub?: string; next: Partial<FinFilters> };

export function FinancialAnalytics({ data, filters }: { data: FinSummary; filters: FinFilters }) {
  const queryNav = useQueryNav();
  const f: FinFilters = { ...filters, session: filters.session || data.filters.session || "" };
  const t = data.totals;
  const o = data.options;
  const money = data.scope.money;
  const canOpen = data.scope.transactions;
  const [busy, setBusy] = useState<string | null>(null);
  const [typesOpen, setTypesOpen] = useState(false);
  const selected = new Set(f.types ? f.types.split(",") : []);
  const faculties = [...new Map(o.programmes.map((p) => [p.faculty_code, p.faculty])).entries()].sort((a, b) => a[1].localeCompare(b[1]));
  const depts = [...new Map(o.programmes.filter((p) => !f.fac || p.faculty_code === f.fac).map((p) => [p.dept_code, p.department])).entries()].sort((a, b) => a[1].localeCompare(b[1]));
  const progs = o.programmes.filter((p) => (!f.fac || p.faculty_code === f.fac) && (!f.dept || p.dept_code === f.dept));
  const catLabel = (code: string) => o.categories.find((c) => c.code === code)?.label ?? code;

  const words = [data.scope.label,
    f.from && f.to ? (f.from === f.to ? f.from : `${f.from} → ${f.to}`) : f.preset ? PRESETS.find((p) => p.key === f.preset)?.label : null,
    f.session ? `session ${f.session}` : "all sessions",
    selected.size ? [...selected].map(catLabel).join(", ") : "all payment types",
    f.sex ? sexWord(f.sex) : null, f.fac ? faculties.find((x) => x[0] === f.fac)?.[1] : null, f.dept ? depts.find((x) => x[0] === f.dept)?.[1] : null,
    f.prog ? o.programmes.find((x) => x.programme_code === f.prog)?.programme : null, f.level ? `${f.level} Level` : null, f.entry ? entryWord(f.entry) : null,
    f.channel ? `channel ${f.channel}` : null, f.q ? `search “${f.q}”` : null].filter(Boolean).join(" · ");

  function go(next: Partial<FinFilters>) {
    const n: FinFilters = { ...f, ...next };
    if (next.fac !== undefined) { n.dept = ""; n.prog = ""; }
    if (next.dept !== undefined) { n.prog = ""; }
    if (next.preset !== undefined) {
      const r = presetRange(next.preset);
      if (r) { n.from = r.from; n.to = r.to; n.granularity = presetGranularity(next.preset); }
      else if (next.preset === "") { n.from = ""; n.to = ""; }
    }
    if ((next.from !== undefined || next.to !== undefined) && next.preset === undefined) n.preset = n.from || n.to ? "custom" : "";
    queryNav(`/finance/analytics?${finQuery(n)}`);
  }
  const txHref = (extra: Partial<FinFilters> = {}, more: Record<string, string | number | undefined> = {}) => `/finance/analytics/transactions?${finQuery({ ...f, ...extra }, more)}`;
  const toggleType = (code: string) => { const s = new Set(selected); if (s.has(code)) s.delete(code); else s.add(code); go({ types: [...s].join(",") }); };

  /* the breakdown tables share one shape and one export */
  const rows = (xs: BreakRow[]) => xs.map((r, i) => [
    <span key="sn" className="tnum sub2">{i + 1}</span>,
    <button key="l" type="button" className="lnk b600" style={{ background: "none", border: 0, padding: 0, font: "inherit", cursor: "pointer", textAlign: "left" }} onClick={() => go(r.next)} title={`Narrow to ${r.label}`}>{r.label}{r.sub ? <div className="sub2">{r.sub}</div> : null}</button>,
    <span key="t" className="tnum">{vzNum(r.transactions)}</span>,
    <span key="p" className="tnum">{vzNum(r.payers)}</span>,
    <span key="a" className="tnum b600">{naira(r.amount)}</span>,
    <span key="s" className="tnum sub2">{t.amount ? `${Math.round((100 * Number(r.amount)) / Number(t.amount))}%` : "—"}</span>,
    canOpen ? <LinkBtn key="x" href={txHref(r.next)} size="sm">Transactions</LinkBtn> : <span key="x" />,
  ]);
  const COLS = ["S/N|num", "", "Transactions|num", "Unique payers|num", "Amount|num", "Share|num", "|num"];
  async function exportTable(kind: "xlsx" | "pdf", what: string, xs: BreakRow[]) {
    setBusy(what + kind);
    try {
      const serial = docSerial("FIN");
      const head = ["S/N", what, "Transactions", "Unique Paying Students", "Amount (₦)", "Share"];
      const body = xs.map((r, i) => [i + 1, r.sub ? `${r.label} (${r.sub})` : r.label, r.transactions, r.payers, Number(r.amount), t.amount ? `${Math.round((100 * Number(r.amount)) / Number(t.amount))}%` : ""]);
      body.push(["", "Total", t.transactions, t.payers, Number(t.amount), "100%"]);
      const title = `Revenue by ${what} — Financial Analytics`;
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, head, body, { sheetName: `By ${what}`.slice(0, 31), serial, sub: words }), `revenue-by-${what.toLowerCase().replace(/\s+/g, "-")}-${serial}.xlsx`);
      else brandedPrint(title, words, head, body, serial);
      notify("Financial report generated successfully.");
    } catch (e) { notifyProblem((e as Problem) ?? { status: 0, title: "Unable to load financial statistics. Please try again." }); }
    finally { setBusy(null); }
  }
  const table = (what: string, xs: BreakRow[], id: string) => (
    <Panel title={`Revenue by ${what.toLowerCase()}`} right={xs.length ? <span className="row row--inline row--tight"><Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => void exportTable("xlsx", what, xs)}>Excel</Btn><Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => void exportTable("pdf", what, xs)}>PDF</Btn></span> : null} key={id}>
      {xs.length ? <DTable pageSize={0} cols={[COLS[0], `${what}`, ...COLS.slice(2)]} rows={rows(xs)} texts={xs.map((r) => `${r.label} ${r.sub ?? ""}`)} />
        : <PBody><div className="sub2">No payment records match the selected filters.</div></PBody>}
    </Panel>
  );

  const catRows: BreakRow[] = data.byCategory.map((x) => ({ ...x, key: x.code, label: x.label, next: { types: x.code } }));
  const facRows: BreakRow[] = data.byFaculty.map((x) => ({ ...x, key: x.faculty_code ?? "none", label: x.faculty ?? "No faculty on record", next: { fac: x.faculty_code ?? "" } }));
  const deptRows: BreakRow[] = data.byDepartment.map((x) => ({ ...x, key: x.dept_code ?? "none", label: x.department ?? "No department on record", sub: data.scope.kind === "UNIVERSITY" || data.scope.kind === "COLLEGE" || data.scope.kind === "PG_SCHOOL" ? x.faculty ?? undefined : undefined, next: { fac: x.faculty_code ?? "", dept: x.dept_code ?? "" } }));
  const progRows: BreakRow[] = data.byProgramme.map((x) => ({ ...x, key: x.programme_code ?? "none", label: x.programme ?? "No programme on record", sub: x.department ?? undefined, next: { fac: x.faculty_code ?? "", dept: x.dept_code ?? "", prog: x.programme_code ?? "" } }));
  const levelRows: BreakRow[] = data.byLevel.map((x) => ({ ...x, key: String(x.level), label: x.level == null ? "No level on record" : `${x.level} Level`, next: { level: x.level == null ? "" : String(x.level) } }));
  const sexRows: BreakRow[] = data.byGender.map((x) => ({ ...x, key: String(x.sex), label: sexWord(x.sex), next: { sex: x.sex ?? "" } }));
  const entryRows: BreakRow[] = data.byEntry.map((x) => ({ ...x, key: String(x.entry_mode), label: entryWord(x.entry_mode), next: { entry: x.entry_mode ?? "" } }));
  const sessionRows: BreakRow[] = data.bySession.map((x) => ({ ...x, key: String(x.session), label: x.session ?? "No session", next: { session: x.session ?? "" } }));
  const channelRows: BreakRow[] = data.byChannel.map((x) => ({ ...x, key: String(x.channel), label: x.channel ?? "Not recorded", next: { channel: x.channel ?? "" } }));
  const orgRows = data.scope.kind === "DEPARTMENT" ? progRows : data.scope.kind === "FACULTY" ? deptRows : facRows;
  const orgWord = data.scope.kind === "DEPARTMENT" ? "Programme" : data.scope.kind === "FACULTY" ? "Department" : "Faculty";
  const donut: DonutItem[] = catRows.slice(0, 12).map((r, i) => ({ l: r.label, v: Number(r.amount), c: PALETTE[i % PALETTE.length] }));
  const trendMax = Math.max(1, ...data.trend.map((x) => Number(x.amount)));
  const cmp = data.compare;

  const tiles: [string, string, string | null, string, string | null][] = [
    ["Total revenue", naira(t.revenue), "var(--green-ink)", `${vzNum(t.transactions)} transaction${t.transactions === 1 ? "" : "s"}`, canOpen ? txHref() : null],
    ["Transactions", vzNum(t.transactions), null, "Confirmed payments in the selection", canOpen ? txHref() : null],
    ["Unique paying students", vzNum(t.payers), "var(--chrome)", "Distinct payers, however many payments each", null],
    ["Net revenue", naira(t.net_revenue), null, t.refunded_count ? `${vzNum(t.refunded_count)} refund${t.refunded_count === 1 ? "" : "s"} paid, ${naira(t.refunded_amount)}` : "No refunds paid in the selection", null],
    ["Pending references", vzNum(t.pending_count), t.pending_count ? "var(--amber-ink)" : null, `${naira(t.pending_amount)} generated, not yet confirmed`, null],
    ["Failed gateway attempts", vzNum(t.failed_count), t.failed_count ? "var(--red-ink)" : null, "Declined, short-paid or unsigned callbacks", "/finance/gateways"],
  ];

  return (
    <>
      <PageHead title={analyticsHeading(data.scope)} description={`${words}`}
        actions={<>{canOpen ? <LinkBtn kind="primary" href={txHref()}>All transactions</LinkBtn> : null}<LinkBtn href="/stats">Student Statistics</LinkBtn><Btn kind="ghost" onClick={() => queryNav("/finance/analytics")}>Reset filters</Btn></>} />

      <div className="scope">
        <div className="scope__f"><Field id="fa-preset" label="Date">
          <select id="fa-preset" className="ctl" value={f.preset} onChange={(e) => go({ preset: e.target.value })}>{PRESETS.map((p) => <option key={p.key} value={p.key}>{p.label}</option>)}</select>
        </Field></div>
        <div className="scope__f"><Field id="fa-from" label="From"><input id="fa-from" type="date" className="ctl" value={f.from} onChange={(e) => go({ from: e.target.value })} /></Field></div>
        <div className="scope__f"><Field id="fa-to" label="To"><input id="fa-to" type="date" className="ctl" value={f.to} onChange={(e) => go({ to: e.target.value })} /></Field></div>
        <div className="scope__f"><Field id="fa-gran" label="Trend by">
          <select id="fa-gran" className="ctl" value={f.granularity} onChange={(e) => go({ granularity: e.target.value })}>{o.granularities.map((g) => <option key={g} value={g}>{g.charAt(0).toUpperCase() + g.slice(1)}</option>)}</select>
        </Field></div>
        <div className="scope__f" style={{ position: "relative" }}><Field id="fa-types" label="Payment types">
          <button id="fa-types" type="button" className="ctl" style={{ textAlign: "left", cursor: "pointer" }} onClick={() => setTypesOpen(!typesOpen)} aria-expanded={typesOpen}>
            {selected.size ? `${selected.size} selected` : "All payment types"}
          </button>
          {typesOpen ? (
            <div className="card" style={{ position: "absolute", zIndex: 20, marginTop: 4, minWidth: 280, maxHeight: 320, overflow: "auto" }}>
              <div className="card__body">
                <label className="row row--tight" style={{ gap: 8 }}><input type="checkbox" checked={selected.size === 0} onChange={() => go({ types: "" })} /> All payment types</label>
                {o.categories.map((c) => (
                  <label key={c.code} className="row row--tight" style={{ gap: 8 }}><input type="checkbox" checked={selected.has(c.code)} onChange={() => toggleType(c.code)} /> {c.label}{!c.revenue ? <span className="sub2"> (not revenue)</span> : null}</label>
                ))}
                <div className="row mt-2"><Btn kind="secondary" size="sm" onClick={() => setTypesOpen(false)}>Done</Btn></div>
              </div>
            </div>
          ) : null}
        </Field></div>
        <div className="scope__f"><Field id="fa-sex" label="Gender">
          <select id="fa-sex" className="ctl" value={f.sex} onChange={(e) => go({ sex: e.target.value })}><option value="">All</option>{o.genders.map((g) => <option key={g} value={g}>{sexWord(g)}</option>)}</select>
        </Field></div>
        {data.scope.kind === "FACULTY" || data.scope.kind === "DEPARTMENT" ? null : (
          <div className="scope__f"><Field id="fa-fac" label={data.scope.kind === "COLLEGE" ? "Faculty / School" : "Faculty"}>
            <select id="fa-fac" className="ctl" value={f.fac} onChange={(e) => go({ fac: e.target.value })}><option value="">All</option>{faculties.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select>
          </Field></div>
        )}
        {data.scope.kind === "DEPARTMENT" ? null : (
          <div className="scope__f"><Field id="fa-dept" label="Department">
            <select id="fa-dept" className="ctl" value={f.dept} onChange={(e) => go({ dept: e.target.value })}><option value="">All</option>{depts.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select>
          </Field></div>
        )}
        <div className="scope__f"><Field id="fa-prog" label="Programme">
          <select id="fa-prog" className="ctl" value={f.prog} onChange={(e) => go({ prog: e.target.value })}><option value="">All</option>{progs.map((p) => <option key={p.programme_code} value={p.programme_code}>{p.programme}</option>)}</select>
        </Field></div>
        <div className="scope__f"><Field id="fa-level" label="Level">
          <select id="fa-level" className="ctl" value={f.level} onChange={(e) => go({ level: e.target.value })}><option value="">All</option>{o.levels.map((l) => <option key={l} value={String(l)}>{l} Level</option>)}</select>
        </Field></div>
        <div className="scope__f"><Field id="fa-session" label="Session of the payment">
          <select id="fa-session" className="ctl" value={f.session || "ALL"} onChange={(e) => go({ session: e.target.value })}><option value="ALL">All sessions</option>{o.sessions.map((s) => <option key={s} value={s}>{s}{s === o.currentSession ? " (current)" : ""}</option>)}</select>
        </Field></div>
        <div className="scope__f"><Field id="fa-entry" label="Entry type">
          <select id="fa-entry" className="ctl" value={f.entry} onChange={(e) => go({ entry: e.target.value })}><option value="">All</option>{o.entryModes.map((m) => <option key={m} value={m}>{entryWord(m)}</option>)}</select>
        </Field></div>
        <div className="scope__f"><Field id="fa-channel" label="Channel">
          <select id="fa-channel" className="ctl" value={f.channel} onChange={(e) => go({ channel: e.target.value })}><option value="">All</option>{o.channels.map((c) => <option key={c} value={c}>{c}</option>)}</select>
        </Field></div>
        <div className="scope__f"><Field id="fa-q" label="Search">
          <input id="fa-q" className="ctl" defaultValue={f.q} placeholder="Name, number, reference, receipt" onKeyDown={(e) => { if (e.key === "Enter") go({ q: (e.target as HTMLInputElement).value }); }} onBlur={(e) => { if (e.target.value !== f.q) go({ q: e.target.value }); }} />
        </Field></div>
      </div>

      <div className="grid grid--3">
        {tiles.map(([label, v, colour, caption, href]) => {
          const inner = <><div className="eyebrow">{label}</div><div className="n" style={colour ? { color: colour } : undefined}>{v}</div><div className="c">{caption}</div></>;
          return href ? <Link key={label} href={href} className="tile stat-tile" title={`Open ${label.toLowerCase()}`}>{inner}</Link> : <div key={label} className="tile">{inner}</div>;
        })}
      </div>

      {cmp ? (
        <Note kind="info" title={`Compared with ${cmp.label.toLowerCase()}${cmp.from ? ` (${cmp.from} → ${cmp.to})` : ""}`}>
          Revenue {naira(cmp.amount)} then, {naira(t.amount)} now ({pct(Number(t.amount), Number(cmp.amount))}) · transactions {vzNum(cmp.transactions)} → {vzNum(t.transactions)} ({pct(t.transactions, cmp.transactions)}) · unique payers {vzNum(cmp.payers)} → {vzNum(t.payers)} ({pct(t.payers, cmp.payers)}).
        </Note>
      ) : null}

      {t.transactions === 0 ? <Note kind="info" title="No payment records match the selected filters">Widen the date, the session or the payment types; a payment counts once it is confirmed.</Note> : null}

      <div className="grid grid--2">
        <Panel title="Revenue by payment type"><PBody>
          {donut.length ? <Donut items={donut} capLabel="Revenue" capValue={naira(t.amount)} onPick={(item) => { const r = catRows.find((x) => x.label === item.l); if (r) go(r.next); }} /> : <div className="sub2">Nothing to draw.</div>}
        </PBody></Panel>
        <Panel title={`Revenue by ${orgWord.toLowerCase()}`}><PBody>
          {orgRows.length ? <HBars items={orgRows.slice(0, 12).map((r) => ({ l: r.label, v: Number(r.amount) }))} colour={VZ.s1} onPick={(_, i) => go(orgRows[i].next)} /> : <div className="sub2">Nothing to draw.</div>}
        </PBody></Panel>
        <Panel title={`Revenue trend by ${f.granularity}`}><PBody>
          {data.trend.length ? <Line series={[{ l: "Revenue", v: data.trend.map((x) => Number(x.amount)), c: VZ.s3 }]} xs={data.trend.map((x) => bucketLabel(x.bucket, f.granularity))} yMax={trendMax} yLabel="₦" /> : <div className="sub2">Nothing to draw.</div>}
        </PBody></Panel>
        <Panel title="Revenue by level and by gender"><PBody>
          {levelRows.length ? <VBars items={levelRows.map((r, i) => ({ l: r.label.replace(" Level", ""), v: Number(r.amount), c: PALETTE[i % PALETTE.length] }))} /> : <div className="sub2">Nothing to draw.</div>}
          <div className="row mt-2">{sexRows.map((r) => <span key={r.key} className="row row--tight"><Pil kind={r.key === "M" ? "info" : r.key === "F" ? "ok" : "grey"}>{r.label}</Pil><span className="tnum">{naira(r.amount)} · {vzNum(r.payers)} payer{r.payers === 1 ? "" : "s"}</span></span>)}</div>
        </PBody></Panel>
      </div>

      {table("Payment type", catRows, "cat")}
      {data.scope.kind === "FACULTY" || data.scope.kind === "DEPARTMENT" ? null : table("Faculty", facRows, "fac")}
      {data.scope.kind === "DEPARTMENT" ? null : table("Department", deptRows, "dept")}
      {table("Programme", progRows, "prog")}
      <div className="grid grid--2">
        {table("Level", levelRows, "level")}
        {table("Gender", sexRows, "sex")}
        {table("Entry type", entryRows, "entry")}
        {table("Session", sessionRows, "session")}
      </div>
      {table("Channel", channelRows, "channel")}

      <Panel title={`Revenue by ${f.granularity}`} right={data.trend.length ? <span className="sub2">{data.trend.length} period{data.trend.length === 1 ? "" : "s"}</span> : null}>
        {data.trend.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Period", "Transactions|num", "Unique payers|num", "Amount|num", "|num"]} rows={data.trend.map((x, i) => [
            <span key="sn" className="tnum sub2">{i + 1}</span>,
            <span key="l" className="b600">{bucketLabel(x.bucket, f.granularity)}</span>,
            <span key="t" className="tnum">{vzNum(x.transactions)}</span>,
            <span key="p" className="tnum">{vzNum(x.payers)}</span>,
            <span key="a" className="tnum b600">{naira(x.amount)}</span>,
            canOpen ? <LinkBtn key="x" href={txHref({ preset: "custom", from: x.bucket, to: periodEnd(x.bucket, f.granularity) })} size="sm">Transactions</LinkBtn> : <span key="x" />,
          ])} texts={data.trend.map((x) => x.bucket)} />
        ) : <PBody><div className="sub2">No payment records match the selected filters.</div></PBody>}
      </Panel>

      {SETTERS.has(data.scope.office) && money ? <Categories categories={o.categories} onChanged={() => queryNav(`/finance/analytics?${finQuery(f)}`)} /> : null}
    </>
  );
}

/** the last day of the period a bucket opens, so a period's transactions are exactly its rows */
function periodEnd(bucket: string, granularity: string): string {
  const d = new Date(bucket + "T00:00:00");
  if (isNaN(d.getTime())) return bucket;
  const e = new Date(d);
  if (granularity === "week") e.setDate(e.getDate() + 6);
  else if (granularity === "month") { e.setMonth(e.getMonth() + 1); e.setDate(0); }
  else if (granularity === "quarter") { e.setMonth(e.getMonth() + 3); e.setDate(0); }
  else if (granularity === "year") { e.setFullYear(e.getFullYear() + 1); e.setDate(0); }
  return `${e.getFullYear()}-${String(e.getMonth() + 1).padStart(2, "0")}-${String(e.getDate()).padStart(2, "0")}`;
}

/** the Bursary's payment categories: stated here, they appear in every filter, chart and report at once */
function Categories({ categories, onChanged }: { categories: FinCategory[]; onChanged: () => void }) {
  const [all, setAll] = useState<FinCategory[] | null>(null);
  const [edit, setEdit] = useState({ code: "", label: "", pattern: "", kinds: "", ord: "100", revenue: true, active: true });
  const [busy, setBusy] = useState(false);
  const list = all ?? categories;
  async function load() {
    const r = await fetch("/api/bff/api/v1/analytics/finance/categories", { cache: "no-store" });
    if (r.ok) setAll((await r.json()) as FinCategory[]);
  }
  async function save() {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/analytics/finance/categories/${encodeURIComponent(edit.code.trim().toUpperCase())}`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Payment category ${edit.code} stated`) },
        body: JSON.stringify({ label: edit.label, pattern: edit.pattern || null, kinds: edit.kinds.split(",").map((k) => k.trim()).filter(Boolean), ord: Number(edit.ord) || 100, revenue: edit.revenue, active: edit.active }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify(`Payment category ${edit.code.toUpperCase()} stated`);
      setEdit({ code: "", label: "", pattern: "", kinds: "", ord: "100", revenue: true, active: true });
      await load();
      onChanged();
    } finally { setBusy(false); }
  }
  return (
    <Panel title="Payment categories" right={<span className="sub2">A payment falls in the first category, by order, whose kinds hold its reference kind or whose pattern matches its purpose</span>}>
      <DTable pageSize={0} cols={["S/N|num", "Code", "Label", "Reference kinds", "Purpose pattern", "Order|num", "Revenue|mid", "Active|mid", "|num"]} rows={list.map((c, i) => [
        <span key="sn" className="tnum sub2">{i + 1}</span>, <span key="c" className="tnum">{c.code}</span>, <span key="l">{c.label}</span>,
        <span key="k" className="sub2">{(c.kinds ?? []).join(", ") || "—"}</span>, <span key="p" className="sub2 tnum">{c.pattern ?? "—"}</span>, <span key="o" className="tnum">{c.ord}</span>,
        <Pil key="r" kind={c.revenue ? "ok" : "grey"}>{c.revenue ? "Counts" : "Not revenue"}</Pil>, <Pil key="a" kind={c.active ? "ok" : "grey"}>{c.active ? "Active" : "Off"}</Pil>,
        <Btn key="e" kind="ghost" size="sm" onClick={() => setEdit({ code: c.code, label: c.label, pattern: c.pattern ?? "", kinds: (c.kinds ?? []).join(","), ord: String(c.ord), revenue: c.revenue, active: c.active })}>Edit</Btn>,
      ])} texts={list.map((c) => `${c.code} ${c.label}`)} />
      <PBody>
        <div className="grid grid--3">
          <Field id="pc-code" label="Code" hint="Capital letters, digits, underscores; e.g. GST"><input id="pc-code" className="ctl tnum" value={edit.code} onChange={(e) => setEdit({ ...edit, code: e.target.value.toUpperCase() })} /></Field>
          <Field id="pc-label" label="Label"><input id="pc-label" className="ctl" value={edit.label} onChange={(e) => setEdit({ ...edit, label: e.target.value })} /></Field>
          <Field id="pc-pattern" label="Purpose pattern" hint="A regular expression over the reference's purpose, case-insensitive; e.g. ^gst"><input id="pc-pattern" className="ctl tnum" value={edit.pattern} onChange={(e) => setEdit({ ...edit, pattern: e.target.value })} /></Field>
          <Field id="pc-kinds" label="Reference kinds" hint="Comma-separated: APPLICATION, CHECKING, ACCEPTANCE, PG_APPLICATION…"><input id="pc-kinds" className="ctl tnum" value={edit.kinds} onChange={(e) => setEdit({ ...edit, kinds: e.target.value })} /></Field>
          <Field id="pc-ord" label="Order"><input id="pc-ord" className="ctl tnum" inputMode="numeric" value={edit.ord} onChange={(e) => setEdit({ ...edit, ord: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
          <div className="stack">
            <label className="sub2 row"><input type="checkbox" checked={edit.revenue} onChange={(e) => setEdit({ ...edit, revenue: e.target.checked })} /> Counts as revenue</label>
            <label className="sub2 row"><input type="checkbox" checked={edit.active} onChange={(e) => setEdit({ ...edit, active: e.target.checked })} /> Active</label>
          </div>
        </div>
        <div className="row mt-2"><Btn kind="primary" disabled={busy || !edit.code.trim() || !edit.label.trim()} onClick={() => void save()}>{busy ? "Saving…" : "State the category"}</Btn><Btn kind="ghost" onClick={() => void load()}>Show inactive too</Btn></div>
      </PBody>
    </Panel>
  );
}
