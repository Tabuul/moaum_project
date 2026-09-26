import { api } from "@/lib/api";
import type { AdmissionCycle } from "@/lib/matriculation";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Admissions } from "./Admissions";
import { ApplicantsDesk, type Desk } from "./ApplicantsDesk";
import { Reconsiderations } from "./Reconsiderations";
import { LinkBtn, Note, Panel, Tiles } from "@/components/proto/ui";
import type { Pipeline } from "@/lib/screening";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

export default async function AdmissionsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const requested = typeof params.session === "string" ? params.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const [me, cycle, desk] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<AdmissionCycle>(`/api/v1/admissions/sessions/${session}/cycle`),
    api<Desk>(`/api/v1/admissions/sessions/${session}/applicants`),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  const pipeline = await api<Pipeline>(`/api/v1/admissions/sessions/${session}/pipeline`);
  return (
    <Shell route="t/admissions" me={me.ok ? me.data : null}>
      {cycle.ok ? <Admissions cycle={cycle.data} actingOffice={office} /> : <ProblemNotice problem={cycle.problem} />}
      {desk.ok ? <ApplicantsDesk desk={desk.data} actingOffice={office} /> : <ProblemNotice problem={desk.problem} />}
      <Note kind="info" title="Programme eligibility and course suggestions" action={<LinkBtn kind="primary" href={`/admissions/eligibility?session=${encodeURIComponent(session)}`}>Open Programme Eligibility</LinkBtn>}>Every submitted applicant is read against the session&rsquo;s admission settings; where the applied programme is refused, the programmes the candidate qualifies for are listed with every reason, and a change of programme is requested and decided on the record.</Note>
      {pipeline.ok ? (
        <Panel title="Admission pipeline" right={`${session} · JAMB list to matriculation`}>
          <Tiles cls="grid--5" items={[
            ["JAMB admissions uploaded", String(pipeline.data.jamb_uploaded), null, `${pipeline.data.matched} matched · ${pipeline.data.unmatched} unmatched`],
            ["Admitted candidates", String(pipeline.data.admitted), null, "Offers released", `/admissions/eligibility?session=${encodeURIComponent(session)}`],
            ["Acceptance pending", String(pipeline.data.acceptance_pending), pipeline.data.acceptance_pending ? "var(--amber-ink)" : null, `${pipeline.data.acceptance_paid} paid`],
            ["Screening pending", String(pipeline.data.screening_pending), pipeline.data.screening_pending ? "var(--amber-ink)" : null, "Accepted, form not submitted", `/admissions/screening-review?session=${encodeURIComponent(session)}&state=PENDING`],
            ["Screening to review", String(pipeline.data.screening_submitted), pipeline.data.screening_submitted ? "var(--chrome)" : null, `${pipeline.data.screening_returned} returned`, `/admissions/screening-review?session=${encodeURIComponent(session)}&state=REVIEW`],
            ["Screening successful", String(pipeline.data.screening_successful), "var(--green-ink)", "Cleared to pay fees", `/admissions/screening-review?session=${encodeURIComponent(session)}&state=SUCCESSFUL`],
            ["Screening unsuccessful", String(pipeline.data.screening_unsuccessful), pipeline.data.screening_unsuccessful ? "var(--red-ink)" : null, "With the reason", `/admissions/screening-review?session=${encodeURIComponent(session)}&state=UNSUCCESSFUL`],
            ["Change of programme", String(pipeline.data.change_requested), pipeline.data.change_requested ? "var(--amber-ink)" : null, `${pipeline.data.change_approved} approved`, `/admissions/eligibility?session=${encodeURIComponent(session)}&status=PENDING_CHANGE`],
            ["School fees paid", String(pipeline.data.fees_paid), null, `${pipeline.data.registered} registered courses`],
            ["Ready for matriculation", String(pipeline.data.ready_for_matric), pipeline.data.ready_for_matric ? "var(--chrome)" : null, `${pipeline.data.matriculated} matriculated`, `/matriculation/manage?session=${encodeURIComponent(session)}`],
          ]} />
        </Panel>
      ) : null}
      <Reconsiderations session={session} actingOffice={office} />
    </Shell>
  );
}
