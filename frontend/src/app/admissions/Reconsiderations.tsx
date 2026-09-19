"use client";

/** Non-qualified candidates who hold five O'Level credits and could be moved to an open programme they qualify for.
 *  The office picks a programme from the candidate's qualified options and suggests it — the candidate is emailed
 *  that programme, and the choice is recorded. Nobody is suggested a programme they do not qualify for. */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Candidate {
  applicationId: string;
  name: string;
  regNo: string;
  currentProgramme: string;
  email: string | null;
  suggestions: { code: string; name: string }[];
  notifiedAt: string | null;
  suggestedProgramme: string | null;
}

const OFFICE = ["academic", "registrar", "dregistrar"];

export function Reconsiderations({ session, actingOffice }: { session: string; actingOffice: string | null }) {
  const may = OFFICE.includes(actingOffice ?? "");
  const [candidates, setCandidates] = useState<Candidate[] | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [choice, setChoice] = useState<Record<string, string>>({});
  const [rowBusy, setRowBusy] = useState<string | null>(null);
  const [sent, setSent] = useState<string | null>(null);

  async function load() {
    // no setState before the first await: keep this off the synchronous effect path
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/reconsiderations`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); setCandidates([]); return; }
      setProblem(null);
      setCandidates((j.candidates as Candidate[]) ?? []);
    } catch {
      setProblem({ status: 0, title: "Could not load the reconsiderations." });
      setCandidates([]);
    }
  }

  useEffect(() => {
    let live = true;
    void (async () => { await load(); if (!live) return; })();
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session]);

  async function suggest(c: Candidate) {
    const code = choice[c.applicationId] ?? c.suggestions[0]?.code;
    if (!code) return;
    const programme = c.suggestions.find((p) => p.code === code);
    setRowBusy(c.applicationId);
    setProblem(null);
    setSent(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/reconsiderations/suggest`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${programme?.name ?? code} suggested to ${c.name} for ${session}`) },
        body: JSON.stringify({ applicationId: c.applicationId, programme: code }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setSent(`${programme?.name ?? code} suggested to ${c.name}${j.emailed ? " — emailed" : " — recorded (no email on file)"}.`);
      notify(`${programme?.name ?? code} suggested to ${c.name}`);
      await load();
    } finally {
      setRowBusy(null);
    }
  }

  return (
    <Panel title="Reconsiderations — candidates who could be moved"
           right={<span className="sub2">{candidates == null ? "…" : `${candidates.length} candidate${candidates.length === 1 ? "" : "s"}`}</span>}>
      <PBody>
        <div className="sub2" style={{ marginBottom: 8 }}>
          Not offered their own programme, but hold O&rsquo;Level credits in English, Mathematics and three other subjects, and
          qualify for an open programme (its cut-off met, its compulsory subjects credited, a seat free). Choose a programme
          from each candidate&rsquo;s qualified options and suggest it; the candidate is emailed that programme.
        </div>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {sent ? <Note kind="ok" title="Suggested">{sent}</Note> : null}
        {candidates != null && candidates.length === 0 && !problem ? (
          <Note kind="info" title="Nobody to move">No non-qualified candidate currently qualifies for another open programme.</Note>
        ) : null}
        {candidates && candidates.length > 0 ? (
          <DTable
            cols={["Candidate", "JAMB|mid", "Not offered", "Suggested programme", "Told", "Suggest|num"]}
            rows={candidates.map((c) => {
              const selected = choice[c.applicationId] ?? c.suggestions[0]?.code ?? "";
              return [
                <span key="n">{c.name}{c.email ? "" : <div className="sub2">no email on file</div>}</span>,
                <span className="tnum" key="j">{c.regNo}</span>,
                c.currentProgramme,
                <select key="sel" className="ctl" value={selected} disabled={!may || rowBusy === c.applicationId}
                        style={{ minWidth: 220, maxWidth: 320 }}
                        onChange={(e) => setChoice((p) => ({ ...p, [c.applicationId]: e.target.value }))}
                        aria-label={`Programme to suggest to ${c.name}`}>
                  {c.suggestions.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
                </select>,
                c.notifiedAt
                  ? <span key="t" style={{ display: "inline-flex", flexDirection: "column", gap: 3, alignItems: "flex-start" }}><Pil kind="ok">{new Date(c.notifiedAt).toLocaleDateString("en-GB")}</Pil>{c.suggestedProgramme ? <span className="sub2">{c.suggestedProgramme}</span> : null}</span>
                  : <Pil kind="grey" key="t">No</Pil>,
                <Btn key="a" kind="primary" disabled={!may || rowBusy === c.applicationId || !selected}
                     onClick={() => void suggest(c)}>
                  {rowBusy === c.applicationId ? "Suggesting…" : c.notifiedAt ? "Re-suggest" : "Suggest"}
                </Btn>,
              ];
            })}
            texts={candidates.map((c) => `${c.name} ${c.regNo} ${c.currentProgramme} ${c.suggestions.map((sug) => sug.name).join(" ")}`)}
          />
        ) : null}
      </PBody>
    </Panel>
  );
}
