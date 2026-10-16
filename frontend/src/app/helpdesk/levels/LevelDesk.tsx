"use client";

/**
 * Student Level Management (V500): the student found within the agent's reach (components/support/StudentFinder) and the level read,
 * progressed or corrected on the one level screen (components/support/LevelManagement). Nothing is loaded until a search is made.
 */
import { useState } from "react";
import Link from "next/link";
import { LinkBtn, PageHead, Panel, PBody } from "@/components/proto/ui";
import { LevelManagement } from "@/components/support/LevelManagement";
import { StudentFinder } from "@/components/support/StudentFinder";

export function LevelDesk({ q, student: student0 }: { q: string; student: string }) {
  const [student, setStudent] = useState(student0);
  return (
    <>
      <PageHead title="Student level management" eyebrow="ICT Support Desk"
        description="Find the student, check the record, and progress the student to the next level or correct the level. Only the levels of the student's programme are offered; a reason is required, and the registrations, results and transcript are not changed."
        actions={<><LinkBtn href="/helpdesk/levels/history">Level change history</LinkBtn><LinkBtn href="/helpdesk">Support Desk</LinkBtn></>} />

      <StudentFinder q={q} selected={student} onSelect={setStudent} />

      {student ? (
        <Panel title="Student level management" right={<Link className="lnk" href={`/helpdesk/students/${student}`}>Open the support record</Link>}>
          <PBody>
            <LevelManagement key={student} studentId={student} ticket={null} />
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
