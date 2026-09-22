"use client";

/** tResultDesk — proto/part28.html: the stage this office holds, and the five acts it may perform. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { STAGE_LABEL, type SheetListing, type SheetListed } from "@/lib/results";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Note, Panel, PBody, Pil, Tiles, Two, Tick } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

const ORDER = ["ENTRY", "VERIFICATION", "DEPT_BOARD", "FACULTY_SCRUTINY", "FACULTY_COMPILATION", "FACULTY_BOARD", "RECORDS", "SENATE", "PUBLISHED"];

/** the desk of each office, as the chain names it (proto/part28 CHAIN) */
const DESK: Record<string, { stage: string; title: string; unit: string; back: string; next: string; cannot: string; can: string[] }> = {
  lecturer: { stage: "ENTRY", title: "Course lecturer", unit: "The department", back: "nowhere — it starts here", next: "verification", cannot: "approve its own marks, or change a mark once attested without a return.", can: ["Enter CA and examination for every candidate on the roll", "Record an outcome where there is no mark — absent, withheld, incomplete", "Attest the sheet and send it to verification", "Read a sheet returned with its reason and correct it as a new version", "Download the class list, the blank sheet and the template"] },
  exams: { stage: "VERIFICATION", title: "Departmental Examinations Officer", unit: "The department", back: "the lecturer", next: "the Departmental Board", cannot: "change a mark. A wrong mark goes back to the lecturer with the reason.", can: ["Verify that every candidate on the roll carries a mark or an outcome", "Check the arithmetic the engine already did, against the paper", "Send the verified sheet to the Departmental Board", "Return the sheet to the lecturer with the reason on the record", "Remind a lecturer whose sheet is late"] },
  hod: { stage: "DEPT_BOARD", title: "Head of Department", unit: "The Departmental Board", back: "verification", next: "faculty scrutiny", cannot: "approve a stage it already took, or a sheet it entered.", can: ["Approve at the Departmental Board", "Return to the lecturer with the Board's reason", "Read the distribution against the course's history", "Escalate a sheet not yet submitted", "Open the approval chain of any sheet in the department"] },
  facultyexams: { stage: "FACULTY_SCRUTINY", title: "Faculty Examinations Officer", unit: "The Faculty", back: "the Departmental Board", next: "faculty compilation", cannot: "approve; it scrutinises and recommends.", can: ["Scrutinise a departmentally approved set", "Recommend it to the Faculty Officer for compilation", "Return it with the reason", "See every department's sets in one list", "Remind and escalate"] },
  facultyofficer: { stage: "FACULTY_COMPILATION", title: "Faculty Officer", unit: "The Faculty", back: "faculty scrutiny", next: "the Faculty Board", cannot: "alter a mark while compiling.", can: ["Compile the scrutinised sets for the Board", "Send the compilation to the Dean", "Return a set with the reason", "Print the schedule", "Open the approval chain"] },
  dean: { stage: "FACULTY_BOARD", title: "Dean", unit: "The Faculty Board", back: "faculty compilation", next: "Exams and Records", cannot: "approve a stage it already took.", can: ["Approve at the Faculty Board", "Return with the Board's reason", "Read the fail rate against the course's mean", "Forward every approved set at once", "Open the approval chain"] },
  records: { stage: "RECORDS", title: "Exams and Records", unit: "The Registry", back: "the Faculty Board", next: "Senate", cannot: "publish; only the minute does.", can: ["Validate the Faculty Board's sets", "Prepare the Senate schedule", "Return a set with the reason", "Send validated sets to Senate", "Open the approval chain"] },
  registrar: { stage: "SENATE", title: "Registrar", unit: "Senate", back: "Exams and Records", next: "the candidates", cannot: "publish without the minute.", can: ["Record the Senate minute against every validated set", "Release the results to their candidates on the minute", "Return a set Senate withheld, with the reason", "Print the Senate schedule", "Open the approval chain"] },
  dregistrar: { stage: "SENATE", title: "Deputy Registrar", unit: "Senate", back: "Exams and Records", next: "the candidates", cannot: "publish without the minute.", can: ["Record the Senate minute against every validated set", "Release the results to their candidates on the minute", "Return a set Senate withheld, with the reason", "Print the Senate schedule", "Open the approval chain"] },
};

export function Desk({ scope, structure, sessions, listing, actingOffice }: { scope: Scope; structure: ScopeStructure; sessions: string[]; listing: SheetListing; actingOffice: string | null }) {
  const router = useRouter();
  const d = DESK[actingOffice ?? ""] ?? null;
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);

  if (!d) {
    return (
      <>
        <ScopeBar scope={scope} structure={structure} sessions={sessions} what="result sets" count={listing.sheets.length} of={listing.tiles.expected} />
        <Note kind="info" title="This office holds no stage of the result chain">The chain runs lecturer → verification → Departmental Board → faculty scrutiny → compilation → Faculty Board → Exams and Records → Senate. Every sheet in scope is readable from the approval chain.</Note>
      </>
    );
  }
  const me = ORDER.indexOf(d.stage);
  const here = listing.sheets.filter((s) => s.stage === d.stage);
  const late = listing.sheets.filter((s) => ORDER.indexOf(s.stage) < me);
  const past = listing.sheets.filter((s) => ORDER.indexOf(s.stage) > me);
  const forwardable = here.filter((s) => s.mayAct && !s.blockedForYou && !(s.failRate !== null && s.failRate > 50));

  async function forward() {
    setBusy(true);
    setProblem(null);
    let n = 0;
    try {
      for (const s of forwardable) {
        const r = await fetch(`/api/bff/api/v1/results/sheets/${s.id}/advance`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${s.courseCode} approved at ${d.stage.toLowerCase()} by ${actingOffice}`) }, body: "{}" });
        if (!r.ok) {
          setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
          break;
        }
        n++;
      }
      setSaid(n ? `${n} set${n === 1 ? "" : "s"} sent on to ${d.next}` : null);
      if (n) notify(`${n} set${n === 1 ? "" : "s"} sent on to ${d.next}`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const row = (s: SheetListed) => [
    <Two key="c" a={<span className="tnum">{s.courseCode}{s.sitting && s.sitting !== "MAIN" ? <span className="pill pill--info" style={{ marginLeft: 6 }}>{s.sitting === "RESIT" ? "Re-sit" : "Special"}</span> : null}</span>} b={s.courseTitle} />,
    <span className="sub2" key="d">{s.deptName}</span>,
    <span className="tnum" key="n">{s.candidates}</span>,
    s.failRate === null ? <span className="sub2" key="f">—</span> : <span className="tnum" key="f" style={s.failRate > 50 ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{s.failRate}%</span>,
  ];

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} what="result sets" count={listing.sheets.length} of={listing.tiles.expected} />
      <Note kind="info" title={`${d.title} — ${d.unit}`}>A set arrives from {d.back} and leaves for {d.next}. <b>What this desk may not do:</b> {d.cannot}</Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>Each act is on the record in your name, and you cannot act on the same set at the next desk.</Note> : null}
      <Tiles items={[
        ["On this desk now", String(here.length), "var(--chrome)", "Waiting on you"],
        ["Not yet arrived", String(late.length), late.length ? "var(--red-ink)" : null, "Still behind you in the chain"],
        ["Sent on", String(past.length), "var(--green-ink)", "Past this desk"],
        ["Published", String(listing.tiles.senateApproved), null, "Of the sets in scope"],
      ]} />
      <Panel title="What this office may do" right="Five acts, and no others">
        <PBody>
          <div className="grid grid--2">
            {d.can.map((c) => <div key={c} style={{ display: "flex", gap: 9, alignItems: "flex-start" }}><Tick size={16} colour="var(--green-ink)" /><span style={{ fontSize: 13, lineHeight: 1.5 }}>{c}</span></div>)}
          </div>
        </PBody>
      </Panel>
      <Panel title="On this desk" right="Open a set to read it, then decide">
        {here.length === 0 ? <div className="card__body sub2">Nothing is waiting at {STAGE_LABEL[d.stage]?.[0].toLowerCase() ?? d.stage} in this scope.</div> : (
          <DTable cols={["Course", "Department", "Candidates|mid", "Fail rate|mid", "Lecturer", "Action|num"]}
            rows={here.map((s) => [...row(s), <span className="sub2" key="l">{s.lecturer ?? "—"}</span>,
              <span key="a">{s.blockedForYou ? <Pil kind="bad">You took the previous stage</Pil> : null} <Link href={`/results/chain?sheet=${s.id}`} className={`btn btn--sm ${s.failRate !== null && s.failRate > 50 ? "btn--urgent" : "btn--primary"}`}>Open</Link></span>])}
            texts={here.map((s) => `${s.courseCode} ${s.courseTitle} ${s.deptName}`)} />
        )}
      </Panel>
      {late.length ? (
        <Panel title="Not yet arrived" right="These are what will hold the level, not the course">
          <DTable cols={["Course", "Department", "Candidates|mid", "Fail rate|mid", "Stopped at", "Waiting on", "Action|num"]}
            rows={late.map((s) => [...row(s), <Pil kind="bad" key="st">{STAGE_LABEL[s.stage]?.[0] ?? s.stage}</Pil>, <span className="sub2" key="w">{STAGE_LABEL[s.stage]?.[1] ?? ""}{s.daysLate ? ` · ${s.daysLate} days late` : ""}</span>, <Link key="a" href={`/results/chain?sheet=${s.id}`} className="btn btn--ghost btn--sm">Chain</Link>])}
            texts={late.map((s) => `${s.courseCode} ${s.courseTitle} ${s.deptName}`)} />
        </Panel>
      ) : null}
      <Panel title={`Send on to ${d.next}`}>
        <PBody>
          <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center" }}>
            {d.stage === "SENATE" ? (
              <Link href="/results/senate" className="btn btn--primary">Record the Senate minute</Link>
            ) : (
              <button className="btn btn--primary" disabled={busy || forwardable.length === 0} onClick={() => void forward()}>{busy ? "Sending…" : `Forward ${forwardable.length} set${forwardable.length === 1 ? "" : "s"} to ${d.next}`}</button>
            )}
            <Link href="/results/chain" className="btn btn--ghost">Open the approval chain</Link>
          </div>
        </PBody>
      </Panel>
    </>
  );
}
