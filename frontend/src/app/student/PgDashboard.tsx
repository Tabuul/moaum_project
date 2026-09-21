"use client";

/** The postgraduate student's home — its own dashboard, not a continuation of the undergraduate one.
 *  A postgraduate is read by their programme and award (PGD / Master's / Doctoral), not by a 100–600
 *  level or an honours classification. Reuses the register's data (fees, registration, results) with
 *  postgraduate framing, and links to the shared student pages. */
import Link from "next/link";
import type { Me } from "@/lib/student-portal";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Passport } from "@/components/proto/blocks";
import { naira } from "./common";

const stageOf = (level: number) => (level >= 900 ? "MPhil / Doctoral" : level >= 800 ? "Master's degree" : "Postgraduate Diploma");

export interface PgSummary {
  postgraduate: boolean;
  cgpa: number | null;
  standing: string;
  registration: { session: string; semester: number; mode: string; state: string; courses: number } | null;
  research: { stage: string; topic: string | null; degree_kind: string } | null;
}
const RESEARCH: Record<string, string> = {
  REGISTERED: "Registered", SUPERVISED: "Supervised", PROPOSAL_SUBMITTED: "Proposal", PROPOSAL_APPROVED: "Proposal approved",
  SEMINAR_HELD: "Seminar", TITLE_REGISTERED: "Title", PANEL_CONSTITUTED: "Panel", DRAFT_SUBMITTED: "Draft", VIVA_HELD: "Viva",
  CORRECTIONS: "Corrections", FINAL_SUBMITTED: "Final", CLEARED: "Cleared", AWARD_RECOMMENDED: "To Senate", AWARDED: "Awarded", WITHDRAWN: "Withdrawn",
};

export function PgDashboard({ s, pg }: { s: Me; pg?: PgSummary | null }) {
  const f = s.fees;
  const stage = stageOf(s.entryLevel);
  const reg = pg?.registration ?? null;
  const registered = !!reg && (reg.state === "SUBMITTED" || reg.state === "ENDORSED");
  const cgpaShown = pg && pg.standing !== "NEW" && pg.cgpa != null;
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
              <div className="sub2 tnum" style={{ marginTop: 2 }}>{s.matricNo ?? s.admissionNo}</div>
              <div className="sub2" style={{ marginTop: 2 }}>{s.programme} &middot; {s.department}</div>
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

      {pg?.standing === "PROBATION" ? (
        <Note kind="bad" title="On academic probation" action={<Link href="/student/pg-courses" className="btn btn--primary btn--sm">My results</Link>}>
          Your CGPA is below 2.50. You are on probation for a semester and are advised to withdraw if it does not improve (Policy 15.5 / 20).
        </Note>
      ) : registered ? (
        <Note kind="ok" title={`Registered for ${reg!.session} · semester ${reg!.semester}`} action={<Link href="/student/pg-courses" className="btn btn--ghost btn--sm">Registration &amp; results</Link>}>
          {reg!.courses} course{reg!.courses === 1 ? "" : "s"} registered ({reg!.mode === "PART_TIME" ? "part-time" : "full-time"}){reg!.state === "ENDORSED" ? ", endorsed by the department" : ""}. {feeLine}
        </Note>
      ) : (
        <Note kind="info" title="Register your courses" action={<Link href="/student/pg-courses" className="btn btn--primary btn--sm">Course registration &amp; results</Link>}>
          Register the courses your programme carries this semester, and see your results and CGPA there. {feeLine}
        </Note>
      )}

      <Tiles items={[
        ["Programme", stage, null, s.programme],
        ["Registration", registered ? (reg!.state === "ENDORSED" ? "Endorsed" : "Submitted") : "Not started", registered ? "var(--green-ink)" : null, reg ? `${reg.courses} courses` : "This session"],
        ["CGPA", cgpaShown ? Number(pg!.cgpa).toFixed(2) : "—", pg?.standing === "PROBATION" ? "var(--red-ink)" : cgpaShown ? "var(--green-ink)" : null, pg?.standing === "PROBATION" ? "Probation" : cgpaShown ? "Good standing" : "No results yet"],
        ["Research", pg?.research ? (RESEARCH[pg.research.stage] ?? pg.research.stage) : "—", null, pg?.research ? (pg.research.degree_kind === "THESIS" ? "Thesis" : pg.research.degree_kind === "DISSERTATION" ? "Dissertation" : "Project") : "Not started"],
        ["Fees", f.balance > 0 ? naira(f.balance) : f.paidInFull ? "Settled" : "—", f.balance > 0 ? "var(--red-ink)" : f.paidInFull ? "var(--green-ink)" : null, f.balance > 0 ? "Outstanding" : "This session"],
      ]} />

      <Panel title="Postgraduate desks" right={s.name}>
        <PBody>
          <div style={{ display: "grid", gap: 8, gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))" }}>
            <Link href="/student/pg-courses" className="btn btn--ghost btn--sm">Course registration &amp; results</Link>
            <Link href="/student/research" className="btn btn--ghost btn--sm">Research &amp; thesis</Link>
            <Link href="/student/fees" className="btn btn--ghost btn--sm">Fees &amp; payments</Link>
            <Link href="/student/exams" className="btn btn--ghost btn--sm">Examinations</Link>
            <Link href="/student/biodata" className="btn btn--ghost btn--sm">Bio-data</Link>
            <Link href="/student/transcript" className="btn btn--ghost btn--sm">Transcript</Link>
          </div>
          <div className="sub2" style={{ marginTop: 8 }}>
            Supervision, the proposal, the research seminar and the thesis examination are tracked under Research &amp; thesis.
          </div>
        </PBody>
      </Panel>
    </>
  );
}
