"use client";

/** V624: the department takes a course off its programme's broadsheet, and puts it back. A course outside the programme (not
 *  registered under the programme's basis, not bound to it, not a general course) is flagged; any column may be taken off, with
 *  a reason. A course taken off is left out of the sheet before anything is counted and listed here with the students who carry
 *  it — the registrations and results are untouched, and are put right elsewhere (Programme Swap, or the course dropped). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Broadsheet, Stream } from "@/lib/results";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";

export function BroadsheetOmissions({ sheet, prog, level, session, sem, stream, mayOmit }: {
  sheet: Broadsheet; prog: string; level: string | number; session: string; sem: string | number; stream: Stream; mayOmit: boolean;
}) {
  const router = useRouter();
  const [asking, setAsking] = useState<{ course: string; title: string } | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [pick, setPick] = useState("");
  const outsideProgramme = sheet.courses.filter((c) => c.inProgramme === false);
  const omitted = sheet.outside ?? [];

  async function send(path: string, course: string, why: string, body: Record<string, unknown>) {
    setBusy(course);
    try {
      const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) },
        body: JSON.stringify({ prog, level: Number(level), session, sem: Number(sem), stream, course, ...body }) });
      if (!r.ok) { notifyProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return false; }
      notify(why);
      router.refresh();
      return true;
    } finally {
      setBusy(null);
    }
  }

  const takeOff = async () => {
    if (!asking) return;
    const why = `${asking.course} taken off the broadsheet: ${reason.trim()}`;
    if (await send("/api/bff/api/v1/results/broadsheet/omissions", asking.course, why, { reason: reason.trim() })) { setAsking(null); setReason(""); }
  };

  if (!outsideProgramme.length && !omitted.length && !mayOmit) return null;
  return (
    <>
      {omitted.length ? (
        <Note kind="info" title={`${omitted.length} course${omitted.length === 1 ? "" : "s"} taken off this broadsheet by the department`}>
          {"Not columns of this sheet and not counted in its figures. The students' registrations and results are unchanged: a student placed in the wrong programme is corrected under Programme Swap, a course registered in error is dropped from the registration."}
          <ul className="mt-1">
            {omitted.map((o) => (
              <li key={o.courseCode} className="mt-1">
                <b className="tnum">{o.courseCode}</b> {o.title} ({o.units} units) — {o.students.length ? o.students.join("; ") : "no student carries it now"}
                <div className="sub2">{o.reason}{o.omittedBy ? ` — ${o.omittedBy}` : ""}{o.omittedAt ? `, ${new Date(o.omittedAt).toLocaleDateString("en-GB")}` : ""}
                  {mayOmit ? <> · <Btn kind="ghost" disabled={busy !== null} onClick={() => void send("/api/bff/api/v1/results/broadsheet/omissions/restore", o.courseCode, `${o.courseCode} put back on the broadsheet`, {})}>Put back</Btn></> : null}
                </div>
              </li>
            ))}
          </ul>
        </Note>
      ) : null}
      {outsideProgramme.length ? (
        <Note kind="bad" title={`${outsideProgramme.length} course${outsideProgramme.length === 1 ? "" : "s"} on this sheet outside the programme`}>
          {"Registered by students of this class but not the programme's: not bound to it in the programme structure and not a general course. A few students' error, or a student of another programme, brings such a course onto the sheet; a course a few of the class rightly take (a teaching subject, a borrowed elective) looks the same — the department decides."}
          <ul className="mt-1">
            {outsideProgramme.map((c) => (
              <li key={c.courseCode} className="mt-1">
                <b className="tnum">{c.courseCode}</b> {c.title} ({c.units} units)
                {mayOmit ? <> · <Btn kind="ghost" disabled={busy !== null} onClick={() => { setAsking({ course: c.courseCode, title: c.title }); setReason(""); }}>Take off this broadsheet</Btn></> : null}
              </li>
            ))}
          </ul>
        </Note>
      ) : null}
      {mayOmit && sheet.courses.length ? (
        <div className="row row--inline row--tight mt-1">
          <label className="sub2" htmlFor="omit-pick">Take another course off this broadsheet</label>
          <select id="omit-pick" className="ctl" value={pick} onChange={(e) => setPick(e.target.value)}>
            <option value="">Choose a course…</option>
            {sheet.courses.map((c) => <option key={c.courseCode} value={c.courseCode}>{c.courseCode} — {c.title}</option>)}
          </select>
          <Btn kind="ghost" disabled={!pick || busy !== null} onClick={() => { const c = sheet.courses.find((x) => x.courseCode === pick); if (c) { setAsking({ course: c.courseCode, title: c.title }); setReason(""); } }}>Take off</Btn>
        </div>
      ) : null}
      {asking ? (
        <Modal title={`Take ${asking.course} off this broadsheet`} sub={asking.title} onClose={() => setAsking(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsking(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={reason.trim().length < 3 || busy !== null} onClick={() => void takeOff()}>Take it off</Btn></>}>
          <p className="sub2">The course leaves this sheet&rsquo;s columns and figures, and is listed under it with the students who carry it. Their registrations and results are not changed.</p>
          <label className="sub2" htmlFor="omit-reason">Why</label>
          <textarea id="omit-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)}
            placeholder="For example: not offered by the department; registered in error; a student of another programme" />
        </Modal>
      ) : null}
    </>
  );
}
