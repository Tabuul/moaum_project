import Link from "next/link";
import { api } from "@/lib/api";
import type { Register } from "@/lib/student";
import type { TranscriptQueue, CertificateRegister, GraduationView } from "@/lib/credentials";
import type { SheetListing } from "@/lib/results";
import type { AdmissionCycle, MatriculationOverview } from "@/lib/matriculation";
import type { PersonRow } from "@/app/people/People";
import { Note, Panel, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { day } from "@/lib/format";

/** rRegistrar — proto/part17.html, with the register's own figures. */
export async function RegistrarDashboard({ session }: { session: string }) {
  const [students, persons, sheets, transcripts, certificates, cycle, matric, graduation] = await Promise.all([
    api<Register>("/api/v1/student/students"),
    api<PersonRow[]>("/api/v1/iam/persons"),
    api<SheetListing>(`/api/v1/results/sheets?session=${encodeURIComponent(session)}`),
    api<TranscriptQueue>("/api/v1/credentials/transcript-requests"),
    api<CertificateRegister>("/api/v1/credentials/certificates"),
    api<AdmissionCycle>(`/api/v1/admissions/sessions/${session}/cycle`),
    api<MatriculationOverview>(`/api/v1/matriculation/sessions/${session}`),
    api<GraduationView>(`/api/v1/graduation/sessions/${session}`),
  ]);
  const staff = persons.ok ? persons.data.filter((p) => !p.endedOn) : [];
  const openTranscripts = transcripts.ok ? transcripts.data.requests.filter((t) => t.row.stage !== "RELEASED").length : 0;
  const awaitingCollection = certificates.ok ? certificates.data.certificates.filter((c) => c.status === "PRINTED").length : 0;
  const c = cycle.ok ? cycle.data : null;
  const m = matric.ok ? matric.data : null;
  const g = graduation.ok ? graduation.data : null;
  const inWorkflow = sheets.ok ? sheets.data.tiles.inWorkflow : 0;
  const notSubmitted = sheets.ok ? sheets.data.tiles.notSubmitted : 0;

  return (
    <>
      <Note kind="bad" title="The NDPA Compliance Audit Return is due on 31 March"
        action={<Link href="/people" className="btn btn--urgent btn--sm">Open users &amp; roles</Link>}>
        The return is filed by the Data Protection Officer under your signature. The record of processing activities and the impact assessments arrive with the governance module; until then, the offices held under your grants are the part of it this portal can already show.
      </Note>
      <Tiles items={[
        ["Students on the register", students.ok ? students.data.total.toLocaleString() : "—", null, "All levels and modes"],
        ["Staff on the register", staff.length.toLocaleString(), null, `${staff.filter((p) => p.username).length} with an account`],
        ["Senate business", String(inWorkflow), null, "Result sets in the workflow"],
        ["Credentials in hand", String(openTranscripts + awaitingCollection), "var(--chrome)", "Transcripts and certificates"],
      ]} />
      <Panel title="Registry business">
        <DTable cols={["Item", "Detail", "Status|num"]} rows={[
          [<Two key="i" a={`Admissions ${session}`} b={c ? `${c.offers.toLocaleString()} offers · ${c.accepted.toLocaleString()} accepted` : "—"} />,
            <span key="d">{c ? (c.notYetOnRegister ? `${c.notYetOnRegister.toLocaleString()} admitted candidates not yet on the register` : c.offers ? "Every admitted candidate is on the register" : "No CAPS list committed yet") : "The admissions module did not answer"}</span>,
            c ? (c.notYetOnRegister ? <Pil kind="bad" key="s">Chasing</Pil> : c.settingsInForce ? <Pil kind="ok" key="s">Settings in force</Pil> : <Pil kind="info" key="s">Awaiting settings</Pil>) : <Pil kind="grey" key="s">—</Pil>],
          [<Two key="i" a="Matriculation" b={m ? `${m.totals.registered.toLocaleString()} registered · ${m.totals.confirmed.toLocaleString()} confirmed` : "—"} />,
            <span key="d">{m ? (m.runs.length ? `Run ${m.runs[0].ref} on ${day(m.runs[0].runAt)}` : m.totals.pending ? `${m.totals.pending} faculty list${m.totals.pending === 1 ? "" : "s"} not returned` : "No faculty list has students on it yet") : "—"}</span>,
            m ? (m.runs.length ? <Pil kind="ok" key="s">Run</Pil> : <Pil kind="info" key="s">In progress</Pil>) : <Pil kind="grey" key="s">—</Pil>],
          [<Two key="i" a="Convocation" b={g ? `${g.tiles.auditPassed.toLocaleString()} candidates passed the audit` : "—"} />,
            <span key="d">{g ? (g.tiles.outstanding ? `${g.tiles.outstanding} with an unmet requirement` : g.tiles.approved ? `${g.tiles.approved} awards approved by Senate` : "Awaiting the degree audit") : "—"}</span>,
            g && g.tiles.approved ? <Pil kind="ok" key="s">Approved</Pil> : <Pil kind="info" key="s">In progress</Pil>],
          [<Two key="i" a="Name of the University" b="Renamed 30 December 2024" />, <span key="d">Credentials issued before that date bear the former name</span>, <Pil kind="ok" key="s">Both names verify</Pil>],
        ]} />
      </Panel>
      <Note kind="info" title="Both names must resolve for as long as a graduate is alive">
        A degree awarded in 2011 says Benue State University, Makurdi. An employer verifying it in 2041 must get an answer, not a dead page. The verification service therefore accepts either name and answers for the same institution &mdash; and the old web domain must keep redirecting for the same reason.
      </Note>
      <Panel title="Council and Senate">
        <DTable cols={["Body", "Next sitting|mid", "Papers|mid", "Status|num"]} rows={[
          ["Governing Council", <span className="sub2" key="n">—</span>, <span className="sub2" key="p">—</span>, <Pil kind="grey" key="s">No sitting recorded</Pil>],
          ["Senate", <span className="sub2" key="n">—</span>, <span className="tnum" key="p">{inWorkflow}</span>, notSubmitted ? <Pil kind="bad" key="s">{notSubmitted} result set{notSubmitted === 1 ? "" : "s"} outstanding</Pil> : <Pil kind="ok" key="s">Nothing outstanding</Pil>],
          ["Congregation", <span className="sub2" key="n">—</span>, <span className="sub2" key="p">—</span>, <Pil kind="grey" key="s">No sitting recorded</Pil>],
          ["Appointments and Promotions", <span className="sub2" key="n">—</span>, <span className="sub2" key="p">—</span>, <Pil kind="grey" key="s">Arrives with the Staff module</Pil>],
        ]} />
      </Panel>
    </>
  );
}
