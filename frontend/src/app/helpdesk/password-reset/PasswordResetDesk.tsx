"use client";

/**
 * Student Password Reset (V485): the student found by the server within the agent's reach (components/support/StudentFinder —
 * the matriculation number, the JAMB number, the application number, the name, the phone or the e-mail) and opened on the one
 * reset screen. Nothing is loaded until a search is made, and only the page of matches the server returns.
 */
import { useState } from "react";
import Link from "next/link";
import { LinkBtn, PageHead, Panel, PBody } from "@/components/proto/ui";
import { PasswordReset } from "@/components/support/PasswordReset";
import { StudentFinder } from "@/components/support/StudentFinder";

export function PasswordResetDesk({ q, student: student0 }: { q: string; student: string }) {
  const [student, setStudent] = useState(student0);

  return (
    <>
      <PageHead title="Student password reset" eyebrow="ICT Support Desk"
        description="Find the student, check who they are, and reset the password. The default student credential is the matriculation number, and the student must change it at the next sign-in. No email is needed, and the password is never shown or recorded."
        actions={<><LinkBtn href="/helpdesk/password-reset/bulk">Bulk password reset</LinkBtn><LinkBtn href="/helpdesk/password-reset/history">Password reset history</LinkBtn><LinkBtn href="/helpdesk">Support Desk</LinkBtn></>} />

      <StudentFinder q={q} selected={student} onSelect={setStudent} />

      {student ? (
        <Panel title="Student password reset" right={<Link className="lnk" href={`/helpdesk/students/${student}`}>Open the support record</Link>}>
          <PBody>
            <PasswordReset key={student} studentId={student} ticket={null} inline />
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
