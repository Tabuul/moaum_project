"use client";

/** The forced password change (V485): the reason the change is required, then the current password, the new one and the new one
 *  again — each with an eye to show what is typed. The portal opens normally once it is changed; nothing here names the password
 *  the student signed in with. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PasswordInput } from "@/components/PasswordInput";
import { signOut } from "@/lib/sign-out";
import type { Problem } from "@/lib/api";

export interface PasswordStatus { mustChange: boolean; resetBySupport: boolean; temporary: boolean; firstPassword: boolean }

/** the student portal's rule: eight characters at the least, never the student's own number (the server holds both) */
const MIN = 8;

export function StudentPassword({ status }: { status: PasswordStatus }) {
  const router = useRouter();
  const [f, setF] = useState({ current: "", next: "", again: "" });
  const [problem, setProblem] = useState<Problem | null>(null);
  const [done, setDone] = useState(false);

  async function change() {
    setProblem(null);
    const r = await fetch("/api/bff/api/v1/student-auth/change-password", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ current: f.current, next: f.next }),
    });
    if (!r.ok) {
      setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
      return;
    }
    setDone(true);
    // the portal again, every check made afresh on the changed account
    router.push("/student");
    router.refresh();
  }

  const mismatch = f.again.length > 0 && f.again !== f.next;
  return (
    <>
      {status.resetBySupport ? (
        <Note kind="bad" title="PASSWORD RESET REQUIRED">Your portal password has been reset by ICT Support. You must change your password before continuing.</Note>
      ) : status.temporary ? (
        <Note kind="bad" title="PASSWORD CHANGE REQUIRED">You signed in with a temporary password. You must choose your own password before continuing.</Note>
      ) : (
        <Note kind="bad" title="PASSWORD CHANGE REQUIRED">Choose your own password before continuing to the Student Portal.</Note>
      )}
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Change password">
        <PBody>
          <form className="stack" onSubmit={(e) => { e.preventDefault(); }}>
            <div className="grid grid--3">
              <Field id="sp-cur" label="Current password" hint="The password you signed in with">
                <PasswordInput id="sp-cur" autoComplete="current-password" value={f.current} onChange={(e) => setF({ ...f, current: e.target.value })} />
              </Field>
              <Field id="sp-new" label="New password" hint={`At least ${MIN} characters, and not containing your matriculation, admission or JAMB number`}>
                <PasswordInput id="sp-new" autoComplete="new-password" value={f.next} onChange={(e) => setF({ ...f, next: e.target.value })} />
              </Field>
              <Field id="sp-again" label="Confirm new password" error={mismatch ? "The two do not match." : undefined}>
                <PasswordInput id="sp-again" autoComplete="new-password" value={f.again} onChange={(e) => setF({ ...f, again: e.target.value })} />
              </Field>
            </div>
            <div className="row row--inline" style={{ gap: 8 }}>
              <Btn kind="primary" type="submit" disabled={done || !f.current || f.next.length < MIN || f.next !== f.again || f.next === f.current}
                busyLabel="CHANGING PASSWORD..." onClick={() => change()}>Change password</Btn>
              <Btn kind="ghost" onClick={() => signOut()}>Sign out</Btn>
            </div>
            {f.next && f.next === f.current ? <div className="sub2">The new password must differ from the current one.</div> : null}
          </form>
        </PBody>
      </Panel>
    </>
  );
}
