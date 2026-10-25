"use client";

/** V652: Examination Attendance — the courses of the scope (ClassList), then a class: the list marked after the paper, the handwritten
 *  rows of the manual / late registration section entered (matched by the number written, or held for verification), the rows pending
 *  verification decided, the reconciliation, and the attendance sheet's versions. The API holds every act to the office's scope. */
import Link from "next/link";
import { useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tabs, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, downloadBlob } from "@/lib/exportbrand";
import { CATEGORY_WORD, MANUAL_PRESETS, manualLines, semWord, words, type CourseRow } from "@/lib/course-registration-report";
import {
  ELIGIBILITY_WORD, FINDINGS, FINDING_WORD, STATUSES, STATUS_WORD, changedMarks, clock, examDay, scopeWords,
  type Marking, type PendingRow, type Reconciliation, type SheetRow,
} from "@/lib/exam-attendance";

export type Tab = "mark" | "manual" | "pending" | "reconcile" | "sheets";

const BASE = "/api/bff/api/v1/exams/attendance";
const n = (v: number | null | undefined) => Number(v ?? 0).toLocaleString("en-GB");
const pdfOf = (refs: string[]) => `/exams/attendance/sheets/pdf?${refs.map((r) => `ref=${encodeURIComponent(r)}`).join("&")}`;

const MANUAL_REASONS = ["Late registration", "Late school-fee payment", "Recently approved registration", "Recently added carry-over course",
  "Delayed system synchronisation", "Registration correction", "Other"];

function useCall() {
  const [problem, setProblem] = useState<Problem | null>(null);
  async function call<T>(path: string, method: "GET" | "POST", body: unknown, why: string): Promise<T | null> {
    setProblem(null);
    const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: body === undefined ? undefined : JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) {
      const p = j ?? { status: r.status, title: r.statusText };
      setProblem(p); notifyProblem(p);
      return null;
    }
    return j as T;
  }
  return { problem, call };
}

/** the courses of the scope, each opening its class */
export function ClassList({ scope, structure, sessions, ceiling, session, semester, rows }: {
  scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling; session: string; semester: number | null; rows: CourseRow[];
}) {
  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} what="courses" count={rows.length} of={rows.length} />
      <Panel title="Examination attendance" right={`${session} · ${semester ? `${semWord(semester)} Semester` : "Every semester"}`}>
        <PBody>
          <div className="sub2">
            Choose a course to mark its list after the paper, enter the handwritten rows of the manual / late registration section, verify those not identified and reconcile it.
            The sheets are issued from the <Link className="lnk" href="/reports/course-registrations">Course Registration Report</Link>, one course or every course ticked.
          </div>
        </PBody>
        {rows.length ? (
          <DTable pageSize={25} noPrint cols={["Course", "Category", "Registered|num", "Card or permit|num", "Latest sheet", "Present|num", "Absent|num", "Manual|num", "Pending|num", ""]}
            rows={rows.map((c) => [
              <Two key="c" a={<b className="tnum">{c.shown_code}</b>} b={c.course_title} />,
              <span key="g" className="sub2">{CATEGORY_WORD[c.category] ?? words(c.category)}</span>,
              <span key="s" className="tnum">{n(c.students)}</span>, <span key="e" className="tnum">{n(c.eligible)}</span>,
              c.sheet_reference ? <Link key="r" className="lnk tnum" href={pdfOf([c.sheet_reference])} target="_blank">{c.sheet_reference}</Link> : <span key="r" className="sub2">None yet</span>,
              <span key="p" className="tnum">{n(c.present)}</span>, <span key="a" className="tnum">{n(c.absent)}</span>,
              <span key="m" className="tnum">{n(c.manual_present)}</span>,
              c.pending ? <Pil key="q" kind="warn">{n(c.pending)}</Pil> : <span key="q" className="sub2 tnum">0</span>,
              <LinkBtn key="o" kind="secondary" href={`/exams/attendance?offering=${c.offering_id}`}>Open</LinkBtn>,
            ])}
            texts={rows.map((c) => `${c.shown_code} ${c.course_code} ${c.course_title}`)} />
        ) : <PBody><div className="sub2">No course registered in this scope.</div></PBody>}
      </Panel>
    </>
  );
}

export function Attendance({ tab, marking, recon, reconProblem, pending, sheets, actorName }: {
  tab: Tab; marking: Marking; recon: Reconciliation | null; reconProblem: Problem | null; pending: PendingRow[]; sheets: SheetRow[]; actorName: string | null;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const { problem, call } = useCall();
  const [busy, setBusy] = useState(false);
  const o = marking.offering;
  const latest = sheets[0] ?? null;
  const [sheetRef, setSheetRef] = useState(latest?.reference ?? "");
  const [invigilator, setInvigilator] = useState("");
  const [chosen, setChosen] = useState<Record<string, string>>(() => Object.fromEntries(marking.students.filter((s) => s.attendance && s.attendance !== "MANUAL_PRESENT").map((s) => [s.student_id, s.attendance!])));
  const [reasons, setReasons] = useState<Record<string, string>>(() => Object.fromEntries(marking.students.filter((s) => s.reason).map((s) => [s.student_id, s.reason!])));
  const [hand, setHand] = useState({ number: "", name: "", programme: "", level: "", reason: MANUAL_REASONS[0], other: "" });
  const [handOut, setHandOut] = useState<Record<string, unknown> | null>(null);
  const [decide, setDecide] = useState<Record<string, { number: string; note: string }>>({});
  const [finding, setFinding] = useState("");
  const [lines, setLines] = useState(String(latest?.manual_lines && MANUAL_PRESETS.includes(latest.manual_lines) ? latest.manual_lines : 10));
  const [custom, setCustom] = useState("");
  const [why, setWhy] = useState("");

  const go = (t: Tab) => {
    const p = new URLSearchParams(params.toString());
    if (t === "mark") p.delete("tab"); else p.set("tab", t);
    router.push(`${pathname}?${p.toString()}`);
  };
  const changes = useMemo(() => changedMarks(marking.students, chosen, reasons), [marking.students, chosen, reasons]);
  const general = o.kind === "GST" && (o.general_office === "GST" || o.general_office === "EPS");
  const pendingOpen = pending.filter((p) => p.state === "PENDING");
  const f = recon?.figures;

  async function saveMarks() {
    if (!changes.length) return;
    setBusy(true);
    try {
      const r = await call<{ recorded: number }>(`${BASE}/${o.offering_id}/marks`, "POST", { marks: changes, sheet: sheetRef || null, invigilator: invigilator.trim() || null },
        `Examination attendance of ${o.shown_code} recorded`);
      if (r) { notify(`${r.recorded} attendance${r.recorded === 1 ? "" : "s"} recorded`); router.refresh(); }
    } finally {
      setBusy(false);
    }
  }

  function unmarkedAbsent() {
    setChosen((c) => {
      const x = { ...c };
      for (const s of marking.students) if (!x[s.student_id] && !s.attendance) x[s.student_id] = "ABSENT";
      return x;
    });
  }

  async function enterHandwritten() {
    setBusy(true);
    try {
      const reason = hand.reason === "Other" ? hand.other.trim() : hand.reason;
      const r = await call<Record<string, unknown>>(`${BASE}/${o.offering_id}/manual`, "POST", {
        number: hand.number.trim() || null, name: hand.name.trim() || null, programme: hand.programme.trim() || null, level: hand.level.trim() || null,
        reason: reason || null, sheet: sheetRef || null, invigilator: invigilator.trim() || null,
      }, `Handwritten attendance row of ${o.shown_code} entered`);
      if (r) {
        setHandOut(r);
        notify(r.outcome === "MATCHED" ? "Matched to the student: manual present" : "Held pending verification");
        setHand((h) => ({ number: "", name: "", programme: "", level: "", reason: h.reason, other: h.other }));
        router.refresh();
      }
    } finally {
      setBusy(false);
    }
  }

  async function decideRow(id: string, valid: boolean) {
    const d = decide[id] ?? { number: "", note: "" };
    setBusy(true);
    try {
      const r = await call<{ outcome: string }>(`${BASE}/pending/${id}/decide`, "POST", { valid, number: valid ? d.number.trim() || null : null, note: d.note.trim() || null },
        valid ? "Handwritten attendance row matched to its student" : "Handwritten attendance row found invalid");
      if (r) { notify(r.outcome === "MATCHED" ? "Matched: manual present, verified" : "Marked invalid"); router.refresh(); }
    } finally {
      setBusy(false);
    }
  }

  async function newVersion() {
    const m = manualLines(lines, custom);
    if (m == null) { notifyProblem({ status: 400, title: "Manual lines are 0 to 60" }); return; }
    setBusy(true);
    try {
      const sc = marking.scope;
      const r = await call<{ sheets: { reference: string }[] }>(`${BASE}/sheets`, "POST",
        { offerings: [o.offering_id], manualLines: m, reason: why.trim() || null, fac: sc.fac, dept: sc.dept, prog: sc.prog, split: "NONE" },
        `Examination attendance sheet of ${o.shown_code} issued`);
      if (r) { notify(`${r.sheets.map((s) => s.reference).join(", ")} issued`); setWhy(""); router.refresh(); }
    } finally {
      setBusy(false);
    }
  }

  async function exportRecon() {
    if (!recon) return;
    const rows = recon.rows.filter((r) => !finding || r.finding === finding);
    const headers = ["Matriculation Number", "Student Name", "Programme", "Level", "Registered", "Card or permit", "On the sheet", "Sheet version", "Attendance", "Source", "Finding"];
    const body = rows.map((r) => [r.matric_no ?? "", r.full_name, r.programme, r.level ?? "", r.registered ? "Yes" : "No", r.eligible ? "Held" : "Not held",
      r.on_list ? "Yes" : "No", r.list_version ? `V${r.list_version}` : "", r.status ? STATUS_WORD[r.status] ?? words(r.status) : "", r.source ? words(r.source) : "", FINDING_WORD[r.finding] ?? words(r.finding)]);
    const meta: [string, string][] = [["Course", `${o.shown_code} — ${o.course_title}`], ["Session", o.session], ["Semester", semWord(o.semester)],
      ["Registered", n(f?.registered)], ["Eligible", n(f?.eligible)], ["On the sheet", n(f?.listed)], ["Present", n(f?.present)], ["Absent", n(f?.absent)],
      ["Manual attendance", n(f?.manual)], ["Pending verification", n(f?.pending)], ...(finding ? [["Finding", FINDING_WORD[finding]] as [string, string]] : []),
      ...(actorName ? [["Generated by", actorName] as [string, string]] : [])];
    downloadBlob(await brandedXlsx(`Attendance reconciliation ${o.shown_code}`, headers, body, { meta }), `attendance-reconciliation-${o.shown_code.replace(/\s+/g, "")}-${o.session.replace("/", "-")}.xlsx`);
  }

  const markedCount = marking.students.filter((s) => s.attendance).length;
  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title={<>{o.shown_code} — {o.course_title}</>} right={<LinkBtn kind="ghost" href="/exams/attendance">Every course</LinkBtn>}>
        <PBody>
          <div className="sub2">
            {o.units} unit{o.units === 1 ? "" : "s"}{o.level ? ` · ${o.level} Level` : ""} · {o.course_department ?? o.course_dept ?? ""} · {o.session} · {semWord(o.semester)} Semester
            {o.exam_on ? ` · ${examDay(o.exam_on)}${o.starts_at ? `, ${clock(o.starts_at)}–${clock(o.ends_at)}` : ""}${o.venue ? `, ${o.venue}` : ""}` : " · not on the examination timetable yet"}
            {" · "}{scopeWords({ faculty: marking.scope.faculty ?? marking.scope.fac, department: marking.scope.department ?? marking.scope.dept, programme: marking.scope.programme ?? marking.scope.prog })}.
            {general ? " A general course: eligibility is the GST & EPS permit." : " Eligibility is the examination card."}
          </div>
        </PBody>
        <Tiles cls="grid--4" items={[
          ["Total registered", n(f?.registered), null, `${n(f?.eligible)} eligible`],
          ["Total on the sheet", n(f?.listed), null, latest ? latest.reference : "no sheet issued"],
          ["Total present", n(f?.present), "var(--green-ink)", `${n(f?.absent)} absent`],
          ["Manual attendance", n(f?.manual), "var(--amber-ink)", `${n(f?.pending)} pending verification`],
        ]} />
      </Panel>

      <Tabs label="Attendance" value={tab} onChange={go} items={[
        { id: "mark", label: "Mark the list", count: `${markedCount}/${marking.students.length}` },
        { id: "manual", label: "Handwritten rows" },
        { id: "pending", label: "Pending verification", count: pendingOpen.length || undefined },
        { id: "reconcile", label: "Reconciliation" },
        { id: "sheets", label: "Sheets", count: sheets.length || undefined },
      ]} />

      {(tab === "mark" || tab === "manual") && marking.keeper ? (
        <Panel title="The paper">
          <PBody>
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
              <Field id="at-sheet" label="Attendance sheet">
                <select id="at-sheet" className="ctl" value={sheetRef} onChange={(e) => setSheetRef(e.target.value)}>
                  <option value="">No sheet named</option>
                  {sheets.map((s) => <option key={s.reference} value={s.reference}>{s.reference}{s === latest ? " (latest)" : ""}</option>)}
                </select>
              </Field>
              <Field id="at-inv" label="Invigilator"><input id="at-inv" className="ctl" value={invigilator} maxLength={120} onChange={(e) => setInvigilator(e.target.value)} style={{ minWidth: 220 }} /></Field>
            </div>
          </PBody>
        </Panel>
      ) : null}

      {tab === "mark" ? (
        <Panel title="Mark the list" right={marking.keeper ? (
          <span className="row row--tight">
            <Btn kind="ghost" size="sm" onClick={unmarkedAbsent}>Unmarked as absent</Btn>
            <Btn kind="primary" disabled={busy || !changes.length} onClick={() => void saveMarks()}>Save marks{changes.length ? ` (${changes.length})` : ""}</Btn>
          </span>
        ) : undefined}>
          {marking.students.length ? (
            <DTable pageSize={50} noPrint cols={["S/N|num", "Student", "Level|num", general ? "Permit" : "Card", "Recorded", ...(marking.keeper ? ["Attendance", "Remark"] : [])]}
              rows={marking.students.map((s, i) => [
                <span key="n" className="tnum">{i + 1}</span>,
                <Two key="s" a={s.full_name} b={`${s.matric_no ?? s.jamb_no ?? ""} · ${s.programme}${s.entry_type === "CARRYOVER" ? " · carry-over" : ""}`} />,
                <span key="l" className="tnum">{s.level ?? ""}</span>,
                <Pil key="e" kind={s.eligible ? "ok" : "bad"}>{ELIGIBILITY_WORD[s.eligibility] ?? s.eligibility}</Pil>,
                s.attendance ? <Two key="r" a={STATUS_WORD[s.attendance] ?? words(s.attendance)} b={`${s.source === "MANUAL" ? "handwritten" : "from the list"}${s.verified_at ? " · verified" : ""}`} /> : <span key="r" className="sub2">—</span>,
                ...(marking.keeper ? [
                  <select key="m" className="ctl" aria-label={`Attendance of ${s.full_name}`} value={chosen[s.student_id] ?? ""} onChange={(e) => setChosen((c) => ({ ...c, [s.student_id]: e.target.value }))}>
                    <option value="">—</option>
                    {STATUSES.map(([k, w]) => <option key={k} value={k}>{w}</option>)}
                  </select>,
                  <input key="w" className="ctl" aria-label={`Remark for ${s.full_name}`} value={reasons[s.student_id] ?? ""} maxLength={300} onChange={(e) => setReasons((x) => ({ ...x, [s.student_id]: e.target.value }))} style={{ minWidth: 140 }} />,
                ] : []),
              ])}
              texts={marking.students.map((s) => `${s.full_name} ${s.matric_no ?? ""} ${s.jamb_no ?? ""} ${s.programme}`)} />
          ) : <PBody><div className="sub2">No student is registered for this course in your scope.</div></PBody>}
          {marking.manual.length ? (
            <PBody>
              <Note kind="bad" title={`${marking.manual.length} handwritten, not registered for the course`}>
                {marking.manual.map((m) => `${m.full_name} (${m.matric_no ?? ""})`).join("; ")}. Their attendance is kept as manual present; the reconciliation names them for the examinations officer.
              </Note>
            </PBody>
          ) : null}
        </Panel>
      ) : null}

      {tab === "manual" ? (
        <Panel title="Handwritten rows — manual / late registration attendance">
          <PBody>
            {marking.keeper ? (
              <>
                <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
                  <Field id="hw-no" label="Matriculation or JAMB number written"><input id="hw-no" className="ctl" value={hand.number} maxLength={40} onChange={(e) => { const v = e.target.value; setHand((h) => ({ ...h, number: v })); }} /></Field>
                  <Field id="hw-name" label="Name written by the student"><input id="hw-name" className="ctl" value={hand.name} maxLength={160} onChange={(e) => { const v = e.target.value; setHand((h) => ({ ...h, name: v })); }} style={{ minWidth: 220 }} /></Field>
                  <Field id="hw-prog" label="Programme"><input id="hw-prog" className="ctl" value={hand.programme} maxLength={160} onChange={(e) => { const v = e.target.value; setHand((h) => ({ ...h, programme: v })); }} /></Field>
                  <Field id="hw-level" label="Level"><input id="hw-level" className="ctl" value={hand.level} maxLength={10} onChange={(e) => { const v = e.target.value; setHand((h) => ({ ...h, level: v })); }} style={{ width: 80 }} /></Field>
                  <Field id="hw-why" label="Reason / remark">
                    <select id="hw-why" className="ctl" value={hand.reason} onChange={(e) => { const v = e.target.value; setHand((h) => ({ ...h, reason: v })); }}>
                      {MANUAL_REASONS.map((r) => <option key={r} value={r}>{r}</option>)}
                    </select>
                  </Field>
                  {hand.reason === "Other" ? <Field id="hw-other" label="Say what"><input id="hw-other" className="ctl" value={hand.other} maxLength={300} onChange={(e) => { const v = e.target.value; setHand((h) => ({ ...h, other: v })); }} /></Field> : null}
                  <Btn kind="primary" disabled={busy || (!hand.number.trim() && !hand.name.trim())} onClick={() => void enterHandwritten()}>Enter the row</Btn>
                </div>
                <div className="sub2" style={{ marginTop: "var(--s-1)" }}>
                  The student is found by the number written — matriculation, admission, JAMB or application number. Found: their attendance is recorded as manual present, from the sheet named above.
                  Not found, or the number names more than one student: the row is held pending verification. No student or registration is created here.
                </div>
              </>
            ) : <div className="sub2">Your office reads the attendance; the examinations officers enter the handwritten rows.</div>}
          </PBody>
          {handOut ? (
            <PBody>
              {handOut.outcome === "MATCHED"
                ? <Note kind={handOut.registered ? "ok" : "bad"} title="Matched — manual present">{handOut.registered ? "The student is registered for the course." : "The student is not registered for the course: the reconciliation names them (handwritten, not registered)."}{handOut.before ? ` Earlier mark: ${STATUS_WORD[String(handOut.before)] ?? String(handOut.before)}.` : ""}</Note>
                : <Note kind="info" title="Held pending verification">{handOut.why === "AMBIGUOUS" ? "The number names more than one student." : "No student is found by that number."} Verify it under Pending verification.</Note>}
            </PBody>
          ) : null}
        </Panel>
      ) : null}

      {tab === "pending" ? (
        <Panel title="Pending verification" right={`${pendingOpen.length} waiting`}>
          {pending.length ? (
            <DTable pageSize={25} noPrint cols={["Written", "Programme", "Level", "Reason", "Sheet", "State", ...(marking.keeper ? ["Matriculation number / note", ""] : [])]}
              rows={pending.map((p) => [
                <Two key="w" a={p.written_name} b={p.written_number ?? "no number written"} />,
                <span key="p">{p.written_programme ?? ""}</span>, <span key="l" className="tnum">{p.written_level ?? ""}</span>,
                <span key="r" className="sub2">{p.reason ?? ""}</span>, <span key="s" className="sub2 tnum">{p.sheet_reference ?? ""}</span>,
                p.state === "PENDING" ? <Pil key="t" kind="warn">Pending</Pil>
                  : p.state === "MATCHED" ? <Two key="t" a={<Pil kind="ok">Matched</Pil>} b={`${p.matched_name ?? ""} ${p.matched_matric ?? ""}`} />
                  : <Two key="t" a={<Pil kind="bad">Invalid</Pil>} b={p.decision_note ?? ""} />,
                ...(marking.keeper ? (p.state === "PENDING" ? [
                  <span key="i" className="row row--tight">
                    <input className="ctl" aria-label="Matriculation number" placeholder="Matriculation number" value={decide[p.id]?.number ?? ""} maxLength={40}
                      onChange={(e) => setDecide((d) => ({ ...d, [p.id]: { number: e.target.value, note: d[p.id]?.note ?? "" } }))} style={{ width: 160 }} />
                    <input className="ctl" aria-label="Note" placeholder="Note (why invalid)" value={decide[p.id]?.note ?? ""} maxLength={500}
                      onChange={(e) => setDecide((d) => ({ ...d, [p.id]: { number: d[p.id]?.number ?? "", note: e.target.value } }))} style={{ width: 160 }} />
                  </span>,
                  <span key="b" className="row row--tight">
                    <Btn kind="secondary" size="sm" disabled={busy || !(decide[p.id]?.number ?? "").trim()} onClick={() => void decideRow(p.id, true)}>Match</Btn>
                    <Btn kind="ghost" size="sm" disabled={busy || (decide[p.id]?.note ?? "").trim().length < 5} onClick={() => void decideRow(p.id, false)}>Invalid</Btn>
                  </span>,
                ] : [<span key="i" />, <span key="b" />]) : []),
              ])}
              texts={pending.map((p) => `${p.written_name} ${p.written_number ?? ""} ${p.written_programme ?? ""}`)} />
          ) : <PBody><div className="sub2">No handwritten row is waiting.</div></PBody>}
        </Panel>
      ) : null}

      {tab === "reconcile" ? (
        <Panel title="Reconciliation" right={<Btn kind="ghost" size="sm" disabled={!recon?.rows.length} onClick={() => void exportRecon()}>Excel</Btn>}>
          {reconProblem ? <PBody><ProblemNotice problem={reconProblem} /></PBody> : null}
          {recon ? (
            <>
              <PBody>
                <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
                  <Btn kind={finding ? "ghost" : "secondary"} size="sm" onClick={() => setFinding("")}>Everyone ({recon.rows.length})</Btn>
                  {FINDINGS.map(([k, w]) => (
                    <Btn key={k} kind={finding === k ? "secondary" : "ghost"} size="sm" disabled={!recon.findings[k]} onClick={() => setFinding(k)}>{w} ({recon.findings[k] ?? 0})</Btn>
                  ))}
                </div>
                {finding ? <div className="sub2" style={{ marginTop: "var(--s-1)" }}>{FINDINGS.find(([k]) => k === finding)?.[3]}</div> : null}
              </PBody>
              <DTable pageSize={50} noPrint cols={["Student", "Level|num", "Registered", "Card or permit", "Sheet", "Attendance", "Finding"]}
                rows={recon.rows.filter((r) => !finding || r.finding === finding).map((r) => [
                  <Two key="s" a={r.full_name} b={`${r.matric_no ?? ""} · ${r.programme}`} />,
                  <span key="l" className="tnum">{r.level ?? ""}</span>,
                  <Pil key="g" kind={r.registered ? "ok" : "bad"}>{r.registered ? "Yes" : "No"}</Pil>,
                  <Pil key="e" kind={r.eligible ? "ok" : "warn"}>{r.eligible ? "Held" : "Not held"}</Pil>,
                  <span key="o" className="sub2">{r.on_list ? `V${r.list_version}` : "Not listed"}</span>,
                  <span key="a">{r.status ? `${STATUS_WORD[r.status] ?? words(r.status)}${r.source === "MANUAL" ? " (handwritten)" : ""}` : "—"}</span>,
                  <Pil key="f" kind={FINDINGS.find(([k]) => k === r.finding)?.[2] ?? "grey"}>{FINDING_WORD[r.finding] ?? words(r.finding)}</Pil>,
                ])}
                texts={recon.rows.filter((r) => !finding || r.finding === finding).map((r) => `${r.full_name} ${r.matric_no ?? ""} ${r.programme}`)} />
            </>
          ) : null}
        </Panel>
      ) : null}

      {tab === "sheets" ? (
        <Panel title="Attendance sheets" right={sheets.length ? <LinkBtn kind="secondary" href={pdfOf([sheets[0].reference])}>Print the latest (PDF)</LinkBtn> : undefined}>
          {sheets.length ? (
            <DTable pageSize={0} noPrint cols={["Reference", "Lists", "Students|num", "Manual lines|num", "Reason", "Issued"]}
              rows={sheets.map((s) => [
                <Two key="r" a={<Link className="lnk tnum" href={pdfOf([s.reference])} target="_blank">{s.reference}</Link>} b={s === latest || sheets.find((x) => x.series === s.series) === s ? "latest official version" : "superseded"} />,
                <span key="l">{scopeWords(s)}</span>, <span key="n" className="tnum">{n(s.students)}</span>, <span key="m" className="tnum">{s.manual_lines}</span>,
                <span key="y" className="sub2">{s.reason ?? "—"}</span>,
                <Two key="i" a={new Date(s.generated_at).toLocaleString("en-GB")} b={s.generated_by_name ?? s.generated_office ?? ""} />,
              ])} />
          ) : <PBody><div className="sub2">No attendance sheet has been issued for this course in your scope.</div></PBody>}
          {marking.keeper ? (
            <PBody>
              <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
                <Field id="sh-lines" label="Manual attendance lines">
                  <select id="sh-lines" className="ctl" value={lines} onChange={(e) => setLines(e.target.value)}>
                    {MANUAL_PRESETS.map((x) => <option key={x} value={String(x)}>{x}</option>)}
                    <option value="custom">Custom</option>
                  </select>
                </Field>
                {lines === "custom" ? <Field id="sh-custom" label="Lines (0 to 60)"><input id="sh-custom" className="ctl" value={custom} maxLength={2} onChange={(e) => setCustom(e.target.value)} style={{ width: 80 }} /></Field> : null}
                <Field id="sh-why" label={sheets.length ? "Why a new version" : "Reason (optional)"} hint={sheets.length ? "Late registration, late payment, a correction…" : undefined}>
                  <input id="sh-why" className="ctl" value={why} maxLength={500} onChange={(e) => setWhy(e.target.value)} style={{ minWidth: 260 }} />
                </Field>
                <Btn kind="primary" disabled={busy || (sheets.length > 0 && why.trim().length < 5)} onClick={() => void newVersion()}>
                  {sheets.length ? "GENERATE A NEW VERSION" : "GENERATE ATTENDANCE SHEET"}
                </Btn>
              </div>
              <div className="sub2" style={{ marginTop: "var(--s-1)" }}>A new version lists the students registered now; the earlier versions are kept exactly as printed.</div>
            </PBody>
          ) : null}
        </Panel>
      ) : null}
    </>
  );
}
