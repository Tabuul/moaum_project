"use client";

/** tPipeline — proto/part26.html: the stages a result passes, and where every set in scope is now. */
import { useQueryNav } from "@/lib/query-nav";
import type { Scope } from "@/lib/scope";
import { STAGE_LABEL, type SheetListing } from "@/lib/results";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

/** the nine stages, with what happens and what each cannot pass without (proto/part26 RP_STAGES, read against the chain V013 carries) */
export const RP_STAGES: [string, string, string, string, string][] = [
  ["ENTRY", "Entry", "Course lecturer", "The lecturer types CA and examination against every approved registration, or records an outcome where there is no mark, then attests.", "A mark or an outcome for every candidate on the roll. A blank row stops the sheet leaving."],
  ["VERIFICATION", "Verification", "Departmental Examinations Officer", "A second academic checks completeness and the arithmetic against the paper, then sends it to the Board or returns it with the reason.", "A different person from the one who entered it."],
  ["DEPT_BOARD", "Departmental Board", "Head of Department", "The Board reads the distribution against the course's own history and approves or returns.", "A person who did not take the previous stage."],
  ["FACULTY_SCRUTINY", "Faculty scrutiny", "Faculty Examinations Officer", "Every department's sets are scrutinised in one list and recommended for compilation.", "The Departmental Board's approval on the record."],
  ["FACULTY_COMPILATION", "Faculty compilation", "Faculty Officer", "The scrutinised sets are compiled for the Faculty Board.", "Scrutiny completed; nothing altered in compiling."],
  ["FACULTY_BOARD", "Faculty Board", "Dean", "The Board approves the compilation and forwards it to Exams and Records.", "A fail rate above half the candidates is read before it is approved."],
  ["RECORDS", "Exams and Records", "The Registry", "The sets are validated and the Senate schedule is prepared.", "The Faculty Board's approval on the record."],
  ["SENATE", "Senate", "Registrar, on the minute", "Senate approves the schedule as a body; the Registrar records the minute against every set.", "A minute number. Nothing is published without one."],
  ["PUBLISHED", "Published", "Nobody — the candidates", "The result is visible to its candidates, statements can be issued, the transcript compiler sees the set, and the query window opens.", "The Senate minute on the face of the set."],
];

export function Pipeline({ scope, structure, sessions, listing, at, office }: { scope: Scope; structure: ScopeStructure; sessions: string[]; listing: SheetListing; at: number; office?: string | null }) {
  // a lecturer sees only their own courses; a HOD only their department (and the programmes under it)
  const hide: ("fac" | "dept" | "prog" | "level")[] = office === "lecturer" ? ["fac", "dept", "prog", "level"] : office === "hod" ? ["fac", "dept"] : [];
  const queryNav = useQueryNav();
  const s = RP_STAGES[at];
  const t = listing.tiles;
  const go = (n: number) => { const q = new URLSearchParams(window.location.search); q.set("at", String(n)); queryNav(`/results/pipeline?${q.toString()}`); };
  const counts = RP_STAGES.map(([code]) => listing.sheets.filter((x) => x.stage === code).length);
  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} what="result sets" count={listing.sheets.length} of={t.expected} hide={hide} />
      <Note kind="info" title="One journey, and every stage has a name on it">
        A result is not a file that appears at the Registry in December. It is a record that starts when a student registers a course and ends on a transcript, and at every point in between there is exactly one office that holds it and one thing that has to be true before it moves. Choose a stage below to see which.
      </Note>
      <Panel title="The result pipeline" right={`${scope.session}${scope.sem ? ` · ${scope.sem === "1" ? "First" : "Second"} semester` : ""}`}>
        <PBody>
          <div className="row row--tight">
            {RP_STAGES.map(([code, label], i) => (
              <Btn key={code} kind={i === at ? "primary" : "ghost"} onClick={() => go(i)} style={{ flexDirection: "column", alignItems: "flex-start", gap: 1 }}>
                <span>{i + 1}. {label}</span>
                <span className="tnum t-xs" style={{ fontWeight: 400, opacity: 0.8 }}>{counts[i]} set{counts[i] === 1 ? "" : "s"} here</span>
              </Btn>
            ))}
          </div>
        </PBody>
      </Panel>
      <Panel title={`Stage ${at + 1} · ${s[1]}`} right={s[2]}>
        <PBody>
          <div className="grid grid--2">
            <div><div className="eyebrow">What happens here</div><p style={{ margin: "var(--s-1) 0 0", lineHeight: 1.6 }}>{s[3]}</p></div>
            <div><div className="eyebrow">What it cannot pass without</div><p style={{ margin: "var(--s-1) 0 0", lineHeight: 1.6 }}>{s[4]}</p></div>
          </div>
          <div className="row mt-2">
            <Btn kind="ghost" disabled={at === 0} onClick={() => go(at - 1)}>← Previous stage</Btn>
            <Btn kind="primary" disabled={at === RP_STAGES.length - 1} onClick={() => go(at + 1)}>Next stage →</Btn>
            <LinkBtn href="/results/chain" kind="ghost">Open the approval chain</LinkBtn>
          </div>
        </PBody>
      </Panel>
      <Tiles items={[
        ["Expected sets", String(t.expected), null, "Offerings with a lecturer, in scope"],
        ["Past Senate", String(t.senateApproved), "var(--green-ink)", t.expected ? `${Math.round((100 * t.senateApproved) / t.expected)}% of the scope` : "Nothing expected yet"],
        ["In the workflow", String(t.inWorkflow), "var(--chrome)", "Moving between desks"],
        ["Not yet submitted", String(t.notSubmitted), t.notSubmitted ? "var(--red-ink)" : null, "With the lecturers"],
      ]} />
      <Panel title="Where every set is now" right="As the chain records it">
        {listing.sheets.length === 0 ? <div className="card__body sub2">No score sheet exists in this scope. Sheets are generated when the examination session is opened over the allocated offerings.</div> : (
          <DTable cols={["Course", "Department", "Candidates|mid", "Fail rate|mid", "Stage", "Waiting on", "Action|num"]}
            rows={listing.sheets.map((x) => {
              const hot = x.failRate !== null && x.failRate > 40;
              return [
                <Two key="c" a={<span className="tnum">{x.courseCode}</span>} b={x.courseTitle} />,
                <span className="sub2" key="d">{x.deptName}</span>,
                <span className="tnum" key="n">{x.candidates}</span>,
                x.failRate === null ? <span className="sub2" key="f">—</span> : <span className={`tnum${hot ? " ink-red b700" : ""}`} key="f">{x.failRate}%</span>,
                <Pil key="s" kind={x.stage === "PUBLISHED" ? "ok" : x.stage === "ENTRY" ? "bad" : "info"}>{STAGE_LABEL[x.stage]?.[0] ?? x.stage}</Pil>,
                <span className="sub2" key="w">{x.stage === "PUBLISHED" ? "Nobody — published" : STAGE_LABEL[x.stage]?.[1] ?? ""}</span>,
                <LinkBtn key="a" href={`/results/chain?sheet=${x.id}`} kind="ghost">Open</LinkBtn>,
              ];
            })}
            texts={listing.sheets.map((x) => `${x.courseCode} ${x.courseTitle} ${x.deptName} ${x.stage}`)} />
        )}
      </Panel>
      {listing.sheets.some((x) => x.failRate !== null && x.failRate > 50) ? (
        <Note kind="bad" title="A set is failing more than half its candidates" action={<LinkBtn href="/results/approvals" kind="primary">Open the queue</LinkBtn>}>
          {listing.sheets.filter((x) => x.failRate !== null && x.failRate > 50).map((x) => `${x.courseCode} at ${x.failRate}% of ${x.candidates}`).join(", ")}. That is not a result to approve on the nod, and it is not a result to refuse either: it is a result to ask a question about, with the lecturer present. The portal carries it forward if the Board approves it — it simply refuses to let it pass unremarked.
        </Note>
      ) : null}
    </>
  );
}
