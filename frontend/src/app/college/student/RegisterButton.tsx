"use client";

/** The College student's one act on the journey: register the level's fixed curriculum for the session, once the fees are cleared. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";

export function RegisterButton({ session, level, items, disabled, label }: { session: string; level: number; items: number; disabled?: boolean; label?: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function register() {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/college/register", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${level} Level registered for ${session}`) },
        body: JSON.stringify({ session }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(`${level} Level registered for ${session}`);
      router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <div>
      <Btn kind="primary" disabled={busy || disabled} onClick={() => void register()}>{busy ? "Registering…" : label ?? `Register ${level} Level · ${items} item${items === 1 ? "" : "s"}`}</Btn>
      {problem ? <div style={{ marginTop: 8 }}><ProblemNotice problem={problem} /></div> : null}
    </div>
  );
}
