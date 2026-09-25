"use client";
/** One external examiner on the desk (V254): the record edited, the invitation sent or resent, the standing changed on a
 *  reason, the CV kept, an appointment recorded for a session and a unit, and the projects with them. */
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ExaminerPil, History, StatusPil, dayOf, daysWords, human, readBase64, when, type Appointment, type AssignmentRow, type Event, type ExaminerRow } from "@/lib/examiners";

export interface ExaminerFull extends ExaminerRow { appointments: Appointment[]; assignments: AssignmentRow[]; files: { id: string; kind: string; filename: string; content_type: string; bytes: number; uploaded_at: string }[]; history: Event[] }
interface Faculty { code: string; name: string; departments: { code: string; name: string; programmes?: { code: string; name: string }[] }[] }
type Dialog = "edit" | "status" | "appoint" | null;

export function ExaminerDetail({ e, faculties, sessions }: { e: ExaminerFull; faculties: Faculty[]; sessions: string[] }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [tab, setTab] = useState<"assignments" | "appointments" | "history">("assignments");
  const [reason, setReason] = useState("");
  const [status, setStatus] = useState("SUSPENDED");
  const [f, setF] = useState({ title: e.title ?? "", firstName: e.given_names.split(" ")[0] ?? "", middleName: e.given_names.split(" ").slice(1).join(" "), lastName: e.surname, email: e.email, phone: e.phone ?? "", institution: e.institution, department: e.department ?? "", rank: e.rank ?? "", specialization: e.specialization ?? "", qualification: e.qualification ?? "", professional: e.professional ?? "", experienceYears: e.experience_years == null ? "" : String(e.experience_years), country: e.country ?? "", region: e.region ?? "", orcid: e.orcid ?? "", notes: e.notes ?? "" });
  const [ap, setAp] = useState({ session: sessions[0] ?? "", semester: "", facultyCode: faculties[0]?.code ?? "", deptCode: "", programmeCode: "", period: "", startsOn: "", endsOn: "", instrument: "" });
  const [file, setFile] = useState<File | null>(null);
  const [fileKey, setFileKey] = useState(0);
  const live = e.assignments.filter((a) => !a.ended_at);

  async function call(path: string, method: "POST" | "PUT", body: unknown, reason: string): Promise<boolean> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/examiners/${e.id}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally { setBusy(false); }
  }
  async function upload() {
    if (!file) return;
    if (file.size > 5 * 1024 * 1024 || !["application/pdf", "image/jpeg", "image/png"].includes(file.type)) { const p = { status: 422, title: "A CV is a PDF, a photo a JPEG or PNG, at most 5 MB." }; setProblem(p); notifyProblem(p); return; }
    const b64 = await readBase64(file);
    if (await call("/files", "POST", { filename: file.name, contentType: file.type, contentBase64: b64, kind: file.type === "application/pdf" ? "CV" : "PHOTO" }, `${file.name} kept on ${e.name}'s record`)) { setFile(null); setFileKey((k) => k + 1); }
  }
  const depts = faculties.find((x) => x.code === ap.facultyCode)?.departments ?? [];
  const progs = depts.find((d) => d.code === ap.deptCode)?.programmes ?? [];

  return (
    <>
      <PageHead eyebrow={`External examiner · ${e.institution}`} title={e.name} description={`${e.rank ? e.rank + " · " : ""}${e.specialization ?? "Specialisation not stated"} · ${e.email}`}
        actions={<><ExaminerPil status={e.status} /><LinkBtn href="/examiners">The Register</LinkBtn></>} />
      {problem && !dialog ? <ProblemNotice problem={problem} /> : null}

      <Panel title="Act on the record" right={e.activated_at ? `Account activated ${dayOf(e.activated_at)}` : e.last_invited_at ? `Invited ${dayOf(e.last_invited_at)}${e.invitation_expires_at ? `, link to ${dayOf(e.invitation_expires_at)}` : ""}` : "Not yet invited"}>
        <PBody>
          <div className="row">
            {e.status !== "SUSPENDED" && e.status !== "INACTIVE" ? <Btn kind={e.activated_at ? "ghost" : "primary"} disabled={busy} onClick={() => void call("/invite", "POST", {}, e.last_invited_at ? "Invitation resent" : "Invitation sent")}>{e.last_invited_at ? "Resend Invitation" : "Send Invitation"}</Btn> : null}
            <Btn kind="secondary" disabled={busy} onClick={() => { setStatus(e.status === "ACTIVE" ? "SUSPENDED" : "ACTIVE"); setReason(""); setDialog("status"); }}>{e.status === "ACTIVE" ? "Suspend or Deactivate" : "Set Active"}</Btn>
            <Btn kind="ghost" disabled={busy} onClick={() => setDialog("edit")}>Edit Record</Btn>
            <Btn kind="ghost" disabled={busy} onClick={() => { setAp({ ...ap, session: sessions[0] ?? "" }); setDialog("appoint"); }}>Record an Appointment</Btn>
            <LinkBtn kind="go" href={`/examiners/projects?assign=${e.id}`} className={e.status !== "ACTIVE" ? "btn--disabled" : ""}>Assign a Project</LinkBtn>
          </div>
          <div className="sub2 mt-2">{e.status === "ACTIVE" ? "The examiner signs in with their email address and sees only the projects assigned to them." : e.status === "PENDING_ACTIVATION" ? "The examiner has been sent a link; the account becomes active when they choose a password through it." : e.status === "INVITED" ? "Recorded, not yet invited." : "A suspended or inactive examiner cannot sign in to the workspace; their assignments stay on record."}</div>
        </PBody>
      </Panel>

      <div className="grid grid--2">
        <Panel title="Profile" right={e.pg_examiner_id ? <Pil kind="info">On the PG roster</Pil> : undefined}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[["Institution", e.institution], ["Department", e.department ?? "—"], ["Position", e.rank ?? "—"], ["Specialisation", e.specialization ?? "—"], ["Highest qualification", e.qualification ?? "—"], ["Professional", e.professional ?? "—"], ["Experience", e.experience_years != null ? `${e.experience_years} years` : "—"], ["Country", `${e.country ?? "—"}${e.region ? `, ${e.region}` : ""}`], ["Phone", e.phone ?? "—"], ["ORCID", e.orcid ?? "—"], ["Registered", dayOf(e.created_at)], ["Last sign-in", e.last_sign_in_at ? when(e.last_sign_in_at) : e.has_signin ? "Never" : "No account yet"]]} />
            {e.notes ? <><div className="hr" /><div className="eyebrow mb-1">Desk notes</div><div className="sub2" style={{ whiteSpace: "pre-wrap" }}>{e.notes}</div></> : null}
          </PBody>
        </Panel>
        <Panel title="CV and photo" right={`${e.files.length} file${e.files.length === 1 ? "" : "s"}`}>
          <PBody>
            {e.files.length ? <ul className="plain stack">{e.files.map((x) => <li key={x.id} className="row row--base"><a className="lnk b600" href={`/api/bff/api/v1/examiners/${e.id}/files/${x.id}/content`} target="_blank" rel="noreferrer">{x.filename}</a><span className="sub2">{x.kind === "CV" ? "CV" : "Photo"} · {human(Number(x.bytes))} · {dayOf(x.uploaded_at)}</span></li>)}</ul> : <div className="sub2">Nothing kept yet.</div>}
            <div className="row row--base mt-3">
              <input key={fileKey} type="file" className="ctl" accept=".pdf,.jpg,.jpeg,.png" onChange={(ev) => setFile(ev.target.files?.[0] ?? null)} aria-label="CV or photo" style={{ flex: "1 1 200px" }} />
              <Btn kind="ghost" disabled={busy || !file} onClick={() => void upload()}>Keep File</Btn>
            </div>
            <div className="sub2 mt-1">A PDF is kept as the CV, an image as the photo. At most 5 MB.</div>
          </PBody>
        </Panel>
      </div>

      <Panel title="With this examiner" right={<Tabs label="Assignments, appointments or history" items={[{ id: "assignments", label: "Projects", count: live.length }, { id: "appointments", label: "Appointments", count: e.appointments.length }, { id: "history", label: "History", count: e.history.length }]} value={tab} onChange={setTab} />}>
        {tab === "assignments" ? (e.assignments.length ? (
          <DTable cols={["Project", "Candidate", "Session|mid", "Deadline|mid", "Status|mid", "Assessment|mid", "|num"]} rows={e.assignments.map((a) => [
            <span key="t"><Link className="lnk" href={`/examiners/assignments/${a.id}`}>{a.title}</Link><div className="sub2">{a.department}</div></span>,
            <span key="c">{a.student}<div className="sub2 tnum">{a.number}</div></span>,
            <span key="s" className="tnum">{a.session}</span>,
            <span key="d" className={`tnum${a.overdue ? " ink-red b600" : ""}`}>{dayOf(a.deadline)}<div className="sub2">{daysWords(a.days_left, a.status)}</div></span>,
            <StatusPil key="st" status={a.status} />,
            <span key="as" className="tnum">{a.total != null ? `${a.total} / ${a.max_total} · ${a.grade ?? ""}` : "—"}</span>,
            <LinkBtn key="o" href={`/examiners/assignments/${a.id}`} size="sm">Open</LinkBtn>,
          ])} />
        ) : <PBody><div className="sub2">No project has been sent to this examiner yet.</div></PBody>) : tab === "appointments" ? (e.appointments.length ? (
          <DTable cols={["Session", "Unit", "Programme", "Period", "From|mid", "To|mid", "Status|mid", "|num"]} rows={e.appointments.map((a) => [
            <span key="s" className="tnum">{a.session}{a.semester ? <span className="sub2"> · semester {a.semester}</span> : null}</span>, <span key="u">{a.department}<div className="sub2">{a.faculty}</div></span>, <span key="p" className="sub2">{a.programme ?? "Every programme"}</span>, <span key="pe" className="sub2">{a.period ?? "—"}{a.instrument ? <div>{a.instrument}</div> : null}</span>,
            <span key="f" className="tnum">{dayOf(a.starts_on)}</span>, <span key="t" className="tnum">{dayOf(a.ends_on)}</span>, <Pil key="st" kind={a.status === "ACTIVE" ? "ok" : "grey"}>{a.status === "ACTIVE" ? "Active" : a.status === "ENDED" ? "Ended" : "Suspended"}</Pil>,
            a.status === "ACTIVE" ? <Btn key="e" kind="ghost" size="sm" disabled={busy} onClick={() => { const why = window.prompt("End this appointment? Give the reason for the record.") ?? ""; if (why.trim()) void fetch(`/api/bff/api/v1/examiners/appointments/${a.id}/end`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Appointment ended") }, body: JSON.stringify({ reason: why.trim() }) }).then(() => { notify("Appointment ended"); router.refresh(); }); }}>End</Btn> : <span key="e" />,
          ])} />
        ) : <PBody><div className="sub2">No appointment recorded yet. Record the session and the unit the letter names.</div></PBody>) : <PBody><History events={e.history} /></PBody>}
      </Panel>

      {dialog === "edit" ? (
        <Modal title={`Edit ${e.name}`} sub="The record as the appointment letter needs it" onClose={() => setDialog(null)} wide
          foot={<><Btn kind="ghost" onClick={() => setDialog(null)}>Cancel</Btn><Btn kind="primary" disabled={busy} onClick={async () => { if (await call("", "PUT", { ...f, experienceYears: f.experienceYears ? Number(f.experienceYears) : null }, "Examiner record saved")) setDialog(null); }}>Save</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="grid grid--3">
            {([["title", "Title"], ["firstName", "First name"], ["middleName", "Middle name"], ["lastName", "Last name"], ["email", "Email"], ["phone", "Phone"], ["institution", "Institution"], ["department", "Department"], ["rank", "Position or rank"], ["specialization", "Area of specialisation"], ["qualification", "Highest qualification"], ["professional", "Professional qualifications"], ["experienceYears", "Years of experience"], ["country", "Country"], ["region", "State or region"], ["orcid", "ORCID"]] as [keyof typeof f, string][]).map(([k, label]) => (
              <Field key={k} id={`ed-${k}`} label={label}><input id={`ed-${k}`} className="ctl" value={String(f[k])} onChange={(ev) => setF({ ...f, [k]: ev.target.value })} /></Field>
            ))}
          </div>
          <Field id="ed-notes" label="Desk notes" hint="Never shown to the examiner"><textarea id="ed-notes" className="ctl" rows={2} value={f.notes} onChange={(ev) => setF({ ...f, notes: ev.target.value })} /></Field>
        </Modal>
      ) : null}
      {dialog === "status" ? (
        <Modal title={`${e.name}: standing`} sub="A suspended or inactive examiner cannot sign in; their record and assessments stay" onClose={() => setDialog(null)}
          foot={<><Btn kind="ghost" onClick={() => setDialog(null)}>Cancel</Btn><Btn kind={status === "ACTIVE" ? "primary" : "urgent"} disabled={busy || (status !== "ACTIVE" && reason.trim().length < 5)} onClick={async () => { if (await call("/status", "POST", { status, reason: reason.trim() || null }, `Examiner set ${status.toLowerCase()}`)) setDialog(null); }}>{status === "ACTIVE" ? "Set Active" : status === "SUSPENDED" ? "Suspend" : "Deactivate"}</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="stack">
            <Field id="st-status" label="Standing">
              <select id="st-status" className="ctl" value={status} onChange={(ev) => setStatus(ev.target.value)}>
                {e.activated_at ? <option value="ACTIVE">Active</option> : null}<option value="SUSPENDED">Suspended</option><option value="INACTIVE">Inactive</option>
              </select>
            </Field>
            {status !== "ACTIVE" ? <Field id="st-reason" label="Reason" required><textarea id="st-reason" className="ctl" rows={3} value={reason} onChange={(ev) => setReason(ev.target.value)} /></Field> : <div className="sub2">The examiner regains the workspace at once.</div>}
            {!e.activated_at ? <Note kind="info" title="Not yet activated">An examiner becomes active by choosing a password through the invitation link; send or resend it instead.</Note> : null}
          </div>
        </Modal>
      ) : null}
      {dialog === "appoint" ? (
        <Modal title={`Appoint ${e.name}`} sub="A session, a unit and a period, as the letter names them" onClose={() => setDialog(null)} wide
          foot={<><Btn kind="ghost" onClick={() => setDialog(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !ap.session || !ap.facultyCode || !ap.deptCode || !ap.startsOn || !ap.endsOn} onClick={async () => { if (await call("/appointments", "POST", { ...ap, semester: ap.semester ? Number(ap.semester) : null, programmeCode: ap.programmeCode || null, period: ap.period || null, instrument: ap.instrument || null }, "Appointment recorded")) setDialog(null); }}>Record Appointment</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="grid grid--3">
            <Field id="ap-session" label="Academic session" required><select id="ap-session" className="ctl" value={ap.session} onChange={(ev) => setAp({ ...ap, session: ev.target.value })}>{sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></Field>
            <Field id="ap-sem" label="Semester"><select id="ap-sem" className="ctl" value={ap.semester} onChange={(ev) => setAp({ ...ap, semester: ev.target.value })}><option value="">Whole session</option><option value="1">First</option><option value="2">Second</option></select></Field>
            <Field id="ap-period" label="Examination period"><input id="ap-period" className="ctl" value={ap.period} onChange={(ev) => setAp({ ...ap, period: ev.target.value })} placeholder="e.g. Second semester examinations" /></Field>
            <Field id="ap-fac" label="Faculty" required><select id="ap-fac" className="ctl" value={ap.facultyCode} onChange={(ev) => setAp({ ...ap, facultyCode: ev.target.value, deptCode: "", programmeCode: "" })}>{faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
            <Field id="ap-dept" label="Department" required><select id="ap-dept" className="ctl" value={ap.deptCode} onChange={(ev) => setAp({ ...ap, deptCode: ev.target.value, programmeCode: "" })}><option value="">Choose…</option>{depts.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}</select></Field>
            <Field id="ap-prog" label="Programme"><select id="ap-prog" className="ctl" value={ap.programmeCode} onChange={(ev) => setAp({ ...ap, programmeCode: ev.target.value })}><option value="">Every programme of the department</option>{progs.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}</select></Field>
            <Field id="ap-from" label="Appointment starts" required><input id="ap-from" className="ctl" type="date" value={ap.startsOn} onChange={(ev) => setAp({ ...ap, startsOn: ev.target.value })} /></Field>
            <Field id="ap-to" label="Appointment ends" required><input id="ap-to" className="ctl" type="date" value={ap.endsOn} onChange={(ev) => setAp({ ...ap, endsOn: ev.target.value })} /></Field>
            <Field id="ap-instr" label="Letter or minute"><input id="ap-instr" className="ctl" value={ap.instrument} onChange={(ev) => setAp({ ...ap, instrument: ev.target.value })} placeholder="e.g. AO/EXT/2026/014" /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
