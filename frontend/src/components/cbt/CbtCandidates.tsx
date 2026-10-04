"use client";
/** The candidates of a CBT examination (V322): every student registered on the offering with their GST standing, eligibility and attempt —
 *  paged and filtered on the server, a candidate opened for their attempts, events and result versions, an attempt terminated with a reason. */
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, KvGrid, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { ATTEMPT_WORD, EVENT_WORD, clock, liveStatus, num, pct1, whenAt, type Candidate, type CandidateDetail, type CandidatePage, type CbtExam } from "@/lib/cbt";
import { cbtSend } from "./CbtExam";

export interface CandidateFilters { status: string; fac: string; dept: string; prog: string; level: string; q: string; sort: string }
export const NO_FILTERS: CandidateFilters = { status: "", fac: "", dept: "", prog: "", level: "", q: "", sort: "name" };

export const candidateQuery = (f: CandidateFilters, page: number, size: number) => {
  const p = new URLSearchParams();
  for (const k of ["status", "fac", "dept", "prog", "level", "q", "sort"] as const) if (f[k]) p.set(k, f[k]);
  p.set("page", String(page)); p.set("size", String(size));
  return p.toString();
};

/** every page of a filtered candidate list, for an export */
export async function allCandidates(examId: string, f: CandidateFilters, path = "candidates"): Promise<Candidate[]> {
  const out: Candidate[] = [];
  for (let page = 1; page < 200; page++) {
    const r = await fetch(`/api/bff/api/v1/cbt/exams/${examId}/${path}?${candidateQuery(f, page, 500)}`);
    const j = (await r.json()) as CandidatePage;
    if (!r.ok) throw new Error((j as unknown as Problem).title ?? r.statusText);
    out.push(...j.rows);
    if (out.length >= j.total || !j.rows.length) break;
  }
  return out;
}

export function CandidateFilterBar({ f, set, options, exam }: { f: CandidateFilters; set: (p: Partial<CandidateFilters>) => void; options: CandidatePage["options"] | null; exam: { violation_limit: number } }) {
  const departments = options ? options.departments.filter((d) => !f.fac || d.faculty_code === f.fac) : [];
  const programmes = options ? options.programmes.filter((p) => !f.dept || p.dept_code === f.dept) : [];
  return (
    <div className="grid grid--4">
      <Field id="cf-status" label="Status"><select id="cf-status" className="ctl" value={f.status} onChange={(e) => set({ status: e.target.value })}>
        <option value="">All</option><option value="IN_PROGRESS">Writing</option><option value="SUBMITTED">Submitted</option><option value="NOT_STARTED">Not started</option><option value="TIME_EXPIRED">Time expired</option>
        <option value="DISCONNECTED">Disconnected</option><option value="WARNED">With a warning</option><option value="CRITICAL">Violations at the limit of {exam.violation_limit}</option><option value="TERMINATED">Terminated</option>
        <option value="INELIGIBLE">Not eligible</option><option value="PASSED">Passed</option><option value="FAILED">Failed</option></select></Field>
      <Field id="cf-fac" label="Faculty"><select id="cf-fac" className="ctl" value={f.fac} onChange={(e) => set({ fac: e.target.value, dept: "", prog: "" })}><option value="">All</option>{(options?.faculties ?? []).map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
      <Field id="cf-dept" label="Department"><select id="cf-dept" className="ctl" value={f.dept} onChange={(e) => set({ dept: e.target.value, prog: "" })}><option value="">All</option>{departments.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
      <Field id="cf-prog" label="Programme"><select id="cf-prog" className="ctl" value={f.prog} onChange={(e) => set({ prog: e.target.value })}><option value="">All</option>{programmes.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
      <Field id="cf-level" label="Level"><select id="cf-level" className="ctl" value={f.level} onChange={(e) => set({ level: e.target.value })}><option value="">All</option>{(options?.levels ?? []).map((x) => <option key={x} value={String(x)}>{x} Level</option>)}</select></Field>
      <Field id="cf-q" label="Search" hint="Name or number"><input id="cf-q" className="ctl" value={f.q} onChange={(e) => set({ q: e.target.value })} /></Field>
      <Field id="cf-sort" label="Order"><select id="cf-sort" className="ctl" value={f.sort} onChange={(e) => set({ sort: e.target.value })}><option value="name">Name A–Z</option><option value="score">Score, highest first</option><option value="status">Status</option><option value="started">Started, latest first</option><option value="violations">Violations, most first</option></select></Field>
    </div>
  );
}

export function CandidateModal({ examId, student, canManage, onClose, onChanged, amend }: { examId: string; student: string; canManage: boolean; onClose: () => void; onChanged: () => void; amend?: (attempt: string, max: number) => void }) {
  const [d, setD] = useState<CandidateDetail | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    const r = await fetch(`/api/bff/api/v1/cbt/exams/${examId}/candidates/${student}`);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
    setD(j as CandidateDetail);
  }, [examId, student]);
  useEffect(() => { const t = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(t); }, [load]);
  const c = d?.candidate;
  const running = d?.attempts.find((a) => a.status === "IN_PROGRESS");
  async function terminate() {
    if (!running) return;
    setBusy(true);
    try {
      const j = await cbtSend(`/exams/${examId}/attempts/${running.id}/terminate`, "POST", { reason: reason.trim() }, `Terminate the attempt of ${c?.surname ?? "the candidate"}`);
      if (j) { setReason(""); await load(); onChanged(); }
    } finally { setBusy(false); }
  }
  return (
    <Modal title={c ? `${c.surname}, ${c.other_names}` : "Candidate"} sub={c ? `${c.number} · ${c.programme} · ${c.level} Level` : undefined} wide onClose={onClose}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!d || !c ? <div className="sub2">Loading…</div> : (
        <>
          <KvGrid cls="grid--4" pairs={[
            ["GST entitlement", c.entitled ? <Pil key="e" kind="ok">Paid</Pil> : <Pil key="e" kind="bad">Not paid</Pil>],
            ["Eligible now", c.eligible ? <Pil key="g" kind="ok">Yes</Pil> : <Pil key="g" kind="bad">No</Pil>],
            ["Attempts", `${c.attempts}`], ["Status", (ATTEMPT_WORD[c.attempt_status] ?? [c.attempt_status])[0]],
          ]} />
          <Panel title="Attempts">
            {d.attempts.length ? <DTable cols={["#|mid", "Status|mid", "Started", "Ends", "Submitted", "Answered|num", "Violations|num", "Score|num", "%|num", "Grade|mid", "Connection", "Ended"]} rows={d.attempts.map((a) => [
              <span key="n" className="tnum">{a.number}</span>, <Pil key="s" kind={(ATTEMPT_WORD[a.status] ?? ["", "grey"])[1]}>{(ATTEMPT_WORD[a.status] ?? [a.status])[0]}</Pil>,
              <span key="st" className="tnum sub2">{whenAt(a.started_at)}</span>, <span key="en" className="tnum sub2">{whenAt(a.ends_at)}</span>, <span key="su" className="tnum sub2">{whenAt(a.submitted_at)}</span>,
              <span key="an" className="tnum">{a.answered}/{a.questions}</span>, <span key="v" className={`tnum${a.violations ? " ink-red" : ""}`}>{a.violations}</span>,
              <span key="sc" className="tnum">{a.score == null ? "—" : `${a.score}/${a.max_marks}`}</span>, <span key="p" className="tnum">{pct1(a.percentage)}</span>, <span key="g" className="tnum">{a.grade ?? "—"}{a.outcome === "VOID" ? " (void)" : ""}</span>,
              <span key="ip" className="sub2">{a.ip ?? "—"}<div className="sub2" style={{ maxWidth: 220, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }} title={a.user_agent ?? ""}>{a.user_agent ?? ""}</div></span>,
              <span key="r" className="sub2">{a.finished_reason ?? "—"}</span>,
            ])} /> : <PBody><div className="sub2">No attempt yet.</div></PBody>}
          </Panel>
          <Panel title="Activity record" right={<span className="sub2">Evidence for an authorised officer; never a verdict by itself</span>}>
            {d.events.length ? <DTable pageSize={20} cols={["Time", "Event", "Detail", "IP"]} rows={d.events.map((e, i) => [
              <span key={`t${i}`} className="tnum sub2">{new Date(e.at).toLocaleTimeString("en-GB")}</span>,
              <span key={`k${i}`}>{e.violation ? <Pil kind="bad">{EVENT_WORD[e.kind] ?? e.kind}</Pil> : <span>{EVENT_WORD[e.kind] ?? e.kind}</span>}</span>,
              <span key={`d${i}`} className="sub2">{e.detail ?? ""}</span>, <span key={`i${i}`} className="sub2 tnum">{e.ip ?? ""}</span>,
            ])} /> : <PBody><div className="sub2">Nothing recorded.</div></PBody>}
          </Panel>
          {d.versions.length ? (
            <Panel title="Result versions" right={amend && canManage && c.attempt_id && c.attempt_status !== "IN_PROGRESS" ? <Btn kind="secondary" size="sm" onClick={() => amend(c.attempt_id as string, c.max_marks ?? 0)}>Amend the score</Btn> : null}>
              <DTable cols={["Version|mid", "Score|num", "%|num", "Grade|mid", "Outcome|mid", "Reason", "By", "When"]} rows={d.versions.map((v) => [
                <span key="v" className="tnum">{v.version}</span>, <span key="s" className="tnum">{v.score}/{v.max_marks}</span>, <span key="p" className="tnum">{pct1(v.percentage)}</span>,
                <span key="g" className="tnum">{v.grade ?? "—"}</span>, <Pil key="o" kind={v.outcome === "VOID" ? "bad" : v.passed ? "ok" : "warn"}>{v.outcome === "VOID" ? "Void" : v.passed ? "Pass" : "Fail"}</Pil>,
                <span key="r" className="sub2">{v.reason ?? (v.version === 1 ? "Automatic scoring" : "")}</span>, <span key="b" className="sub2">{v.changed_by ?? "—"}{v.changed_office ? ` · ${v.changed_office}` : ""}</span>, <span key="w" className="tnum sub2">{whenAt(v.changed_at)}</span>,
              ])} />
            </Panel>
          ) : null}
          {canManage && running ? (
            <Panel title="Terminate the running attempt" right={<Pil kind="bad">Irreversible</Pil>}>
              <PBody>
                <div className="sub2 mb-2">The attempt ends now and is scored from the answers saved so far, marked terminated with your reason. The candidate&rsquo;s screen is told at its next heartbeat.</div>
                <Field id="cd-reason" label="Reason" required><textarea id="cd-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
                <Btn kind="urgent" disabled={busy || !reason.trim()} onClick={() => void terminate()}>{busy ? "Terminating…" : "Terminate the attempt"}</Btn>
              </PBody>
            </Panel>
          ) : null}
        </>
      )}
    </Modal>
  );
}

export function CbtCandidates({ exam, canManage }: { exam: CbtExam; base: string; canManage: boolean }) {
  const router = useRouter();
  const [f, setF] = useState<CandidateFilters>(NO_FILTERS);
  const [page, setPage] = useState(1);
  const [data, setData] = useState<CandidatePage | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    const r = await fetch(`/api/bff/api/v1/cbt/exams/${exam.id}/candidates?${candidateQuery(f, page, 50)}`);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
    setProblem(null); setData(j as CandidatePage);
  }, [exam.id, f, page]);
  useEffect(() => { const t = window.setTimeout(() => void load(), f.q ? 300 : 0); return () => window.clearTimeout(t); }, [load, f.q]);
  const set = (p: Partial<CandidateFilters>) => { setF({ ...f, ...p }); setPage(1); };
  /* the server's clock as the page read it; before the first read nobody is judged disconnected */
  const serverNow = data ? new Date(data.now).getTime() : 0;
  const pages = data ? Math.max(1, Math.ceil(data.total / data.size)) : 1;

  const HEAD = ["S/N", "Matric No", "Student", "Faculty", "Department", "Programme", "Level", "GST paid", "Eligible", "Status", "Started", "Submitted", "Answered", "Violations", "Score", "%", "Grade"];
  async function exportAs(kind: "xlsx" | "pdf") {
    setBusy(true);
    try {
      const rows = await allCandidates(exam.id, { ...f, sort: "name" });
      const body = rows.map((c, i) => [i + 1, c.number, `${c.surname}, ${c.other_names}`, c.faculty, c.department, c.programme, c.level, c.entitled ? "Yes" : "No", c.eligible ? "Yes" : "No",
        (ATTEMPT_WORD[liveStatus(c.attempt_status, c.last_activity_at, serverNow)] ?? [c.attempt_status])[0], c.started_at ? whenAt(c.started_at) : "", c.submitted_at ? whenAt(c.submitted_at) : "",
        c.answered, c.violations, c.score == null ? "" : Number(c.score), c.percentage == null ? "" : Number(c.percentage), c.grade ?? ""]);
      const title = `${exam.course_code} CBT Candidates`;
      const sub = `${exam.title} · ${exam.reference} · ${exam.session}`;
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, HEAD, body, { sheetName: "Candidates", serial: docSerial("CBT"), sub }), `${exam.reference.replace(/\//g, "-")}-candidates.xlsx`);
      else brandedPrint(title, sub, HEAD, body);
    } catch (e) { notifyProblem({ status: 500, title: "The export could not be built", detail: e instanceof Error ? e.message : String(e) }); }
    finally { setBusy(false); }
  }

  return (
    <>
      <Panel title="Filters" right={<span className="row row--inline row--tight"><Btn kind="secondary" size="sm" disabled={busy || !data?.total} onClick={() => void exportAs("xlsx")}>Excel</Btn><Btn kind="ghost" size="sm" disabled={busy || !data?.total} onClick={() => void exportAs("pdf")}>PDF</Btn></span>}>
        <PBody><CandidateFilterBar f={f} set={set} options={data?.options ?? null} exam={exam} /></PBody>
      </Panel>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {data && !data.total ? <Note kind="info" title="No candidate for these filters">A candidate is a student registered on the offering with a submitted registration. Widen the filters.</Note> : null}
      <Panel title={`Candidates · ${data ? num(data.total) : "…"}`} right={data && pages > 1 ? <span className="row row--inline row--tight sub2"><Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn>Page {page} of {pages}<Btn kind="ghost" size="sm" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</Btn></span> : null}>
        {data ? <DTable noPrint cols={["S/N|num", "Student", "Programme", "Level|mid", "GST|mid", "Eligible|mid", "Status|mid", "Time left|mid", "Answered|num", "Violations|num", "Score|num", "Grade|mid", "|num"]} rows={data.rows.map((c, i) => {
          const st = liveStatus(c.attempt_status, c.last_activity_at, serverNow);
          return [
            <span key="n" className="tnum sub2">{(page - 1) * data.size + i + 1}</span>,
            <span key="s"><b>{c.surname}, {c.other_names}</b><div className="sub2 tnum">{c.number}</div></span>,
            <span key="p" className="sub2">{c.programme}<div>{c.department}</div></span>, <span key="l" className="tnum">{c.level}</span>,
            <Pil key="e" kind={c.entitled ? "ok" : "bad"}>{c.entitled ? "Paid" : "Unpaid"}</Pil>, <Pil key="g" kind={c.eligible ? "ok" : "grey"}>{c.eligible ? "Yes" : "No"}</Pil>,
            <Pil key="st" kind={(ATTEMPT_WORD[st] ?? ["", "grey"])[1]}>{(ATTEMPT_WORD[st] ?? [st])[0]}</Pil>,
            <span key="t" className="tnum">{c.attempt_status === "IN_PROGRESS" && c.time_left != null ? clock(c.time_left) : "—"}</span>,
            <span key="a" className="tnum">{c.attempt_id ? c.answered : "—"}</span>, <span key="v" className={`tnum${c.violations >= exam.violation_limit && c.violations ? " ink-red b600" : c.violations ? " ink-red" : ""}`}>{c.violations}</span>,
            <span key="sc" className="tnum">{c.score == null ? "—" : `${c.score}/${c.max_marks} · ${pct1(c.percentage)}`}</span>, <span key="gr" className="tnum">{c.grade ?? "—"}{c.outcome === "VOID" ? " void" : ""}</span>,
            <Btn key="o" kind="ghost" size="sm" onClick={() => setOpen(c.student_id)}>Open</Btn>,
          ];
        })} texts={data.rows.map((c) => `${c.surname} ${c.other_names} ${c.number} ${c.attempt_status}`)} /> : <PBody><div className="sub2">Loading…</div></PBody>}
      </Panel>
      {open ? <CandidateModal examId={exam.id} student={open} canManage={canManage} onClose={() => setOpen(null)} onChanged={() => { void load(); router.refresh(); }} /> : null}
    </>
  );
}
