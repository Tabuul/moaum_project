"use client";

/** V558: the student lifecycle reconciliation — the cohort engine's position of every active student read as a recommendation
 *  (graduation candidate, spillover year 1 and 2, the maximum spillover reached, records to review or correct), every figure a
 *  way into its students; the Registry reviews and verifies, previews a batch and reconciles it step by step, and a reconciliation
 *  is corrected on a reason. The server holds the scope, the rules and the history; the screen only asks. */
import { useCallback, useEffect, useMemo, useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { StudentOpen } from "@/components/StudentModal";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import {
  BASIS, COMPLETION, EXCLUDED, FOLLOW, LCONF, LEAD, LIMIT_CHOICES, OUTCOME, REC, STATE, aboutToReconcile, actionable, batchPath, chunks, crossTab, fmt,
  reasonOk, recKind, recWord, spillColumns,
  type LifeList, type LifeRow, type LifeStudent, type LifeSummary, type Preview, type Reconciliation, type Skipped,
} from "@/lib/lifecycle";
import { LifecycleHistory } from "./LifecycleHistory";

export interface LifeParams { view: string; rec: string; state: string; conf: string; basis: string; completion: string; batch: string; outcome: string; corrected: string; page: string }
interface Scope { fac: string; dept: string; prog: string; cohort: string; q: string }
type Structure = { code: string; name: string; departments: { code: string; name: string }[] }[];
type Problem = Parameters<typeof notifyProblem>[0];

const API = "/api/bff/api/v1/cohorts/lifecycle";
const RECONCILABLE = "GRADUATION_CANDIDATE,SPILLOVER,MAXIMUM_SPILLOVER_REACHED";
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const name = (r: { surname?: string; other_names?: string }) => `${r.surname ?? ""}, ${r.other_names ?? ""}`.replace(/^, |, $/g, "");

async function send(method: "POST", path: string, body: unknown, reason: string): Promise<{ ok: boolean; data: Record<string, unknown> | null }> {
  const r = await fetch(`${API}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
  const data = (await r.json().catch(() => null)) as Record<string, unknown> | null;
  if (!r.ok) notifyProblem((data ?? { status: r.status, title: r.statusText }) as unknown as Problem);
  return { ok: r.ok, data };
}

export function Lifecycle({ params, scope, structure, canAct, generatedBy }: { params: LifeParams; scope: Scope; structure: Structure; canAct: boolean; generatedBy: string | null }) {
  const go = useQueryNav();
  const view = ["figures", "students", "batches"].includes(params.view) ? params.view : "figures";
  const page = Math.max(1, Number(params.page || 1));
  const [summary, setSummary] = useState<LifeSummary | null>(null);
  const [list, setList] = useState<LifeList | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const [size, setSize] = useState(50);
  const [chosen, setChosen] = useState<Set<string>>(new Set());
  const [every, setEvery] = useState(false);
  const [mark, setMark] = useState<{ state: string; note: string } | null>(null);
  const [recon, setRecon] = useState<{ ids: string[] | null } | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [checking, setChecking] = useState<string | null>(null);
  const [drill, setDrill] = useState<{ fac?: string; facName?: string; dept?: string; deptName?: string }>({});

  /** the scope and the figure's filters, as the API reads them */
  const { rec, state, conf, basis, completion } = params;
  const { fac, dept, prog, cohort, q } = scope;
  const filter = useMemo(() => ({ rec: rec || null, state: state || null, conf: conf || null, basis: basis || null, completion: completion || null,
    cohort: cohort || null, fac: fac || null, dept: dept || null, prog: prog || null, q: q || null }), [rec, state, conf, basis, completion, cohort, fac, dept, prog, q]);
  const qs = useCallback((extra: Record<string, string | number | null | undefined>) => {
    const out = new URLSearchParams();
    for (const [k, v] of Object.entries({ ...filter, ...extra })) if (v !== null && v !== undefined && v !== "") out.set(k, String(v));
    return out.toString();
  }, [filter]);

  /** a way into the students behind a figure: the page's own address, so a figure is a link like any other */
  const href = useCallback((patch: Record<string, string>) => {
    const next: Record<string, string> = { tab: "lifecycle", fac: scope.fac, dept: scope.dept, prog: scope.prog, cohort: scope.cohort, q: scope.q,
      view: params.view, rec: params.rec, lstate: params.state, lconf: params.conf, basis: params.basis, completion: params.completion, ...patch };
    const out = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "view" && v === "figures")) out.set(k, v);
    return `/cohorts?${out.toString()}`;
  }, [scope, params]);
  const into = (patch: Record<string, string>) => href({ view: "students", rec: "", lstate: "", lconf: "", basis: "", completion: "", ...patch });

  // the figures, read after the page paints and after every act
  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const r = await fetch(`${API}/summary?${qs({ rec: null, state: null, conf: null, basis: null, completion: null })}`, { cache: "no-store" });
        const j = await r.json().catch(() => null);
        if (!live) return;
        if (!r.ok) { setFailed((j as { title?: string } | null)?.title ?? "The figures could not be read."); return; }
        setFailed(null);
        setSummary(j as LifeSummary);
      } catch { if (live) setFailed("The connection to the portal dropped."); }
    })();
    return () => { live = false; };
  }, [qs, tick]);

  // the students behind a figure
  useEffect(() => {
    if (view !== "students") return;
    let live = true;
    (async () => {
      try {
        const r = await fetch(`${API}/students?${qs({ page, size })}`, { cache: "no-store" });
        const j = await r.json().catch(() => null);
        if (!live) return;
        if (!r.ok) { setFailed((j as { title?: string } | null)?.title ?? "The list could not be read."); return; }
        setList(j as LifeList);
      } catch { if (live) setFailed("The connection to the portal dropped."); }
    })();
    return () => { live = false; };
  }, [view, qs, page, size, tick]);

  const byRec = (k: string) => summary?.byRecommendation.find((r) => r.recommendation === k);
  const count = (k: string) => Number(byRec(k)?.n ?? 0);
  const spills = spillColumns((summary?.byRecommendation ?? []).map((r) => r.recommendation));
  const lead = [LEAD[0], ...spills, ...LEAD.slice(3)];
  const reconcilable = (summary?.byRecommendation ?? []).filter((r) => actionable(r.recommendation));
  const sumOf = (k: "pending" | "verified" | "reconciled" | "requires_correction" | "under_review" | "rejected") => reconcilable.reduce((a, r) => a + Number(r[k] ?? 0), 0);
  const chosenCount = every ? Number(list?.total ?? 0) : chosen.size;
  const selection = () => (every ? { filter } : { studentIds: [...chosen] });
  const reload = () => { setChosen(new Set()); setEvery(false); setTick((t) => t + 1); };

  async function checkCompletion() {
    let after: string | null = null; let done = 0; let pool = 0;
    setChecking("Checking…");
    try {
      for (let round = 0; round < 200; round++) {
        const { ok, data } = await send("POST", "/refresh", { after, fac: scope.fac || null, dept: scope.dept || null, prog: scope.prog || null }, "Lifecycle completion checked");
        if (!ok || !data) break;
        if (data.pool != null) pool = Number(data.pool);
        done += Number(data.checked ?? 0);
        setChecking(`Checked ${fmt(done)}${pool ? ` of ${fmt(pool)}` : ""}…`);
        if (data.done) break;
        after = String(data.next);
      }
      notify(`Completion checked for ${fmt(done)} student${done === 1 ? "" : "s"}`);
      reload();
    } finally { setChecking(null); }
  }

  async function exportList(kind: "xlsx" | "pdf") {
    if (!list?.total) return;
    const rows: LifeRow[] = [];
    for (let p = 1; (p - 1) * 2000 < list.total && p <= 25; p++) {
      const r = await fetch(`${API}/students?${qs({ page: p, size: 2000 })}`, { cache: "no-store" });
      if (!r.ok) { notifyProblem({ status: r.status, title: "The list could not be read." } as Problem); return; }
      const j = (await r.json()) as LifeList;
      rows.push(...j.rows);
      if (j.rows.length < 2000) break;
    }
    const head = ["Student", "Matric No.", "Programme", "Department", "Faculty", "Entry session", "Effective cohort", "Length", "Level", "Expected completion",
      "Sessions beyond", "Recommendation", "Basis", "Confidence", "Completion", "Review", "Explanation"];
    const body = rows.map((r) => [name(r), r.matric_no ?? "", r.programme, r.department, r.faculty, r.entry_session ?? "", r.effective_cohort ?? "",
      r.duration_years ? `${r.duration_years} sessions` : "", r.current_level ?? "", r.expected_completion ?? "", r.spillover_years, recWord(r.recommendation),
      r.candidate_basis ? BASIS[r.candidate_basis] ?? r.candidate_basis : "", LCONF[r.confidence]?.[0] ?? r.confidence, r.completion ? COMPLETION[r.completion]?.[0] ?? r.completion : "",
      STATE[r.review_state]?.[0] ?? r.review_state, r.explanation]);
    const title = `${params.rec ? params.rec.split(",").map(recWord).join(", ") : "Every recommendation"} — Lifecycle reconciliation`;
    const meta: [string, string][] = [["Session", summary?.currentSession ?? "—"], ["Filters", Object.entries(filter).filter(([, v]) => v).map(([k, v]) => `${k} ${v}`).join(", ") || "None"]];
    if (kind === "xlsx") downloadBlob(await brandedXlsx(title, head, body, { sheetName: "Lifecycle", serial: docSerial("LCR"), meta }), "lifecycle-reconciliation.xlsx");
    else brandedPrint(title, `From the cohort engine for ${summary?.currentSession ?? "the current session"}`, head.slice(0, 16), body.map((r) => r.slice(0, 16)), docSerial("LCR"), { meta, generatedBy, orientation: "landscape" });
  }

  const tile = (k: string): [string, string, string | null, string, string] => {
    const r = byRec(k);
    const sub = k === "GRADUATION_CANDIDATE" ? `${fmt(r?.final_year)} final year · ${fmt(r?.completed_beyond)} completed beyond the length`
      : k === "MAXIMUM_SPILLOVER_REACHED" ? `Beyond the ${summary?.maxSpilloverYears ?? 2}-session limit · the Registry decides`
      : actionable(k) ? `${fmt(r?.verified)} verified · ${fmt(r?.reconciled)} reconciled` : REC[k]?.[2] ?? "";
    const colour = !count(k) ? null : recKind(k) === "bad" ? "var(--red-ink)" : recKind(k) === "warn" ? "var(--amber-ink)" : null;
    return [recWord(k), fmt(count(k)), colour, sub, into({ rec: k })];
  };

  const cohortRows = summary ? crossTab(summary.byCohort, (r) => r.cohort ?? "Not stated").sort((a, b) => b.key.localeCompare(a.key)) : [];
  const drillRows = !summary ? [] : drill.dept
    ? crossTab(summary.byProgramme.filter((p) => p.department === drill.dept), (r) => r.code).map((x) => ({ ...x, label: x.first.name, link: { fac: drill.fac ?? "", dept: drill.dept ?? "", prog: x.key } }))
    : drill.fac
      ? crossTab(summary.byDepartment.filter((d) => d.faculty === drill.fac), (r) => r.code).map((x) => ({ ...x, label: x.first.name, link: { fac: drill.fac ?? "", dept: x.key, prog: "" } }))
      : crossTab(summary.byFaculty, (r) => r.code).map((x) => ({ ...x, label: x.first.name, link: { fac: x.key, dept: "", prog: "" } }));
  const crossCols = [LEAD[0], ...spills, "MAXIMUM_SPILLOVER_REACHED", "REQUIRES_REVIEW", "DATA_INCOMPLETE"];
  const departments = (structure.find((f) => f.code === scope.fac)?.departments ?? structure.flatMap((f) => f.departments)).map((d) => ({ value: d.code, label: d.name }));

  return (
    <>
      <div className="row row--base">
        {[["figures", "Figures"], ["students", "Students"], ["batches", "Batches and history"]].map(([k, l]) => (
          <LinkBtn key={k} kind={view === k ? "primary" : "ghost"} href={href({ view: k })}>{l}</LinkBtn>
        ))}
        <span className="grow" />
        <span className="sub2">{summary ? `${summary.currentSession ?? "No current session"} · positions computed ${when(summary.computedTo)}` : ""}</span>
      </div>
      {failed ? <Note kind="bad" title="The reconciliation could not be read">{failed}</Note> : null}

      {view === "figures" && summary ? (
        <>
          <Tiles items={lead.map(tile)} cls={lead.length > 4 ? "grid--5" : "grid--4"} />
          <Tiles items={FOLLOW.map(tile)} />
          <Tiles items={[
            ["Pending review", fmt(sumOf("pending")), sumOf("pending") ? "var(--amber-ink)" : null, "Graduation candidates, spillover and the maximum not yet reviewed", into({ rec: RECONCILABLE, lstate: "PENDING" })],
            ["Verified", fmt(sumOf("verified")), null, "Ready to reconcile in a batch", into({ rec: RECONCILABLE, lstate: "VERIFIED" })],
            ["Reconciled", fmt(sumOf("reconciled")), "var(--green-ink)", `In ${summary.currentSession ?? "the current session"} · ${fmt(summary.batches)} batches in all`, into({ rec: RECONCILABLE, lstate: "RECONCILED" })],
            ["Requires correction", fmt(sumOf("requires_correction")), sumOf("requires_correction") ? "var(--red-ink)" : null, `${fmt(sumOf("rejected"))} rejected · ${fmt(sumOf("under_review"))} under review`, into({ rec: RECONCILABLE, lstate: "REQUIRES_CORRECTION" })],
          ]} />
          <Panel title="By effective cohort" right="Every count opens its students">
            <DTable pageSize={0} cols={["Cohort", ...crossCols.map((k) => `${recWord(k)}|mid`), "Students|mid"]} rows={cohortRows.map((c, i) => [
              <span key={"k" + i}>{c.key === "Not stated" ? <span className="sub2">Not stated</span> : <b>{c.key}</b>}</span>,
              ...crossCols.map((k) => <span key={k + i} className="tnum">{c.by[k] ? <a className="lnk" href={into({ rec: k, cohort: c.key === "Not stated" ? "" : c.key })}>{fmt(c.by[k])}</a> : <span className="sub2">0</span>}</span>),
              <span key={"n" + i} className="tnum">{c.key === "Not stated" ? fmt(c.n) : <a className="lnk" href={into({ cohort: c.key })}>{fmt(c.n)}</a>}</span>,
            ])} />
          </Panel>
          <Panel title={drill.dept ? `Programmes of ${drill.deptName}` : drill.fac ? `Departments of ${drill.facName}` : "By faculty"}
            right={<span className="row row--inline row--tight">
              {drill.fac ? <Btn kind="ghost" size="sm" onClick={() => setDrill(drill.dept ? { fac: drill.fac, facName: drill.facName } : {})}>Back to {drill.dept ? drill.facName : "faculties"}</Btn> : null}
              <span className="sub2">Choose a name to go down a level</span>
            </span>}>
            <DTable pageSize={0} cols={[drill.dept ? "Programme" : drill.fac ? "Department" : "Faculty", ...crossCols.map((k) => `${recWord(k)}|mid`), "Students|mid"]} rows={drillRows.map((x, i) => [
              <span key={"k" + i}>{drill.dept ? <a className="lnk" href={into(x.link)}>{x.label}</a>
                : <button type="button" className="lnk" onClick={() => setDrill(drill.fac ? { ...drill, dept: x.key, deptName: x.label } : { fac: x.key, facName: x.label })}>{x.label}</button>}</span>,
              ...crossCols.map((k) => <span key={k + i} className="tnum">{x.by[k] ? <a className="lnk" href={into({ ...x.link, rec: k })}>{fmt(x.by[k])}</a> : <span className="sub2">0</span>}</span>),
              <span key={"n" + i} className="tnum"><a className="lnk" href={into(x.link)}>{fmt(x.n)}</a></span>,
            ])} />
          </Panel>
          <Panel title="Completion" right={summary.checkedTo ? `Last checked ${when(summary.checkedTo)}` : "Not yet checked"}>
            <PBody>
              <div className="row row--base">
                <span className="sub2">
                  {fmt(summary.checked)} of the {fmt(summary.pool)} students at or beyond their programme&rsquo;s length checked against their published results and the courses they still owe.
                  A student beyond the length becomes a graduation candidate only when every registered course is passed and published; a missing result is never read as a failure.
                </span>
                <span className="grow" />
                {canAct ? <Btn kind="primary" busy={checking !== null} busyLabel={checking ?? "Checking…"} disabled={checking !== null} onClick={() => checkCompletion()}>Refresh analysis</Btn> : null}
              </div>
            </PBody>
            <DTable pageSize={0} noPrint cols={["Completion", "Students|mid"]} rows={summary.byCompletion.map((c, i) => [
              <Pil key={"c" + i} kind={COMPLETION[c.completion]?.[1] ?? "grey"}>{COMPLETION[c.completion]?.[0] ?? c.completion}</Pil>,
              <a key={"n" + i} className="lnk tnum" href={into({ completion: c.completion })}>{fmt(c.n)}</a>,
            ])} />
          </Panel>
          <Note kind="info" title="How a recommendation is made">
            From the cohort engine: the entry session (or the session it was merged into, or the cohort the Registry set), the programme&rsquo;s length, approved deferments and the
            current session — never the matriculation number alone, and a planned session counts for nobody. Nothing changes until the Registry verifies a recommendation and
            reconciles it in a batch: a spillover stays active, a graduation candidate goes on the graduation list for the Senate, and at the maximum the officer decides.
          </Note>
        </>
      ) : null}

      {view === "students" ? (
        <Panel title={params.rec ? params.rec.split(",").map((k) => (k === "SPILLOVER" ? "Spillover" : recWord(k))).join(", ") : "Every active student"}
          right={<span className="row row--inline row--tight">
            <span className="sub2">{list ? `${fmt(list.total)} student${list.total === 1 ? "" : "s"} · names A–Z` : ""}</span>
            {list?.total ? <>
              <Btn kind="ghost" size="sm" onClick={() => exportList("xlsx")}>Excel</Btn>
              <Btn kind="ghost" size="sm" onClick={() => exportList("pdf")}>PDF</Btn>
            </> : null}
          </span>}>
          <PBody>
            <form className="row" onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); go(href({ q: String(f.get("q") ?? ""), page: "" })); }}>
              <Field id="lc-q" label="Search" style={{ flex: "2 1 220px" }}><input id="lc-q" name="q" className="ctl" type="search" defaultValue={scope.q} placeholder="Name or matriculation number" /></Field>
              <Field id="lc-rec" label="Recommendation" style={{ flex: "1 1 190px" }}>
                <select id="lc-rec" className="ctl" value={params.rec} onChange={(e) => go(href({ rec: e.target.value, page: "" }))}>
                  <option value="">Any</option><option value={RECONCILABLE}>Every one reconciled</option><option value="SPILLOVER">Spillover, any year</option>
                  {Object.keys(REC).map((k) => <option key={k} value={k}>{recWord(k)}</option>)}
                </select>
              </Field>
              <Field id="lc-state" label="Review" style={{ flex: "1 1 150px" }}>
                <select id="lc-state" className="ctl" value={params.state} onChange={(e) => go(href({ lstate: e.target.value, page: "" }))}>
                  <option value="">Any</option>{Object.entries(STATE).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}
                </select>
              </Field>
              <Field id="lc-conf" label="Confidence" style={{ flex: "1 1 120px" }}>
                <select id="lc-conf" className="ctl" value={params.conf} onChange={(e) => go(href({ lconf: e.target.value, page: "" }))}>
                  <option value="">Any</option>{Object.entries(LCONF).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}
                </select>
              </Field>
              <Field id="lc-comp" label="Completion" style={{ flex: "1 1 160px" }}>
                <select id="lc-comp" className="ctl" value={params.completion} onChange={(e) => go(href({ completion: e.target.value, page: "" }))}>
                  <option value="">Any</option>{Object.entries(COMPLETION).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}
                </select>
              </Field>
              <Field id="lc-fac" label="Faculty" style={{ flex: "1 1 170px" }}><SearchSelect id="lc-fac" value={scope.fac} onChange={(v) => go(href({ fac: v, dept: "", prog: "", page: "" }))} allLabel="Any faculty" options={structure.map((f) => ({ value: f.code, label: f.name }))} /></Field>
              <Field id="lc-dept" label="Department" style={{ flex: "1 1 170px" }}><SearchSelect id="lc-dept" value={scope.dept} onChange={(v) => go(href({ dept: v, prog: "", page: "" }))} allLabel="Any department" options={departments} /></Field>
              <Field id="lc-cohort" label="Cohort" style={{ flex: "1 1 130px" }}>
                <select id="lc-cohort" className="ctl" value={scope.cohort} onChange={(e) => go(href({ cohort: e.target.value, page: "" }))}>
                  <option value="">Any</option>{cohortRows.filter((c) => c.key !== "Not stated").map((c) => <option key={c.key} value={c.key}>{c.key}</option>)}
                </select>
              </Field>
              <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
                <Btn kind="primary" type="submit">Search</Btn>
                <LinkBtn href={href({ view: "students", rec: "", lstate: "", lconf: "", basis: "", completion: "", fac: "", dept: "", prog: "", cohort: "", q: "" })}>Clear</LinkBtn>
              </div>
            </form>
            {params.basis || scope.prog ? <div className="row row--tight mt-2">
              {params.basis ? <Pil kind="info">{BASIS[params.basis] ?? params.basis}</Pil> : null}
              {scope.prog ? <Pil kind="info">Programme {scope.prog}</Pil> : null}
              <a className="lnk sub2" href={href({ basis: "", prog: "" })}>remove</a>
            </div> : null}
          </PBody>
          {canAct && list?.total ? (
            <PBody>
              <div className="row row--base">
                <span className="sub2">{chosenCount ? `${fmt(chosenCount)} chosen${every ? " — every student this view lists" : ""}` : "Tick students, or choose every student this view lists"}</span>
                {list.total > list.rows.length || !every ? <Btn kind="ghost" size="sm" onClick={() => { setEvery(!every); setChosen(new Set()); }}>{every ? "Choose by ticking" : `Choose all ${fmt(list.total)}`}</Btn> : null}
                <span className="grow" />
                <Btn kind="ghost" size="sm" disabled={!chosenCount} onClick={() => setMark({ state: "UNDER_REVIEW", note: "" })}>Under review</Btn>
                <Btn kind="secondary" size="sm" disabled={!chosenCount} onClick={() => setMark({ state: "VERIFIED", note: "" })}>Verify</Btn>
                <Btn kind="ghost" size="sm" disabled={!chosenCount} onClick={() => setMark({ state: "REQUIRES_CORRECTION", note: "" })}>Requires correction</Btn>
                <Btn kind="ghost" size="sm" disabled={!chosenCount} onClick={() => setMark({ state: "REJECTED", note: "" })}>Reject</Btn>
                <Btn kind="ghost" size="sm" disabled={!chosenCount} onClick={() => setMark({ state: "PENDING", note: "" })}>Back to pending</Btn>
                <Btn kind="primary" size="sm" disabled={!chosenCount} onClick={() => setRecon({ ids: every ? null : [...chosen] })}>Reconcile…</Btn>
              </div>
            </PBody>
          ) : null}
          {list && list.rows.length ? (
            <DTable pageSize={0} cols={[...(canAct ? ["|mid"] : []), "S/N|num", "Student", "Programme", "Cohort", "Level|mid", "Expected|mid", "Recommendation", "Confidence|mid", "Completion|mid", "Review|mid", "|num"]}
              rows={list.rows.map((r, i) => [
                ...(canAct ? [<input key="c" type="checkbox" aria-label={`Choose ${name(r)}`} disabled={every} checked={every || chosen.has(r.id)}
                  onChange={(e) => setChosen((prev) => { const n = new Set(prev); if (e.target.checked) n.add(r.id); else n.delete(r.id); return n; })} />] : []),
                <span key="sn" className="tnum sub2">{(list.page - 1) * list.size + i + 1}</span>,
                <span key="n"><strong>{name(r)}</strong><div className="sub2 tnum">{r.matric_no ?? r.admission_no ?? "—"}</div></span>,
                <span key="p">{r.programme}<div className="sub2">{r.department} · {r.faculty}</div></span>,
                <span key="co" className="tnum">{r.entry_session ?? "—"}{r.effective_cohort && r.effective_cohort !== r.entry_session ? <> → <b>{r.effective_cohort}</b></> : null}
                  <div className="sub2">{r.duration_years ? `${r.duration_years} sessions` : "length not set"}</div></span>,
                <span key="l" className="tnum">{r.current_level ?? "—"}{r.final_level ? <div className="sub2">final {r.final_level}</div> : null}</span>,
                <span key="e" className="tnum">{r.expected_completion ?? "—"}{r.spillover_years ? <div className="sub2">{r.spillover_years} beyond</div> : null}</span>,
                <span key="r"><Pil kind={recKind(r.recommendation)}>{recWord(r.recommendation)}</Pil>{r.candidate_basis ? <div className="sub2">{BASIS[r.candidate_basis]}</div> : null}</span>,
                <Pil key="cf" kind={LCONF[r.confidence]?.[1] ?? "grey"} title={r.confidence_reasons ?? undefined}>{LCONF[r.confidence]?.[0] ?? r.confidence}</Pil>,
                <span key="cp" className="sub2">{r.completion ? COMPLETION[r.completion]?.[0] ?? r.completion : "—"}</span>,
                <span key="st"><Pil kind={STATE[r.review_state]?.[1] ?? "grey"}>{STATE[r.review_state]?.[0] ?? r.review_state}</Pil>{r.batch_ref ? <div className="sub2 tnum">{r.batch_ref}</div> : null}</span>,
                <span key="a" className="row row--inline row--tight row--right"><Btn kind="ghost" size="sm" onClick={() => setOpen(r.id)}>Explain</Btn><StudentOpen id={r.id} label="Record" kind="ghost" /></span>,
              ])} />
          ) : list ? <PBody><div className="sub2">No student within these filters.</div></PBody> : <PBody><div className="sub2">Reading…</div></PBody>}
          {list && list.total > list.size ? (
            <PBody><div className="row row--base">
              <span className="sub2">Showing {fmt((list.page - 1) * list.size + 1)}–{fmt(Math.min(list.page * list.size, list.total))} of {fmt(list.total)}</span>
              <span className="grow" />
              {page > 1 ? <LinkBtn href={href({ page: String(page - 1) })} kind="ghost">Previous</LinkBtn> : null}
              {list.page * list.size < list.total ? <LinkBtn href={href({ page: String(page + 1) })} kind="ghost">Next</LinkBtn> : null}
              <select className="ctl" value={String(size)} onChange={(e) => setSize(Number(e.target.value))} aria-label="Rows a page">{[25, 50, 100, 500].map((s) => <option key={s} value={s}>{s} a page</option>)}</select>
            </div></PBody>
          ) : null}
        </Panel>
      ) : null}

      {view === "batches" ? <LifecycleHistory params={params} scope={scope} canAct={canAct} generatedBy={generatedBy} href={href} onChanged={reload} /> : null}

      {mark ? <MarkModal mark={mark} count={chosenCount} onChange={setMark} onClose={() => setMark(null)}
        onDone={() => { setMark(null); reload(); }} selection={selection} /> : null}
      {recon ? <ReconcileModal ids={recon.ids} filter={filter} session={summary?.currentSession ?? null} onClose={() => setRecon(null)} onDone={reload} /> : null}
      {open ? <ExplainModal id={open} canAct={canAct} onClose={() => setOpen(null)} onReconcile={(id) => { setOpen(null); setRecon({ ids: [id] }); }} onChanged={reload} /> : null}
    </>
  );
}

const MARK_WORD: Record<string, [string, string]> = {
  UNDER_REVIEW: ["Mark under review", "marked under review"], VERIFIED: ["Verify", "verified"], REQUIRES_CORRECTION: ["Requires correction", "marked as requiring correction"],
  REJECTED: ["Reject", "rejected"], PENDING: ["Back to pending", "set back to pending"],
};

function MarkModal({ mark, count, onChange, onClose, onDone, selection }: {
  mark: { state: string; note: string }; count: number; onChange: (m: { state: string; note: string }) => void; onClose: () => void; onDone: () => void;
  selection: () => Record<string, unknown>;
}) {
  const needsNote = mark.state === "REJECTED" || mark.state === "REQUIRES_CORRECTION";
  async function run() {
    const single = count === 1;
    const { ok, data } = await send("POST", "/mark", { ...selection(), state: mark.state, note: mark.note.trim() || null, single },
      `Lifecycle recommendations ${MARK_WORD[mark.state][1]}${mark.note.trim() ? `: ${mark.note.trim()}` : ""}`);
    if (!ok || !data) return;
    const low = Number(data.low ?? 0); const skipped = Number(data.skipped ?? 0);
    notify(`${fmt(Number(data.marked ?? 0))} ${MARK_WORD[mark.state][1]}${low ? ` · ${fmt(low)} low-confidence held back — verify each on its own` : ""}${skipped ? ` · ${fmt(skipped)} left as they were` : ""}`, low || skipped ? "warn" : "ok");
    onDone();
  }
  return (
    <Modal title={`${MARK_WORD[mark.state][0]} — ${fmt(count)} student${count === 1 ? "" : "s"}`} sub="The review is kept for the current session; nothing on the record changes" onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><Btn kind="primary" disabled={needsNote && !mark.note.trim()} busyLabel="Saving…" onClick={() => run()}>{MARK_WORD[mark.state][0]}</Btn></>}>
      {mark.state === "VERIFIED" ? <Note kind="info" title="Only what is reconciled is verified">
        Graduation candidates, spillover and the maximum spillover are verified; a record already reconciled is left as it is. A low-confidence record is verified one at a time,
        from its own Explain window — in a group it is held back.
      </Note> : null}
      <Field id="lc-note" label={needsNote ? "What is wrong" : "Note (optional)"} required={needsNote}>
        <textarea id="lc-note" className="ctl" rows={3} maxLength={2000} value={mark.note} onChange={(e) => onChange({ ...mark, note: e.target.value })}
          placeholder={needsNote ? "e.g. The entry session on the record is wrong: the admission letter says 2019/2020" : ""} />
      </Field>
    </Modal>
  );
}

function ReconcileModal({ ids, filter, session, onClose, onDone }: {
  ids: string[] | null; filter: Record<string, string | null>; session: string | null; onClose: () => void; onDone: () => void;
}) {
  const [limit, setLimit] = useState("");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const [description, setDescription] = useState(`Lifecycle reconciliation — ${session ?? "the current session"}`);
  const [reason, setReason] = useState("");
  const [progress, setProgress] = useState<string | null>(null);
  const [result, setResult] = useState<{ ref: string; reconciled: number; skipped: Skipped[] } | null>(null);
  const choice = LIMIT_CHOICES.find((c) => c.value === limit);

  // what the batch would do, read again whenever the choice at the maximum changes; nothing is written
  useEffect(() => {
    let live = true;
    (async () => {
      const r = await fetch(`${API}/preview`, { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...(ids ? { studentIds: ids } : { filter }), limitOutcome: choice?.outcome ?? null, limitStatus: choice?.status ?? null }) });
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (!r.ok) { setFailed((j as { detail?: string; title?: string } | null)?.detail ?? (j as { title?: string } | null)?.title ?? "The preview could not be read."); return; }
      setFailed(null);
      setPreview(j as Preview);
    })();
    return () => { live = false; };
  }, [ids, filter, choice]);

  const atLimit = Number(preview?.byRecommendation.MAXIMUM_SPILLOVER_REACHED ?? 0) + Number(preview?.excluded.LIMIT_OUTCOME_NOT_CHOSEN ?? 0);

  async function run() {
    if (!preview?.eligible) return;
    const opened = await send("POST", "/batches", { description: description.trim() }, `Lifecycle reconciliation batch opened: ${description.trim()}`);
    const ref = opened.ok ? String(opened.data?.batch_ref ?? "") : "";
    const path = batchPath(ref);
    if (!path) return;
    let reconciled = 0; const skipped: Skipped[] = [];
    const steps = chunks(preview.studentIds, 200);
    for (const [i, step] of steps.entries()) {
      setProgress(`Reconciling ${fmt(Math.min((i + 1) * 200, preview.eligible))} of ${fmt(preview.eligible)}…`);
      const { ok, data } = await send("POST", `/batches/${path}/reconcile`, { studentIds: step, limitOutcome: choice?.outcome ?? null, limitStatus: choice?.status ?? null, reason: reason.trim() },
        `Lifecycle reconciliation ${ref}: ${reason.trim()}`);
      if (!ok || !data) break;
      reconciled += Number(data.reconciled ?? 0);
      skipped.push(...((data.skipped as Skipped[] | undefined) ?? []));
    }
    await send("POST", `/batches/${path}/close`, {}, `Lifecycle reconciliation batch ${ref} closed`);
    setProgress(null);
    setResult({ ref, reconciled, skipped });
    notify(`${ref}: ${fmt(reconciled)} reconciled${skipped.length ? `, ${fmt(skipped.length)} left out` : ""}`, skipped.length ? "warn" : "ok");
    onDone();
  }

  async function skippedSheet() {
    if (!result?.skipped.length) return;
    downloadBlob(await brandedXlsx(`Left out of ${result.ref} — Lifecycle reconciliation`, ["Student", "Matric No.", "Why"],
      [...result.skipped].sort((a, b) => name(a).localeCompare(name(b))).map((s) => [name(s), s.matric_no ?? "", s.message]), { sheetName: "Left out", serial: docSerial("LCR") }),
    `${result.ref.replace(/\//g, "-")}-left-out.xlsx`);
  }

  if (result) {
    return (
      <Modal title={`${result.ref}: ${fmt(result.reconciled)} reconciled`} sub={result.skipped.length ? `${fmt(result.skipped.length)} left out, each with the reason` : "Every student in the batch was reconciled"} onClose={onClose}
        foot={<>{result.skipped.length ? <Btn kind="ghost" onClick={() => skippedSheet()}>Excel of those left out</Btn> : null}<Btn kind="primary" onClick={onClose}>Done</Btn></>}>
        {result.skipped.length ? (
          <DTable pageSize={10} cols={["Student", "Why"]} rows={[...result.skipped].sort((a, b) => name(a).localeCompare(name(b))).map((s, i) => [
            <span key={"n" + i}><strong>{name(s)}</strong><div className="sub2 tnum">{s.matric_no ?? ""}</div></span>, <span key={"w" + i} className="sub2">{s.message}</span>,
          ])} />
        ) : <Note kind="ok" title="Reconciled">Each reconciliation is on the student&rsquo;s history under {result.ref}; it can be corrected from Batches and history.</Note>}
      </Modal>
    );
  }
  return (
    <Modal wide title="Reconcile a batch" sub={preview ? aboutToReconcile(preview.eligible) : "Reading what the batch would do…"} onClose={onClose}
      foot={<>
        <Btn kind="ghost" disabled={progress !== null} onClick={onClose}>Cancel</Btn>
        <Btn kind="primary" busy={progress !== null} busyLabel={progress ?? "Reconciling…"} disabled={!preview?.eligible || !reasonOk(reason) || !description.trim() || progress !== null}
          onClick={() => run()}>Reconcile {fmt(preview?.eligible ?? 0)} record{preview?.eligible === 1 ? "" : "s"}</Btn>
      </>}>
      {failed ? <Note kind="bad" title="The preview could not be read">{failed}</Note> : null}
      {preview ? (
        <>
          <div className="grid grid--2">
            <div>
              <b>What happens</b>
              <ul className="sub2">
                {Object.entries(preview.byRecommendation).map(([k, v]) => (
                  <li key={k}>{fmt(v)} {recWord(k).toLowerCase()} — {k === "GRADUATION_CANDIDATE" ? "put on the graduation list for the Senate; the status stays"
                    : k === "MAXIMUM_SPILLOVER_REACHED" ? (choice?.status ? `made ${choice.status.toLowerCase()}` : "kept active, flagged as at the maximum") : "spillover confirmed; the status stays active"}</li>
                ))}
                {preview.levelsRaised ? <li>{fmt(preview.levelsRaised)} level{preview.levelsRaised === 1 ? "" : "s"} raised to the programme&rsquo;s final level (none lowered)</li> : null}
                {preview.alreadyOnGraduationList ? <li>{fmt(preview.alreadyOnGraduationList)} already on the graduation list: audited again, not added twice</li> : null}
                {Object.entries(preview.statusMoves).filter(([k]) => k.split("→")[0] !== k.split("→")[1]).map(([k, v]) => <li key={k}>{fmt(v)} status{v === 1 ? "" : "es"} changed: {k.replace("→", " → ").toLowerCase().replace(/_/g, " ")}</li>)}
              </ul>
              <div className="sub2">Confidence: {Object.entries(preview.byConfidence).map(([k, v]) => `${fmt(v)} ${LCONF[k]?.[0].toLowerCase() ?? k}`).join(" · ") || "—"}</div>
            </div>
            <div>
              <b>Left out</b>
              {Object.keys(preview.excluded).length ? (
                <ul className="sub2">{Object.entries(preview.excluded).map(([k, v]) => <li key={k}>{fmt(v)} — {EXCLUDED[k] ?? k}</li>)}</ul>
              ) : <div className="sub2">Nobody: every chosen student is verified and reconcilable.</div>}
            </div>
          </div>
          {atLimit ? (
            <Field id="lc-limit" label={`At the maximum spillover (${fmt(atLimit)} chosen) — your decision`}>
              <select id="lc-limit" className="ctl" value={limit} onChange={(e) => setLimit(e.target.value)}>
                <option value="">Choose what the batch does for them…</option>
                {LIMIT_CHOICES.map((c) => <option key={c.value} value={c.value}>{c.label}</option>)}
              </select>
            </Field>
          ) : null}
          <Field id="lc-desc" label="Batch description" required>
            <input id="lc-desc" className="ctl" maxLength={300} value={description} onChange={(e) => setDescription(e.target.value)} />
          </Field>
          <Field id="lc-reason" label="Reason, kept on each student's history" required hint="A few words at least: the evidence the Registry relied on">
            <textarea id="lc-reason" className="ctl" rows={3} maxLength={2000} value={reason} onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. Registry review of the 2025/2026 registrations and published results" />
          </Field>
          <Note kind="info" title="Each student all or nothing">
            The batch is sent 200 students at a time. Each student is checked again at that moment; one whose record changed since it was verified is left out with the reason, and
            nobody is reconciled twice in a session. No matriculation number, result, registration or payment is touched, and nobody becomes graduated here.
          </Note>
        </>
      ) : null}
    </Modal>
  );
}

function ExplainModal({ id, canAct, onClose, onReconcile, onChanged }: { id: string; canAct: boolean; onClose: () => void; onReconcile: (id: string) => void; onChanged: () => void }) {
  const [s, setS] = useState<LifeStudent | null>(null);
  const [failed, setFailed] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const [note, setNote] = useState("");
  const [correct, setCorrect] = useState<{ id: string; reason: string } | null>(null);

  useEffect(() => {
    let live = true;
    (async () => {
      const r = await fetch(`${API}/students/${id}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (!r.ok) { setFailed((j as { title?: string } | null)?.title ?? "The student could not be read."); return; }
      setS(j as LifeStudent);
    })();
    return () => { live = false; };
  }, [id, tick]);

  async function markOne(state: string) {
    const { ok } = await send("POST", "/mark", { studentIds: [id], state, note: note.trim() || null, single: true }, `Lifecycle recommendation ${MARK_WORD[state][1]}${note.trim() ? `: ${note.trim()}` : ""}`);
    if (ok) { notify(`Recommendation ${MARK_WORD[state][1]}`); setNote(""); setTick((t) => t + 1); onChanged(); }
  }
  async function runCorrect() {
    if (!correct) return;
    const { ok } = await send("POST", `/reconciliations/${correct.id}/correct`, { reason: correct.reason.trim() }, `Lifecycle reconciliation corrected: ${correct.reason.trim()}`);
    if (ok) { notify("Reconciliation corrected"); setCorrect(null); setTick((t) => t + 1); onChanged(); }
  }

  return (
    <Modal wide title={s ? name(s) : "Lifecycle"} sub={s ? `${s.matric_no ?? s.admission_no ?? ""} · ${s.programme}` : ""} onClose={onClose}
      foot={<>{s ? <StudentOpen id={s.id} label="Open the record" kind="ghost" /> : null}<Btn kind="primary" onClick={onClose}>Close</Btn></>}>
      {failed ? <Note kind="bad" title="Not available">{failed}</Note> : null}
      {s ? (
        <>
          <div className="row row--tight">
            <Pil kind={recKind(s.recommendation)}>{recWord(s.recommendation)}</Pil>
            {s.candidate_basis ? <Pil kind="info">{BASIS[s.candidate_basis]}</Pil> : null}
            <Pil kind={LCONF[s.confidence]?.[1] ?? "grey"}>{LCONF[s.confidence]?.[0] ?? s.confidence} confidence</Pil>
            <Pil kind={STATE[s.review_state]?.[1] ?? "grey"}>{STATE[s.review_state]?.[0] ?? s.review_state}</Pil>
          </div>
          <p>{s.explanation}.</p>
          {s.confidence_reasons ? <Note kind={s.confidence === "LOW" ? "bad" : "info"} title="What lowers the confidence">{s.confidence_reasons}.</Note> : null}
          <div className="grid grid--2">
            <div className="kv"><span className="k">Cohort</span><span className="v">{s.entry_session ?? "—"}{s.effective_cohort && s.effective_cohort !== s.entry_session ? ` → ${s.effective_cohort} (${s.cohort_source === "MERGED" ? "session merged" : "set by the Registry"})` : ""}</span></div>
            <div className="kv"><span className="k">Length</span><span className="v">{s.duration_years ? `${s.duration_years} sessions` : "Not set"}{s.duration_source === "UNIVERSITY_RULE" ? " (University rule)" : ""}{s.final_level ? ` · final ${s.final_level} Level` : ""}</span></div>
            <div className="kv"><span className="k">Level</span><span className="v">{s.current_level ?? "—"} on record{s.computed_level && s.computed_level !== s.current_level ? ` · ${s.computed_level} by the cohort` : ""}</span></div>
            <div className="kv"><span className="k">Completion</span><span className="v">{s.completion ? COMPLETION[s.completion]?.[0] ?? s.completion : "—"}{s.outstanding_courses ? ` · owed: ${s.outstanding_courses}` : ""}{s.awaiting_courses ? ` · awaited: ${s.awaiting_courses}` : ""}{s.completion_checked_at ? ` · checked ${when(s.completion_checked_at)}` : ""}</span></div>
            {s.reviewed_at ? <div className="kv"><span className="k">Review</span><span className="v">{STATE[s.review_state]?.[0]} by {s.reviewed_by ?? "—"} on {when(s.reviewed_at)}{s.review_note ? ` — ${s.review_note}` : ""}</span></div> : null}
          </div>
          {canAct && s.review_state !== "RECONCILED" ? (
            <div className="row row--base">
              <Field id="lc-one-note" label="Note" style={{ flex: "2 1 260px" }}><input id="lc-one-note" className="ctl" maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Needed to reject or ask for a correction" /></Field>
              <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
                {s.actionable && s.review_state !== "VERIFIED" ? <Btn kind="secondary" size="sm" busyLabel="Verifying…" onClick={() => markOne("VERIFIED")}>Verify</Btn> : null}
                <Btn kind="ghost" size="sm" onClick={() => markOne("UNDER_REVIEW")}>Under review</Btn>
                <Btn kind="ghost" size="sm" disabled={!note.trim()} onClick={() => markOne("REQUIRES_CORRECTION")}>Requires correction</Btn>
                <Btn kind="ghost" size="sm" disabled={!note.trim()} onClick={() => markOne("REJECTED")}>Reject</Btn>
                {s.actionable && s.review_state === "VERIFIED" ? <Btn kind="primary" size="sm" onClick={() => onReconcile(s.id)}>Reconcile…</Btn> : null}
              </div>
            </div>
          ) : null}
          <Panel title="Reconciliations" right="Kept; a correction is recorded beside it">
            {s.reconciliations.length ? (
              <DTable pageSize={0} cols={["Batch", "Session", "Recommendation", "Outcome", "Status|mid", "Level|mid", "By", "|num"]} rows={s.reconciliations.map((x: Reconciliation, i) => [
                <span key={"b" + i} className="tnum">{x.batch_ref}</span>, <span key={"s" + i} className="tnum">{x.effective_session}</span>,
                <span key={"r" + i}>{recWord(x.recommendation)}</span>,
                <span key={"o" + i}>{OUTCOME[x.outcome] ?? x.outcome}{x.graduand_unmet ? <div className="sub2">audit: {x.graduand_unmet}</div> : null}
                  {x.corrected_at ? <div className="sub2 ink-red">Corrected {when(x.corrected_at)}: {x.correction_reason}</div> : null}</span>,
                <span key={"st" + i} className="tnum">{x.previous_status === x.new_status ? x.new_status.toLowerCase() : `${x.previous_status.toLowerCase()} → ${x.new_status.toLowerCase()}`}</span>,
                <span key={"l" + i} className="tnum">{x.previous_level === x.new_level ? x.new_level ?? "—" : `${x.previous_level} → ${x.new_level}`}</span>,
                <span key={"by" + i} className="sub2">{x.reconciled_by ?? "—"}<div>{when(x.reconciled_at)}</div></span>,
                canAct && !x.corrected_at ? <Btn key={"c" + i} kind="ghost" size="sm" onClick={() => setCorrect({ id: x.id, reason: "" })}>Correct…</Btn> : <span key={"c" + i} />,
              ])} />
            ) : <PBody><div className="sub2">Not reconciled yet.</div></PBody>}
          </Panel>
          {correct ? (
            <div className="row row--base">
              <Field id="lc-correct" label="Why the reconciliation is corrected" required style={{ flex: "2 1 300px" }}>
                <input id="lc-correct" className="ctl" maxLength={2000} value={correct.reason} onChange={(e) => setCorrect({ ...correct, reason: e.target.value })} />
              </Field>
              <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
                <Btn kind="ghost" size="sm" onClick={() => setCorrect(null)}>Cancel</Btn>
                <Btn kind="primary" size="sm" disabled={!reasonOk(correct.reason)} busyLabel="Correcting…" onClick={() => runCorrect()}>Correct it</Btn>
              </div>
            </div>
          ) : null}
        </>
      ) : !failed ? <div className="sub2">Reading…</div> : null}
    </Modal>
  );
}

