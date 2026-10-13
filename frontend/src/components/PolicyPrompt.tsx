"use client";

/**
 * V441 — a legal document (the Privacy Policy first) published since the person last accepted one: asked once per version,
 * by the person's own act, recorded on the server; never again for an unchanged version. "Not now" puts it off for this
 * browser session only — the next sign-in asks again until it is accepted. An examination room is left alone.
 */
import { useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { idleExempt } from "@/lib/idle";
import { legalDay } from "@/lib/legal-text";

export interface PolicyPromptData {
  subjectKind: "STUDENT" | "STAFF" | "APPLICANT";
  documents: { document_id: string; kind: string; version: number; title: string; effective_on: string | null }[];
}

const PUT_OFF_KEY = "moaum_policy_put_off";
const PATH: Record<string, string> = { PRIVACY_POLICY: "/privacy-policy", TERMS_OF_USE: "/privacy-policy", COOKIE_NOTICE: "/privacy-policy#s-cookies" };

function putOff(): boolean {
  try { return sessionStorage.getItem(PUT_OFF_KEY) === "1"; } catch { return false; }
}

export function PolicyPrompt({ p }: { p: PolicyPromptData }) {
  const pathname = usePathname();
  const router = useRouter();
  const [open, setOpen] = useState(() => !putOff());
  const [read, setRead] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  if (!open || idleExempt(pathname) || !p.documents.length) return null;
  const names = p.documents.map((d) => `${d.title} (version ${d.version})`).join(" and ");

  async function accept() {
    setBusy(true);
    setProblem(null);
    try {
      for (const d of p.documents) {
        const r = await fetch("/api/bff/api/v1/privacy/acceptance", {
          method: "POST", headers: { "Content-Type": "application/json", "X-Reason": "Policy accepted by the person" },
          body: JSON.stringify({ documentId: d.document_id }),
        });
        if (!r.ok) { setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return; }
      }
      setOpen(false);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  function later() {
    try { sessionStorage.setItem(PUT_OFF_KEY, "1"); } catch { /* fine */ }
    setOpen(false);
  }

  return (
    <Modal title="Please read and accept" sub={names} onClose={later}
      foot={<>
        <button type="button" className="btn btn--primary btn--sm" disabled={busy || !read} onClick={() => void accept()}>{busy ? "Recording…" : "I have read and accept"}</button>
        <button type="button" className="btn btn--ghost btn--sm" disabled={busy} onClick={later}>Not now</button>
      </>}>
      <p style={{ marginTop: 0 }}>
        The University has published {p.documents.length === 1 ? "a new version of its" : "new versions of its"} {p.documents.map((d) => d.title).join(" and ")}.
        It explains what personal information the portal holds about you, why, who may see it and what you can ask. Your acceptance is recorded once for this version.
      </p>
      <ul style={{ margin: "0 0 10px", paddingLeft: 20 }}>
        {p.documents.map((d) => (
          <li key={d.document_id}><a className="lnk" href={PATH[d.kind] ?? "/privacy-policy"} target="_blank" rel="noopener">{d.title}, version {d.version}</a>{d.effective_on ? <span className="sub2"> · effective {legalDay(d.effective_on)}</span> : null}</li>
        ))}
      </ul>
      <label className="row row--inline row--tight"><input type="checkbox" checked={read} onChange={(e) => setRead(e.target.checked)} /> I have read {p.documents.length === 1 ? "it" : "them"}</label>
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}
