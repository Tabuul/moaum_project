"use client";

/** Academic progress and graduation eligibility for a postgraduate: the coursework as the register holds it,
 *  the research stage, and each requirement answered met, pending or not met — from the record, never typed. */
import type { Me } from "@/lib/student-portal";
import { KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { RESEARCH_WORD, awardWord, eligibility, fmtDay, type PgSummary } from "../pg-common";

const STATE: Record<string, ["ok" | "warn" | "bad", string, string]> = { MET: ["ok", "✓", "Completed"], PENDING: ["warn", "⚠", "Pending"], NOT_MET: ["bad", "✕", "Not satisfied"] };

export function Progress({ s, pg }: { s: Me; pg: PgSummary }) {
  const cw = pg.coursework;
  const checks = eligibility(pg, s.fees);
  const met = checks.filter((c) => c.state === "MET").length;
  const notMet = checks.filter((c) => c.state === "NOT_MET").length;
  const graduated = s.status === "GRADUATED" || !!pg.graduand;
  const cgpaShown = pg.standing !== "NEW" && pg.cgpa != null;
  const pct = cw && cw.units_registered > 0 ? Math.round((100 * cw.units_passed) / cw.units_registered) : 0;
  const standing = graduated ? "GRADUATED" : notMet ? "NOT_ELIGIBLE" : met === checks.length ? "ELIGIBLE" : "PENDING";
  const STANDING: Record<string, ["ok" | "warn" | "bad" | "info", string]> = {
    GRADUATED: ["ok", "Graduated"], ELIGIBLE: ["ok", "Eligible for graduation"], PENDING: ["warn", "Requirements pending"], NOT_ELIGIBLE: ["bad", "Not yet eligible"],
  };

  return (
    <>
      <PageHead title="Academic Progress" description={`${s.programme} · ${awardWord(s.entryLevel)} · entered ${s.entrySession}. Your coursework, research and each graduation requirement as the record answers it today.`}
        actions={<><LinkBtn kind="primary" href="/student/pg-courses">Registration &amp; Results</LinkBtn><LinkBtn href="/student/research">Research &amp; Thesis</LinkBtn><LinkBtn href="/student/graduation">Graduation</LinkBtn></>} />

      <Tiles items={[
        ["Units earned", cw ? `${cw.units_passed} / ${cw.units_registered}` : "—", cw && cw.units_registered ? (pct === 100 ? "var(--green-ink)" : null) : null, cw ? `${pct}% of the units you registered` : "Nothing registered yet"],
        ["Courses passed", cw ? `${cw.passed} / ${cw.courses}` : "—", cw && cw.failed ? "var(--red-ink)" : null, cw ? (cw.failed ? `${cw.failed} failed, to be repeated` : `${cw.graded} graded so far`) : "Nothing registered yet"],
        ["CGPA", cgpaShown ? Number(pg.cgpa).toFixed(2) : "—", pg.standing === "PROBATION" ? "var(--red-ink)" : cgpaShown ? "var(--green-ink)" : null, pg.standing === "PROBATION" ? "Probation · below 2.50" : cgpaShown ? "of 5.00" : "No results yet"],
        ["Graduation", graduated ? "Graduated" : `${met} / ${checks.length}`, STANDING[standing][0] === "ok" ? "var(--green-ink)" : STANDING[standing][0] === "bad" ? "var(--red-ink)" : null, STANDING[standing][1]],
      ]} />

      {cw && cw.units_registered > 0 ? (
        <div className="card"><div className="card__body">
          <div className="row row--between"><span className="b600">Units earned</span><span className="tnum sub2">{cw.units_passed} of {cw.units_registered} registered</span></div>
          <div className="meter mt-2"><div className="meter__bar"><div className="meter__fill" style={{ width: `${pct}%` }} /></div></div>
          <div className="sub2 mt-1">Your programme&rsquo;s required units are on its handbook; the register counts the units you have passed against those you have registered. Deficiency courses earn no credit (Policy 11.3.3).</div>
        </div></div>
      ) : null}

      <Panel title="Graduation eligibility" right={<Pil kind={STANDING[standing][0]}>{STANDING[standing][1]}</Pil>}>
        <ul className="plain">
          {checks.map((c, i) => {
            const [kind, mark, word] = STATE[c.state];
            return (
              <li key={i} className="row row--between" style={{ gap: "var(--s-3)", padding: "10px var(--s-4)", borderBottom: "1px solid var(--line)" }}>
                <span style={{ minWidth: 0 }}><strong>{mark} {c.label}</strong><div className="sub2">{c.detail}</div></span>
                <span className="row row--inline row--tight"><Pil kind={kind}>{word}</Pil>{c.href ? <LinkBtn href={c.href}>Open</LinkBtn> : null}</span>
              </li>
            );
          })}
        </ul>
        <PBody><div className="sub2">Each line is read from the module that owns it: coursework and results from the School&rsquo;s register, research from your research record, fees from the Bursary, clearance from each unit. Nothing here is decided on this page.</div></PBody>
      </Panel>

      <div className="grid grid--2">
        <Panel title="Programme" right={awardWord(s.entryLevel)}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Programme", s.programme], ["Department", s.department], ["Faculty", s.faculty], ["Entry session", s.entrySession],
              ["Current level", String(s.level)], ["Status", s.status.charAt(0) + s.status.slice(1).toLowerCase().replace(/_/g, " ")],
              ["Registrations", cw ? `${cw.registrations} (${cw.endorsed} endorsed)` : "—"], ["Standing", pg.standing === "PROBATION" ? "Probation" : cgpaShown ? "Good standing" : "No results yet"],
            ]} />
          </PBody>
        </Panel>
        <Panel title="Research" right={pg.research ? RESEARCH_WORD[pg.research.stage] ?? pg.research.stage : "Not started"}>
          <PBody>
            {pg.research ? (
              <KvGrid cls="grid--2" pairs={[
                ["Kind", pg.research.degree_kind.charAt(0) + pg.research.degree_kind.slice(1).toLowerCase()], ["Stage", RESEARCH_WORD[pg.research.stage] ?? pg.research.stage],
                ["Supervisor", pg.supervisors?.[0]?.name ?? "Not yet assigned"], ["Topic", pg.research.topic ?? "—"],
                ["Draft submitted", fmtDay(pg.researchDates?.draft_submitted_at)], ["Viva", pg.researchDates?.viva_held_at ? `${fmtDay(pg.researchDates.viva_held_at)} · ${(pg.researchDates.viva_outcome ?? "").replace(/_/g, " ").toLowerCase()}` : "—"],
                ["Final submitted", fmtDay(pg.researchDates?.final_submitted_at)], ["Cleared", fmtDay(pg.researchDates?.cleared_at)],
              ]} />
            ) : <div className="sub2">Your research record opens when you first visit Research &amp; Thesis.</div>}
          </PBody>
        </Panel>
      </div>

      {pg.graduand ? (
        <Note kind="ok" title={`Award of ${pg.graduand.award} · ${pg.graduand.session}`} action={<LinkBtn kind="primary" href="/student/graduation">Graduation and Certificate</LinkBtn>}>
          {pg.graduand.senate_state === "APPROVED" ? `Approved by Senate${pg.graduand.senate_minute ? ` under minute ${pg.graduand.senate_minute}` : ""}.` : "Awaiting Senate."} Convocation clearance and your certificate are on the Graduation screen.
        </Note>
      ) : null}
    </>
  );
}
