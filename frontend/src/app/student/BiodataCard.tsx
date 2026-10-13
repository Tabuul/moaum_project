"use client";

/** V425: where the student's biodata stands, on the dashboard — one line and a button, never a paragraph; and the student's own
 *  word that a record that came over from the old portal (or has gone unreviewed) is correct */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Panel, PBody, Pil } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface BiodataStatus {
  status: "UP_TO_DATE" | "INCOMPLETE" | "REVIEW_REQUIRED" | "OUTDATED";
  required: number; completed: number; missing?: string[] | null; missing_labels?: string[] | null;
  last_updated?: string | null; confirmed_at?: string | null; migrated?: boolean | null;
}

export function BiodataCard({ b }: { b: BiodataStatus | null }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  if (!b || b.status === "UP_TO_DATE") {
    return null;
  }
  const missing = Math.max(0, b.required - b.completed);
  const incomplete = b.status === "INCOMPLETE";
  const title = incomplete ? "Biodata update required" : b.status === "OUTDATED" ? "Biodata review due" : "Biodata review required";
  const line = incomplete
    ? `${missing} required field${missing === 1 ? "" : "s"} incomplete${b.missing_labels?.length ? ": " + b.missing_labels.slice(0, 4).join(", ") + (b.missing_labels.length > 4 ? ", …" : "") : "."}`
    : b.status === "OUTDATED" ? "Your record has not been reviewed for some time. Check it, then confirm it is still correct."
    : "Your record came over from the old portal. Check it, then confirm it is correct.";

  async function confirm() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/me/biodata/confirm", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("My biodata is correct") }, body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify("Thank you — your biodata is confirmed");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel title="Biodata" right={<Pil kind={incomplete ? "bad" : "warn"}>{title.toUpperCase()}</Pil>}>
      <PBody>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <div className="row row--between row--wrap">
          <div>
            <div className="b600">{title}</div>
            <div className="sub2">{line}</div>
          </div>
          <span className="row row--inline row--tight">
            <LinkBtn kind={incomplete ? "primary" : "secondary"} size="sm" href="/student/biodata">{incomplete ? "Update biodata" : "Review biodata"}</LinkBtn>
            {!incomplete ? <Btn kind="primary" size="sm" disabled={busy} onClick={() => void confirm()}>{busy ? "Confirming…" : "My biodata is correct"}</Btn> : null}
          </span>
        </div>
      </PBody>
    </Panel>
  );
}
