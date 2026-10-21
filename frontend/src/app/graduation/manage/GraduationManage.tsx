"use client";

/** V602: Graduation Management — the figures the existing engines give, graduation batches on the Senate's minute (preview, confirm,
 *  execute, history), the graduated by session, and the reports. Every verdict and every act is the server's. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { CONFIDENCE, REPORT_BY, batchPath, batchState, confirmWords, outcomeWord, tally, verdictKind, verdictWord,
  type Batch, type BatchRow, type Management, type Verdict } from "@/lib/graduation-batch";

const STATUSES: [string, string][] = [["", "Active or on probation (in study)"], ["ACTIVE", "Active"], ["PROBATION", "On probation"], ["DEFERRED", "Deferred"],
  ["GRADUATED", "Graduated"], ["DORMANT", "Dormant"], ["WITHDRAWN", "Withdrawn"]];

type Step = "filter" | "preview" | "running" | "done";

export function GraduationManage({ scope, structure, sessions, view, actingOffice }: {
  scope: Scope; structure: ScopeStructure; sessions: string[]; view: Management; actingOffice: string | null;
}) {
  const router = useRouter();
  const f = view.figures;
  const office = ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");
  const registrar = ["registrar", "dregistrar"].includes(actingOffice ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [step, setStep] = useState<Step>("filter");
  const [entry, setEntry] = useState("");
  const [level, setLevel] = useState("400");
  const [status, setStatus] = useState("");
  const [q, setQ] = useState("");
  const [rows, setRows] = useState<Verdict[]>([]);
  const [minute, setMinute] = useState("");
  const [reason, setReason] = useState("");
  const [progress, setProgress] = useState<{ ref: string; graduated: number; refused: number; remaining: number }>({ ref: "", graduated: 0, refused: 0, remaining: 0 });
  const [detail, setDetail] = useState<Batch | null>(null);
  const [reportBy, setReportBy] = useState("faculty");
  const [report, setReport] = useState<Record<string, unknown>[] | null>(null);
  const [correct, setCorrect] = useState<{ id: string; name: string } | null>(null);
  const [cReason, setCReason] = useState("");
  const [cEvidence, setCEvidence] = useState("");

  const scopeQuery = () => {
    const p = new URLSearchParams({ session: scope.session });
    if (scope.fac) p.set("fac", scope.fac);
    if (scope.dept) p.set("dept", scope.dept);
    if (scope.prog) p.set("prog", scope.prog);
    return p;
  };
  const filter = () => ({ entry: entry || null, level: level || null, status: status || null, q: q || null, fac: scope.fac || null, dept: scope.dept || null, prog: scope.prog || null });

  async function call<T>(path: string, method: "GET" | "POST", body: unknown, reason: string): Promise<T | null> {
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

  async function preview() {
    setBusy(true);
    try {
      const j = await call<{ rows: Verdict[]; selected: number }>("/api/bff/api/v1/graduation/batches/preview", "POST", { session: scope.session, filter: filter() }, "Graduation batch previewed");
      if (!j) return;
      setRows(j.rows);
      setStep("preview");
      notify(`${j.selected} student${j.selected === 1 ? "" : "s"} named; ${tally(j.rows).eligible} eligible`);
    } finally {
      setBusy(false);
    }
  }

  async function confirmAndGraduate() {
    setBusy(true);
    try {
      const opened = await call<Batch>("/api/bff/api/v1/graduation/batches", "POST",
        { session: scope.session, senateMinute: minute.trim(), reason: reason.trim(), filter: filter() }, `Graduation batch opened: ${reason.trim()}`);
      if (!opened) return;
      const path = batchPath(opened.batch_ref);
      setStep("running");
      let graduated = 0;
      let refused = 0;
      let remaining = opened.eligible;
      setProgress({ ref: opened.batch_ref, graduated, refused, remaining });
      for (let i = 0; i < 100; i++) {
        const r = await call<{ graduated: number; refused: unknown[]; remaining: number; done: boolean }>(`/api/bff/api/v1/graduation/batches/${path}/execute`, "POST", {}, `Graduation batch ${opened.batch_ref} executed`);
        if (!r) break;
        graduated += r.graduated;
        refused += r.refused.length;
        remaining = r.remaining;
        setProgress({ ref: opened.batch_ref, graduated, refused, remaining });
        if (r.done) break;
      }
      setStep("done");
      notify(`${opened.batch_ref}: ${graduated} graduated${refused ? `, ${refused} refused` : ""}`);
      const d = await call<Batch>(`/api/bff/api/v1/graduation/batches/${path}`, "GET", undefined, "Graduation batch read");
      if (d) setDetail(d);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  async function openDetail(ref: string) {
    const d = await call<Batch>(`/api/bff/api/v1/graduation/batches/${batchPath(ref)}`, "GET", undefined, "Graduation batch read");
    if (d) setDetail(d);
  }

  async function loadReport(by: string) {
    setReportBy(by);
    const p = scopeQuery();
    p.set("by", by);
    const r = await call<{ rows: Record<string, unknown>[] }>(`/api/bff/api/v1/graduation/report?${p.toString()}`, "GET", undefined, "Graduation report read");
    if (r) setReport(r.rows);
  }

  async function sendCorrection() {
    if (!correct) return;
    setBusy(true);
    try {
      const r = await call<Record<string, unknown>>(`/api/bff/api/v1/graduation/students/${correct.id}/correct`, "POST", { reason: cReason.trim(), evidence: cEvidence.trim() }, `Graduation corrected: ${cReason.trim()}`);
      if (!r) return;
      notify(`${correct.name}: status back to ACTIVE; documents issued ${String(r.documents_issued ?? 0)}, transcript requests ${String(r.transcript_requests ?? 0)}, final clearance ${String(r.final_clearance ?? "not started")}`);
      setCorrect(null); setCReason(""); setCEvidence("");
      if (detail) await openDetail(detail.batch_ref);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const t = tally(rows);
  const reportLabel = REPORT_BY.find((x) => x[0] === reportBy)?.[1] ?? reportBy;
  const reportHeaders = ["S/N", reportLabel, "Graduated", "From SP1", "From SP2", "Normal", "Cleared", "Clearance pending", "Clearance not started", "By batch"];
  const reportRows = (report ?? []).map((r, i) => [i + 1, String(r.label), Number(r.graduated), Number(r.sp1), Number(r.sp2), Number(r.normal), Number(r.cleared), Number(r.clearance_pending), Number(r.clearance_not_started), Number(r.by_batch)]);
  const reportMeta: [string, string][] = [["Graduation session", scope.session], ["Grouped by", reportLabel], ...(scope.fac ? [["Faculty", scope.fac] as [string, string]] : []), ...(scope.dept ? [["Department", scope.dept] as [string, string]] : []), ...(scope.prog ? [["Programme", scope.prog] as [string, string]] : [])];

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} what="students" count={f.students} of={f.students} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Tiles items={[
        ["Students reviewed", f.students, `${f.in_study} in study · ${f.graduated_all} graduated`],
        ["Graduation eligible", f.candidates, `${f.candidates_high} high confidence · ${f.candidates_low} low`],
        ["Already graduated", f.graduated_session, `graduation session ${scope.session}`],
        ["Not eligible", f.sp1 + f.sp2 + f.maximum, `${f.sp1} SP1 · ${f.sp2} SP2 · ${f.maximum} at the limit`],
      ]} />
      <Tiles items={[
        ["Has carry-over", f.carry_over, "a failed course not yet passed"],
        ["Has outstanding result", f.outstanding_result, "a registered course with no published result"],
        ["Deferred", f.deferred, "not graduated while deferred"],
        ["Requires review", f.requires_review, `${f.data_incomplete} data incomplete`],
      ]} />
      <Tiles items={[
        ["On the list, met", f.listed_met, `${f.listed_unmet} with a requirement unmet · ${f.referred} referred`],
        ["Awards approved", f.approved, `for ${scope.session}`],
        ["Clearance pending", f.clearance_pending, "final clearance under way"],
        ["Clearance completed", f.clearance_completed, "every required office cleared"],
      ]} />
      <PBody>
        <div className="sub2">
          Figures from the cohort engine, the lifecycle desk (last analysed {f.completion_checked_at ? new Date(f.completion_checked_at).toLocaleString("en-GB") : "never"}), the graduation list and the clearance engine.{" "}
          <LinkBtn kind="ghost" href={`/cohorts?tab=lifecycle&session=${encodeURIComponent(scope.session)}`}>Lifecycle reconciliation</LinkBtn>{" "}
          <LinkBtn kind="ghost" href={`/graduation?session=${encodeURIComponent(scope.session)}`}>Graduation list & Senate approval</LinkBtn>{" "}
          <LinkBtn kind="ghost" href={`/student-query?graduation=GRADUATED&graduationSession=${encodeURIComponent(scope.session)}`}>Graduated students</LinkBtn>{" "}
          <LinkBtn kind="ghost" href={`/clearance?wf=FINAL&session=${encodeURIComponent(scope.session)}`}>Final clearance desk</LinkBtn>
        </div>
      </PBody>

      {office ? (
        <Panel title="Graduation batch" right={step === "filter" ? "Choose the students, preview, then confirm on the Senate's minute" : step === "preview" ? `${t.selected} chosen · ${t.eligible} eligible` : progress.ref}>
          {step === "filter" || step === "preview" ? (
            <PBody>
              <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
                <Field id="gb-entry" label="Year of entry or session"><input id="gb-entry" className="ctl tnum" value={entry} onChange={(e) => setEntry(e.target.value)} placeholder="2021 or 2021/2022" maxLength={9} /></Field>
                <Field id="gb-level" label="Current level"><select id="gb-level" className="ctl" value={level} onChange={(e) => setLevel(e.target.value)}>
                  <option value="">Any</option>{[100, 200, 300, 400, 500, 600, 700, 800, 900].map((l) => <option key={l} value={String(l)}>{l} Level</option>)}</select></Field>
                <Field id="gb-status" label="Current status"><select id="gb-status" className="ctl" value={status} onChange={(e) => setStatus(e.target.value)}>
                  {STATUSES.map(([k, w]) => <option key={k} value={k}>{w}</option>)}</select></Field>
                <Field id="gb-q" label="Matriculation number, JAMB number or name"><input id="gb-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="MOAU/AD/BUS/21/12345" maxLength={80} /></Field>
                <Btn kind="primary" disabled={busy} onClick={() => void preview()}>{busy ? "Reconciling…" : "RECONCILE GRADUATION STATUS"}</Btn>
              </div>
              <div className="sub2" style={{ marginTop: "var(--s-2)" }}>The scope bar&rsquo;s faculty, department and programme bound the choice; at most 5,000 students a batch. Nothing is written by the preview.</div>
            </PBody>
          ) : null}
          {step === "preview" ? (
            <>
              <PBody>
                <div className="row row--tight" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
                  {t.byVerdict.map(([v, n]) => <Pil key={v} kind={verdictKind(v)}>{n} {verdictWord(v).toLowerCase()}</Pil>)}
                  {!rows.length ? <span className="sub2">No student matches the filter.</span> : null}
                </div>
              </PBody>
              <DTable pageSize={25}
                cols={["Student", "Programme", "Level|num", "Status", "Verdict", "Confidence|mid", "Reason", "|num"]}
                rows={rows.map((r) => [
                  <Two key="s" a={r.name} b={r.number ?? "—"} />, <span key="p">{r.programme ?? r.programmeCode}</span>,
                  <span key="l" className="tnum">{r.level ?? "—"}{r.finalLevel ? ` / ${r.finalLevel}` : ""}</span>, <span key="st">{r.status}</span>,
                  <Pil key="v" kind={verdictKind(r.verdict)}>{verdictWord(r.verdict)}</Pil>,
                  <Pil key="c" kind={CONFIDENCE[r.confidence ?? ""]?.[1] ?? "grey"}>{CONFIDENCE[r.confidence ?? ""]?.[0] ?? "—"}</Pil>,
                  <span key="r" className="sub2">{r.reason}{r.spilloverState && r.spilloverState.startsWith("SPILLOVER") ? ` · ${r.spilloverState.replace("SPILLOVER_YEAR_", "SP")}` : ""}</span>,
                  <LinkBtn key="o" kind="ghost" href={`/students/${r.studentId}`}>View</LinkBtn>,
                ])}
                texts={rows.map((r) => `${r.number ?? ""} ${r.name} ${r.programme ?? ""} ${r.verdict} ${r.reason ?? ""}`)}
              />
              <PBody>
                <Note kind={t.eligible ? "info" : "bad"} title={confirmWords(t, scope.session)}>
                  <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end", marginTop: "var(--s-2)" }}>
                    <Field id="gb-minute" label="Senate minute"><input id="gb-minute" className="ctl" value={minute} onChange={(e) => setMinute(e.target.value)} placeholder="e.g. SEN/2026/04/12" maxLength={60} /></Field>
                    <Field id="gb-reason" label="What the batch is for"><input id="gb-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. 2024/2025 graduands of the Faculty of Science confirmed" maxLength={200} style={{ minWidth: 360 }} /></Field>
                    <Btn kind="primary" disabled={busy || !t.eligible || minute.trim().length < 3 || reason.trim().length < 10} onClick={() => void confirmAndGraduate()}>{busy ? "Working…" : "CONFIRM & GRADUATE"}</Btn>
                    <Btn kind="ghost" disabled={busy} onClick={() => { setStep("filter"); setRows([]); }}>Back</Btn>
                  </div>
                </Note>
              </PBody>
            </>
          ) : null}
          {step === "running" || step === "done" ? (
            <PBody>
              <Note kind={step === "done" ? "ok" : "info"} title={step === "done" ? `${progress.ref} executed` : `${progress.ref} running…`}
                action={step === "done" ? <Btn kind="ghost" onClick={() => { setStep("filter"); setRows([]); setMinute(""); setReason(""); }}>New batch</Btn> : undefined}>
                {progress.graduated} graduated · {progress.refused} refused · {progress.remaining} waiting. Each record was revalidated as it was graduated; the Bursary and the Students Account Office are told once the batch is done.
              </Note>
            </PBody>
          ) : null}
        </Panel>
      ) : null}

      <Panel title="Batches" right={`${view.batches.length} in ${scope.session}`}>
        {view.batches.length ? (
          <DTable pageSize={10}
            cols={["Batch", "Minute", "For", "Selected|num", "Eligible|num", "Graduated|num", "Rejected|num", "Review|num", "State", "By", "|num"]}
            rows={view.batches.map((b) => [
              <b key="r" className="tnum">{b.batch_ref}</b>, <span key="m">{b.senate_minute}</span>, <span key="f" className="sub2">{b.reason}</span>,
              <span key="s" className="tnum">{b.selected}</span>, <span key="e" className="tnum">{b.eligible}</span>, <span key="g" className="tnum">{b.graduated}</span>,
              <span key="j" className="tnum">{b.rejected}</span>, <span key="v" className="tnum">{b.review}</span>,
              <Pil key="st" kind={batchState(b)[1]}>{batchState(b)[0]}</Pil>,
              <span key="by" className="sub2">{b.created_by_name ?? b.actor_office} · {new Date(b.created_at).toLocaleDateString("en-GB")}</span>,
              <Btn key="o" kind="ghost" size="sm" onClick={() => void openDetail(b.batch_ref)}>Open</Btn>,
            ])}
            texts={view.batches.map((b) => `${b.batch_ref} ${b.senate_minute} ${b.reason}`)}
          />
        ) : <PBody><div className="sub2">No graduation batch for {scope.session} yet. The session&rsquo;s whole list is still approved on the Graduation screen; a batch confirms chosen students on the same minute.</div></PBody>}
      </Panel>

      {detail ? (
        <Panel title={`${detail.batch_ref} · ${detail.session} · minute ${detail.senate_minute}`} right={<Btn kind="ghost" size="sm" onClick={() => setDetail(null)}>Close</Btn>}>
          <PBody><div className="sub2">{detail.reason} · {detail.selected} selected, {detail.eligible} eligible, {detail.graduated} graduated, {detail.rejected} rejected, {detail.review} requiring review.</div></PBody>
          <DTable pageSize={25}
            cols={["Student", "Programme", "Level|num", "Status now", "Verdict", "Outcome", "|num"]}
            rows={(detail.rows ?? []).map((r: BatchRow) => [
              <Two key="s" a={r.name} b={r.number} />, <span key="p">{r.programme ?? "—"}</span>, <span key="l" className="tnum">{r.level}</span>, <span key="st">{r.status}</span>,
              <Pil key="v" kind={verdictKind(r.verdict)}>{verdictWord(r.verdict)}</Pil>,
              <Pil key="o" kind={outcomeWord(r)[1]}>{outcomeWord(r)[0]}</Pil>,
              <span key="a" className="row row--tight">
                <LinkBtn kind="ghost" href={`/students/${r.student_id}`}>View</LinkBtn>
                {registrar && r.outcome === "GRADUATED" && r.status === "GRADUATED" ? <Btn kind="ghost" size="sm" onClick={() => setCorrect({ id: r.student_id, name: r.name })}>Correct…</Btn> : null}
              </span>,
            ])}
            texts={(detail.rows ?? []).map((r: BatchRow) => `${r.number} ${r.name} ${r.verdict} ${r.outcome ?? ""} ${r.reason ?? ""}`)}
          />
        </Panel>
      ) : null}

      {correct ? (
        <Panel title={`Graduation correction — ${correct.name}`} right={<Btn kind="ghost" size="sm" onClick={() => setCorrect(null)}>Cancel</Btn>}>
          <PBody>
            <Note kind="bad" title="An erroneous graduation is put right on a reason and evidence, by the Registrar">
              The status goes back to ACTIVE with its history; the list entry is referred; the impact on documents, transcript requests and the final clearance is recorded. A degree certificate that stands must be revoked first.
            </Note>
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end", marginTop: "var(--s-2)" }}>
              <Field id="gc-reason" label="Reason (at least ten characters)"><input id="gc-reason" className="ctl" value={cReason} onChange={(e) => setCReason(e.target.value)} maxLength={300} style={{ minWidth: 320 }} /></Field>
              <Field id="gc-evidence" label="Evidence — the minute, the letter or the decision"><input id="gc-evidence" className="ctl" value={cEvidence} onChange={(e) => setCEvidence(e.target.value)} maxLength={200} style={{ minWidth: 280 }} /></Field>
              <Btn kind="urgent" disabled={busy || cReason.trim().length < 10 || !cEvidence.trim()} onClick={() => void sendCorrection()}>{busy ? "Working…" : "Put the graduation right"}</Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Graduation reports" right={
        <span className="row row--tight">
          <select className="ctl" value={reportBy} onChange={(e) => void loadReport(e.target.value)} aria-label="Group the report by">
            {REPORT_BY.map(([k, w]) => <option key={k} value={k}>{w}</option>)}
          </select>
          {!report ? <Btn kind="ghost" size="sm" onClick={() => void loadReport(reportBy)}>Load</Btn> : null}
          {report && report.length ? (
            <>
              <Btn kind="ghost" size="sm" onClick={() => void brandedXlsx(`Graduated students by ${reportLabel.toLowerCase()}`, reportHeaders, reportRows, { serial: docSerial("GRAD"), meta: reportMeta })
                .then((b) => downloadBlob(b, `graduation-by-${reportBy}-${scope.session.replace("/", "-")}.xlsx`))}>Excel</Btn>
              <Btn kind="ghost" size="sm" onClick={() => brandedPrint(`Graduated students by ${reportLabel.toLowerCase()}`, `Graduation session ${scope.session}`, reportHeaders, reportRows, docSerial("GRAD"), { meta: reportMeta, orientation: "landscape" })}>PDF</Btn>
            </>
          ) : null}
        </span>
      }>
        {report ? (
          report.length ? (
            <DTable pageSize={0} cols={[reportLabel, "Graduated|num", "From SP1|num", "From SP2|num", "Normal|num", "Cleared|num", "Clearance pending|num", "Not started|num", "By batch|num"]}
              rows={report.map((r) => [<b key="l">{String(r.label)}</b>, ...["graduated", "sp1", "sp2", "normal", "cleared", "clearance_pending", "clearance_not_started", "by_batch"].map((k) => <span key={k} className="tnum">{String(r[k] ?? 0)}</span>)])} />
          ) : <PBody><div className="sub2">No graduate of {scope.session} within the scope yet.</div></PBody>
        ) : <PBody><div className="sub2">Graduated students of the session counted by faculty, department, programme, year of entry, matriculation year or the spillover state they graduated from, with their final clearance. S/N first on the Excel and the PDF.</div></PBody>}
      </Panel>
    </>
  );
}
