"use client";
/** V766: the transfer applicant changes their password: the current one, and a new one of eight characters or more that is neither the
 *  JAMB number nor the application number (IUT_PASSWORD). Once admitted, this password opens the student door with the admission number
 *  at the first sign-in there, which carries it over (D18); from then on the student portal keeps its own, and a change here does not
 *  reach it (portalOpened). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PasswordInput } from "@/components/PasswordInput";
import { newPasswordProblem } from "@/lib/applicant-password";
import { numberOf } from "@/lib/transfer-application";
import { ME, call } from "../../call";

export function TransferPassword({ applicationNo, jambRegNo, admitted, portalOpened = false }: {
  applicationNo: string; jambRegNo: string | null; admitted: boolean; portalOpened?: boolean;
}) {
  const router = useRouter();
  const [f, setF] = useState({ current: "", next: "", again: "" });
  const [problem, setProblem] = useState<Problem | null>(null);
  const forbidden = [applicationNo, jambRegNo].filter(Boolean).map((x) => numberOf(String(x)));
  const local = newPasswordProblem(f.next, f.again) ?? (forbidden.includes(numberOf(f.next)) ? "Not your JAMB number or application number." : null);
  async function save() {
    if (local) { setProblem({ status: 400, title: local }); return; }
    setProblem(null);
    const r = await call("POST", `${ME}/password`, { current: f.current, next: f.next });
    if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
    notify("Your password is changed.");
    setF({ current: "", next: "", again: "" });
    router.push("/transfer/portal");
    router.refresh();
  }
  return (
    <div className="stack" style={{ maxWidth: 560 }}>
      {admitted && !portalOpened ? (
        <Note kind="info" title="Your first sign-in as a student uses this password">Sign in as a student with your admission number and this password. From then on
          the student portal keeps its own password, changed there.</Note>
      ) : admitted ? (
        <Note kind="info" title="Your student portal has its own password">You have signed in as a student, so a password changed here opens only this application
          page. Change the student portal&rsquo;s password in the student portal.</Note>
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Change password">
        <PBody>
          <Field id="tpw-cur" label="Current password" required>
            <PasswordInput id="tpw-cur" autoComplete="current-password" value={f.current} onChange={(e) => setF({ ...f, current: e.target.value })} />
          </Field>
          <Field id="tpw-new" label="New password" required hint="Eight characters or more; not your JAMB number or application number">
            <PasswordInput id="tpw-new" autoComplete="new-password" value={f.next} onChange={(e) => setF({ ...f, next: e.target.value })} />
          </Field>
          <Field id="tpw-again" label="New password again" required error={f.again && f.again !== f.next ? "The two do not match" : undefined}>
            <PasswordInput id="tpw-again" autoComplete="new-password" value={f.again} onChange={(e) => setF({ ...f, again: e.target.value })} />
          </Field>
          <div className="row mt-2">
            <Btn kind="primary" disabled={!f.current || !!local} title={local ?? undefined} onClick={() => save()}>Save my password</Btn>
          </div>
        </PBody>
      </Panel>
    </div>
  );
}
