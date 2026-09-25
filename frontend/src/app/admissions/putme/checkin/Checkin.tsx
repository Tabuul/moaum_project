"use client";

/** The check-in desk at the door (V260): scan the slip's QR (the scanner types the link), or type the application
 *  or JAMB number; the portal answers with the candidate's photograph, batch, day, time, room, seat and
 *  workstation; the desk checks them in, or marks them absent or disqualified with a remark. A second arrival on
 *  the same slip is refused as already checked in. */
import { useRef, useState } from "react";
import Link from "next/link";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Passport } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { ATTENDANCE, BATCH_STATE, EXAM_STATUS, STATUS, callPutme, clock, dayOf, longDay, whenAt, type Batch, type Candidate } from "@/lib/putme";

const DOOR = ["academic", "registrar", "dregistrar", "records", "ict", "super"];

export function Checkin({ session: s, batches, office }: { session: string; batches: Batch[]; office: string | null }) {
  const door = !!office && DOOR.includes(office);
  const [key, setKey] = useState("");
  const [c, setC] = useState<Candidate | null>(null);
  const [last, setLast] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [remarks, setRemarks] = useState("");
  const box = useRef<HTMLInputElement>(null);
  const today = new Date().toISOString().slice(0, 10);
  const todays = batches.filter((b) => String(b.held_on).slice(0, 10) === today && b.state === "PUBLISHED");

  async function lookup(k: string) {
    if (!k.trim()) return;
    setBusy(true); setLast(null);
    try {
      const r = await callPutme<Candidate>(s, "GET", `/lookup?key=${encodeURIComponent(k.trim())}`, undefined, "Look a candidate up at the door");
      if (!r.ok) { setC(null); notifyProblem(r.problem, "No candidate matches"); return; }
      setC(r.data);
    } finally { setBusy(false); }
  }
  async function checkin() {
    if (!c) return;
    setBusy(true);
    try {
      const r = await callPutme<Candidate & { result: string }>(s, "POST", "/checkin", { key: c.putme_token }, `Check in ${c.application_no} at the door`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setC(r.data); setLast(r.data.result); notify(r.data.result, r.data.result.startsWith("already") ? "warn" : "ok");
      setKey(""); box.current?.focus();
    } finally { setBusy(false); }
  }
  async function mark(attendance: string, examStatus: string) {
    if (!c) return;
    if (attendance === "DISQUALIFIED" && !remarks.trim()) { notifyProblem({ status: 422, title: "A disqualification carries its remark." }); return; }
    setBusy(true);
    try {
      const r = await callPutme<Candidate>(s, "POST", "/attendance", { applicationId: c.application_id, attendance, examStatus, remarks: remarks.trim() || null }, `Mark ${c.application_no} ${attendance.toLowerCase()}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setC({ ...c, ...r.data }); notify("Marked"); setRemarks("");
    } finally { setBusy(false); }
  }
  const seatedToday = c?.held_on ? String(c.held_on).slice(0, 10) === today : false;

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/admissions/putme?session=${encodeURIComponent(s)}`}>Post-UTME CBT</Link><span>›</span><strong>Check-in desk</strong></div>
      <PageHead title="Check-in desk" description={`${s}. Scan the slip's QR, or type the application or JAMB number. The portal shows the record; compare the face, then check the candidate in.`}
        actions={<><LinkBtn kind="ghost" href={`/admissions/putme?session=${encodeURIComponent(s)}`}>Back to the desk</LinkBtn></>} />
      {!door ? <Note kind="info" title="You are reading this desk">The Academic Office, the Registry, Records and ICT check candidates in.</Note> : null}
      <Panel title="Find the candidate" right={todays.length ? `${todays.length} batch(es) sit today` : "No batch sits today"}>
        <PBody>
          <form className="row row--tight" style={{ alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); void lookup(key); }}>
            <Field id="ck-key" label="Slip QR, application number or JAMB number" className="grow"><input id="ck-key" ref={box} className="ctl" autoFocus autoComplete="off" value={key} onChange={(e) => setKey(e.target.value)} placeholder="Scan, or type APP/26/000123 or the JAMB number" /></Field>
            <Btn kind="primary" type="submit" disabled={busy || !key.trim()}>Find</Btn>
          </form>
        </PBody>
      </Panel>
      {c ? (
        <Panel title={<>{c.surname}, {c.other_names} <Pil kind={STATUS[c.status]?.[1] ?? "grey"}>{STATUS[c.status]?.[0] ?? c.status}</Pil></>} right={c.application_no}>
          <PBody>
            <div className="row row--top" style={{ gap: "var(--s-4)" }}>
              <Passport w={120} h={148} src={c.passport_id ? `/api/bff/api/v1/admissions/sessions/${s}/applications/${c.application_id}/documents/${c.passport_id}/content` : null} alt={`${c.surname} ${c.other_names}`} />
              <div className="grow">
                {!c.batch ? <Note kind="bad" title="Not seated in any batch">{c.why}. Send the candidate to the Academic Office desk.</Note>
                  : !seatedToday ? <Note kind="bad" title={`Seated on ${longDay(c.held_on)}, not today`}>Batch {c.batch} sits {dayOf(c.held_on)} at {clock(c.starts_at)}. Do not admit the candidate today.</Note>
                  : c.attendance === "CHECKED_IN" || c.attendance === "PRESENT" ? <Note kind="bad" title={`Already checked in at ${whenAt(c.checked_in_at)}`}>A second arrival on this slip is an impersonation. Hold both and call the Academic Office.</Note>
                  : c.attendance === "DISQUALIFIED" ? <Note kind="bad" title="Disqualified">The candidate is not admitted.</Note>
                  : <Note kind="ok" title={`Seated today · batch ${c.batch}, seat ${c.seat}`} action={door ? <Btn kind="primary" onClick={() => void checkin()} disabled={busy}>Check in</Btn> : null}>Compare the face with the photograph, then check the candidate in.</Note>}
                <KvGrid cls="grid--3" pairs={[
                  ["JAMB", <span key="j" className="tnum">{c.jamb_reg_no}</span>], ["Programme", c.programme], ["Faculty", c.faculty ?? "—"],
                  ["Batch", c.batch ?? "—"], ["Day", c.held_on ? dayOf(c.held_on) : "—"], ["Time", c.starts_at ? `${clock(c.starts_at)} – ${clock(c.ends_at)}` : "—"],
                  ["Centre", c.centre ?? "—"], ["Room", c.room ?? "—"], ["Seat · workstation", <span key="s" className="tnum">{c.seat ?? "—"}{c.workstation ? ` · ${c.workstation}` : ""}</span>],
                  ["Attendance", <Pil key="a" kind={ATTENDANCE[c.attendance]?.[1] ?? "grey"}>{ATTENDANCE[c.attendance]?.[0] ?? c.attendance}</Pil>], ["Examination", <Pil key="x" kind={EXAM_STATUS[c.exam_status]?.[1] ?? "grey"}>{EXAM_STATUS[c.exam_status]?.[0] ?? c.exam_status}</Pil>], ["Batch state", c.batch_id ? <Pil key="b" kind={BATCH_STATE[batches.find((b) => b.id === c.batch_id)?.state ?? ""]?.[1] ?? "grey"}>{BATCH_STATE[batches.find((b) => b.id === c.batch_id)?.state ?? ""]?.[0] ?? "—"}</Pil> : "—"],
                ]} />
                {last ? <div className="sub2 mt-2">{last}</div> : null}
              </div>
            </div>
            {door && c.batch ? (
              <>
                <div className="hr" />
                <div className="row row--tight" style={{ alignItems: "flex-end" }}>
                  <Field id="ck-rm" label="Remark" className="grow"><input id="ck-rm" className="ctl" value={remarks} onChange={(e) => setRemarks(e.target.value)} placeholder="Required for a disqualification" /></Field>
                  <Btn kind="secondary" onClick={() => void mark("PRESENT", "IN_PROGRESS")} disabled={busy}>Seated, started</Btn>
                  <Btn kind="secondary" onClick={() => void mark("PRESENT", "COMPLETED")} disabled={busy}>Completed</Btn>
                  <Btn kind="ghost" onClick={() => void mark("ABSENT", "ABSENT")} disabled={busy}>Absent</Btn>
                  <Btn kind="urgent" onClick={() => void mark("DISQUALIFIED", "DISQUALIFIED")} disabled={busy}>Disqualify</Btn>
                </div>
              </>
            ) : null}
          </PBody>
        </Panel>
      ) : null}
      {todays.length ? (
        <Panel title="Sitting today" right={dayOf(today)}>
          <PBody>
            {todays.map((b) => <div key={b.id} className="row row--tight" style={{ justifyContent: "space-between", marginBottom: 4 }}><span><Link className="lnk b600" href={`/admissions/putme/batches/${b.id}?session=${encodeURIComponent(s)}`}>{b.label}</Link> <span className="sub2">· {clock(b.starts_at)} – {clock(b.ends_at)} · {b.centre ?? b.venue}{b.room ? ` · ${b.room}` : ""}</span></span><span className="tnum sub2">{b.checked_in} of {b.assigned} checked in</span></div>)}
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
