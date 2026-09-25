import type { Me } from "@/components/proto/Shell";
import { LinkBtn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ConfirmFee } from "./ConfirmFee";

export interface PgHome {
  session: string;
  counts: { total: number; submitted: number; recommended: number; faculty?: number; offered: number; accepted: number; admitted: number };
  pgStudents: number;
  /** the register's end of the lifecycle (V255) */
  pipeline?: { active: number; newly_admitted: number; on_research: number; awaiting_defence: number; finishing: number; graduation_eligible: number; graduated: number; not_in_study: number };
  byProgramme: { programme_name: string; pg_award: string | null; applications: number; in_progress: number; offered: number; taken: number }[];
  recent?: {
    application_no: string; session: string; state: string; entry_level: number;
    surname: string; other_names: string; email: string; phone: string | null;
    programme_name: string; pg_award: string | null; submitted_at: string | null; fee_confirmed_at: string | null;
  }[];
}

/** the Secretary's home (V211/V209): what waits on the Secretary this session, with the lists behind the figures */
export interface PgSecHome {
  session: string;
  counts: { toRegister: number; toEndorse: number; feesToConfirm: number; examsPending: number; clearances: number };
  toEndorse: { id: string; semester: number; mode: string; updated_at: string; surname: string; other_names: string; matric_no: string | null; programme_name: string; pg_award: string | null; courses: number }[];
  feesToConfirm: { reference: string; kind: string; amount: number; expires_at: string; application_id?: string; application_no: string; surname: string; other_names: string }[];
  clearances: { id: string; degree_kind: string; topic: string | null; final_submitted_at: string | null; updated_at: string; surname: string; other_names: string; matric_no: string | null; programme_name: string; pg_award: string | null }[];
}

const STATE_LABEL: Record<string, string> = {
  DRAFT: "Draft", SUBMITTED: "Submitted", DEPT_RECOMMENDED: "Dept recommended", DEPT_DECLINED: "Declined by dept",
  FAC_RECOMMENDED: "Faculty recommended", FAC_DECLINED: "Declined by faculty",
  OFFERED: "Offered", NOT_OFFERED: "Not offered", ACCEPTED: "Accepted", ADMITTED: "Admitted",
};
const FEE_KIND: Record<string, string> = { APPLICATION: "Application fee", CHECKING: "Checking fee", ACCEPTANCE: "Acceptance fee" };
const DEGREE: Record<string, string> = { PROJECT: "Project", DISSERTATION: "Dissertation", THESIS: "Thesis" };

function shortDate(v: string | null): string {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" });
}
const naira = (n: number) => "₦" + Number(n).toLocaleString();

/** The Dean's home (V202): what waits on the School, the latest applicants, and the pipeline by programme —
 *  the School's own desk, separate from the Academic Office. */
export function PgSchoolDashboard({ home }: { me: Me | null; home: PgHome | null; role?: string }) {
  if (!home) {
    return <Note kind="bad" title="The postgraduate figures could not be read">This dashboard reads the postgraduate admissions register; it did not answer.</Note>;
  }
  const c = home.counts;
  const awaitingSchool = Number(c.faculty ?? 0);
  const toAdmit = Number(c.accepted);
  const progs = home.byProgramme ?? [];
  const recent = home.recent ?? [];
  /* carry the session so the desk opens on the intake that has these applications, not an empty one */
  const desk = `/admissions/postgraduate?session=${encodeURIComponent(home.session)}`;
  return (
    <>
      {awaitingSchool ? (
        <Note kind="info" title={`${awaitingSchool} application${awaitingSchool === 1 ? "" : "s"} recommended by a faculty, awaiting the School`} action={<LinkBtn kind="primary" href={desk}>Decide them</LinkBtn>}>
          The department and the faculty have recommended these; the School offers or refuses each.
        </Note>
      ) : toAdmit ? (
        <Note kind="ok" title={`${toAdmit} applicant${toAdmit === 1 ? " has" : "s have"} accepted an offer, ready to admit`} action={<LinkBtn kind="primary" href={desk}>Admit them</LinkBtn>}>
          Admitting puts each on the register as a postgraduate student, to matriculate on fees and registration.
        </Note>
      ) : (
        <Note kind="ok" title={`Nothing waits on the School for ${home.session}`} action={<LinkBtn kind="ghost" href={desk}>Postgraduate admissions</LinkBtn>}>
          Faculty recommendations and fresh acceptances appear here to be acted on.
        </Note>
      )}

      <Tiles items={[
        ["Applications", String(c.total), null, home.session, desk],
        ["Awaiting the School", String(awaitingSchool), awaitingSchool ? "var(--chrome)" : null, "Recommended by a faculty", desk],
        ["Offered", String(c.offered), Number(c.offered) ? "var(--green-ink)" : null, "Awaiting acceptance"],
        ["To admit", String(toAdmit), toAdmit ? "var(--chrome)" : null, "Accepted, not yet on the register", desk],
        ["PG students", String(home.pgStudents), null, "On the register", "/admissions/postgraduate/students"],
      ]} />

      {home.pipeline ? (
        <Tiles items={[
          ["Active students", String(home.pipeline.active), null, `${home.pipeline.newly_admitted} newly admitted in ${home.session}`, "/admissions/postgraduate/students"],
          ["On research", String(home.pipeline.on_research), Number(home.pipeline.on_research) ? "var(--chrome)" : null, "Supervised to title registered", "/admissions/postgraduate/research"],
          ["Awaiting defence", String(home.pipeline.awaiting_defence), Number(home.pipeline.awaiting_defence) ? "var(--amber-ink)" : null, "Panel constituted, draft with examiners", "/admissions/postgraduate/research?stage=DRAFT_SUBMITTED"],
          ["Finishing", String(home.pipeline.finishing), null, "Viva held, corrections, final submitted", "/admissions/postgraduate/clearance"],
          ["Graduation eligible", String(home.pipeline.graduation_eligible), Number(home.pipeline.graduation_eligible) ? "var(--green-ink)" : null, "Cleared or recommended to Senate", "/admissions/postgraduate/board"],
          ["Graduated", String(home.pipeline.graduated), null, "Awards recorded on the register", "/graduation"],
        ]} cls="grid--3" />
      ) : null}

      <Panel title="Latest applications" right={<LinkBtn kind="ghost" href={desk}>Open admissions desk</LinkBtn>}>
        {recent.length ? (
          <DTable cols={["Applicant", "Programme", "Session|mid", "Fee|mid", "Status|mid", "Applied|num"]}
            rows={recent.map((a) => [
              <span key="n"><span>{a.surname}, {a.other_names}</span><div className="sub2">{a.application_no} · {a.email}</div></span>,
              <span key="p"><span>{a.programme_name}</span><div className="sub2">{a.pg_award ?? ""}</div></span>,
              <span key="s" className="tnum">{a.session}</span>,
              <span key="f">{a.fee_confirmed_at ? <span className="ink-green">Paid</span> : <span className="sub2">Unpaid</span>}</span>,
              <span key="st">{STATE_LABEL[a.state] ?? a.state}</span>,
              <span key="d" className="tnum">{shortDate(a.submitted_at)}</span>,
            ])}
            texts={recent.map((a) => `${a.surname} ${a.other_names} ${a.application_no} ${a.email} ${a.programme_name}`)} />
        ) : <PBody><div className="sub2">No postgraduate application has been submitted yet.</div></PBody>}
      </Panel>

      <Panel title="By programme" right={home.session}>
        {progs.length ? (
          <DTable cols={["Programme", "Applications|mid", "In progress|mid", "Offered|mid", "Accepted / admitted|num"]}
            rows={progs.map((p) => [
              <span key="p"><span>{p.programme_name}</span><div className="sub2">{p.pg_award ?? ""}</div></span>,
              <span className="tnum" key="a">{p.applications}</span>,
              <span className="tnum" key="i">{p.in_progress}</span>,
              <span className="tnum" key="o">{p.offered}</span>,
              <span className="tnum" key="t">{p.taken}</span>,
            ])} texts={progs.map((p) => p.programme_name)} />
        ) : <PBody><div className="sub2">No postgraduate application has been submitted for {home.session} yet.</div></PBody>}
      </Panel>
    </>
  );
}

/** The Secretary's home: registration, fees, examinations and thesis clearance — what waits on the
 *  Secretary this session, each figure opening the desk that clears it. */
export function PgSecretaryDashboard({ home }: { me: Me | null; home: PgSecHome | null }) {
  if (!home) {
    return <Note kind="bad" title="The Secretary's figures could not be read">This dashboard reads the postgraduate registration, fee and research registers; it did not answer.</Note>;
  }
  const c = home.counts;
  const registrations = "/admissions/postgraduate/results";                 // where a registration is endorsed
  const registrationDesk = `/admissions/postgraduate/registration?session=${encodeURIComponent(home.session)}`;
  const examinations = `/admissions/postgraduate/examinations?session=${encodeURIComponent(home.session)}`;
  const admissions = `/admissions/postgraduate?session=${encodeURIComponent(home.session)}`;
  const clearance = "/admissions/postgraduate/clearance";
  const register = registrationDesk;
  const waiting = Number(c.toEndorse) + Number(c.feesToConfirm) + Number(c.clearances);
  return (
    <>
      {waiting ? (
        <Note kind="info" title={`${waiting} item${waiting === 1 ? "" : "s"} wait on the Secretary for ${home.session}`} action={<LinkBtn kind="primary" href={registrationDesk}>Registration desk</LinkBtn>}>
          {Number(c.toEndorse) ? `${c.toEndorse} registration${Number(c.toEndorse) === 1 ? "" : "s"} to endorse` : null}
          {Number(c.toEndorse) && (Number(c.feesToConfirm) || Number(c.clearances)) ? " · " : null}
          {Number(c.feesToConfirm) ? `${c.feesToConfirm} fee${Number(c.feesToConfirm) === 1 ? "" : "s"} to confirm` : null}
          {Number(c.feesToConfirm) && Number(c.clearances) ? " · " : null}
          {Number(c.clearances) ? `${c.clearances} thes${Number(c.clearances) === 1 ? "is" : "es"} to clear` : null}
          .
        </Note>
      ) : (
        <Note kind="ok" title={`Nothing waits on the Secretary for ${home.session}`} action={<LinkBtn kind="ghost" href={registrationDesk}>Registration desk</LinkBtn>}>
          Submitted registrations, fee references and theses awaiting clearance appear here to be acted on.
        </Note>
      )}

      <Tiles items={[
        ["To register", String(c.toRegister), Number(c.toRegister) ? "var(--chrome)" : null, "PG students yet to register this session", register],
        ["Fees to confirm", String(c.feesToConfirm), Number(c.feesToConfirm) ? "var(--chrome)" : null, "Live references awaiting confirmation", admissions],
        ["Exams pending", String(c.examsPending), Number(c.examsPending) ? "var(--chrome)" : null, "Registered courses without a result", examinations],
        ["Clearances", String(c.clearances), Number(c.clearances) ? "var(--chrome)" : null, "Theses awaiting the Secretary's clearance", clearance],
      ]} />

      <Panel title="What waits on the Secretary" right={home.session}>
        <PBody style={{ display: "grid", gap: "var(--s-4)" }}>
          <section>
            <div className="row row--base mb-2">
              <div className="b600">Registrations to endorse</div>
              <span className="sub2">{c.toEndorse} submitted</span>
              <span className="grow" />
              <LinkBtn kind="ghost" href={registrations}>Endorse on the registrations desk</LinkBtn>
            </div>
            {home.toEndorse.length ? (
              <DTable cols={["Student", "Programme", "Semester|mid", "Courses|num", "Submitted|num"]}
                rows={home.toEndorse.map((r) => [
                  <span key="n"><span>{r.surname}, {r.other_names}</span><div className="sub2 tnum">{r.matric_no ?? "—"}</div></span>,
                  <span key="p"><span>{r.programme_name}</span><div className="sub2">{r.pg_award ?? ""} · {r.mode === "PART_TIME" ? "Part-time" : "Full-time"}</div></span>,
                  <span key="s" className="tnum">{r.semester === 2 ? "Second" : r.semester === 3 ? "Summer" : "First"}</span>,
                  <span key="c" className="tnum">{r.courses}</span>,
                  <span key="d" className="tnum">{shortDate(r.updated_at)}</span>,
                ])}
                texts={home.toEndorse.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.programme_name}`)} />
            ) : <div className="sub2">No registration is waiting to be endorsed.</div>}
          </section>

          <section style={{ borderTop: "1px solid var(--line-2)", paddingTop: "var(--s-3)" }}>
            <div className="row row--base mb-2">
              <div className="b600">Fees to confirm</div>
              <span className="sub2">{c.feesToConfirm} live reference{Number(c.feesToConfirm) === 1 ? "" : "s"}</span>
              <span className="grow" />
              <LinkBtn kind="ghost" href={admissions}>Admissions desk</LinkBtn>
            </div>
            {home.feesToConfirm.length ? (
              <DTable cols={["Applicant", "Fee", "Amount|num", "Reference", "Expires|num", "|num"]}
                rows={home.feesToConfirm.map((f) => [
                  <span key="n"><span>{f.surname}, {f.other_names}</span><div className="sub2 tnum">{f.application_no}</div></span>,
                  <span key="k">{FEE_KIND[f.kind] ?? f.kind}</span>,
                  <span key="a" className="tnum">{naira(f.amount)}</span>,
                  <span key="r" className="tnum">{f.reference}</span>,
                  <span key="e" className="tnum">{shortDate(f.expires_at)}</span>,
                  f.application_id ? <ConfirmFee key="c" applicationId={f.application_id} reference={f.reference} who={`${f.surname}, ${f.other_names}`} /> : <span key="c" />,
                ])}
                texts={home.feesToConfirm.map((f) => `${f.surname} ${f.other_names} ${f.application_no} ${f.reference}`)} />
            ) : <div className="sub2">No fee reference is awaiting confirmation.</div>}
          </section>

          <section style={{ borderTop: "1px solid var(--line-2)", paddingTop: "var(--s-3)" }}>
            <div className="row row--base mb-2">
              <div className="b600">Theses awaiting clearance</div>
              <span className="sub2">{c.clearances} finally submitted</span>
              <span className="grow" />
              <LinkBtn kind="ghost" href={clearance}>Thesis clearance</LinkBtn>
            </div>
            {home.clearances.length ? (
              <DTable cols={["Candidate", "Programme", "Work", "Submitted|num"]}
                rows={home.clearances.map((t) => [
                  <span key="n"><span>{t.surname}, {t.other_names}</span><div className="sub2 tnum">{t.matric_no ?? "—"}</div></span>,
                  <span key="p"><span>{t.programme_name}</span><div className="sub2">{t.pg_award ?? ""}</div></span>,
                  <span key="w"><span>{DEGREE[t.degree_kind] ?? t.degree_kind}</span><div className="sub2">{t.topic ?? "—"}</div></span>,
                  <span key="d" className="tnum">{shortDate(t.final_submitted_at ?? t.updated_at)}</span>,
                ])}
                texts={home.clearances.map((t) => `${t.surname} ${t.other_names} ${t.matric_no ?? ""} ${t.topic ?? ""}`)} />
            ) : <div className="sub2">No thesis is awaiting clearance.</div>}
          </section>
        </PBody>
      </Panel>
    </>
  );
}
