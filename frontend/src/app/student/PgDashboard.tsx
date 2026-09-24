"use client";

/** The postgraduate student's home — its own dashboard, not a continuation of the undergraduate one.
 *  A postgraduate is read by their programme and award (PGD / Master's / Doctoral), not by a 100–600
 *  level or an honours classification. Reuses the register's data (fees, registration, results) with
 *  postgraduate framing, and links to the shared student pages. Shape as the prototype's s/pgdash:
 *  the record, four tiles, the one thing to do next, and this session at a glance. */
import Link from "next/link";
import type { Me } from "@/lib/student-portal";
import { KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Passport } from "@/components/proto/blocks";
import { naira } from "./common";

const stageOf = (level: number) => (level >= 900 ? "MPhil / Doctoral" : level >= 800 ? "Master's degree" : "Postgraduate Diploma");

export interface PgSummary {
  postgraduate: boolean;
  cgpa: number | null;
  standing: string;
  registration: { session: string; semester: number; mode: string; state: string; courses: number; units?: number } | null;
  research: { stage: string; topic: string | null; degree_kind: string; supervisor?: string | null } | null;
}
const RESEARCH: Record<string, string> = {
  REGISTERED: "Registered", SUPERVISED: "Supervised", PROPOSAL_SUBMITTED: "Proposal", PROPOSAL_APPROVED: "Proposal approved",
  SEMINAR_HELD: "Seminar", TITLE_REGISTERED: "Title", PANEL_CONSTITUTED: "Panel", DRAFT_SUBMITTED: "Draft", VIVA_HELD: "Viva",
  CORRECTIONS: "Corrections", FINAL_SUBMITTED: "Final", CLEARED: "Cleared", AWARD_RECOMMENDED: "To Senate", AWARDED: "Awarded", WITHDRAWN: "Withdrawn",
};
const DEGREE: Record<string, string> = { THESIS: "Thesis", DISSERTATION: "Dissertation", PROJECT: "Project" };
const SEM = ["", "first semester", "second semester", "third semester"];

/** what the research stage asks of the student next — the prototype's "Submit your research proposal" note, by stage */
function nextStep(r: NonNullable<PgSummary["research"]>, degree: string): [string, string, "info" | "ok" | "bad"] | null {
  const who = r.supervisor ? `Your supervisor (${r.supervisor}) has been assigned. ` : "";
  switch (r.stage) {
    case "REGISTERED": return ["Await the assignment of a supervisor", "The department assigns a supervisor after registration (Policy 14). Your research desk shows the assignment once it is made.", "info"];
    case "SUPERVISED": return ["Submit your research proposal", `${who}Submit your proposal under Research & thesis; a Master's proposal is due within 6 months of first registration, a doctoral one within 12 (Policy 21).`, "info"];
    case "PROPOSAL_SUBMITTED": return ["Your proposal is with the department", `${who}The proposal is being considered; you will be told when it is approved or returned.`, "info"];
    case "PROPOSAL_APPROVED": return ["Present at the research seminar", `Your proposal is approved. The department schedules the research seminar; the Postgraduate School's representative attends and reports (Policy 22).`, "ok"];
    case "SEMINAR_HELD": return ["Register your title", "The seminar is held. Register the title of your research with the School, with the plagiarism report (Policy 23).", "ok"];
    case "TITLE_REGISTERED": return [`Write the ${degree.toLowerCase()}`, "Your title is registered. Submit the draft when your supervisor is satisfied it is ready for examination (Policy 25).", "info"];
    case "PANEL_CONSTITUTED": return ["Submit your draft for examination", "A panel of examiners is constituted. Submit the draft through your research desk.", "info"];
    case "DRAFT_SUBMITTED": return ["Your draft is with the examiners", "The oral examination (viva) is scheduled once the examiners have reported (Policy 27).", "info"];
    case "VIVA_HELD": return ["The viva has been held", "The panel's decision is recorded on your research desk.", "info"];
    case "CORRECTIONS": return ["Make the corrections", "The panel asked for corrections. Make them within the time given, and have your supervisor certify them (Policy 29).", "bad"];
    case "FINAL_SUBMITTED": return ["Await clearance", "Your final version is with the School for clearance (Policy 31–32).", "info"];
    case "CLEARED": return ["Cleared for binding", "Your final version is cleared. The School Board recommends the award to Senate.", "ok"];
    case "AWARD_RECOMMENDED": return ["Recommended to Senate", "The School Board has recommended your award; Senate's word completes it (Policy 33).", "ok"];
    case "AWARDED": return ["Degree awarded", "Congratulations — the award is recorded. Your certificate and transcript follow from the Registry.", "ok"];
    default: return null;
  }
}

export function PgDashboard({ s, pg }: { s: Me; pg?: PgSummary | null }) {
  const f = s.fees;
  const stage = stageOf(s.entryLevel);
  const reg = pg?.registration ?? null;
  const registered = !!reg && (reg.state === "SUBMITTED" || reg.state === "ENDORSED");
  const cgpaShown = pg && pg.standing !== "NEW" && pg.cgpa != null;
  const research = pg?.research ?? null;
  const degree = research ? (DEGREE[research.degree_kind] ?? research.degree_kind) : null;
  const step = research ? nextStep(research, degree ?? "thesis") : null;
  const regWord = !reg ? "Not started" : reg.state === "ENDORSED" ? "Endorsed" : reg.state === "SUBMITTED" ? "Submitted" : reg.state.charAt(0) + reg.state.slice(1).toLowerCase();
  const modeWord = reg ? (reg.mode === "PART_TIME" ? "Part-time" : "Full-time") : null;
  const feeLine = f.paidInFull ? `School fees settled in full for ${f.session}.`
    : f.balance > 0 ? `${naira(f.balance)} outstanding for ${f.session}${f.due > 0 ? "" : " — no charge stated yet"}.`
    : f.due > 0 ? `Fully paid for ${f.session}.` : `No charge stated yet for ${f.session}.`;

  return (
    <>
      <Panel title="Postgraduate student" right="Your record on the register">
        <PBody>
          <div style={{ display: "flex", gap: 18, alignItems: "flex-start", flexWrap: "wrap" }}>
            <Passport w={96} h={118} radius={6} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
            <div style={{ flexGrow: 1, minWidth: 240 }}>
              <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: "-.3px" }}>{s.name}</div>
              <div className="sub2 tnum mt-1">{s.matricNo ?? s.admissionNo}</div>
              <div className="sub2 mt-1">{s.programme} &middot; {s.department}</div>
              <div className="sub2">{s.faculty}</div>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 10 }}>
                <span className={`pill ${s.status === "ACTIVE" ? "pill--ok" : "pill--info"}`}><span className="dot" style={{ background: s.status === "ACTIVE" ? "var(--green)" : "var(--chrome)" }} />{s.status.charAt(0) + s.status.slice(1).toLowerCase()}</span>
                <Pil kind="info">{stage}</Pil>
                <Pil kind="grey">Postgraduate · {s.entrySession}</Pil>
              </div>
            </div>
          </div>
        </PBody>
      </Panel>

      <Tiles items={[
        ["School fees", f.due > 0 ? naira(f.due) : "—", f.balance > 0 ? "var(--red-ink)" : f.paidInFull ? "var(--green-ink)" : null, f.balance > 0 ? `${naira(f.balance)} outstanding` : f.paidInFull ? `Paid in full · ${f.session}` : f.session, "/student/fees"],
        ["Registration", regWord, registered ? "var(--green-ink)" : null, reg ? `${SEM[reg.semester] ?? `semester ${reg.semester}`} · ${reg.courses} course${reg.courses === 1 ? "" : "s"}` : "This session", "/student/pg-courses"],
        ["CGPA", cgpaShown ? Number(pg!.cgpa).toFixed(2) : "—", pg?.standing === "PROBATION" ? "var(--red-ink)" : cgpaShown ? "var(--green-ink)" : null, pg?.standing === "PROBATION" ? "Probation · below 2.50" : cgpaShown ? "of 5.00 · good standing" : "No results yet", "/student/pg-courses"],
        ["Research", research ? (RESEARCH[research.stage] ?? research.stage) : "—", research && !["WITHDRAWN"].includes(research.stage) ? "var(--chrome)" : null, research ? (step ? step[0].toLowerCase() : degree ?? "") : "Not started", "/student/research"],
      ]} />

      {pg?.standing === "PROBATION" ? (
        <Note kind="bad" title="On academic probation" action={<Link href="/student/pg-courses" className="btn btn--primary btn--sm">My results</Link>}>
          Your CGPA is below 2.50. You are on probation for a semester and are advised to withdraw if it does not improve (Policy 15.5 / 20).
        </Note>
      ) : !registered ? (
        <Note kind="info" title={reg ? `Complete your registration for ${reg.session}` : "Register your courses"} action={<Link href="/student/pg-courses" className="btn btn--primary btn--sm">Course registration</Link>}>
          Register the courses your programme carries this semester; the department endorses the form. {feeLine}
        </Note>
      ) : step ? (
        <Note kind={step[2]} title={step[0]} action={<Link href="/student/research" className="btn btn--ghost btn--sm">Research &amp; thesis</Link>}>
          {step[1]}
        </Note>
      ) : (
        <Note kind="ok" title={`Registered for ${reg!.session} · ${SEM[reg!.semester] ?? `semester ${reg!.semester}`}`} action={<Link href="/student/pg-courses" className="btn btn--ghost btn--sm">Registration &amp; results</Link>}>
          {reg!.courses} course{reg!.courses === 1 ? "" : "s"} registered ({modeWord!.toLowerCase()}){reg!.state === "ENDORSED" ? ", endorsed by the department" : ""}. {feeLine}
        </Note>
      )}

      <Panel title="This session" right={reg ? `${reg.session} · ${SEM[reg.semester] ?? `semester ${reg.semester}`}` : s.session}>
        <PBody>
          <KvGrid cls="grid--2" pairs={[
            ["Programme", s.programme],
            ["Level / mode", `${s.level}${modeWord ? ` · ${modeWord}` : ""}`],
            ["Registration", reg ? `${regWord} · ${reg.courses} course${reg.courses === 1 ? "" : "s"}${reg.units != null ? `, ${reg.units} units` : ""}` : "Not started"],
            ["Research", research ? `${RESEARCH[research.stage] ?? research.stage} · ${(degree ?? "").toLowerCase()}${research.supervisor ? ` · ${research.supervisor}` : ""}` : "Not started"],
            ["School fees", feeLine.replace(/\.$/, "")],
            ["Standing", pg?.standing === "PROBATION" ? "Probation" : cgpaShown ? "Good standing" : "No results yet"],
          ]} />
          {research?.topic ? <div className="sub2 mt-3">Topic: {research.topic}</div> : null}
        </PBody>
      </Panel>
    </>
  );
}
