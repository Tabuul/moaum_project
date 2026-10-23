"use client";

/** V640: the query builder — a source the server offers, conditions on its fields, the columns, a sort or a grouping; run a page at a
 *  time, exported with S/N first (an official DBO reference on request), saved and shared; the query log; the official reports. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, Note, Panel, PBody, Pil, Tabs, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { arity, cell, definition, opsFor, OP_WORDS, QUERY_PRESETS, type Cond, type Definition, type QSource, type QueryResult } from "@/lib/dbops";

export interface SavedQuery { id: string; name: string; description: string | null; kind: string; source: string; definition: Definition; shared_offices: string[]; owner: string | null; mine: boolean; updated_at: string }
export interface HistoryPage { rows: { at: string; actor: string | null; actor_office: string; action: string; source: string; title: string | null; scope: string | null; row_count: number | null; reference: string | null; format: string | null }[]; total: number; page: number; size: number; everyone: boolean }
export interface ReportsPage { rows: { reference: string; kind: string; title: string; scope: string | null; row_count: number | null; generated_by: string | null; actor_office: string; generated_at: string }[]; total: number; page: number; size: number }

type Tab = "query" | "saved" | "history" | "reports";
const BASE = "/api/bff/api/v1/dbops";

export function QueryBuilder({ sources, period, structure, sessions, types, saved, offices, history, reports, preset, open, tab, actorName, office }: {
  sources: QSource[]; period: { session: string; semester: number }; structure: ScopeStructure; sessions: string[]; types: { code: string; label: string }[];
  saved: SavedQuery[]; offices: { code: string; label: string }[]; history: HistoryPage | null; reports: ReportsPage | null;
  preset: string; open: string; tab: string; actorName: string | null; office: string | null;
}) {
  const router = useRouter();
  const start = (() => {
    const fromSaved = open ? saved.find((s) => s.id === open) : null;
    if (fromSaved) return { def: fromSaved.definition, title: fromSaved.name };
    const p = QUERY_PRESETS[preset];
    if (p && sources.some((s) => s.key === p.source)) return { def: { ...p, filters: p.filters ?? [], columns: [] } as Definition, title: p.title };
    return { def: { source: sources[0]?.key ?? "STUDENTS", filters: [], columns: [] } as Definition, title: "" };
  })();
  const [view, setView] = useState<Tab>(["saved", "history", "reports"].includes(tab) ? (tab as Tab) : "query");
  const [sourceKey, setSourceKey] = useState(start.def.source);
  const [filters, setFilters] = useState<Cond[]>(start.def.filters ?? []);
  const [columns, setColumns] = useState<string[]>(start.def.columns?.length ? start.def.columns : sources.find((s) => s.key === start.def.source)?.columns ?? []);
  const [sort, setSort] = useState<{ field: string; dir: string } | null>(start.def.sort ?? null);
  const [group, setGroup] = useState<string>(start.def.group?.field ?? "");
  const [groupSum, setGroupSum] = useState<string>(start.def.group?.sum ?? "");
  const [session, setSession] = useState(start.def.session ?? period.session);
  const [semester, setSemester] = useState(start.def.semester ?? period.semester);
  const [rule, setRule] = useState(start.def.rule ?? "CARD");
  const [title, setTitle] = useState(start.title);
  const [result, setResult] = useState<QueryResult | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [official, setOfficial] = useState(false);
  const [saveName, setSaveName] = useState("");
  const [saveNote, setSaveNote] = useState("");
  const [shareWith, setShareWith] = useState<string[]>([]);
  const [sharing, setSharing] = useState<SavedQuery | null>(null);
  const [hist, setHist] = useState<HistoryPage | null>(history);
  const [regs, setRegs] = useState<ReportsPage | null>(reports);
  const [regQ, setRegQ] = useState("");
  const src = sources.find((s) => s.key === sourceKey) ?? sources[0];
  const auditor = ["dbops", "ict", "admin", "super", "audit"].includes(office ?? "");

  async function call<T>(path: string, method: "GET" | "POST" | "PUT", body: unknown, reason: string): Promise<T | null> {
    setProblem(null);
    const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) {
      const p = j ?? { status: r.status, title: r.statusText };
      setProblem(p); notifyProblem(p);
      return null;
    }
    return j as T;
  }

  const def = (): Definition => definition(src, { session, semester, rule, filters, columns, sort, group: group ? { field: group, sum: groupSum || null } : null });

  function chooseSource(k: string) {
    const s = sources.find((x) => x.key === k);
    setSourceKey(k);
    setFilters([]);
    setColumns(s?.columns ?? []);
    setSort(null);
    setGroup("");
    setGroupSum("");
    setResult(null);
  }

  function optionsOf(f: { options?: string[] }): { value: string; label: string }[] | null {
    const o = f.options;
    if (!o || !o.length) return null;
    if (o[0] === "@faculty") return structure.faculties.map((x) => ({ value: x.code, label: x.name }));
    if (o[0] === "@department") return structure.faculties.flatMap((x) => x.departments.map((d) => ({ value: d.code, label: d.name })));
    if (o[0] === "@programme") return structure.faculties.flatMap((x) => x.departments.flatMap((d) => d.programmes.map((p) => ({ value: p.code, label: p.name }))));
    if (o[0] === "@programme_type") return types.map((t) => ({ value: t.code, label: t.label }));
    if (o[0] === "@session") return sessions.map((s) => ({ value: s, label: s }));
    if (o[0].startsWith("@")) return null;
    return o.map((v) => ({ value: v, label: v.toLowerCase().replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase()) }));
  }

  async function run(page = 1) {
    setBusy(true);
    try {
      const r = await call<QueryResult>(`${BASE}/query/run`, "POST", { definition: def(), page, size: 50 }, `Database query run: ${src.label}`);
      if (r) setResult(r);
    } finally {
      setBusy(false);
    }
  }

  async function exportAll(format: "XLSX" | "PDF") {
    const w = format === "PDF" ? window.open("", "_blank") : null;
    setBusy(true);
    try {
      const d = def();
      const r = await call<QueryResult>(`${BASE}/query/run`, "POST", { definition: d, page: 1, size: 50000, export: true }, `Database query exported: ${src.label}`);
      if (!r) { w?.close(); return; }
      const name = title.trim() || src.label;
      let serial = docSerial("DBO-QUERY");
      if (official) {
        const issued = await call<{ reference: string }>(`${BASE}/query/issue`, "POST", { title: name, definition: d, rows: r.total }, `Official reference issued: ${name}`);
        if (!issued) { w?.close(); return; }
        serial = issued.reference;
      }
      const headers = r.columns.map((c) => c.label);
      const rows = r.rows.map((x) => r.columns.map((c) => cell(x[c.key], c.type)));
      const meta: [string, string][] = [["Data source", src.label], ["Scope", r.scope],
        ...(src.period ? [["Session", String(d.session)], ["Semester", String(d.semester)]] as [string, string][] : []),
        ...d.filters.map((c) => [src.fields.find((f) => f.key === c.field)?.label ?? c.field, `${OP_WORDS[c.op] ?? c.op} ${c.values ? c.values.join(", ") : [c.value, c.value2].filter(Boolean).join(" and ")}`.trim()] as [string, string]),
        ["Rows", r.total.toLocaleString("en-GB")], ["Data as of", new Date(r.at).toLocaleString("en-GB")], ...(actorName ? [["Generated by", actorName] as [string, string]] : [])];
      if (format === "XLSX") {
        const b = await brandedXlsx(name, headers, rows, { serial, meta });
        downloadBlob(b, `${name.replace(/[^A-Za-z0-9]+/g, "-").toLowerCase()}.xlsx`);
      } else {
        brandedPrint(name, `${src.label} · ${r.scope}`, headers, rows, serial, { meta, orientation: "landscape", window: w, generatedBy: actorName });
      }
      await call(`${BASE}/log`, "POST", { action: format === "PDF" ? "PRINT" : "EXPORT", source: src.key, title: name, rows: r.total, reference: serial.startsWith("DBO/") ? serial : null, format, definition: d },
        `Database query ${format === "PDF" ? "printed" : "exported"}: ${name}`);
      if (official) notify(`${serial} issued`);
    } finally {
      setBusy(false);
    }
  }

  async function save() {
    setBusy(true);
    try {
      const r = await call<SavedQuery>(`${BASE}/saved`, "POST", { name: saveName.trim(), description: saveNote.trim() || null, kind: "QUERY", definition: def(), sharedOffices: shareWith },
        `Database query saved: ${saveName.trim()}`);
      if (r) { notify(`Saved: ${r.name}`); setSaveName(""); setSaveNote(""); router.refresh(); }
    } finally {
      setBusy(false);
    }
  }

  async function share() {
    if (!sharing) return;
    const r = await call<SavedQuery>(`${BASE}/saved/${sharing.id}/share`, "POST", { offices: shareWith }, `Saved query shared: ${sharing.name}`);
    if (r) { notify(`${r.name} shared`); setSharing(null); router.refresh(); }
  }

  async function archive(s: SavedQuery) {
    const r = await call(`${BASE}/saved/${s.id}/archive`, "POST", {}, `Saved query archived: ${s.name}`);
    if (r) router.refresh();
  }

  function load(s: SavedQuery) {
    const d = s.definition;
    const known = sources.find((x) => x.key === d.source);
    if (!known) { notify(`Your office does not read ${s.source.toLowerCase()}`); return; }
    setSourceKey(d.source); setFilters(d.filters ?? []); setColumns(d.columns?.length ? d.columns : known.columns); setSort(d.sort ?? null);
    setGroup(d.group?.field ?? ""); setGroupSum(d.group?.sum ?? ""); if (d.session) setSession(d.session); if (d.semester) setSemester(d.semester);
    setRule(d.rule ?? "CARD"); setTitle(s.name); setResult(null); setView("query");
  }

  async function loadHistory(all: boolean, page = 1) {
    const r = await call<HistoryPage>(`${BASE}/history?all=${all}&page=${page}&size=50`, "GET", undefined, "Query log read");
    if (r) setHist(r);
  }

  async function loadReports(page = 1) {
    const r = await call<ReportsPage>(`${BASE}/reports?page=${page}&size=50${regQ.trim() ? `&q=${encodeURIComponent(regQ.trim())}` : ""}`, "GET", undefined, "Official reports read");
    if (r) setRegs(r);
  }

  const setCond = (i: number, patch: Partial<Cond>) => setFilters((fs) => fs.map((c, j) => (j === i ? { ...c, ...patch } : c)));
  const numeric = src.fields.filter((f) => (f.type === "INT" || f.type === "NUM") && !["level", "semester", "reg_level", "course_level", "entry_level", "entry_year"].includes(f.key));

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Tabs label="Query builder" value={view} onChange={setView} items={[
        { id: "query", label: "Query" }, { id: "saved", label: "Saved & shared", count: saved.length },
        { id: "history", label: "Query log" }, { id: "reports", label: "Official reports" }]} />

      {view === "query" ? (
        <>
          <Panel title="Query" right={src.note}>
            <PBody>
              <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
                <Field id="qb-src" label="Data source">
                  <select id="qb-src" className="ctl" value={sourceKey} onChange={(e) => chooseSource(e.target.value)}>
                    {sources.map((s) => <option key={s.key} value={s.key}>{s.label}</option>)}
                  </select>
                </Field>
                {src.period ? (
                  <>
                    <Field id="qb-ses" label="Session"><select id="qb-ses" className="ctl" value={session} onChange={(e) => setSession(e.target.value)}>
                      {sessions.map((x) => <option key={x} value={x}>{x}</option>)}</select></Field>
                    <Field id="qb-sem" label="Semester"><select id="qb-sem" className="ctl" value={semester} onChange={(e) => setSemester(Number(e.target.value))}>
                      <option value={1}>First</option><option value={2}>Second</option><option value={3}>Third</option></select></Field>
                    <Field id="qb-rule" label="Paid means"><select id="qb-rule" className="ctl" value={rule} onChange={(e) => setRule(e.target.value)}>
                      <option value="CARD">A school-fees payment confirmed (card rule)</option><option value="FULL">Paid in full (Bursary rule)</option></select></Field>
                  </>
                ) : null}
                <Field id="qb-title" label="Report title"><input id="qb-title" className="ctl" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={300} placeholder={src.label} style={{ minWidth: 260 }} /></Field>
              </div>
              {src.required ? <div className="sub2" style={{ marginTop: "var(--s-1)" }}>{src.label} are read for a programme, a department and a level, or a student: add one of those conditions.</div> : null}
            </PBody>
            <PBody>
              <b>Conditions</b> <span className="sub2">all must hold</span>
              {filters.map((c, i) => {
                const f = src.fields.find((x) => x.key === c.field) ?? src.fields[0];
                const ops = opsFor(f.type);
                const op = ops.includes(c.op) ? c.op : ops[0];
                const opts = optionsOf(f);
                const a = arity(op);
                return (
                  <div key={i} className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "center", marginTop: "var(--s-1)" }}>
                    <select className="ctl" aria-label="Field" value={f.key} onChange={(e) => setCond(i, { field: e.target.value, op: opsFor(src.fields.find((x) => x.key === e.target.value)!.type)[0], value: "", value2: "", values: [] })}>
                      {src.fields.map((x) => <option key={x.key} value={x.key}>{x.label}</option>)}
                    </select>
                    <select className="ctl" aria-label="Operator" value={op} onChange={(e) => setCond(i, { op: e.target.value })}>
                      {ops.map((o) => <option key={o} value={o}>{OP_WORDS[o] ?? o}</option>)}
                    </select>
                    {a === 1 && f.type === "BOOL" ? (
                      <select className="ctl" aria-label="Value" value={c.value ?? ""} onChange={(e) => setCond(i, { op, value: e.target.value })}><option value="">—</option><option value="true">Yes</option><option value="false">No</option></select>
                    ) : a === 1 && opts && (op === "eq" || op === "ne") ? (
                      <select className="ctl" aria-label="Value" value={c.value ?? ""} onChange={(e) => setCond(i, { op, value: e.target.value })}>
                        <option value="">Choose</option>{opts.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}</select>
                    ) : a === "list" && opts ? (
                      <select className="ctl" aria-label="Values" multiple value={c.values ?? []} style={{ minWidth: 200, height: 80 }}
                        onChange={(e) => setCond(i, { op, values: Array.from(e.target.selectedOptions).map((o) => o.value) })}>
                        {opts.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}</select>
                    ) : a === 1 || a === "list" ? (
                      <input className="ctl" aria-label="Value" type={f.type === "DATE" ? "date" : "text"} value={c.value ?? ""} maxLength={200}
                        placeholder={a === "list" ? "one, two, three" : ""} onChange={(e) => setCond(i, { op, value: e.target.value, values: [] })} />
                    ) : a === 2 ? (
                      <>
                        <input className="ctl" aria-label="From" type={f.type === "DATE" ? "date" : "text"} value={c.value ?? ""} onChange={(e) => setCond(i, { op, value: e.target.value })} />
                        <span className="sub2">and</span>
                        <input className="ctl" aria-label="To" type={f.type === "DATE" ? "date" : "text"} value={c.value2 ?? ""} onChange={(e) => setCond(i, { op, value2: e.target.value })} />
                      </>
                    ) : null}
                    <Btn kind="ghost" size="sm" onClick={() => setFilters((fs) => fs.filter((_, j) => j !== i))}>Remove</Btn>
                  </div>
                );
              })}
              <div style={{ marginTop: "var(--s-2)" }}>
                <Btn kind="ghost" size="sm" disabled={filters.length >= 25} onClick={() => setFilters((fs) => [...fs, { field: src.fields[0].key, op: opsFor(src.fields[0].type)[0], value: "" }])}>Add a condition</Btn>
              </div>
            </PBody>
            <PBody>
              <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
                <Field id="qb-cols" label="Columns">
                  <select id="qb-cols" className="ctl" multiple value={columns} style={{ minWidth: 240, height: 120 }} onChange={(e) => setColumns(Array.from(e.target.selectedOptions).map((o) => o.value))}>
                    {src.fields.map((f) => <option key={f.key} value={f.key}>{f.label}</option>)}
                  </select>
                </Field>
                <Field id="qb-sort" label="Order by">
                  <select id="qb-sort" className="ctl" value={sort?.field ?? ""} onChange={(e) => setSort(e.target.value ? { field: e.target.value, dir: sort?.dir ?? "asc" } : null)}>
                    <option value="">{`Default (${src.fields.find((f) => f.key === src.sort)?.label ?? src.sort}${src.sortDir === "desc" ? ", newest first" : ", A to Z"})`}</option>
                    {src.fields.map((f) => <option key={f.key} value={f.key}>{f.label}</option>)}
                  </select>
                </Field>
                {sort ? (
                  <Field id="qb-dir" label="Direction"><select id="qb-dir" className="ctl" value={sort.dir} onChange={(e) => setSort({ ...sort, dir: e.target.value })}>
                    <option value="asc">Ascending</option><option value="desc">Descending</option></select></Field>
                ) : null}
                <Field id="qb-group" label="Count by (optional)">
                  <select id="qb-group" className="ctl" value={group} onChange={(e) => setGroup(e.target.value)}>
                    <option value="">No grouping — list the rows</option>
                    {src.fields.filter((f) => !f.money).map((f) => <option key={f.key} value={f.key}>{f.label}</option>)}
                  </select>
                </Field>
                {group && numeric.length ? (
                  <Field id="qb-sum" label="And add up"><select id="qb-sum" className="ctl" value={groupSum} onChange={(e) => setGroupSum(e.target.value)}>
                    <option value="">Nothing</option>{numeric.map((f) => <option key={f.key} value={f.key}>{f.label}</option>)}</select></Field>
                ) : null}
                <span className="ml-auto row row--tight">
                  <Btn kind="primary" disabled={busy} onClick={() => void run(1)}>RUN QUERY</Btn>
                </span>
              </div>
            </PBody>
          </Panel>

          {result ? (
            <Panel title={title.trim() || src.label} right={`${result.total.toLocaleString("en-GB")} ${result.grouped ? "groups" : "rows"} · ${result.scope} · read ${new Date(result.at).toLocaleTimeString("en-GB")}`}>
              <PBody>
                <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "center" }}>
                  <label className="row row--tight" style={{ alignItems: "center" }}>
                    <input type="checkbox" checked={official} onChange={(e) => setOfficial(e.target.checked)} />
                    <span>Issue an official reference (DBO/…/YYYY/NNNNNN) for the export</span>
                  </label>
                  <span className="ml-auto row row--tight">
                    <Btn kind="ghost" size="sm" disabled={busy || !result.total} onClick={() => void exportAll("XLSX")}>Excel</Btn>
                    <Btn kind="ghost" size="sm" disabled={busy || !result.total} onClick={() => void exportAll("PDF")}>PDF</Btn>
                  </span>
                </div>
              </PBody>
              {result.rows.length ? (
                <DTable pageSize={0} noPrint cols={["S/N|num", ...result.columns.map((c) => c.label + (c.type === "INT" || c.type === "NUM" ? "|num" : ""))]}
                  rows={result.rows.map((r, i) => [
                    <span key="n" className="tnum">{(result.page - 1) * result.size + i + 1}</span>,
                    ...result.columns.map((c) => {
                      const v = cell(r[c.key], c.type);
                      return <span key={c.key} className={typeof v === "number" ? "tnum" : undefined}>{c.money && typeof v === "number" ? `₦${v.toLocaleString("en-GB")}` : String(v)}</span>;
                    }),
                  ])} />
              ) : <PBody><div className="sub2">Nothing matches.</div></PBody>}
              {!result.grouped ? (
                <PBody>
                  <div className="row" style={{ gap: "var(--s-2)", alignItems: "center" }}>
                    <span className="sub2">Page {result.page} of {Math.max(1, Math.ceil(result.total / result.size))}</span>
                    <span className="ml-auto row row--tight">
                      <Btn kind="ghost" size="sm" disabled={busy || result.page <= 1} onClick={() => void run(result.page - 1)}>Previous</Btn>
                      <Btn kind="ghost" size="sm" disabled={busy || result.page * result.size >= result.total} onClick={() => void run(result.page + 1)}>Next</Btn>
                    </span>
                  </div>
                </PBody>
              ) : null}
            </Panel>
          ) : null}

          <Panel title="Save this query">
            <PBody>
              <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
                <Field id="qb-name" label="Name"><input id="qb-name" className="ctl" value={saveName} onChange={(e) => setSaveName(e.target.value)} maxLength={150} style={{ minWidth: 280 }}
                  placeholder="e.g. 2026/2027 First Semester — Faculty of Science examination readiness" /></Field>
                <Field id="qb-note" label="Description"><input id="qb-note" className="ctl" value={saveNote} onChange={(e) => setSaveNote(e.target.value)} maxLength={1000} style={{ minWidth: 260 }} /></Field>
                <Field id="qb-share" label="Share with">
                  <select id="qb-share" className="ctl" multiple value={shareWith} onChange={(e) => setShareWith(Array.from(e.target.selectedOptions).map((o) => o.value))} style={{ minWidth: 220, height: 80 }}>
                    {offices.filter((o) => ["ict", "academic", "registrar", "dregistrar", "records", "dbops", "admin", "super"].includes(o.code)).map((o) => <option key={o.code} value={o.code}>{o.label}</option>)}
                  </select>
                </Field>
                <Btn kind="secondary" disabled={busy || saveName.trim().length < 3} onClick={() => void save()}>Save</Btn>
              </div>
              <div className="sub2" style={{ marginTop: "var(--s-1)" }}>A saved query keeps the source, the conditions, the columns, the order and the grouping — never SQL. An office it is shared with runs it within its own scope.</div>
            </PBody>
          </Panel>
        </>
      ) : null}

      {view === "saved" ? (
        <Panel title="Saved and shared queries" right={`${saved.length}`}>
          {saved.length ? (
            <DTable pageSize={25} noPrint cols={["Query", "Source", "Shared with", "By", "|num"]}
              rows={saved.map((s) => [
                <Two key="n" a={s.name} b={s.description ?? ""} />, <span key="s">{sources.find((x) => x.key === s.source)?.label ?? s.source}</span>,
                <span key="w" className="sub2">{s.shared_offices.length ? s.shared_offices.map((o) => offices.find((x) => x.code === o)?.label ?? o).join(", ") : "—"}</span>,
                <span key="b" className="sub2">{s.mine ? "You" : s.owner ?? ""}</span>,
                <span key="a" className="row row--tight">
                  <Btn kind="ghost" size="sm" onClick={() => load(s)}>Open</Btn>
                  {s.mine ? <Btn kind="ghost" size="sm" onClick={() => { setSharing(s); setShareWith(s.shared_offices); }}>Share</Btn> : null}
                  {s.mine ? <Btn kind="ghost" size="sm" onClick={() => void archive(s)}>Archive</Btn> : null}
                </span>,
              ])} texts={saved.map((s) => `${s.name} ${s.description ?? ""} ${s.source}`)} />
          ) : <PBody><div className="sub2">No query saved or shared with your office yet.</div></PBody>}
          {sharing ? (
            <PBody>
              <Note kind="info" title={`Share ${sharing.name}`}>
                <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
                  <select className="ctl" multiple aria-label="Offices" value={shareWith} onChange={(e) => setShareWith(Array.from(e.target.selectedOptions).map((o) => o.value))} style={{ minWidth: 260, height: 100 }}>
                    {offices.map((o) => <option key={o.code} value={o.code}>{o.label}</option>)}
                  </select>
                  <Btn kind="secondary" onClick={() => void share()}>Share</Btn>
                  <Btn kind="ghost" onClick={() => setSharing(null)}>Cancel</Btn>
                </div>
              </Note>
            </PBody>
          ) : null}
        </Panel>
      ) : null}

      {view === "history" ? (
        <Panel title="Query log" right={auditor ? (
          <span className="row row--tight">
            <Btn kind={hist?.everyone ? "ghost" : "secondary"} size="sm" onClick={() => void loadHistory(false)}>Mine</Btn>
            <Btn kind={hist?.everyone ? "secondary" : "ghost"} size="sm" onClick={() => void loadHistory(true)}>Everyone&rsquo;s</Btn>
          </span>
        ) : "Your queries and reports"}>
          {hist && hist.rows.length ? (
            <DTable pageSize={0} noPrint cols={["When", "Who", "Action", "Source", "Report", "Scope", "Rows|num", "Reference"]}
              rows={hist.rows.map((h, i) => [
                <span key="w" className="tnum">{new Date(h.at).toLocaleString("en-GB")}</span>, <Two key="a" a={h.actor ?? "—"} b={h.actor_office} />,
                <Pil key="c" kind={h.action === "ISSUE" ? "ok" : h.action === "RUN" ? "grey" : "info"}>{h.action}</Pil>, <span key="s">{h.source}</span>,
                <span key="t" className="sub2">{h.title ?? ""}{h.format ? ` · ${h.format}` : ""}</span>, <span key="p" className="sub2">{h.scope ?? ""}</span>,
                <span key="n" className="tnum">{h.row_count ?? ""}</span>, <span key="r" className="tnum">{h.reference ?? (i < 0 ? "" : "")}</span>,
              ])} />
          ) : <PBody><div className="sub2">Nothing on the log yet.</div></PBody>}
          {hist ? (
            <PBody>
              <div className="row" style={{ gap: "var(--s-2)", alignItems: "center" }}>
                <span className="sub2">Page {hist.page} of {Math.max(1, Math.ceil(hist.total / hist.size))} · newest first</span>
                <span className="ml-auto row row--tight">
                  <Btn kind="ghost" size="sm" disabled={hist.page <= 1} onClick={() => void loadHistory(hist.everyone, hist.page - 1)}>Previous</Btn>
                  <Btn kind="ghost" size="sm" disabled={hist.page * hist.size >= hist.total} onClick={() => void loadHistory(hist.everyone, hist.page + 1)}>Next</Btn>
                </span>
              </div>
            </PBody>
          ) : null}
        </Panel>
      ) : null}

      {view === "reports" ? (
        <Panel title="Official reports" right={
          <span className="row row--tight">
            <input className="ctl" aria-label="Reference or title" value={regQ} onChange={(e) => setRegQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void loadReports(1); }} placeholder="DBO/EXAM/2026/000001" />
            <Btn kind="ghost" size="sm" onClick={() => void loadReports(1)}>Search</Btn>
          </span>
        }>
          {regs && regs.rows.length ? (
            <DTable pageSize={0} noPrint cols={["Reference", "Report", "Scope", "Rows|num", "Issued by", "Issued"]}
              rows={regs.rows.map((r) => [
                <b key="r" className="tnum">{r.reference}</b>, <span key="t">{r.title}</span>, <span key="s" className="sub2">{r.scope ?? ""}</span>,
                <span key="n" className="tnum">{r.row_count ?? ""}</span>, <Two key="b" a={r.generated_by ?? "—"} b={r.actor_office} />,
                <span key="d" className="tnum">{new Date(r.generated_at).toLocaleString("en-GB")}</span>,
              ])} />
          ) : <PBody><div className="sub2">No official report issued yet.</div></PBody>}
          {regs ? (
            <PBody>
              <div className="row" style={{ gap: "var(--s-2)", alignItems: "center" }}>
                <span className="sub2">Page {regs.page} of {Math.max(1, Math.ceil(regs.total / regs.size))} · newest first</span>
                <span className="ml-auto row row--tight">
                  <Btn kind="ghost" size="sm" disabled={regs.page <= 1} onClick={() => void loadReports(regs.page - 1)}>Previous</Btn>
                  <Btn kind="ghost" size="sm" disabled={regs.page * regs.size >= regs.total} onClick={() => void loadReports(regs.page + 1)}>Next</Btn>
                </span>
              </div>
            </PBody>
          ) : null}
        </Panel>
      ) : null}
    </>
  );
}
