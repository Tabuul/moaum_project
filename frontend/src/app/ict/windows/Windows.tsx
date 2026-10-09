"use client";
/** PAYMENT & REGISTRATION WINDOWS (V288): the Director of ICT opens, closes, reopens, schedules, extends and shortens the portal's
 *  windows for school fees payment and course registration, per session and per semester; every act is confirmed with its reason,
 *  supersedes the rule before it and is kept in the history below, which exports. The states are the server's, from its clock. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface WindowRow { type: string; scope: "SESSION" | "SEMESTER"; semesterAsked: number | null; configured: boolean; state: string; phase: string; opens_at: string | null; closes_at: string | null; late_until: string | null; late_fee_enabled: boolean; forced: string | null; reason: string | null; window_id: string | null; semester: number | null }
export interface WindowEvent { id: string; window_type: string; session: string; semester: number | null; action: string; previous_state: string | null; new_state: string | null; previous_opens_at: string | null; previous_closes_at: string | null; previous_late_until: string | null; new_opens_at: string | null; new_closes_at: string | null; new_late_until: string | null; late_fee_enabled: boolean | null; reason: string | null; office: string | null; at: string; officer: string | null }
export interface WindowsPage { session: string; sessions: { name: string; state: string }[]; semesters: { number: number; state: string }[]; openSemester: number; windows: WindowRow[]; affected: number; lateFees: { kind: string; lines: number; total: number }[]; events: WindowEvent[]; now: string;
  /** V380: the CCE session (where the Centre's students study), the CCE calendar's open semester in this session, and how many CCE students there are */
  cce?: { session: string | null; openSemester: number; students: number } }

const TYPE_WORD: Record<string, string> = { SCHOOL_FEES_PAYMENT: "School fees payment", COURSE_REGISTRATION: "Course registration", ADMISSION_STATUS_CHECKING: "Admission status checking", POST_UTME_REGISTRATION: "Post-UTME registration", POSTGRADUATE_APPLICATION: "Postgraduate application",
  CCE_SCHOOL_FEES_PAYMENT: "CCE school fees payment", CCE_COURSE_REGISTRATION: "CCE course registration" };
const STATE: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = { OPEN: ["OPEN", "ok"], CLOSED: ["CLOSED", "bad"], SCHEDULED: ["SCHEDULED", "info"], EXPIRED: ["EXPIRED", "warn"] };
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const remaining = (iso: string | null | undefined, now: string) => { if (!iso) return ""; const ms = new Date(iso).getTime() - new Date(now).getTime(); if (ms <= 0) return "passed"; const d = Math.floor(ms / 86400000), h = Math.floor((ms % 86400000) / 3600000); return d ? `${d} day${d === 1 ? "" : "s"} ${h} h left` : `${h} h left`; };
const local = (iso: string | null | undefined) => { if (!iso) return ""; const d = new Date(iso); const pad = (n: number) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`; };

type Act = { type: string; semester: number | null; action: string; row: WindowRow };

export function Windows({ page, actingOffice }: { page: WindowsPage; actingOffice: string | null }) {
  const router = useRouter();
  const go = useQueryNav();
  const may = actingOffice === "ict";
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [act, setAct] = useState<Act | null>(null);
  const [opens, setOpens] = useState(""); const [closes, setCloses] = useState(""); const [late, setLate] = useState(""); const [lateFee, setLateFee] = useState(false); const [reason, setReason] = useState("");
  const [typeFilter, setTypeFilter] = useState("");
  const session = page.session;
  // the API leaves a null field out of the JSON: the session-wide rows arrive with no semesterAsked at all, so put the nulls back
  // before anything tests against them (without this no row matched, and the page failed on every load)
  const windows: WindowRow[] = page.windows.map((w) => ({ ...w, semesterAsked: w.semesterAsked ?? null, semester: w.semester ?? null }));
  const rowOf = (type: string, sem: number | null): WindowRow =>
    windows.find((w) => w.type === type && w.semesterAsked === sem)
    ?? { type, scope: sem == null ? "SESSION" : "SEMESTER", semesterAsked: sem, configured: false, state: "OPEN", phase: "NORMAL", opens_at: null, closes_at: null, late_until: null, late_fee_enabled: false, forced: null, reason: null, window_id: null, semester: null };
  const fees = rowOf("SCHOOL_FEES_PAYMENT", null), reg = rowOf("COURSE_REGISTRATION", page.openSemester);
  // V380: the Centre for Continuing Education's students answer to their own two windows, never to the full-time ones of the same session
  const cceSem = page.cce?.openSemester ?? 1;
  const cceFees = rowOf("CCE_SCHOOL_FEES_PAYMENT", null), cceReg = rowOf("CCE_COURSE_REGISTRATION", cceSem);

  const start = (type: string, semester: number | null, action: string) => {
    const row = rowOf(type, semester);
    setAct({ type, semester, action, row });
    setOpens(action === "SCHEDULE" ? "" : local(row.opens_at)); setCloses(local(row.closes_at)); setLate(local(row.late_until)); setLateFee(row.late_fee_enabled); setReason("");
    setProblem(null);
  };
  const submit = async () => {
    if (!act) return;
    const needsReason = ["CLOSE", "REOPEN", "SHORTEN"].includes(act.action);
    if (needsReason && !reason.trim()) { setProblem({ status: 422, title: "Give the reason; it goes on the record." }); return; }
    setBusy(true);
    try {
      const body: Record<string, unknown> = { session, semester: act.semester, action: act.action, reason: reason.trim() || null, lateFeeEnabled: lateFee };
      if (opens) body.opensAt = new Date(opens).toISOString();
      if (closes) body.closesAt = new Date(closes).toISOString();
      if (late) body.lateUntil = new Date(late).toISOString();
      const r = await fetch(`/api/bff/api/v1/portal-windows/${act.type}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${TYPE_WORD[act.type]} ${session}: ${act.action.toLowerCase()}`) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return; }
      notify(`${TYPE_WORD[act.type]}: ${act.action.toLowerCase()} recorded${j?.told ? ` · ${j.told} student notice${j.told === 1 ? "" : "s"} queued` : ""}`);
      setAct(null); router.refresh();
    } finally { setBusy(false); }
  };

  const card = (w: WindowRow, title: string, sub: string) => {
    const [word, kind] = STATE[w.state] ?? [w.state, "grey"];
    return (
      <Panel title={title} right={<Pil kind={kind}>{word}{w.phase === "LATE" ? " · LATE PERIOD" : ""}{!w.configured ? " · by default" : ""}</Pil>}>
        <PBody>
          <div className="sub2">{sub}</div>
          <KvGrid cls="grid--3" pairs={[
            ["Opens", w.opens_at ? when(w.opens_at) : w.configured ? "Immediately" : "—"], ["Closes", w.closes_at ? `${when(w.closes_at)} · ${remaining(w.closes_at, page.now)}` : w.configured ? "No closing date" : "—"],
            ["Late period until", w.late_until ? `${when(w.late_until)}${w.late_fee_enabled ? " · late fee applies" : " · no late fee"}` : "None"],
            ["Rule", w.forced === "CLOSED" ? "Closed by the Director" : w.forced === "OPEN" ? "Opened by the Director" : w.configured ? "By the dates" : "Not configured: open"], ["Reason", w.reason ?? "—"], ["Scope", w.semester == null ? "Whole session" : `Semester ${w.semester}`],
          ]} />
          {may ? (
            <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }}>
              {w.state === "OPEN" ? <Btn kind="urgent" size="sm" onClick={() => start(w.type, w.semesterAsked, "CLOSE")}>Close now</Btn> : <Btn kind="go" size="sm" onClick={() => start(w.type, w.semesterAsked, w.configured ? "REOPEN" : "OPEN")}>{w.configured ? "Reopen now" : "Open now"}</Btn>}
              <Btn kind="secondary" size="sm" onClick={() => start(w.type, w.semesterAsked, "SCHEDULE")}>Schedule</Btn>
              <Btn kind="ghost" size="sm" onClick={() => start(w.type, w.semesterAsked, "EXTEND")}>Extend</Btn>
              <Btn kind="ghost" size="sm" onClick={() => start(w.type, w.semesterAsked, "SHORTEN")}>Shorten</Btn>
              <Btn kind="ghost" size="sm" onClick={() => start(w.type, w.semesterAsked, "EDIT")}>Edit window</Btn>
            </div>
          ) : null}
        </PBody>
      </Panel>
    );
  };

  const HEAD = ["S/N", "Window", "Session", "Semester", "Action", "Previous status", "New status", "Start", "End", "Late until", "Late fee", "Reason", "Changed by", "Changed at"];
  const events = page.events.filter((e) => !typeFilter || e.window_type === typeFilter);
  const body = () => events.map((e, i) => [i + 1, TYPE_WORD[e.window_type] ?? e.window_type, e.session, e.semester ?? "Session", e.action, e.previous_state ?? "", e.new_state ?? "", when(e.new_opens_at), when(e.new_closes_at), when(e.new_late_until), e.late_fee_enabled ? "Yes" : "No", e.reason ?? "", `${e.officer ?? ""}${e.office ? ` (${e.office})` : ""}`, when(e.at)]);
  const excel = async () => { const blob = await brandedXlsx("Portal Window History", HEAD, body(), { sheetName: "Windows", serial: docSerial("PWH"), sub: session }); downloadBlob(blob, `portal-window-history-${session.replace("/", "-")}.xlsx`); };
  const pdf = () => brandedPrint("Portal Window History", session, HEAD, body());

  return (
    <>
      <PageHead title="Payment & registration windows" description="Whether the portal's school fees payment and course registration are open, closed, scheduled or in their late period, for a session and each semester. The Director of ICT controls availability; the Bursary and the Academic Office keep every financial and academic rule. Every act is confirmed with its reason and kept in the history."
        actions={<span className="row row--inline row--tight"><label htmlFor="pw-session" className="sub2">Session</label><select id="pw-session" className="ctl" value={session} onChange={(e) => go(`/ict/windows?session=${encodeURIComponent(e.target.value)}`)}>{page.sessions.map((s) => <option key={s.name} value={s.name}>{s.name} — {s.state === "CLOSED" ? "COMPLETED" : s.state === "NOT_YET_OPEN" ? "PLANNED" : s.state}</option>)}</select></span>} />
      {problem && !act ? <ProblemNotice problem={problem} /> : null}
      {!may ? <Note kind="info" title="Read only">The portal&rsquo;s windows are opened and closed by the Director of ICT alone.</Note> : null}
      <Note kind="info" title="Admission status checking has its own page" action={<LinkBtn kind="secondary" href={`/ict/admission-checking?session=${encodeURIComponent(session)}`}>Admission Status Checking</LinkBtn>}>
        The window in which applicants pay the admission checking fee and check their admission status runs over the admission exercise, with its own report; its acts appear in the history below as well.
      </Note>
      <Tiles items={[
        ["SCHOOL FEES PAYMENT", (STATE[fees.state] ?? [fees.state])[0], fees.state === "OPEN" ? "var(--green-ink)" : "var(--red-ink)", fees.closes_at ? `Closes ${when(fees.closes_at)}` : fees.configured ? "No closing date" : "Open by default"],
        ["COURSE REGISTRATION", (STATE[reg.state] ?? [reg.state])[0], reg.state === "OPEN" ? "var(--green-ink)" : "var(--red-ink)", `Semester ${page.openSemester}${reg.closes_at ? ` · closes ${when(reg.closes_at)}` : reg.configured ? "" : " · open by default"}`],
        ["LATE SCHOOL FEES", fees.phase === "LATE" ? "ACTIVE" : "NOT ACTIVE", fees.phase === "LATE" ? "var(--amber-ink)" : null, fees.late_until ? `Until ${when(fees.late_until)}` : "No late period set"],
        ["LATE REGISTRATION", reg.phase === "LATE" ? "ACTIVE" : "NOT ACTIVE", reg.phase === "LATE" ? "var(--amber-ink)" : null, reg.late_until ? `Until ${when(reg.late_until)}` : "No late period set"],
        ["STUDENTS AFFECTED", String(page.affected), null, `Standing in ${session}`],
        ["LATE FEE LINES", String(page.lateFees.reduce((n, l) => n + Number(l.lines), 0)), null, page.lateFees.length ? page.lateFees.map((l) => `${l.kind.replace("_", " ").toLowerCase()}: ₦${Number(l.total).toLocaleString()}`).join(" · ") : "None stated on the fee schedule"],
      ]} />
      <div className="grid grid--2">
        {card(fees, "SCHOOL FEES PAYMENT", `${session} · the whole session. A reference already generated is paid and confirmed as usual; closing stops new references only.`)}
        {card(reg, `COURSE REGISTRATION · SEMESTER ${page.openSemester}`, `${session} · the open semester. Closing stops drafting, changing and submitting a registration.`)}
      </div>
      <Panel title="CCE STUDENTS&rsquo; WINDOWS" right={page.cce?.session ? `CCE session ${page.cce.session} · ${page.cce.students} CCE student${page.cce.students === 1 ? "" : "s"}` : null}>
        <PBody>
          <div className="sub2">The Centre for Continuing Education&rsquo;s students study in the CCE session on the CCE calendar; these two windows govern them, and the full-time windows above never do (nor do these reach a full-time student). Unset, each is open and the CCE calendar decides.
            {page.cce?.session && page.cce.session !== session ? <> CCE students are in <b>{page.cce.session}</b>: <a href={`/ict/windows?session=${encodeURIComponent(page.cce.session)}`}>choose it</a> to set their windows.</> : null}</div>
        </PBody>
      </Panel>
      <div className="grid grid--2">
        {card(cceFees, "CCE SCHOOL FEES PAYMENT", `${session} · the CCE students' school fees. Closing stops new references only.`)}
        {card(cceReg, `CCE COURSE REGISTRATION · SEMESTER ${cceSem}`, `${session} · the CCE calendar's open semester. Closing stops CCE students drafting, changing and submitting a registration.`)}
      </div>
      <Panel title="EVERY SEMESTER" right="A semester&rsquo;s own rule stands over the session&rsquo;s">
        <DTable pageSize={0} cols={["Window", "Scope", "Status|mid", "Phase|mid", "Opens|mid", "Closes|mid", "Late until|mid", "Rule", "|num"]} rows={windows.map((w) => [
          TYPE_WORD[w.type] ?? w.type, w.scope === "SESSION" ? "Whole session" : `Semester ${w.semesterAsked}`,
          <Pil key="s" kind={(STATE[w.state] ?? [w.state, "grey"])[1]}>{w.state}{!w.configured ? " (default)" : ""}</Pil>, w.phase === "LATE" ? <Pil key="p" kind="warn">LATE</Pil> : <span key="p" className="sub2">{w.phase.toLowerCase()}</span>,
          <span key="o" className="tnum sub2">{when(w.opens_at)}</span>, <span key="c" className="tnum sub2">{when(w.closes_at)}</span>, <span key="l" className="tnum sub2">{when(w.late_until)}</span>,
          <span key="r" className="sub2">{w.forced ? `Forced ${w.forced.toLowerCase()}` : w.configured ? "By the dates" : "Not configured"}{w.semester == null && w.scope === "SEMESTER" && w.configured ? " · session rule" : ""}</span>,
          may ? <span key="a" className="row row--inline row--tight row--end">{w.state === "OPEN" ? <Btn kind="urgent" size="sm" onClick={() => start(w.type, w.semesterAsked, "CLOSE")}>Close</Btn> : <Btn kind="go" size="sm" onClick={() => start(w.type, w.semesterAsked, w.configured ? "REOPEN" : "OPEN")}>Open</Btn>}<Btn kind="ghost" size="sm" onClick={() => start(w.type, w.semesterAsked, "EDIT")}>Edit</Btn></span> : null,
        ])} />
      </Panel>
      <Panel title="WINDOW HISTORY" right={<span className="row row--inline row--tight"><select className="ctl" value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)}><option value="">Every window</option><option value="SCHOOL_FEES_PAYMENT">School fees payment</option><option value="COURSE_REGISTRATION">Course registration</option><option value="ADMISSION_STATUS_CHECKING">Admission status checking</option><option value="CCE_SCHOOL_FEES_PAYMENT">CCE school fees payment</option><option value="CCE_COURSE_REGISTRATION">CCE course registration</option></select><Btn kind="secondary" size="sm" disabled={!events.length} onClick={() => void excel()}>Excel</Btn><Btn kind="ghost" size="sm" disabled={!events.length} onClick={pdf}>PDF</Btn></span>}>
        {events.length ? <DTable pageSize={30} cols={["S/N|num", "Window", "Semester|mid", "Action|mid", "Before|mid", "After|mid", "Start|mid", "End|mid", "Late until|mid", "Reason", "Changed by", "At|mid"]} rows={events.map((e, i) => [
          <span key="n" className="tnum sub2">{i + 1}</span>, TYPE_WORD[e.window_type] ?? e.window_type, e.semester ?? "Session", <b key="a">{e.action}</b>, <span key="b" className="sub2">{e.previous_state ?? ""}</span>, <Pil key="c" kind={(STATE[e.new_state ?? ""] ?? ["", "grey"])[1]}>{e.new_state}</Pil>,
          <span key="s" className="tnum sub2">{when(e.new_opens_at)}</span>, <span key="e" className="tnum sub2">{when(e.new_closes_at)}</span>, <span key="l" className="tnum sub2">{when(e.new_late_until)}{e.late_fee_enabled ? " · fee" : ""}</span>,
          <span key="r" className="sub2">{e.reason ?? ""}</span>, <span key="w" className="sub2">{e.officer ?? ""}{e.office ? ` (${e.office})` : ""}</span>, <span key="t" className="tnum sub2">{when(e.at)}</span>,
        ])} /> : <PBody><div className="sub2">No act on this session&rsquo;s windows yet; both are open by default.</div></PBody>}
      </Panel>

      {act ? (
        <Modal title={`${act.action === "CLOSE" ? "Close" : act.action === "REOPEN" ? "Reopen" : act.action === "OPEN" ? "Open" : act.action === "SCHEDULE" ? "Schedule" : act.action === "EXTEND" ? "Extend" : act.action === "SHORTEN" ? "Shorten" : "Edit"} ${TYPE_WORD[act.type].toLowerCase()}`}
          sub={`${session} · ${act.semester == null ? "whole session" : `semester ${act.semester}`}`} onClose={() => setAct(null)}
          foot={<><Btn kind="ghost" onClick={() => setAct(null)}>Back</Btn><Btn kind={act.action === "CLOSE" ? "urgent" : "primary"} disabled={busy} onClick={() => void submit()}>{act.action === "CLOSE" ? "Yes, close it now" : act.action === "REOPEN" || act.action === "OPEN" ? "Open it" : "Record"}</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          {act.action === "CLOSE" ? <Note kind="bad" title={`Are you sure you want to close ${TYPE_WORD[act.type].toLowerCase()} for ${session}${act.semester ? ` semester ${act.semester}` : ""}?`}>It takes effect the moment you confirm. {act.type.endsWith("SCHOOL_FEES_PAYMENT") ? "A reference already generated is still paid and confirmed; no new reference is generated." : "No registration is drafted, changed or submitted."} The students of the session are told.</Note> : null}
          {act.action !== "CLOSE" ? (
            <>
              <div className="sub2 mb-2">{act.action === "OPEN" || act.action === "REOPEN" ? "Leave the dates blank to open now with no closing; or give the closing (and the late period) the window runs to." : act.action === "SCHEDULE" ? "The window opens and closes by these dates, on the server's clock in Africa/Lagos." : act.action === "EXTEND" ? "Move the closing, or the late period, later. The previous dates stay in the history." : act.action === "SHORTEN" ? "Move the closing earlier; the students are told." : "Change any of the dates; the rule before is kept in the history."}</div>
              <div className="grid grid--3">
                <Field id="pw-o" label="Opens"><input id="pw-o" type="datetime-local" className="ctl" value={opens} onChange={(e) => setOpens(e.target.value)} /></Field>
                <Field id="pw-c" label="Closes"><input id="pw-c" type="datetime-local" className="ctl" value={closes} onChange={(e) => setCloses(e.target.value)} /></Field>
                <Field id="pw-l" label={act.type.endsWith("SCHOOL_FEES_PAYMENT") ? "Late payment until" : "Late registration until"}><input id="pw-l" type="datetime-local" className="ctl" value={late} onChange={(e) => setLate(e.target.value)} /></Field>
              </div>
              <label className="sub2 row row--tight" style={{ gap: 6 }}><input type="checkbox" className="pchk" checked={lateFee} onChange={(e) => setLateFee(e.target.checked)} /> {act.type.endsWith("SCHOOL_FEES_PAYMENT") ? "The late payment fee the Bursar stated applies in the late period" : "The late registration fee the Bursar stated applies in the late period"}{act.action === "REOPEN" ? " (a reopening with the late fee on charges it; off, the normal fee)" : ""}</label>
            </>
          ) : null}
          <Field id="pw-r" label="Reason" required={["CLOSE", "REOPEN", "SHORTEN"].includes(act.action)} hint="On the record and in the students' notice"><textarea id="pw-r" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
