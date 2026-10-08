"use client";
/** V367: the GST/EPS courses bound to programmes but not opened for the session. A course is owed only when it runs in the session
 *  (V366), so until it is opened its students owe nothing and see no fee. The office that runs the courses opens them all at once,
 *  each in its own semester; everyone else is told whose act it is. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note } from "@/components/proto/ui";
import type { GstGap } from "@/lib/gst";

export function GstGapsNote({ gaps, session, office, may }: { gaps: GstGap[] | undefined; session: string; office: "GST" | "EPS" | null; may: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  if (!gaps || !gaps.length) return null;
  const word = office ?? "GST/EPS";
  const list = gaps.slice(0, 12).map((g) => `${g.course_code} (${g.levels} level, ${g.programmes} programme${g.programmes === 1 ? "" : "s"})`).join(", ") + (gaps.length > 12 ? ` and ${gaps.length - 12} more` : "");
  async function openAll() {
    if (!office) return;
    if (!window.confirm(`Open the ${gaps!.length} ${word} course${gaps!.length === 1 ? "" : "s"} not yet offered for ${session}, each in its own semester? Their students then owe the GST fee for them.`)) return;
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/gst/${office}/offerings/open-all?session=${encodeURIComponent(session)}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${word} courses opened for ${session}`) }, body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(`${j?.opened ?? 0} ${word} course${j?.opened === 1 ? "" : "s"} opened for ${session}`);
      router.refresh();
    } finally { setBusy(false); }
  }
  return (
    <Note kind="bad" title={`${gaps.length} ${word} course${gaps.length === 1 ? " is" : "s are"} bound to programmes but not opened for ${session}`}
      action={may && office ? <Btn kind="primary" disabled={busy} onClick={() => void openAll()}>{busy ? "Opening…" : `Open them for ${session}`}</Btn> : null}>
      Until a course is opened for the session its students owe nothing for it and see no GST fee: {list}.
      {may && office ? " Opening them puts each in its own semester; a course that should not run is deactivated on the courses page instead." : ` The ${office ? `${office} office opens them` : "GST and EPS offices open them"} on their courses page.`}
    </Note>
  );
}
