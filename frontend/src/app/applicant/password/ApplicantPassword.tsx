"use client";
/** The applicant's own password (V687). After a temporary password from the Director of ICT, the Academic Office or ICT Support the
 *  portal opens nothing else until it is changed (the API's ApplicantPasswordGate); otherwise it is the applicant's to change at will. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PasswordInput } from "@/components/PasswordInput";
import { newPasswordProblem } from "@/lib/applicant-password";

export interface PasswordState { mustChange: boolean; temporaryUntil: string | null; name: string; applicationNo: string | null }

export function ApplicantPassword({ state }: { state: PasswordState }) {
  const router = useRouter();
  const [f, setF] = useState({ current: "", next: "", again: "" });
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const local = newPasswordProblem(f.next, f.again);
  async function save() {
    if (local) { setProblem({ status: 400, title: local }); return; }
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/applicant/me/password", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ currentPassword: f.current, newPassword: f.next }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      notify("Your password is changed.");
      setF({ current: "", next: "", again: "" });
      router.push("/applicant");
      router.refresh();
    } finally { setBusy(false); }
  }
  const until = state.temporaryUntil
    ? new Date(state.temporaryUntil).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })
    : null;
  return (
    <div className="stack" style={{ maxWidth: 560 }}>
      {state.mustChange ? (
        <Note kind="bad" title="Choose your own password to continue">
          {`You signed in with a temporary password from the University${until ? `, which works until ${until}` : ""}. Your application opens once you choose your own.`}
        </Note>
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Change password">
        <PBody>
          <Field id="ap-cur" label={state.mustChange ? "Temporary password" : "Current password"} required>
            <PasswordInput id="ap-cur" autoComplete="current-password" value={f.current} onChange={(e) => setF({ ...f, current: e.target.value })} />
          </Field>
          <Field id="ap-new" label="New password" required hint="Eight characters or more; not your JAMB or application number">
            <PasswordInput id="ap-new" autoComplete="new-password" value={f.next} onChange={(e) => setF({ ...f, next: e.target.value })} />
          </Field>
          <Field id="ap-again" label="New password again" required error={f.again && f.again !== f.next ? "The two do not match" : undefined}>
            <PasswordInput id="ap-again" autoComplete="new-password" value={f.again} onChange={(e) => setF({ ...f, again: e.target.value })} />
          </Field>
          <div className="row mt-2">
            <Btn kind="primary" disabled={busy || !f.current || !!local} onClick={() => void save()}>{busy ? "Saving…" : "Save my password"}</Btn>
          </div>
        </PBody>
      </Panel>
    </div>
  );
}
