"use client";

/** What waits on this office in student clearance (V416): for each clearance in use and each stage the office signs, the
 *  students whose stage is open and undecided, the documents uploaded for it to review, and those past the deadline the
 *  Registry set — each figure opens the desk on those students. Nothing is drawn for an office that signs no stage. */
import { useEffect, useState } from "react";
import Link from "next/link";
import { Panel, PBody, Pil } from "@/components/proto/ui";

interface Awaiting { workflow: string; workflow_label: string; unit: string; label: string; awaiting: number; with_student: number; overdue: number; documents: number }

export function ClearanceAwaiting() {
  const [rows, setRows] = useState<Awaiting[] | null>(null);
  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/clearance/awaiting").then((r) => (r.ok ? r.json() : [])).then((j: Awaiting[]) => { if (live) setRows(Array.isArray(j) ? j : []); }).catch(() => { if (live) setRows([]); });
    return () => { live = false; };
  }, []);
  if (!rows || !rows.length) return null;
  const shown = rows.filter((r) => r.awaiting || r.documents || r.overdue);
  const desk = (r: Awaiting, status = "PENDING") => `/clearance?${new URLSearchParams({ wf: r.workflow, unit: r.unit, status }).toString()}`;
  return (
    <Panel title="Student clearance" right={<Link className="sub2" href="/clearance">Open the desk</Link>}>
      <PBody>
        {!shown.length ? <div className="sub2">Nobody is waiting on your office.</div> : shown.map((r) => (
          <div key={`${r.workflow}/${r.unit}`} className="row row--tight" style={{ flexWrap: "wrap", padding: "4px 0", borderBottom: "1px solid var(--line-2)" }}>
            <b style={{ minWidth: 220 }}>{r.workflow_label} · {r.label}</b>
            <Link href={desk(r)}><Pil kind={r.awaiting ? "info" : "grey"}>{r.awaiting.toLocaleString()} awaiting you</Pil></Link>
            {r.documents ? <Link href={desk(r, "")}><Pil kind="warn">{r.documents.toLocaleString()} document{r.documents === 1 ? "" : "s"} to review</Pil></Link> : null}
            {r.overdue ? <Link href={desk(r)}><Pil kind="bad">{r.overdue.toLocaleString()} past the deadline</Pil></Link> : null}
            {r.with_student ? <span className="sub2">{r.with_student.toLocaleString()} with the student to act</span> : null}
          </div>
        ))}
      </PBody>
    </Panel>
  );
}
