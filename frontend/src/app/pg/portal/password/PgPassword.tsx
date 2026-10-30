"use client";
/** The postgraduate applicant's own password (V706). After the School or ICT reset it to the application number — or, for an applicant
 *  brought over from the old portal, on its first sign-in on either number (V709) — the portal opens nothing else until it is changed
 *  (the API's ApplicantPasswordGate); otherwise it is the applicant's to change at will. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PasswordInput } from "@/components/PasswordInput";
import { newPasswordProblem } from "@/lib/applicant-password";

export interface PgPasswordState { mustChange: boolean; name: string; applicationNo: string | null; resetAt: string | null }

export function PgPassword({ state }: { state: PgPasswordState }) {
  const router = useRouter();
  const [f, setF] = useState({ current: "", next: "", again: "" });
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const local = newPasswordProblem(f.next, f.again);
  async function save() {
    if (local) { setProblem({ status: 400, title: local }); return; }
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/pg/me/password", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ currentPassword: f.current, newPassword: f.next }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      notify("Your password is changed.");
      setF({ current: "", next: "", again: "" });
      router.push("/pg/portal");
      router.refresh();
    } finally { setBusy(false); }
  }
  return (
    <div className="stack" style={{ maxWidth: 560 }}>
      {state.mustChange ? (
        <Note kind="bad" title="Choose your own password to continue">
          {`You signed in with your application number${state.applicationNo ? ` (${state.applicationNo})` : ""} or the old portal's. Your application opens once you choose your own password.`}
        </Note>
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Change password">
        <PBody>
          <Field id="pgp-cur" label={state.mustChange ? "The number you signed in with" : "Current password"} hint={state.mustChange ? "Your application number, or the old portal's" : undefined} required>
            <PasswordInput id="pgp-cur" autoComplete="current-password" value={f.current} onChange={(e) => setF({ ...f, current: e.target.value })} />
          </Field>
          <Field id="pgp-new" label="New password" required hint="Eight characters or more; not your application number, old or new">
            <PasswordInput id="pgp-new" autoComplete="new-password" value={f.next} onChange={(e) => setF({ ...f, next: e.target.value })} />
          </Field>
          <Field id="pgp-again" label="New password again" required error={f.again && f.again !== f.next ? "The two do not match" : undefined}>
            <PasswordInput id="pgp-again" autoComplete="new-password" value={f.again} onChange={(e) => setF({ ...f, again: e.target.value })} />
          </Field>
          <div className="row mt-2">
            <Btn kind="primary" disabled={busy || !f.current || !!local} onClick={() => void save()}>{busy ? "Saving…" : "Save my password"}</Btn>
          </div>
        </PBody>
      </Panel>
    </div>
  );
}
