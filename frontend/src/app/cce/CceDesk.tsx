"use client";

/**
 * The CCE desk (V379) — the Academic Office's CCE Management and the Centre for Continuing Education's desk. The Academic Office
 * loads JAMB's CCE list (a preview, then commit or discard), sets how the CCE session follows undergraduate, offers programmes on
 * the route and publishes the admission list; the Centre reviews each application; the Registry reads; the Bursary states the CCE
 * applicant fees. Every act is the server's, under the signed-in officer; the page shows what it returns.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ccall, naira, when, type CceTab, type Overview } from "@/lib/cce";
import { CceCandidates, CceImports, CceUpload } from "./CceList";
import { CceAdmissionList, CceApplication, CceApplications, CceStudents } from "./CceApplications";
import { CceFees, CceHistory, CceProgrammes, CceReports, CceSession } from "./CceSetup";
import { CceAttendance, CceCalendar, CceClasses, CceRegistrations, CceSchoolFees, CceTimetable } from "./CceClasses";
import { CceExams, CceProgression } from "./CceExams";


/** what the acting office may do here; the server decides again */
export interface Powers { office: string | null; academic: boolean; centre: boolean; decide: boolean; bursar: boolean }

export function powersOf(office: string | null): Powers {
  const o = office ?? "";
  return { office, academic: o === "academic" || o === "super", centre: o === "cce" || o === "super", decide: ["cce", "academic", "super"].includes(o), bursar: o === "bursar" || o === "super" };
}

/** a write to the desk, its reason recorded; the toast says what happened */
export async function cceSend<T>(path: string, method: "POST" | "PUT", body: unknown, reason: string): Promise<T | null> {
  const r = await ccall<T>(`/api/v1/cce${path}`, method, body ?? {}, reason);
  if (!r.ok) { notifyProblem(r.problem); return null; }
  notify(reason);
  return r.data;
}

/** the session picker every tab shares: the calendar's sessions, the current CCE session marked */
export function SessionPick({ sessions, value, current, onChange }: { sessions: { session: string; state: string; listed?: number }[]; value: string; current: string | null; onChange: (s: string) => void }) {
  return (
    <select className="ctl" style={{ width: 210 }} aria-label="CCE session" value={value} onChange={(e) => onChange(e.target.value)}>
      {sessions.map((s) => <option key={s.session} value={s.session}>{s.session}{s.session === current ? " · current CCE" : ""}{s.listed ? ` (${s.listed} listed)` : ""}</option>)}
    </select>
  );
}

export function CceDesk({ tab, id, office, initialSession, initialStatus }: { tab: CceTab; id: string | null; office: string | null; initialSession: string | null; initialStatus: string | null }) {
  const powers = powersOf(office);
  const [ov, setOv] = useState<Overview | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [session, setSession] = useState<string>(initialSession ?? "");
  const [tick, setTick] = useState(0);
  const feesOnly = office === "bursar";
  useEffect(() => {
    if (feesOnly) return;
    let live = true;
    void ccall<Overview>(`/api/v1/cce/overview${session ? `?session=${encodeURIComponent(session)}` : ""}`).then((r) => {
      if (!live) return;
      if (r.ok) { setOv(r.data); setProblem(null); } else setProblem(r.problem);
    });
    return () => { live = false; };
  }, [session, tick, feesOnly]);

  // the Bursary reads the CCE fees only: the applicant fees, and (V380) the CCE school fees and the payments
  if (feesOnly) return tab === "school-fees" ? <CceSchoolFees session={initialSession ?? ""} powers={powers} pick={null} refresh={() => undefined} /> : <CceFees powers={powers} />;
  if (problem) return <ProblemNotice problem={problem} />;
  if (!ov) return <Note kind="info" title="Loading the CCE desk…">One moment.</Note>;
  const s = ov.session;
  const pick = <SessionPick sessions={ov.sessions} value={s} current={ov.mapping.route_session} onChange={setSession} />;
  const props = { session: s, powers, pick, refresh: () => setTick((t) => t + 1) };
  switch (tab) {
    case "upload": return <CceUpload {...props} mapping={ov.mapping} />;
    case "imports": return <CceImports {...props} />;
    case "candidates": return <CceCandidates {...props} initialStatus={initialStatus} />;
    case "applications": return id ? <CceApplication id={id} powers={powers} /> : <CceApplications {...props} initialState={initialStatus} />;
    case "processing": return <CceApplications {...props} processing />;
    case "admission-list": return <CceAdmissionList {...props} />;
    case "students": return <CceStudents {...props} />;
    case "programmes": return <CceProgrammes {...props} />;
    case "session": return <CceSession powers={powers} refresh={props.refresh} />;
    case "reports": return <CceReports {...props} overview={ov} />;
    case "history": return <CceHistory {...props} />;
    case "fees": return <CceFees powers={powers} session={s} />;
    case "calendar": return <CceCalendar {...props} />;
    case "classes": return <CceClasses {...props} />;
    case "timetable": return <CceTimetable {...props} />;
    case "registrations": return <CceRegistrations {...props} />;
    case "attendance": return <CceAttendance {...props} />;
    case "school-fees": return <CceSchoolFees {...props} />;
    case "exams": return <CceExams {...props} />;
    case "progression": return <CceProgression {...props} />;
    default: return <CceOverview ov={ov} pick={pick} powers={powers} />;
  }
}

/* ── the overview ─────────────────────────────────────────────────────────────────────────────────────────────── */

function CceOverview({ ov, pick, powers }: { ov: Overview; pick: React.ReactNode; powers: Powers }) {
  const c = ov.stats;
  const m = ov.mapping;
  const q = (path: string, status?: string) => `/cce/${path}?session=${encodeURIComponent(ov.session)}${status ? `&status=${status}` : ""}`;
  return (
    <>
      <PageHead title="Centre for Continuing Education" description={`CCE ${ov.session} · part-time, ${m.default_duration_years} years by default`}
        actions={pick} />
      <div className="grid grid--2">
        <Note kind={m.route_session === ov.session ? "ok" : "info"} title={`CCE session ${m.route_session ?? "—"} · undergraduate ${m.undergraduate_session ?? "—"}`}>
          {m.relationship ?? "—"}{m.overridden ? <> — named by the Academic Office: {m.override_reason}</> : <> — follows undergraduate by the offset ({m.session_offset}).</>}
          {ov.session !== m.route_session ? <> You are looking at {ov.session}.</> : null}{" "}
          <LinkBtn kind="ghost" size="sm" href="/cce/session">The session mapping</LinkBtn>
        </Note>
        <Note kind={ov.window.state === "OPEN" ? "ok" : "info"} title={`CCE application window for ${ov.session}: ${ov.window.state.toLowerCase()}`}>
          Only those on the committed CCE list may apply.
          {ov.window.closes_at ? ` Closes ${when(ov.window.closes_at)}.` : ""}
        </Note>
      </div>
      <Tiles cls="grid--5" items={[
        ["LISTED", c.imported ?? 0, null, `${c.eligible ?? 0} eligible to apply · ${c.withdrawn ?? 0} withdrawn`, q("candidates")],
        ["APPLIED", c.started ?? 0, null, `${c.submitted ?? 0} submitted`, q("applications")],
        ["TO REVIEW", (c.pending ?? 0) + (c.under_review ?? 0), (c.pending ?? 0) ? "var(--amber-ink)" : null, `${c.with_applicant ?? 0} back with the applicant`, q("processing")],
        ["ADMITTED", c.admitted ?? 0, "var(--green-ink)", `${c.approved_unpublished ?? 0} approved, not yet published · ${c.not_admitted ?? 0} not admitted`, q("admission-list")],
        ["STUDENTS", c.activated ?? 0, null, `${c.accepted ?? 0} accepted · ${c.acceptance_paid ?? 0} acceptance paid · ${c.matriculated ?? 0} matriculated`, q("students")],
      ]} />
      <div className="grid grid--2">
        <Panel title="The admission stages" right={`${ov.programmesOffered} programme${ov.programmesOffered === 1 ? "" : "s"} offered on CCE`}>
          <PBody>
            <ol style={{ margin: 0, paddingLeft: 18, lineHeight: 1.7 }}>
              <li>The Academic Office loads JAMB&rsquo;s CCE list for the CCE session {powers.academic ? <LinkBtn kind="ghost" size="sm" href="/cce/upload">Upload the list</LinkBtn> : null}</li>
              <li>A listed candidate applies with the JAMB number and date of birth, completes the form, pays the CCE application fee and submits</li>
              <li>The Centre reviews: documents verified, more asked for where needed, then recommended</li>
              <li>Someone other than the recommending officer approves — the Director of the Centre or the Academic Office</li>
              <li>The Academic Office publishes the admission list; the applicant reads the outcome, accepts and pays the acceptance fee</li>
              <li>The candidate comes onto the register: CCE, part-time, in the CCE session admitted for</li>
            </ol>
          </PBody>
        </Panel>
        <Panel title="The CCE applicant fees" right={<LinkBtn kind="ghost" size="sm" href="/cce/fees">Fees</LinkBtn>}>
          <PBody>
            {ov.fees ? (
              <>
                <div>Application fee <b>{naira(ov.fees.application_fee)}</b>{Number(ov.fees.portal_charge) ? <> + portal charge {naira(ov.fees.portal_charge)}</> : null} · acceptance fee <b>{naira(ov.fees.acceptance_fee)}</b></div>
                {!ov.fees.stated ? <div className="sub2 mt-1">Carried from {ov.fees.carried_from}: the Bursary has not stated {ov.session}&rsquo;s own.</div> : null}
                <div className="sub2 mt-1">No admission checking fee is charged to a CCE applicant.</div>
              </>
            ) : <div className="sub2">The Bursary has not stated the CCE applicant fees; applicants cannot pay until it does.</div>}
          </PBody>
        </Panel>
      </div>
      <Panel title="The CCE session in operation" right={<Pil kind="info">{ov.mapping.route_session ?? ov.session}</Pil>}>
        <PBody>
          
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <LinkBtn kind="ghost" href={q("calendar")}>CCE calendar</LinkBtn>
            <LinkBtn kind="ghost" href={q("classes")}>CCE classes</LinkBtn>
            <LinkBtn kind="ghost" href={q("timetable")}>Evening timetable</LinkBtn>
            <LinkBtn kind="ghost" href={q("registrations")}>Course registration</LinkBtn>
            <LinkBtn kind="ghost" href={q("attendance")}>Attendance</LinkBtn>
            <LinkBtn kind="ghost" href={q("school-fees")}>CCE school fees</LinkBtn>
            <LinkBtn kind="ghost" href={q("exams")}>Examinations</LinkBtn>
            <LinkBtn kind="ghost" href={q("progression")}>Progression</LinkBtn>
          </div>
        </PBody>
      </Panel>
      <Panel title="By programme" right={<Pil kind="info">{ov.session}</Pil>}>
        {ov.byProgramme.length ? (
          <DTable cols={["Programme", "Faculty", "Listed|num", "Applied|num", "Admitted|num", "Students|num"]} texts={ov.byProgramme.map((r) => `${r.programme} ${r.faculty ?? ""}`)}
            rows={ov.byProgramme.map((r) => [<span key="p">{r.programme}<div className="sub2 tnum">{r.programme_code}</div></span>, r.faculty ?? "—", r.listed, r.applied, r.admitted, r.students])} />
        ) : <PBody><div className="sub2">Nobody is on the CCE list for {ov.session} yet.</div></PBody>}
      </Panel>
    </>
  );
}
