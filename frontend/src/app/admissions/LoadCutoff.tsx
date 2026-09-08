"use client";

/**
 * The one UTME cut-off a session loads its JAMB lists under (V024): stated
 * before the file is uploaded, whatever the faculty or programme. A
 * candidate under it is read, held back on record, and not loaded. The
 * faculty's and the programme's own cut-offs are the screening's.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

export function LoadCutoff({ session, cutoff, may }: { session: string; cutoff: number | null; may: boolean }) {
  const router = useRouter();
  const [value, setValue] = useState(cutoff === null ? "" : String(cutoff));
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const n = parseInt(value, 10);
  const dirty = Number.isFinite(n) && n !== cutoff;

  async function state() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/load-cutoff`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`General UTME cut-off for loading the ${session} lists stated as ${n}`) },
        body: JSON.stringify({ cutoff: n }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel title="General UTME cut-off for loading the JAMB lists" right={cutoff === null ? <Pil kind="bad">Not stated · nothing loads</Pil> : <Pil kind="ok">{cutoff} · in force for loading</Pil>}>
      <PBody>
        <div className="sub2" style={{ marginBottom: 10 }}>
          Stated before the file is uploaded. A candidate on the JAMB list with a UTME score under it is read, held back on record beside the batch, and <b>not loaded</b> &mdash; whatever the faculty or programme. The faculty&rsquo;s and the programme&rsquo;s own cut-offs are not applied here: they are the screening&rsquo;s, and stay there.
        </div>
        <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center" }}>
          <input className="tnum ws__in" style={{ width: 96 }} value={value} inputMode="numeric" disabled={!may} aria-label="General UTME cut-off for loading" placeholder="150" onChange={(e) => setValue(e.target.value)} />
          <span className="sub2">of 400</span>
          <Btn kind="primary" disabled={!may || !dirty || busy} onClick={() => void state()}>{busy ? "Stating…" : cutoff === null ? "State the cut-off" : "Change the cut-off"}</Btn>
          {!may ? <span className="sub2">Stated by the Academic Office or the Registrar.</span> : null}
        </div>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {cutoff === null ? (
          <Note kind="bad" title="No UTME list can be loaded until this is stated">
            The loading refuses rather than guessing a number. State it here, then upload the list on the JAMB admission lists screen.
          </Note>
        ) : null}
      </PBody>
    </Panel>
  );
}
