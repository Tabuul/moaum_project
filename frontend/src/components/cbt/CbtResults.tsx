"use client";
/** The results of a CBT examination (V322): every score the moment it exists, the sitting's figures, the workflow — auto-scored, under review,
 *  approved, published — an amendment with its reason (stronger authority once published), the scores onto the course's score sheet,
 *  the analytics by faculty, department, programme, level and grade, the score distribution, and the exports. */
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Donut, GroupBars, HBars, VZ } from "@/components/proto/vz";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { ATTEMPT_WORD, RESULTS_WORD, num, pct1, whenAt, type CbtExam, type Group, type ResultsPage } from "@/lib/cbt";
import { cbtSend } from "./CbtExam";
import { CandidateFilterBar, CandidateModal, NO_FILTERS, allCandidates, candidateQuery, type CandidateFilters } from "./CbtCandidates";

export function CbtResults({ exam, canManage, stronger }: { exam: CbtExam; base: string; canManage: boolean; stronger: boolean }) {
  const router = useRouter();
  const [f, setF] = useState<CandidateFilters>({ ...NO_FILTERS, sort: "name" });
  const [page, setPage] = useState(1);
  const [data, setData] = useState<ResultsPage | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [amend, setAmend] = useState<{ attempt: string; max: number } | null>(null);
  const [amendForm, setAmendForm] = useState({ score: "", outcome: "SCORED", reason: "" });
  const [ask, setAsk] = useState<{ action: string; title: string; text: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    const r = await fetch(`/api/bff/api/v1/cbt/exams/${exam.id}/results?${candidateQuery(f, page, 100)}`);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
    setProblem(null); setData(j as ResultsPage);
  }, [exam.id, f, page]);
  useEffect(() => { const t = window.setTimeout(() => void load(), f.q ? 300 : 0); return () => window.clearTimeout(t); }, [load, f.q]);
  const set = (p: Partial<CandidateFilters>) => { setF({ ...f, ...p }); setPage(1); };
  const rs = exam.results_state;
  const stats = data?.stats ?? exam.stats;
  const pages = data ? Math.max(1, Math.ceil(data.total / data.size)) : 1;

  async function run(work: () => Promise<Record<string, unknown> | null>) {
    setBusy(true);
    try { const j = await work(); if (j) { await load(); router.refresh(); } } finally { setBusy(false); }
  }
  const workflow = (action: string) => run(() => cbtSend(`/exams/${exam.id}/results/${action}`, "POST", {}, `${action.charAt(0).toUpperCase() + action.slice(1)} the results of ${exam.reference}`));
  const toSheet = () => run(async () => {
    const j = await cbtSend(`/exams/${exam.id}/results/to-sheet`, "POST", {}, `Send the ${exam.reference} scores to the ${exam.course_code} score sheet`);
    if (j) notifyProblem({ status: 200, title: `${j.written} score${j.written === 1 ? "" : "s"} written to the score sheet as the examination component` });
    return j;
  });
  const doAmend = () => {
    if (!amend) return;
    const a = amend;
    void run(async () => {
      const j = await cbtSend(`/exams/${exam.id}/attempts/${a.attempt}/result`, "PUT", { score: Number(amendForm.score), outcome: amendForm.outcome, reason: amendForm.reason.trim() }, `Amend a ${exam.reference} score: ${amendForm.reason.trim()}`);
      if (j) setAmend(null);
      return j;
    });
  };

  const HEAD = ["S/N", "Matric No", "Student", "Faculty", "Department", "Programme", "Level", "Score", "Max", "%", "Grade", "Status"];
  async function exportAs(kind: "xlsx" | "pdf") {
    setBusy(true);
    try {
      const rows = (await allCandidates(exam.id, { ...f, sort: "name" }, "results")).filter((c) => c.attempt_id);
      const body = rows.map((c, i) => [i + 1, c.number, `${c.surname}, ${c.other_names}`, c.faculty, c.department, c.programme, c.level, c.score == null ? "" : Number(c.score), c.max_marks ?? "", c.percentage == null ? "" : Number(c.percentage), c.grade ?? "",
        c.outcome === "VOID" ? "Void" : c.percentage == null ? (ATTEMPT_WORD[c.attempt_status] ?? [c.attempt_status])[0] : c.passed ? "Pass" : "Fail"]);
      const title = `${exam.course_code} CBT Results`;
      const sub = `${exam.title} · ${exam.reference} · ${exam.session} · results ${(RESULTS_WORD[rs] ?? [rs])[0].toLowerCase()}`;
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, HEAD, body, { sheetName: "Results", serial: docSerial("CBT"), sub }), `${exam.reference.replace(/\//g, "-")}-results.xlsx`);
      else brandedPrint(title, sub, HEAD, body);
    } catch (e) { notifyProblem({ status: 500, title: "The export could not be built", detail: e instanceof Error ? e.message : String(e) }); }
    finally { setBusy(false); }
  }
  const groupRows = (gs: Group[], name: (g: Group) => string) => gs.map((g) => ({ l: name(g), v: [Number(g.candidates), Number(g.scored), Number(g.passed)], key: name(g) }));
  const keys = [{ l: "Candidates", c: VZ.axis }, { l: "Scored", c: VZ.s1 }, { l: "Passed", c: VZ.good }];
  const groupTable = (title: string, gs: Group[], name: (g: Group) => string) => (
    <Panel title={title}>
      <PBody>{gs.length ? <GroupBars rows={groupRows(gs, name)} keys={keys} /> : <div className="sub2">Nothing to show.</div>}</PBody>
      {gs.length ? <DTable cols={["S/N|num", title.replace(/^By /, ""), "Candidates|num", "Started|num", "Completed|num", "Scored|num", "Average|num", "Highest|num", "Lowest|num", "Passed|num", "Failed|num", "Pass rate|num"]} rows={gs.map((g, i) => [
        <span key="n" className="tnum sub2">{i + 1}</span>, <b key="l">{name(g)}</b>, <span key="c" className="tnum">{num(g.candidates)}</span>, <span key="s" className="tnum">{num(g.started)}</span>, <span key="co" className="tnum">{num(g.completed)}</span>,
        <span key="sc" className="tnum">{num(g.scored)}</span>, <span key="a" className="tnum">{pct1(g.average)}</span>, <span key="h" className="tnum">{pct1(g.highest)}</span>, <span key="lo" className="tnum">{pct1(g.lowest)}</span>,
        <span key="p" className="tnum ink-green">{num(g.passed)}</span>, <span key="f" className="tnum ink-red">{num(g.failed)}</span>, <span key="r" className="tnum">{g.scored ? pct1((Number(g.passed) * 100) / Number(g.scored)) : "—"}</span>,
      ])} /> : null}
    </Panel>
  );

  return (
    <>
      <Tiles items={[
        ["CANDIDATES", num(stats.candidates), null, `${num(stats.not_started)} never started`],
        ["COMPLETED", num(stats.completed), null, `${num(stats.submitted)} submitted · ${num(stats.time_expired)} expired · ${num(stats.terminated)} terminated`],
        ["SCORES PROCESSED", num(stats.scored), "var(--green-ink)", "Automatic, at submission"],
        ["AVERAGE", pct1(stats.average), null, `Highest ${pct1(stats.highest)} · lowest ${pct1(stats.lowest)}`],
        ["PASS", num(stats.passed), stats.passed ? "var(--green-ink)" : null, `Pass mark ${pct1(exam.pass_mark)}`],
        ["FAIL", num(stats.failed), stats.failed ? "var(--red-ink)" : null, `${num(stats.void)} void`],
        ["PASS RATE", stats.scored ? pct1((Number(stats.passed) * 100) / Number(stats.scored)) : "—", null, "Of scores processed"],
        ["RESULTS", (RESULTS_WORD[rs] ?? [rs])[0], rs === "PUBLISHED" ? "var(--green-ink)" : null, exam.results_published_at ? `Published ${whenAt(exam.results_published_at)}` : exam.results_approved_at ? `Approved ${whenAt(exam.results_approved_at)}` : "Students see nothing until published"],
      ]} />
      <Panel title="Result workflow" right={<Pil kind={(RESULTS_WORD[rs] ?? ["", "grey"])[1]}>{(RESULTS_WORD[rs] ?? [rs])[0]}</Pil>}>
        <PBody>
          <div className="sub2 mb-2">Scores are computed the moment an attempt ends and the office sees them at once. A student sees a result only once it is published. Auto-scored → under review → approved → published; approval needs the examination completed. Once published, a score changes, or the publication is withdrawn, only with the Registrar or the Super Administrator.</div>
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            {canManage && (rs === "PENDING" || rs === "AUTO_SCORED") ? <Btn kind="secondary" disabled={busy} onClick={() => void workflow("review")}>Start the review</Btn> : null}
            {canManage && (rs === "AUTO_SCORED" || rs === "UNDER_REVIEW") ? <Btn kind="primary" disabled={busy || exam.state !== "COMPLETED"} onClick={() => setAsk({ action: "approve", title: "Approve the results", text: "The scores as they stand are approved. Publication follows as a separate act." })}>Approve</Btn> : null}
            {canManage && rs === "APPROVED" ? <Btn kind="go" disabled={busy} onClick={() => setAsk({ action: "publish", title: "Publish the results", text: "Every candidate who sat the examination is told by e-mail and sees their score, percentage, grade and pass/fail on the portal." })}>Publish to students</Btn> : null}
            {stronger && rs === "PUBLISHED" ? <Btn kind="urgent" disabled={busy} onClick={() => setAsk({ action: "unpublish", title: "Withdraw the publication", text: "Students no longer see the results; they return to approved." })}>Withdraw publication</Btn> : null}
            {canManage && (rs === "APPROVED" || rs === "PUBLISHED") ? <Btn kind="secondary" disabled={busy || !exam.has_sheet || exam.sheet_stage !== "ENTRY"} onClick={() => setAsk({ action: "to-sheet", title: "Send the scores to the score sheet", text: `Each candidate's best percentage becomes the examination component of ${exam.course_code} (scaled to ${100 - exam.ca_max} marks) on the course's score sheet, as a new version with this examination named as the reason; a CA already entered is kept, and without one the mark is incomplete until the lecturer enters it. The result pipeline carries it from there.` })}>Send to the score sheet</Btn> : null}
            {canManage && (rs === "APPROVED" || rs === "PUBLISHED") && !exam.has_sheet ? <span className="sub2">No score sheet yet: it opens with the examination session.</span> : null}
            {canManage && exam.has_sheet && exam.sheet_stage && exam.sheet_stage !== "ENTRY" ? <span className="sub2">The score sheet is past entry ({exam.sheet_stage.toLowerCase().replace(/_/g, " ")}).</span> : null}
          </div>
        </PBody>
      </Panel>

      <Panel title="Filters" right={<span className="row row--inline row--tight"><Btn kind="secondary" size="sm" disabled={busy || !data?.total} onClick={() => void exportAs("xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" disabled={busy || !data?.total} onClick={() => void exportAs("pdf")}>PDF</Btn></span>}>
        <PBody><CandidateFilterBar f={f} set={set} options={data?.options ?? null} exam={exam} /></PBody>
      </Panel>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title={`Results · ${data ? num(data.total) : "…"} candidate${data?.total === 1 ? "" : "s"}`} right={data && pages > 1 ? <span className="row row--inline row--tight sub2"><Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn>Page {page} of {pages}<Btn kind="ghost" size="sm" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</Btn></span> : null}>
        {data ? (data.rows.length ? <DTable noPrint cols={["S/N|num", "Matric No", "Student", "Faculty", "Department", "Programme", "Level|mid", "Score|num", "%|num", "Grade|mid", "Status|mid", "|num"]} rows={data.rows.map((c, i) => [
          <span key="n" className="tnum sub2">{(page - 1) * data.size + i + 1}</span>, <span key="m" className="tnum">{c.number}</span>, <b key="s">{c.surname}, {c.other_names}</b>,
          <span key="f" className="sub2">{c.faculty}</span>, <span key="d" className="sub2">{c.department}</span>, <span key="p" className="sub2">{c.programme}</span>, <span key="l" className="tnum">{c.level}</span>,
          <span key="sc" className="tnum">{c.score == null ? "—" : `${c.score}/${c.max_marks}`}</span>, <span key="pc" className="tnum">{pct1(c.percentage)}</span>, <b key="g" className="tnum">{c.grade ?? "—"}</b>,
          c.outcome === "VOID" ? <Pil key="st" kind="bad">Void</Pil> : c.percentage == null ? <Pil key="st" kind={(ATTEMPT_WORD[c.attempt_status] ?? ["", "grey"])[1]}>{(ATTEMPT_WORD[c.attempt_status] ?? [c.attempt_status])[0]}</Pil> : c.passed ? <Pil key="st" kind="ok">Pass</Pil> : <Pil key="st" kind="warn">Fail</Pil>,
          <span key="o" className="row row--inline row--tight"><Btn kind="ghost" size="sm" onClick={() => setOpen(c.student_id)}>Open</Btn>{(canManage && rs !== "PUBLISHED") || stronger ? (c.attempt_id && c.attempt_status !== "IN_PROGRESS" ? <Btn kind="ghost" size="sm" onClick={() => { setAmendForm({ score: c.score == null ? "" : String(c.score), outcome: c.outcome ?? "SCORED", reason: "" }); setAmend({ attempt: c.attempt_id as string, max: c.max_marks ?? 0 }); }}>Amend</Btn> : null) : null}</span>,
        ])} texts={data.rows.map((c) => `${c.surname} ${c.other_names} ${c.number} ${c.grade ?? ""}`)} /> : <PBody><div className="sub2">No candidate for these filters.</div></PBody>) : <PBody><div className="sub2">Loading…</div></PBody>}
      </Panel>

      {data ? (
        <>
          <div className="grid grid--2">
            <Panel title="Pass / fail"><PBody><Donut items={[{ l: "Passed", v: Number(stats.passed), c: VZ.good }, { l: "Failed", v: Number(stats.failed), c: VZ.crit }, { l: "Void", v: Number(stats.void), c: VZ.axis }, { l: "Not scored", v: Number(stats.candidates) - Number(stats.scored), c: VZ.warn }]} capLabel="candidates" capValue={num(stats.candidates)} /></PBody></Panel>
            <Panel title="Grade distribution"><PBody>{data.byGrade.length ? <HBars items={data.byGrade.map((g) => ({ l: g.grade ?? "—", v: Number(g.scored) }))} colour={VZ.s1} /> : <div className="sub2">No score yet.</div>}</PBody></Panel>
          </div>
          <div className="grid grid--2">
            <Panel title="Score distribution" right={<span className="sub2">by 10-point band</span>}><PBody>{data.buckets.length ? <HBars items={data.buckets.map((b) => ({ l: `${b.low}–${b.high}%`, v: Number(b.n) }))} colour={VZ.s3} /> : <div className="sub2">No score yet.</div>}</PBody></Panel>
            <Panel title="Participation"><PBody><Donut items={[{ l: "Submitted", v: Number(stats.submitted), c: VZ.good }, { l: "Time expired", v: Number(stats.time_expired), c: VZ.warn }, { l: "Terminated", v: Number(stats.terminated), c: VZ.crit }, { l: "Not started", v: Number(stats.not_started), c: VZ.axis }]} capLabel="candidates" capValue={num(stats.candidates)} />
              <KvGrid cls="grid--3" pairs={[["Eligible", num(data.totals.eligible)], ["Disconnected now", num(data.totals.disconnected)], ["Writing now", num(data.totals.in_progress)]]} /></PBody></Panel>
          </div>
          {groupTable("By faculty", data.byFaculty, (g) => g.faculty ?? "")}
          {groupTable("By department", data.byDepartment, (g) => g.department ?? "")}
          {groupTable("By programme", data.byProgramme, (g) => g.programme ?? "")}
          {groupTable("By level", data.byLevel, (g) => `${g.level} Level`)}
        </>
      ) : null}
      {!data?.total && data ? <Note kind="info" title="Nothing scored yet">Scores appear here the moment candidates submit.</Note> : null}

      {open ? <CandidateModal examId={exam.id} student={open} canManage={canManage} onClose={() => setOpen(null)} onChanged={() => { void load(); router.refresh(); }} amend={(canManage && rs !== "PUBLISHED") || stronger ? (attempt, max) => { setOpen(null); setAmendForm({ score: "", outcome: "SCORED", reason: "" }); setAmend({ attempt, max }); } : undefined} /> : null}
      {amend ? (
        <Modal title="Amend a score" sub={rs === "PUBLISHED" ? "The results are published: this is the Registrar's or the Super Administrator's act" : "A new version with its reason; the old one is kept"} onClose={() => setAmend(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setAmend(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || amendForm.score === "" || !amendForm.reason.trim()} onClick={doAmend}>Record the amendment</Btn></span>}>
          <div className="grid grid--2">
            <Field id="am-score" label={`Score (0 to ${amend.max})`} required><input id="am-score" className="ctl tnum" inputMode="decimal" value={amendForm.score} onChange={(e) => setAmendForm({ ...amendForm, score: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
            <Field id="am-out" label="Outcome"><select id="am-out" className="ctl" value={amendForm.outcome} onChange={(e) => setAmendForm({ ...amendForm, outcome: e.target.value })}><option value="SCORED">Scored</option><option value="VOID">Void (malpractice or an invalid sitting)</option></select></Field>
          </div>
          <Field id="am-reason" label="Reason" required hint="On the record with your name and office"><textarea id="am-reason" className="ctl" rows={3} value={amendForm.reason} onChange={(e) => setAmendForm({ ...amendForm, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}
      {ask ? (
        <Modal title={ask.title} sub={exam.reference} onClose={() => setAsk(null)} foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setAsk(null)}>Back</Btn><Btn kind={ask.action === "unpublish" ? "urgent" : "primary"} disabled={busy} onClick={() => { const a = ask.action; setAsk(null); if (a === "to-sheet") void toSheet(); else void workflow(a); }}>{ask.title}</Btn></span>}>
          <p>{ask.text}</p>
        </Modal>
      ) : null}
    </>
  );
}
