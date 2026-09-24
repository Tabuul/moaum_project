"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

export function ChangePassword({ next }: { next: string }) {
  const router = useRouter();
  const [f, setF] = useState({ current: "", next: "", again: "" });
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function change() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/auth/change-password", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ current: f.current, next: f.next }) });
      if (!r.ok) {
        setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
        return;
      }
      router.push(next);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="Choose a password of your own">
        The Registry set the one you signed in with, so it changes now. At least ten characters, and not your username; a sentence you will remember is better than a word you will not.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Change your password">
        <PBody>
          <div className="grid grid--3">
            <div className="field"><label htmlFor="cp-cur">Current password</label><input id="cp-cur" type="password" autoComplete="current-password" value={f.current} onChange={(e) => setF({ ...f, current: e.target.value })} /></div>
            <div className="field"><label htmlFor="cp-new">New password</label><input id="cp-new" type="password" autoComplete="new-password" value={f.next} onChange={(e) => setF({ ...f, next: e.target.value })} /></div>
            <div className="field"><label htmlFor="cp-again">New password, again</label><input id="cp-again" type="password" autoComplete="new-password" value={f.again} onChange={(e) => setF({ ...f, again: e.target.value })} />{f.again && f.again !== f.next ? <div className="hint ink-red">The two do not match.</div> : null}</div>
          </div>
          <div><Btn kind="primary" disabled={busy || !f.current || f.next.length < 10 || f.next !== f.again} onClick={() => void change()}>{busy ? "Changing…" : "Change the password"}</Btn></div>
        </PBody>
      </Panel>
    </>
  );
}
