"use client";
/** V372: what to look at on a paper before publishing it — the same question twice, options that read the same, a blank option, an
 *  option such as "all of the above" when the options are shuffled, a multiple-select question with one key, keys bunched on one
 *  letter. Warnings for the office; the server refuses nothing for them. */
import { useEffect, useState } from "react";
import { Note, Panel, PBody, Pil } from "@/components/proto/ui";

export interface PaperCheck { n: number | null; question_id: string | null; severity: "HIGH" | "MEDIUM" | "LOW"; code: string; detail: string }

const SEVERITY: Record<PaperCheck["severity"], [string, "bad" | "warn" | "grey"]> = { HIGH: ["Fix before publishing", "bad"], MEDIUM: ["Check", "warn"], LOW: ["Note", "grey"] };

/** reload: changes whenever the paper is saved, so the checks are read again */
export function CbtPaperChecks({ examId, reload }: { examId: string; reload: string }) {
  const [checks, setChecks] = useState<PaperCheck[] | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let gone = false;
    fetch(`/api/bff/api/v1/cbt/exams/${encodeURIComponent(examId)}/checks`)
      .then(async (r) => { const j = await r.json().catch(() => null); if (gone) return; if (r.ok && Array.isArray(j)) { setChecks(j as PaperCheck[]); setFailed(false); } else setFailed(true); })
      .catch(() => { if (!gone) setFailed(true); });
    return () => { gone = true; };
  }, [examId, reload]);
  if (failed || !checks) return null;
  if (!checks.length) return <Note kind="ok" title="Paper checks">Nothing to look at.</Note>;
  const high = checks.filter((c) => c.severity === "HIGH").length;
  return (
    <Panel title="Paper checks" right={<span className="sub2">{checks.length} to look at{high ? ` · ${high} to fix before publishing` : ""}</span>}>
      <PBody>
        <div className="sub2 mb-2">Warnings only; nothing is refused for them.</div>
        <div style={{ display: "grid", gap: 8 }}>
          {checks.map((c, i) => (
            <div key={i} className="row row--inline row--tight" style={{ alignItems: "flex-start", gap: 10 }}>
              <Pil kind={SEVERITY[c.severity][1]}>{SEVERITY[c.severity][0]}</Pil>
              <span><b className="tnum">{c.n ? `Question ${c.n}` : "The paper"}</b> — {c.detail}</span>
            </div>
          ))}
        </div>
      </PBody>
    </Panel>
  );
}
