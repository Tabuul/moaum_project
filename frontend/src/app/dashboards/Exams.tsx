import Link from "next/link";
import type { Me } from "@/components/proto/Shell";
import type { SheetListing, SheetListed } from "@/lib/results";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { AllocationHistory, type AllocationRow } from "./AllocationHistory";

const bucket = (st: string) => st === "ENTRY" ? "entry" : st === "PUBLISHED" ? "published" : st === "SENATE" ? "senate" : "workflow";

/** The Exams Officer's home: the result-sheet pipeline in their scope, the sheets still with lecturers to
 *  chase, and the result queries awaiting an answer — from the results module (V013). */
export function ExamsDashboard({ me, listing, openQueries, session, history = [] }: { me: Me | null; listing: SheetListing | null; openQueries: number | null; session: string; history?: AllocationRow[] }) {
  const t = listing?.tiles;
  const sheets = listing?.sheets ?? [];
  const counts = { entry: 0, workflow: 0, senate: 0, published: 0 };
  for (const s of sheets) counts[bucket(s.stage) as keyof typeof counts]++;
  const notSubmitted = sheets.filter((s) => s.stage === "ENTRY");
  const q = openQueries ?? 0;
  return (
    <>
      {q ? (
        <Note kind="bad" title={`${q} result quer${q === 1 ? "y" : "ies"} awaiting an answer`} action={<Link href="/results/queries" className="btn btn--urgent btn--sm">Answer queries</Link>}>
          A student has questioned a published mark. Each is routed to the department that owns the course and answered on the record; the corrected mark flows back through the chain.
        </Note>
      ) : (t?.notSubmitted ?? 0) ? (
        <Note kind="info" title={`${t?.notSubmitted} score sheet${(t?.notSubmitted ?? 0) === 1 ? " is" : "s are"} still with lecturers`} action={<Link href="/results/desk" className="btn btn--primary btn--sm">Result desk</Link>}>
          A sheet that misses this Senate waits for the next sitting, and its candidates carry an incomplete result. Chase the ones below before the deadline.
        </Note>
      ) : (
        <Note kind="ok" title="Every sheet is submitted" action={<Link href="/results/desk" className="btn btn--primary btn--sm">Result desk</Link>}>
          No sheet is still with a lecturer this session. Move the ones in the workflow along, and record the Senate minute when the Board sits.
        </Note>
      )}

      <Tiles items={[
        ["Expected sheets", String(t?.expected ?? 0), null, `In scope · ${session}`],
        ["Not submitted", String(t?.notSubmitted ?? 0), (t?.notSubmitted ?? 0) ? "var(--red-ink)" : "var(--green-ink)", "Still with lecturers", "/results/desk"],
        ["In the workflow", String(t?.inWorkflow ?? 0), null, "Moving through the desks", "/results/desk"],
        ["Senate approved", String(t?.senateApproved ?? 0), "var(--green-ink)", "Published to students"],
      ]} />

      <Panel title="Result pipeline" right={`${sheets.length} sheet${sheets.length === 1 ? "" : "s"} in scope`}>
        <Tiles cls="grid--4" items={[
          ["With lecturers", String(counts.entry), counts.entry ? "var(--red-ink)" : "var(--green-ink)", "Marks not submitted", "/results/desk"],
          ["In the approval chain", String(counts.workflow), counts.workflow ? "var(--chrome)" : null, "Verification → Records", "/results/desk"],
          ["Awaiting Senate", String(counts.senate), counts.senate ? "var(--chrome)" : null, "Ready for the minute", "/results/senate"],
          ["Published", String(counts.published), "var(--green-ink)", "Released to students"],
        ]} />
      </Panel>

      <Panel title="Sheets still with lecturers" right={notSubmitted.length ? `${notSubmitted.length} to chase` : "None outstanding"}>
        {notSubmitted.length ? (
          <DTable cols={["Course", "Lecturer", "Candidates|mid", "Status|num"]}
            rows={notSubmitted.slice(0, 12).map((s: SheetListed) => [
              <span key="c"><strong className="tnum">{s.courseCode}</strong>{s.sitting && s.sitting !== "MAIN" ? <span className="pill pill--info" style={{ marginLeft: 6 }}>{s.sitting === "RESIT" ? "Re-sit" : "Special"}</span> : null}<div className="sub2">{s.courseTitle}</div></span>,
              <span className="sub2" key="l">{s.lecturer ?? "No lecturer allocated"}</span>,
              <span className="tnum" key="n">{s.candidates}</span>,
              (s.daysLate ?? 0) > 0 ? <Pil kind="bad" key="s">{s.daysLate} days overdue</Pil> : <Pil kind="info" key="s">Not submitted</Pil>,
            ])} texts={notSubmitted.map((s) => `${s.courseCode} ${s.courseTitle} ${s.lecturer ?? ""}`)} />
        ) : <PBody><div className="sub2">Every sheet has left the lecturers. Nothing to chase for this Senate.</div></PBody>}
      </Panel>

      <AllocationHistory rows={history} mode="department" session={session} />

      <Panel title="Examinations desks" right={me?.name ? `Signed in as ${me.name}` : "Examinations"}>
        <PBody>
          <div style={{ display: "grid", gap: 8, gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))" }}>
            <Link href="/examinations/sessions" className="btn btn--ghost btn--sm">Examination sessions</Link>
            <Link href="/results/desk" className="btn btn--ghost btn--sm">Result desk</Link>
            <Link href="/results/approvals" className="btn btn--ghost btn--sm">Approvals</Link>
            <Link href="/results/queries" className="btn btn--ghost btn--sm">Result queries{q ? ` (${q})` : ""}</Link>
            <Link href="/exams/question-bank" className="btn btn--ghost btn--sm">CBT question bank</Link>
          </div>
        </PBody>
      </Panel>
    </>
  );
}
