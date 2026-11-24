"use client";

/** V779 · "My selections": every course the student has selected, with how it stands — registered or unpaid, and the Academic Office's
 *  verification of it (four states, each with its reason in the student's own words); a question the Office asked and a box to answer
 *  it; an unpaid selection is taken back here. A course the student selected is never called a carry-over. */
import { useState } from "react";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { useAct } from "../common";
import {
  courseSemesterWord, evidenceWord, failedInWord, naira, num, originSourceWord, plural, registrationCategoryWord, registrationStatusWord, verificationTone,
  verificationWord, viaWord, type MySummer, type SummerCourse,
} from "@/lib/summer";

/** the reply to a question the Office asked about a selection, at most 500 characters (POST /me/summer/note) */
function Reply({ session, c }: { session: string; c: SummerCourse }) {
  const { act, busy, problem } = useAct();
  const [text, setText] = useState(c.student_note ?? "");
  return (
    <div className="mt-1">
      <label className="sub2 blk" htmlFor={`sn-${c.course_code}`}>Your reply</label>
      <textarea id={`sn-${c.course_code}`} className="ctl" rows={2} maxLength={500} value={text} onChange={(e) => setText(e.target.value)} style={{ width: "100%" }} />
      <div className="row row--tight mt-1">
        <Btn kind="ghost" size="sm" busy={busy === "note"} busyLabel="Sending…" disabled={busy !== null || !text.trim()}
             onClick={() => void act("note", "POST", "/me/summer/note", { session, course: c.course_code, note: text.trim() }, `Reply on Summer course ${c.course_code}`, "Your reply is sent")}>Send reply</Btn>
        <span className="sub2 tnum">{text.length}/500</span>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
    </div>
  );
}

export function Selections({ d, printHref }: { d: MySummer; printHref: string | null }) {
  const { act, busy, problem } = useAct();
  // what the student has selected, and what the Office decided against even before it was paid: each with where it stands and why
  const rows = (d.courses ?? []).filter((c) => c.status === "SELECTED" || c.status === "REGISTERED" || c.status === "TAKEN_OFF"
    || c.verification === "NOT_OUTSTANDING" || c.verification === "REJECTED");
  if (!rows.length) return null;
  const live = rows.filter((c) => c.status === "SELECTED" || c.status === "REGISTERED");
  const units = d.summary?.units ?? live.reduce((s, c) => s + (c.units ?? 0), 0);
  const count = d.summary?.selected ?? live.length;
  const payable = num(d.summary?.due ?? d.account?.due);
  const session = d.session ?? "";
  return (
    <Panel title="My selections" right={
      <span className="row row--inline row--tight">
        <span>{plural(count, "course")} · {units} unit{units === 1 ? "" : "s"}</span>
        {printHref ? <a className="btn btn--ghost btn--sm" href={printHref} target="_blank" rel="noopener">{(d.summary?.registered ?? 0) > 0 ? "Print confirmation" : "Print selection summary"}</a> : null}
      </span>}>
      <DTable pageSize={0} noPrint title="My Summer Semester selections"
        cols={["Code", "Title", "Units|num", "Owed in", "Registration category", "Registration status", "Verification", "Reason or question", "|mid"]}
        rows={rows.map((c) => {
          const asked = c.clarification_open && c.clarification_note;
          return [
            <b key={`c${c.course_code}`} className="tnum">{c.course_code}</b>,
            <span key={`n${c.course_code}`}>{c.title ?? "—"}<span className="blk sub2">{courseSemesterWord(c)} semester</span></span>,
            <span key={`u${c.course_code}`} className="tnum">{c.units ?? "—"}</span>,
            <span key={`o${c.course_code}`} className="sub2">{failedInWord(c)}{c.original_source && (c.original_session || c.original_semester) ? <span className="blk">{originSourceWord(c.original_source)}</span> : null}</span>,
            <span key={`g${c.course_code}`}>{registrationCategoryWord(c.basis)}</span>,
            c.status === "REGISTERED" ? <Pil key={`r${c.course_code}`} kind="ok">REGISTERED</Pil>
              : c.status === "SELECTED" ? <Pil key={`r${c.course_code}`} kind="warn">{registrationStatusWord("SELECTED").toUpperCase()}</Pil>
              : <Pil key={`r${c.course_code}`} kind="grey">{registrationStatusWord(c.status).toUpperCase()}</Pil>,
            <span key={`v${c.course_code}`}>
              {c.verification ? <Pil kind={verificationTone(c.verification)}>{verificationWord(c.verification)}</Pil> : <span className="sub2">—</span>}
              {c.verification === "CONFIRMED_OUTSTANDING" && c.verified_via ? <span className="blk sub2">{viaWord(c.verified_via)}</span>
                : c.verification === "PENDING_VERIFICATION" && c.evidence ? <span className="blk sub2">{evidenceWord(c.evidence)}</span> : null}
            </span>,
            <span key={`w${c.course_code}`}>
              {c.verification === "NOT_OUTSTANDING" || c.verification === "REJECTED" ? <span>{c.decision_reason}</span> : null}
              {asked ? <span><b>The Academic Office asks:</b> {c.clarification_note}</span> : null}
              {!asked && c.student_note ? <span className="sub2">Your note: {c.student_note}</span> : null}
              {asked ? <Reply session={session} c={c} /> : null}
            </span>,
            // V739: an unpaid selection is removed whether or not registration is open (after the close it can no longer be paid)
            c.status === "SELECTED" ? (
              <Btn key={`x${c.course_code}`} kind="ghost" size="sm" disabled={busy !== null}
                   onClick={() => void act(`x${c.course_code}`, "POST", "/me/summer/unselect", { session, course: c.course_code }, `Summer course ${c.course_code} taken back`, `${c.course_code} taken back`)}>Remove</Btn>
            ) : <span key={`x${c.course_code}`} />,
          ];
        })}
        foot={["Total", plural(count, "course"), <span key="u" className="tnum">{units}</span>, null, null, null, null, <span key="p" className="tnum">Payable {naira(payable)}</span>, null]} />
      {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : null}
    </Panel>
  );
}
