import { api } from "@/lib/api";
import type { Register, RecordsResult, ChangeQueue } from "@/lib/student";
import type { TranscriptQueue, CertificateRegister } from "@/lib/credentials";
import type { SheetListing } from "@/lib/results";
import { LinkBtn, Note, Panel, PBody, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar } from "@/components/proto/blocks";

interface ApplicantsPreview { counts: { total: number; registered: number }; applicants: { jamb_reg_no: string; surname: string; other_names: string; programme: string | null; registered: boolean }[] }

/** rAcademic — proto/part17.html, with the register's own figures. */
export async function AcademicDashboard({ session }: { session: string }) {
  const now = new Date().getTime();
  const [students, registration, transcripts, sheets, changes, certificates, applicants] = await Promise.all([
    api<Register>(`/api/v1/student/students?session=${encodeURIComponent(session)}`),
    api<RecordsResult>(`/api/v1/student/records/registration?session=${encodeURIComponent(session)}`),
    api<TranscriptQueue>("/api/v1/credentials/transcript-requests"),
    api<SheetListing>(`/api/v1/results/sheets?session=${encodeURIComponent(session)}`),
    api<ChangeQueue>("/api/v1/student/biodata-changes?state=PENDING"),
    api<CertificateRegister>("/api/v1/credentials/certificates"),
    api<ApplicantsPreview>(`/api/v1/admissions/applicants?session=${encodeURIComponent(session)}&limit=6`),
  ]);
  const pool = applicants.ok ? applicants.data : null;
  const poolTotal = pool ? Number(pool.counts.total) : 0;
  const poolRegistered = pool ? Number(pool.counts.registered) : 0;
  const rows = students.ok ? students.data.rows : [];
  const total = students.ok ? students.data.total : 0;
  const registered = new Set(
    (registration.ok ? registration.data.rows : []).filter((r) => r.status === "APPROVED" || r.status === "LOCKED").map((r) => String(r.id)),
  );
  const tq = transcripts.ok ? transcripts.data : null;
  const openTranscripts = tq ? tq.requests.filter((t) => t.row.stage !== "RELEASED") : [];
  const oldest = (list: { requestedAt: string }[]) => {
    if (!list.length) return "—";
    const days = Math.floor((now - Math.min(...list.map((x) => new Date(x.requestedAt).getTime()))) / 86400000);
    return `${days} day${days === 1 ? "" : "s"}`;
  };
  const inWorkflow = sheets.ok ? sheets.data.tiles.inWorkflow : 0;
  const nameChanges = changes.ok ? changes.data.rows.filter((c) => c.field === "surname" || c.label.toLowerCase().includes("name")) : [];
  const reissues = certificates.ok ? certificates.data.certificates.filter((c) => c.duplicateOf) : [];

  /* registration, by faculty: expected is the register; registered is an approved registration in the session */
  const byFaculty = new Map<string, { name: string; expected: number; registered: number }>();
  for (const s of rows) {
    const f = byFaculty.get(s.facultyCode) ?? { name: s.facultyName, expected: 0, registered: 0 };
    f.expected++;
    if (registered.has(s.id)) f.registered++;
    byFaculty.set(s.facultyCode, f);
  }
  const faculties = [...byFaculty.values()].sort((a, b) => a.name.localeCompare(b.name));
  const registeredCount = faculties.reduce((n, f) => n + f.registered, 0);
  const short = faculties.filter((f) => f.expected && f.registered / f.expected < 0.75);

  return (
    <>
      {openTranscripts.length || inWorkflow ? (
        <Note kind="info" title={`${openTranscripts.length} transcript request${openTranscripts.length === 1 ? "" : "s"} and ${inWorkflow} result set${inWorkflow === 1 ? "" : "s"} are with Academic Affairs`}
          action={<LinkBtn kind="primary" href="/credentials/transcripts">Open transcripts</LinkBtn>}>
          {tq && tq.tiles.heldAtClearance ? `${tq.tiles.heldAtClearance} of the transcripts ${tq.tiles.heldAtClearance === 1 ? "is" : "are"} held at clearance, and cannot be produced until the unit holding the candidate signs.` : "Nothing is held at clearance."}
        </Note>
      ) : (
        <Note kind="info" title="Nothing is waiting on Academic Affairs today" action={<LinkBtn kind="primary" href="/admissions">Open admissions</LinkBtn>}>
          Transcript requests and result sets arrive here as the session runs. The register fills when the admitted candidates are brought onto it.
        </Note>
      )}
      <Tiles items={[
        ["Students on the register", total.toLocaleString(), null, "All levels", "/reports/students"],
        ["Registered this session", registeredCount.toLocaleString(), null, total ? `${Math.round((100 * registeredCount) / total)}% · ${session}` : session],
        ["Transcript requests", String(openTranscripts.length), "var(--chrome)", tq ? `${tq.tiles.heldAtClearance} held` : "—"],
        ["Results to Senate", String(inWorkflow), null, "In the workflow"],
      ]} />
      {poolTotal ? (
        <Panel title="Committed admission list" right={<LinkBtn kind="primary" href="/admissions/applicants">Open the applicants</LinkBtn>}>
          <PBody style={{ borderBottom: "1px solid var(--line-2)" }}>
            <div className="sub2">{poolTotal.toLocaleString()} applicant{poolTotal === 1 ? "" : "s"} JAMB admitted for {session}. {poolRegistered.toLocaleString()} {poolRegistered === 1 ? "has" : "have"} registered for post-UTME; {(poolTotal - poolRegistered).toLocaleString()} {poolTotal - poolRegistered === 1 ? "has" : "have"} not yet opened their application.</div>
          </PBody>
          {pool && pool.applicants.length ? (
            <DTable cols={["Applicant", "JAMB number|mid", "Programme", "Post-UTME|num"]} rows={pool.applicants.map((a) => [
              <span key="n">{a.surname}, {a.other_names}</span>,
              <span className="tnum" key="j">{a.jamb_reg_no}</span>,
              <span className="sub2" key="p">{a.programme ?? "—"}</span>,
              a.registered ? <span className="sub2 ink-green" key="s">Registered</span> : <span className="sub2" key="s">Not yet</span>,
            ])} />
          ) : null}
        </Panel>
      ) : null}
      <Panel title="Registration, by faculty" right={session}>
        <DTable
          cols={["Faculty", "Expected|mid", "Registered|mid", "Blocked at the Bursary|mid", "Progress|num"]}
          rows={faculties.map((f) => [
            <span key="f">{f.name}</span>, <span className="tnum" key="e">{f.expected.toLocaleString()}</span>,
            <span className="tnum" key="r">{f.registered.toLocaleString()}</span>, <span className="sub2" key="b">—</span>,
            <Bar key="p" pct={f.expected ? Math.round((100 * f.registered) / f.expected) : 0} colour={f.expected && f.registered / f.expected < 0.75 ? "var(--red)" : "var(--green)"} />,
          ])}
        />
        {!faculties.length ? <PBody><div className="sub2">Nobody is on the register yet. Bring the admitted candidates onto it from Admissions.</div></PBody> : null}
      </Panel>
      {short.length ? (
        <Note kind="bad" title={`${short.map((f) => f.name).join(", ")} ${short.length === 1 ? "is" : "are"} under three-quarters registered`}>
          Whether that is a registration problem or a fees problem showing up in the registration figures, the Bursary&rsquo;s ledger will say when it reaches the portal. Extending registration will not move a blocked student; a payment plan approved by Council would.
        </Note>
      ) : null}
      <Panel title="Credentials in hand">
        <DTable cols={["Type", "Open|mid", "Oldest|mid", "Held|num"]} rows={[
          [<Two key="t" a="Transcripts" b="To institutions and employers" />, <span className="tnum" key="o">{openTranscripts.length}</span>, <span className="tnum" key="a">{oldest(openTranscripts.map((t) => ({ requestedAt: t.row.requestedAt })))}</span>, <span className="tnum" key="h">{tq ? tq.tiles.heldAtClearance : 0}</span>],
          [<Two key="t" a="Certificate reissues" b="Loss or damage" />, <span className="tnum" key="o">{reissues.length}</span>, <span className="sub2" key="a">—</span>, <span className="tnum" key="h">0</span>],
          [<Two key="t" a="Verification requests" b="Employers, public service" />, <span className="sub2" key="o">—</span>, <span className="sub2" key="a">Automatic</span>, <span className="sub2" key="h">Public verification arrives with its module</span>],
          [<Two key="t" a="Name-change applications" b="Marriage, correction" />, <span className="tnum" key="o">{nameChanges.length}</span>, <span className="tnum" key="a">{oldest(nameChanges)}</span>, <span className="tnum" key="h">0</span>],
        ]} />
      </Panel>
    </>
  );
}
