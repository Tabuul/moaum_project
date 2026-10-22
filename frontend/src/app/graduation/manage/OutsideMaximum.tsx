"use client";

/** V638: students outside the maximum academic period — the cards the cohort engine counts, the list (clickable from the card), one
 *  student's review timeline, MARK AS GRADUATED for the students ticked and RECONCILE ACADEMIC STATUS for the whole scope (both
 *  previewed first: identified, eligible, requiring review), the batches, the official graduation date, the reports, and the nightly
 *  reconciliation's switch. Every count, verdict and act is the server's. */
import { useCallback, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { LIST_HEADERS, REC_CONFIDENCE, REC_REPORT_BY, confirmLines, fullName, listRow, plural, reasonsOf, recBatchPath, recBatchState, recOutcome, timeline,
  type Candidate, type Preview, type RecBatch, type RecFigures, type RecRow, type RecSetting, type StudentReview } from "@/lib/graduation-reconciliation";

const BASE = "/api/bff/api/v1/graduation/reconciliation";
const PAGE = 50;
type Mode = "chosen" | "scope";

export function OutsideMaximum({ scope, figures, setting, batches, actingOffice, focus, initial }: {
  scope: Scope; figures: RecFigures; setting: RecSetting; batches: RecBatch[]; actingOffice: string | null; focus: string | null;
  /** the list's first page, read by the page when a card was clicked */
  initial: { rows: Candidate[]; total: number } | null;
}) {
  const router = useRouter();
  const office = ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");
  const setter = ["ict", "registrar", "dregistrar", "super"].includes(actingOffice ?? "");
  const f = figures;
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [listOpen, setListOpen] = useState(initial !== null);
  const [conf, setConf] = useState(focus && ["HIGH", "MEDIUM", "LOW"].includes(focus) ? focus : "");
  const [q, setQ] = useState("");
  const [page, setPage] = useState(1);
  const [rows, setRows] = useState<Candidate[]>(initial?.rows ?? []);
  const [total, setTotal] = useState(initial?.total ?? 0);
  const [ticked, setTicked] = useState<Set<string>>(new Set());
  const [confirm, setConfirm] = useState<{ mode: Mode; preview: Preview; description: string; showReview: boolean } | null>(null);
  const [progress, setProgress] = useState<{ ref: string; graduated: number; refused: number; skipped: number; remaining: number; done: boolean } | null>(null);
  const [review, setReview] = useState<StudentReview | null>(null);
  const [date, setDate] = useState("");
  const [dateNote, setDateNote] = useState("");
  const [batch, setBatch] = useState<RecBatch | null>(null);
  const [reportBy, setReportBy] = useState("faculty");
  const [report, setReport] = useState<Record<string, unknown>[] | null>(null);
  const [switching, setSwitching] = useState(false);

  const scoped = useCallback((p: URLSearchParams) => {
    if (scope.fac) p.set("fac", scope.fac);
    if (scope.dept) p.set("dept", scope.dept);
    if (scope.prog) p.set("prog", scope.prog);
    return p;
  }, [scope.fac, scope.dept, scope.prog]);
  const here = (gr: string) => {
    const p = scoped(new URLSearchParams({ session: scope.session }));
    p.set("gr", gr);
    return `/graduation/manage?${p.toString()}#outside`;
  };
  const scopeWords = scope.prog ? `programme ${scope.prog}` : scope.dept ? `department ${scope.dept}` : scope.fac ? `faculty ${scope.fac}` : "the University";

  const call = useCallback(async <T,>(path: string, method: "GET" | "POST", body: unknown, reason: string): Promise<T | null> => {
    setProblem(null);
    const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) {
      const p = j ?? { status: r.status, title: r.statusText };
      setProblem(p); notifyProblem(p);
      return null;
    }
    return j as T;
  }, []);

  const load = useCallback(async (pg: number, confidence?: string) => {
    const c = confidence ?? conf;
    const p = scoped(new URLSearchParams({ page: String(pg), size: String(PAGE) }));
    if (c) p.set("confidence", c);
    if (q.trim()) p.set("q", q.trim());
    const r = await call<{ rows: Candidate[]; total: number }>(`${BASE}/candidates?${p.toString()}`, "GET", undefined, "Students outside the maximum academic period read");
    if (!r) return;
    setRows(r.rows); setTotal(r.total); setPage(pg);
  }, [call, conf, q, scoped]);

  async function everyRow(): Promise<Candidate[] | null> {
    const p = scoped(new URLSearchParams({ page: "1", size: "10000" }));
    if (conf) p.set("confidence", conf);
    if (q.trim()) p.set("q", q.trim());
    const r = await call<{ rows: Candidate[] }>(`${BASE}/candidates?${p.toString()}`, "GET", undefined, "Students outside the maximum academic period exported");
    return r ? r.rows : null;
  }

  const listTitle = "Students outside the maximum academic period";
  const listMeta = (): [string, string][] => [["Current session", f.currentSession ?? "—"], ["Spillover sessions allowed", String(f.maxSpilloverYears)],
    ["Confidence", conf ? REC_CONFIDENCE[conf][0] : "All"], ["Scope", scopeWords], ...(q.trim() ? [["Search", q.trim()] as [string, string]] : [])];

  async function exportXlsx() {
    const all = await everyRow();
    if (!all) return;
    const b = await brandedXlsx(listTitle, LIST_HEADERS, all.map(listRow), { serial: docSerial("GRADRECON"), meta: listMeta() });
    downloadBlob(b, `outside-maximum-period-${(f.currentSession ?? "").replace("/", "-")}.xlsx`);
  }

  async function exportPdf() {
    const w = window.open("", "_blank");
    const all = await everyRow();
    if (!all) { w?.close(); return; }
    brandedPrint(listTitle, `Current session ${f.currentSession ?? "—"} · ${scopeWords}`, LIST_HEADERS, all.map(listRow), docSerial("GRADRECON"), { meta: listMeta(), orientation: "landscape", window: w });
  }

  async function preview(mode: Mode, includeMedium: boolean, description?: string) {
    setBusy(true);
    try {
      const body = { studentIds: mode === "chosen" ? [...ticked] : null, includeMedium, fac: scope.fac || null, dept: scope.dept || null, prog: scope.prog || null };
      const p = await call<Preview>(`${BASE}/preview`, "POST", body, "Graduation-status reconciliation previewed");
      if (!p) return;
      setProgress(null);
      setConfirm({ mode, preview: p, showReview: false,
        description: description ?? (mode === "chosen" ? `Students outside the maximum academic period, chosen on the list (${scopeWords})` : `Students outside the maximum academic period: ${scopeWords}`) });
    } finally {
      setBusy(false);
    }
  }

  async function confirmGraduation() {
    if (!confirm) return;
    setBusy(true);
    try {
      const body = { description: confirm.description.trim(), studentIds: confirm.mode === "chosen" ? [...ticked] : null, includeMedium: confirm.preview.includeMedium,
        fac: scope.fac || null, dept: scope.dept || null, prog: scope.prog || null };
      const opened = await call<RecBatch>(`${BASE}/batches`, "POST", body, `Graduation-status reconciliation opened: ${confirm.description.trim()}`);
      if (!opened) return;
      const path = recBatchPath(opened.batch_ref);
      const run = { ref: opened.batch_ref, graduated: 0, refused: 0, skipped: 0, remaining: opened.eligible, done: false };
      setProgress({ ...run });
      for (let i = 0; i < 100; i++) {
        const r = await call<{ graduated: number; skipped: number; refused: unknown[]; remaining: number; done: boolean }>(`${BASE}/batches/${path}/run`, "POST",
          { reason: confirm.description.trim() }, `Graduation-status reconciliation ${opened.batch_ref} executed`);
        if (!r) break;
        run.graduated += r.graduated; run.skipped += r.skipped; run.refused += r.refused.length; run.remaining = r.remaining; run.done = r.done;
        setProgress({ ...run });
        if (r.done) break;
      }
      notify(`${opened.batch_ref}: ${plural(run.graduated, "student")} graduated${run.refused ? `, ${run.refused} refused` : ""}`);
      setTicked(new Set());
      if (listOpen) await load(1);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  async function openReview(id: string) {
    const r = await call<StudentReview>(`${BASE}/students/${id}`, "GET", undefined, "Student's academic period reviewed");
    if (!r) return;
    setReview(r);
    const rec = r.reconciliations.find((x) => !x.corrected_at);
    setDate(rec?.graduation_date?.slice(0, 10) ?? "");
    setDateNote(rec?.date_note ?? "");
  }

  async function confirmDate() {
    if (!review) return;
    setBusy(true);
    try {
      const r = await call<{ graduationDate: string }>(`${BASE}/students/${review.student.id}/graduation-date`, "POST", { date, note: dateNote.trim() || null },
        `Official graduation date confirmed: ${date}`);
      if (!r) return;
      notify(`${fullName(review.student)}: official graduation date ${new Date(r.graduationDate).toLocaleDateString("en-GB")} confirmed`);
      await openReview(review.student.id);
    } finally {
      setBusy(false);
    }
  }

  async function openBatch(ref: string) {
    const b = await call<RecBatch>(`${BASE}/batches/${recBatchPath(ref)}`, "GET", undefined, "Graduation-status reconciliation read");
    if (b) setBatch(b);
  }

  async function loadReport(by: string) {
    setReportBy(by);
    const p = scoped(new URLSearchParams({ by }));
    const r = await call<{ rows: Record<string, unknown>[] }>(`${BASE}/report?${p.toString()}`, "GET", undefined, "Reconciled graduates report read");
    if (r) setReport(r.rows);
  }

  async function switchAuto(on: boolean) {
    setBusy(true);
    try {
      const r = await call<RecSetting>(`${BASE}/setting`, "POST", { autoGraduation: on }, `Automatic graduation reconciliation switched ${on ? "on" : "off"}`);
      if (!r) return;
      notify(`Automatic graduation reconciliation is ${r.auto_graduation ? "on" : "off"}`);
      setSwitching(false);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const tick = (id: string) => setTicked((s) => { const n = new Set(s); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  const pageIds = rows.map((r) => r.student_id);
  const allTicked = pageIds.length > 0 && pageIds.every((id) => ticked.has(id));
  const reportLabel = REC_REPORT_BY.find((x) => x[0] === reportBy)?.[1] ?? reportBy;
  const reportHeaders = [reportLabel, "Graduated", "Automatically", "High confidence", "Medium confidence", "Date confirmed", "Cleared", "Clearance pending"];
  const reportRows = (report ?? []).map((r) => [String(r.label), ...["graduated", "automatic", "high", "medium", "date_confirmed", "cleared", "clearance_pending"].map((k) => Number(r[k] ?? 0))]);
  const reportMeta: [string, string][] = [["Grouped by", reportLabel], ["Scope", scopeWords]];
  const recNow = review?.reconciliations.find((x) => !x.corrected_at) ?? null;

  return (
    <div id="outside">
      <Panel title="Students outside the maximum academic period" right={`Current session ${f.currentSession ?? "not set"} · ${plural(f.maxSpilloverYears, "spillover session")} allowed`}>
        <PBody>
          <div className="sub2">
            A student is outside the maximum academic period when the sessions since the expected completion (the programme&rsquo;s length from the
            admission session, with approved deferments) are more than the spillover allowed — counted on the University&rsquo;s session sequence,
            never the calendar year or the matriculation year. Such a student who is still kept in study is reconciled to GRADUATED; nothing on the record is deleted.
          </div>
        </PBody>
        {problem && !confirm && !review && !batch ? <PBody><ProblemNotice problem={problem} /></PBody> : null}
        <Tiles items={[
          ["Active students", f.active, null, "active or on probation"],
          ["Current session", f.current, null, `registered or enrolled for ${f.currentSession ?? "—"}`],
          ["SP1", f.sp1, null, "first spillover session"],
          ["SP2", f.sp2, null, "second spillover session"],
        ]} />
        <Tiles items={[
          ["Outside maximum period", f.outsideMaximum, f.outsideMaximum ? "var(--red-ink)" : null, `${f.eligibleHigh} high · ${f.eligibleMedium} medium confidence`, here("ALL")],
          ["Graduation candidates", f.graduationCandidates, null, "at the final level, on the lifecycle desk", `/cohorts?tab=lifecycle&view=students&rec=GRADUATION_CANDIDATE`],
          ["Graduated", f.graduated, null, `${f.graduatedByReconciliation} by reconciliation · ${f.graduatedAutomatically} automatically`],
          ["Requires review", f.requiresReview, f.requiresReview ? "var(--amber-ink)" : null, "outside the maximum, record conflicts", here("LOW")],
        ]} />
        <Tiles cls="grid--4" items={[
          ["Data incomplete", f.dataIncomplete, null, "on the lifecycle desk", `/cohorts?tab=lifecycle&view=students&rec=DATA_INCOMPLETE`],
          ["Eligible now", f.eligible, null, "high and medium confidence", here("ALL")],
          ["High confidence", f.eligibleHigh, null, "graduated by the nightly run when it is on", here("HIGH")],
          ["Medium confidence", f.eligibleMedium, null, "graduated when the officer includes them", here("MEDIUM")],
        ]} />
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "center" }}>
            <Pil kind={setting.auto_graduation ? "ok" : "grey"}>Automatic reconciliation {setting.auto_graduation ? "on" : "off"}</Pil>
            <span className="sub2">
              {setting.auto_graduation ? "Each night the portal graduates the high-confidence students outside the maximum period." : "Nothing is graduated without an officer's confirmation."}
              {setting.last_automatic_run ? ` Last automatic run ${new Date(setting.last_automatic_run).toLocaleString("en-GB")}.` : ""}
              {setting.updated_by ? ` Set by ${setting.updated_by}${setting.updated_at ? ` on ${new Date(setting.updated_at).toLocaleDateString("en-GB")}` : ""}.` : ""}
            </span>
            {setter ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => setSwitching(true)}>{setting.auto_graduation ? "Switch off" : "Switch on"}</Btn> : null}
            <span className="ml-auto row row--tight">
              {!listOpen ? <Btn kind="secondary" size="sm" onClick={() => { setListOpen(true); void load(1); }}>Show the list</Btn> : null}
              {office ? <Btn kind="primary" size="sm" disabled={busy || !f.outsideMaximum} onClick={() => void preview("scope", false)}>RECONCILE ACADEMIC STATUS</Btn> : null}
            </span>
          </div>
        </PBody>
      </Panel>

      {listOpen ? (
        <Panel title={listTitle} right={`${total.toLocaleString("en-GB")} in ${scopeWords}`}>
          <PBody>
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
              <Field id="om-conf" label="Confidence"><select id="om-conf" className="ctl" value={conf} onChange={(e) => { setConf(e.target.value); void load(1, e.target.value); }}>
                <option value="">All</option>{Object.entries(REC_CONFIDENCE).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select></Field>
              <Field id="om-q" label="Matriculation number, JAMB number or name">
                <input id="om-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void load(1); }} maxLength={80} placeholder="MOAU/AD/BUS/18/12345" />
              </Field>
              <Btn kind="secondary" disabled={busy} onClick={() => void load(1)}>Search</Btn>
              <span className="ml-auto row row--tight">
                <Btn kind="ghost" size="sm" disabled={!total} onClick={() => void exportXlsx()}>Excel</Btn>
                <Btn kind="ghost" size="sm" disabled={!total} onClick={() => void exportPdf()}>PDF</Btn>
                {office ? <Btn kind="primary" size="sm" disabled={busy || !ticked.size} onClick={() => void preview("chosen", false)}>MARK AS GRADUATED{ticked.size ? ` (${ticked.size})` : ""}</Btn> : null}
              </span>
            </div>
          </PBody>
          {rows.length ? (
            <DTable pageSize={0} noPrint
              cols={[...(office ? [""] : []), "S/N|num", "Student", "Programme", "Admission|mid", "Expected completion|mid", "Maximum session|mid", "Beyond|num", "Confidence|mid", "Why", "|num"]}
              rows={rows.map((r, i) => [
                ...(office ? [<input key="t" type="checkbox" aria-label={`Choose ${fullName(r)}`} checked={ticked.has(r.student_id)} onChange={() => tick(r.student_id)} />] : []),
                <span key="n" className="tnum">{(page - 1) * PAGE + i + 1}</span>,
                <Two key="s" a={fullName(r)} b={r.matric_no ?? "—"} />,
                <Two key="p" a={r.programme ?? r.programme_code ?? "—"} b={`${r.department ?? ""}${r.duration_years ? ` · ${r.duration_years} sessions` : ""}`} />,
                <span key="e" className="tnum">{r.entry_session ?? "—"}</span>,
                <span key="x" className="tnum">{r.expected_completion ?? "—"}</span>,
                <span key="m" className="tnum">{r.maximum_session ?? "—"}</span>,
                <span key="b" className="tnum">{r.spillover_years}</span>,
                <Pil key="c" kind={REC_CONFIDENCE[r.confidence]?.[1] ?? "grey"} title={REC_CONFIDENCE[r.confidence]?.[2]}>{REC_CONFIDENCE[r.confidence]?.[0] ?? r.confidence}</Pil>,
                <span key="w" className="sub2">{reasonsOf(r.confidence_reasons).join("; ") || "complete and consistent"}</span>,
                <Btn key="v" kind="ghost" size="sm" onClick={() => void openReview(r.student_id)}>Review</Btn>,
              ])}
            />
          ) : <PBody><div className="sub2">No student outside the maximum academic period matches.</div></PBody>}
          <PBody>
            <div className="row" style={{ gap: "var(--s-2)", alignItems: "center" }}>
              {office ? <Btn kind="ghost" size="sm" disabled={!rows.length} onClick={() => setTicked((s) => { const n = new Set(s); for (const id of pageIds) { if (allTicked) n.delete(id); else n.add(id); } return n; })}>
                {allTicked ? "Untick this page" : "Tick this page"}</Btn> : null}
              <span className="sub2">Page {page} of {Math.max(1, Math.ceil(total / PAGE))} · names A to Z</span>
              <span className="ml-auto row row--tight">
                <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => void load(page - 1)}>Previous</Btn>
                <Btn kind="ghost" size="sm" disabled={page * PAGE >= total} onClick={() => void load(page + 1)}>Next</Btn>
              </span>
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Graduation-status reconciliations" right={`${batches.length} batch${batches.length === 1 ? "" : "es"}`}>
        {batches.length ? (
          <DTable pageSize={10}
            cols={["Batch", "For", "Selected|num", "Eligible|num", "Graduated|num", "Review|num", "State", "By", "|num"]}
            rows={batches.map((b) => [
              <Two key="r" a={b.batch_ref} b={b.mode === "AUTOMATIC" ? "Automatic" : "By an officer"} />, <span key="f" className="sub2">{b.description}</span>,
              <span key="s" className="tnum">{b.selected}</span>, <span key="e" className="tnum">{b.eligible}</span>, <span key="g" className="tnum">{b.graduated}</span>,
              <span key="v" className="tnum">{b.review}</span>, <Pil key="st" kind={recBatchState(b)[1]}>{recBatchState(b)[0]}</Pil>,
              <span key="by" className="sub2">{b.created_by ?? b.actor_office} · {new Date(b.created_at).toLocaleDateString("en-GB")}</span>,
              <Btn key="o" kind="ghost" size="sm" onClick={() => void openBatch(b.batch_ref)}>Open</Btn>,
            ])}
            texts={batches.map((b) => `${b.batch_ref} ${b.description} ${b.mode}`)}
          />
        ) : <PBody><div className="sub2">No student has been reconciled to graduated yet.</div></PBody>}
      </Panel>

      <Panel title="Reconciled graduates" right={
        <span className="row row--tight">
          <select className="ctl" value={reportBy} onChange={(e) => void loadReport(e.target.value)} aria-label="Group the reconciled graduates by">
            {REC_REPORT_BY.map(([k, w]) => <option key={k} value={k}>{w}</option>)}
          </select>
          {!report ? <Btn kind="ghost" size="sm" onClick={() => void loadReport(reportBy)}>Load</Btn> : null}
          {report && report.length ? (
            <>
              <Btn kind="ghost" size="sm" onClick={() => void brandedXlsx(`Reconciled graduates by ${reportLabel.toLowerCase()}`, reportHeaders, reportRows, { serial: docSerial("GRADRECON"), meta: reportMeta })
                .then((b) => downloadBlob(b, `reconciled-graduates-by-${reportBy}.xlsx`))}>Excel</Btn>
              <Btn kind="ghost" size="sm" onClick={() => brandedPrint(`Reconciled graduates by ${reportLabel.toLowerCase()}`, scopeWords, reportHeaders, reportRows, docSerial("GRADRECON"), { meta: reportMeta, orientation: "landscape" })}>PDF</Btn>
            </>
          ) : null}
        </span>
      }>
        {report ? (
          report.length ? (
            <DTable pageSize={0} cols={[reportLabel, "Graduated|num", "Automatically|num", "High|num", "Medium|num", "Date confirmed|num", "Cleared|num", "Clearance pending|num"]}
              rows={reportRows.map((r) => [<b key="l">{r[0]}</b>, ...r.slice(1).map((v, i) => <span key={i} className="tnum">{v}</span>)])} />
          ) : <PBody><div className="sub2">No reconciled graduate within the scope.</div></PBody>
        ) : <PBody><div className="sub2">The students graduated by status reconciliation, counted by faculty, department, programme, admission session, graduation session, spillover state or batch, with their final clearance. S/N first on the Excel and the PDF.</div></PBody>}
      </Panel>

      {confirm ? (
        <Modal wide title={confirm.mode === "chosen" ? "Mark as graduated" : "Reconcile academic status"} sub={scopeWords}
          onClose={() => { if (!busy) { setConfirm(null); setProgress(null); } }}
          foot={progress ? (
            <Btn kind="primary" disabled={busy} onClick={() => { setConfirm(null); setProgress(null); }}>Close</Btn>
          ) : (
            <>
              <Btn kind="ghost" disabled={busy} onClick={() => setConfirm(null)}>CANCEL</Btn>
              <Btn kind="secondary" disabled={busy || !confirm.preview.review} onClick={() => setConfirm({ ...confirm, showReview: !confirm.showReview })}>
                {confirm.showReview ? "HIDE REVIEW LIST" : "VIEW REVIEW LIST"}</Btn>
              <Btn kind="primary" disabled={busy || !confirm.preview.eligible || confirm.description.trim().length < 10} onClick={() => void confirmGraduation()}>
                {busy ? "Working…" : "CONFIRM GRADUATION"}</Btn>
            </>
          )}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          {progress ? (
            <Note kind={progress.done ? "ok" : "info"} title={progress.done ? `${progress.ref} executed` : `${progress.ref} running…`}>
              {progress.graduated} graduated · {progress.skipped} already graduated · {progress.refused} refused · {progress.remaining} waiting. Each record was
              revalidated as it was changed; the students, the Bursary and the Students Account Office are told.
            </Note>
          ) : (
            <>
              <Note kind={confirm.preview.eligible ? "info" : "bad"} title={confirmLines(confirm.preview)[0]}>
                {confirmLines(confirm.preview).slice(1).map((l) => <div key={l}>{l}</div>)}
                <div className="sub2" style={{ marginTop: "var(--s-1)" }}>
                  {confirm.preview.high} high, {confirm.preview.medium} medium, {confirm.preview.low} low confidence. Low confidence is never graduated here;
                  medium is graduated only when you include it after reading the records.
                </div>
              </Note>
              <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end", marginTop: "var(--s-2)" }}>
                <label className="row row--tight" style={{ alignItems: "center" }}>
                  <input type="checkbox" checked={confirm.preview.includeMedium} disabled={busy || !confirm.preview.medium}
                    onChange={(e) => void preview(confirm.mode, e.target.checked, confirm.description)} />
                  <span>Include the {confirm.preview.medium} medium-confidence record{confirm.preview.medium === 1 ? "" : "s"} (I have read them)</span>
                </label>
                <Field id="om-desc" label="What the reconciliation is for (at least ten characters)">
                  <input id="om-desc" className="ctl" value={confirm.description} onChange={(e) => setConfirm({ ...confirm, description: e.target.value })} maxLength={300} style={{ minWidth: 380 }} />
                </Field>
              </div>
              {confirm.showReview ? (
                <DTable pageSize={10} noPrint
                  cols={["Student", "Programme", "Maximum session|mid", "Confidence|mid", "Why it needs review"]}
                  rows={confirm.preview.rows.filter((r) => r.verdict === "REVIEW").map((r) => [
                    <Two key="s" a={fullName(r)} b={r.matric_no ?? "—"} />, <span key="p">{r.programme ?? r.programme_code}</span>,
                    <span key="m" className="tnum">{r.maximum_session ?? "—"}</span>,
                    <Pil key="c" kind={REC_CONFIDENCE[r.confidence]?.[1] ?? "grey"}>{REC_CONFIDENCE[r.confidence]?.[0] ?? r.confidence}</Pil>,
                    <span key="w" className="sub2">{reasonsOf(r.confidence_reasons).join("; ")}</span>,
                  ])}
                  texts={confirm.preview.rows.filter((r) => r.verdict === "REVIEW").map((r) => `${r.matric_no ?? ""} ${fullName(r)} ${r.confidence_reasons ?? ""}`)}
                />
              ) : null}
            </>
          )}
        </Modal>
      ) : null}

      {review ? (
        <Modal wide title={fullName(review.student)} sub={`${review.student.matric_no ?? "—"} · ${review.student.programme ?? ""} · status ${review.student.status}`} onClose={() => setReview(null)}
          foot={<LinkBtn kind="ghost" href={`/students/${review.student.id}`}>Full record</LinkBtn>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          {review.candidate || recNow ? (
            <DTable pageSize={0} noPrint cols={["Academic period", "As counted"]}
              rows={timeline((review.candidate ?? recNow)!).map(([k, v]) => [<b key="k">{k}</b>, <span key="v" className="tnum">{v}</span>])} />
          ) : <Note kind="info" title="Not outside the maximum academic period">The cohort engine does not read this record beyond the spillover allowed.</Note>}
          {review.candidate ? (
            <Note kind={REC_CONFIDENCE[review.candidate.confidence]?.[1] === "ok" ? "ok" : REC_CONFIDENCE[review.candidate.confidence]?.[1] === "bad" ? "bad" : "info"}
              title={`${REC_CONFIDENCE[review.candidate.confidence]?.[0]} confidence — ${review.candidate.recommendation === "REQUIRES_REVIEW" ? "requires review" : "graduated on reconciliation"}`}>
              {reasonsOf(review.candidate.confidence_reasons).length ? reasonsOf(review.candidate.confidence_reasons).map((x) => <div key={x}>{x}</div>) : "The record is complete and nothing conflicts."}
            </Note>
          ) : null}
          {recNow ? (
            <Note kind="ok" title={`Graduated by status reconciliation · ${recNow.batch_ref}`}>
              <div>Status {recNow.previous_status} to {recNow.new_status} on {new Date(recNow.reconciled_at).toLocaleDateString("en-GB")} by {recNow.reconciled_by ?? recNow.actor_office}; {recNow.confidence.toLowerCase()} confidence.</div>
              <div>Graduation session {recNow.graduation_session ?? "—"}; official date {recNow.date_confirmed && recNow.graduation_date ? `${new Date(recNow.graduation_date).toLocaleDateString("en-GB")} (confirmed by ${recNow.date_confirmed_by ?? "the Academic Office"})` : "awaiting the Academic Office's confirmation"}.</div>
              <div>Final clearance {recNow.clearance ?? "—"}. Reason: {recNow.reason}</div>
              {office ? (
                <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end", marginTop: "var(--s-2)" }}>
                  <Field id="om-date" label="Official graduation date"><input id="om-date" type="date" className="ctl" value={date} onChange={(e) => setDate(e.target.value)} /></Field>
                  <Field id="om-dnote" label="The convocation or the Senate's minute"><input id="om-dnote" className="ctl" value={dateNote} onChange={(e) => setDateNote(e.target.value)} maxLength={300} /></Field>
                  <Btn kind="secondary" disabled={busy || !date} onClick={() => void confirmDate()}>Confirm the date</Btn>
                </div>
              ) : null}
            </Note>
          ) : null}
          {review.reconciliations.filter((x) => x.corrected_at).map((x) => (
            <Note key={x.id} kind="info" title={`${x.batch_ref} corrected`}>Put right on {new Date(x.corrected_at!).toLocaleDateString("en-GB")} by {x.corrected_by ?? "the Registrar"}: {x.correction_reason}</Note>
          ))}
          <div className="grid grid--2" style={{ marginTop: "var(--s-2)" }}>
            <div>
              <b>Registrations</b>
              <div className="sub2">{review.registrations.length ? review.registrations.map((r) => `${r.session} sem ${r.semester} · ${r.level}`).join("; ") : "None on record"}</div>
              <b>Deferments</b>
              <div className="sub2">{review.deferments.length ? review.deferments.map((d) => `${d.reference} ${d.session} (${d.state.toLowerCase()})`).join("; ") : "None"}</div>
            </div>
            <div>
              <b>Programme history</b>
              <div className="sub2">{review.programmeHistory.map((h) => `${h.session ?? ""} ${h.kind.toLowerCase().replace(/_/g, " ")}: ${h.programme ?? ""}`).join("; ") || "—"}</div>
              <b>Status history</b>
              <div className="sub2">{review.statusHistory.length ? review.statusHistory.map((h) => `${h.effective_on ?? ""} ${h.from_status ?? "—"} to ${h.to_status}${h.instrument ? ` (${h.instrument})` : ""}`).join("; ") : "No change on record"}</div>
            </div>
          </div>
        </Modal>
      ) : null}

      {batch ? (
        <Modal wide title={batch.batch_ref} sub={`${batch.mode === "AUTOMATIC" ? "Automatic" : "By an officer"} · ${batch.description}`} onClose={() => setBatch(null)}>
          <div className="sub2">
            {batch.selected} chosen · {batch.eligible} eligible · {batch.graduated} graduated · {batch.review} for review · {batch.skipped} skipped · {batch.refused} refused · {batch.corrected} corrected.
            Effective session {batch.effective_session}; {batch.min_confidence === "HIGH" ? "high confidence only" : "high and medium confidence"}.
          </div>
          <DTable pageSize={25}
            cols={["Student", "Programme", "Confidence|mid", "Outcome", "Graduation session|mid", "Official date|mid", "|num"]}
            rows={(batch.rows ?? []).map((r: RecRow) => [
              <Two key="s" a={fullName(r)} b={r.matric_no ?? "—"} />, <span key="p">{r.programme ?? r.programme_code}</span>,
              <Pil key="c" kind={REC_CONFIDENCE[r.confidence]?.[1] ?? "grey"}>{REC_CONFIDENCE[r.confidence]?.[0] ?? r.confidence}</Pil>,
              <Pil key="o" kind={recOutcome(r)[1]}>{recOutcome(r)[0]}</Pil>,
              <span key="g" className="tnum">{r.graduation_session ?? "—"}</span>,
              <span key="d" className="tnum">{r.date_confirmed && r.graduation_date ? new Date(r.graduation_date).toLocaleDateString("en-GB") : "—"}</span>,
              <Btn key="v" kind="ghost" size="sm" onClick={() => { setBatch(null); void openReview(r.student_id); }}>Review</Btn>,
            ])}
            texts={(batch.rows ?? []).map((r) => `${r.matric_no ?? ""} ${fullName(r)} ${r.outcome ?? ""} ${r.reasons ?? ""}`)}
          />
        </Modal>
      ) : null}

      {switching ? (
        <Modal title={setting.auto_graduation ? "Switch automatic reconciliation off" : "Switch automatic reconciliation on"} onClose={() => setSwitching(false)}
          foot={<>
            <Btn kind="ghost" disabled={busy} onClick={() => setSwitching(false)}>Cancel</Btn>
            <Btn kind={setting.auto_graduation ? "secondary" : "urgent"} disabled={busy} onClick={() => void switchAuto(!setting.auto_graduation)}>{setting.auto_graduation ? "Switch off" : "Switch on"}</Btn>
          </>}>
          <Note kind={setting.auto_graduation ? "info" : "bad"} title={setting.auto_graduation ? "Officers reconcile by hand from tonight" : "The portal will graduate students each night"}>
            {setting.auto_graduation
              ? "No student is graduated without an officer's confirmation once this is off."
              : `Each night the portal graduates every high-confidence student outside the maximum academic period (${f.eligibleHigh} now) in a batch of its own, told to each student and to the Bursary. Medium and low confidence are never graduated by the night run.`}
          </Note>
        </Modal>
      ) : null}
    </div>
  );
}
