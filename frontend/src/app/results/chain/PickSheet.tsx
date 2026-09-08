"use client";

import Link from "next/link";
import type { Scope } from "@/lib/scope";
import { STAGE_LABEL, type SheetListing } from "@/lib/results";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Note, Panel, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

/** without a sheet chosen, the sheets in scope, to pick one */
export function PickSheet({ scope, structure, sessions, listing }: { scope: Scope; structure: ScopeStructure; sessions: string[]; listing: SheetListing }) {
  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} what="result sets" count={listing.sheets.length} of={listing.tiles.expected} />
      <Note kind="info" title="Choose a sheet to see its chain">Every score sheet passes the same desks in the same order. Open one to see who has acted on it, who holds it now, and the marks as they stand.</Note>
      <Panel title="Score sheets in this scope" right={`${listing.sheets.length}`}>
        <DTable
          cols={["Course", "Department", "Candidates|mid", "Stage", "|num"]}
          rows={listing.sheets.map((s) => [
            <span key="c"><strong className="tnum">{s.courseCode}</strong><div className="sub2">{s.courseTitle}</div></span>,
            <span className="sub2" key="d">{s.deptName}</span>,
            <span className="tnum" key="n">{s.candidates}</span>,
            s.stage === "PUBLISHED" ? <Pil kind="ok" key="s">Senate approved</Pil> : s.stage === "ENTRY" ? <Pil kind="bad" key="s">Not submitted</Pil> : <Pil kind="info" key="s">{STAGE_LABEL[s.stage]?.[0] ?? s.stage}</Pil>,
            <Link key="a" href={`/results/chain?sheet=${s.id}`} className="btn btn--ghost btn--sm">Open</Link>,
          ])}
          texts={listing.sheets.map((s) => `${s.courseCode} ${s.courseTitle} ${s.deptName} ${s.stage}`)}
        />
      </Panel>
    </>
  );
}
