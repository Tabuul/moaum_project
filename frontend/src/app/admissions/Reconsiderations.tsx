"use client";

/** Non-qualified candidates who hold five O'Level credits and could be moved to an open programme they qualify for.
 *  The office reviews the suggestions and sends each candidate an email; nobody is emailed twice. */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
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
}

const OFFICE = ["academic", "registrar", "dregistrar"];

export function Reconsiderations({ session, actingOffice }: { session: string; actingOffice: string | null }) {
  const may = OFFICE.includes(actingOffice ?? "");
  const [candidates, setCandidates] = useState<Candidate[] | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
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

  async function send() {
    if (!window.confirm("Email every listed candidate who has not yet been told their suggested programme(s)?")) return;
    setBusy(true);
    setProblem(null);
    setSent(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/reconsiderations/notify`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Suggested-programme emails sent for ${session}`) }, body: "{}",
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setSent(`${j.sent} candidate${j.sent === 1 ? "" : "s"} emailed${j.skippedNoEmail ? `, ${j.skippedNoEmail} skipped (no email on file)` : ""}.`);
      await load();
    } finally {
      setBusy(false);
    }
  }

  const pending = (candidates ?? []).filter((c) => !c.notifiedAt && c.email).length;

  return (
    <Panel title="Reconsiderations — candidates who could be moved"
           right={<span style={{ display: "inline-flex", gap: 8, alignItems: "center" }}>
             <span className="sub2">{candidates == null ? "…" : `${candidates.length} candidate${candidates.length === 1 ? "" : "s"}`}</span>
             {may && pending > 0 ? <Btn kind="primary" disabled={busy} onClick={() => void send()}>{busy ? "Sending…" : `Send suggestions to ${pending}`}</Btn> : null}
           </span>}>
      <PBody>
        <div className="sub2" style={{ marginBottom: 8 }}>
          Not offered their own programme, but hold O&rsquo;Level credits in English, Mathematics and three other subjects, and
          qualify for an open programme (its cut-off met, its compulsory subjects credited, a seat free). The suggestion is the
          office&rsquo;s to act on; sending emails the candidate their options.
        </div>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {sent ? <Note kind="ok" title="Sent">{sent}</Note> : null}
        {candidates != null && candidates.length === 0 && !problem ? (
          <Note kind="info" title="Nobody to move">No non-qualified candidate currently qualifies for another open programme.</Note>
        ) : null}
        {candidates && candidates.length > 0 ? (
          <DTable
            cols={["Candidate", "JAMB|mid", "Not offered", "Suggested programmes", "Email|mid", "Told|num"]}
            rows={candidates.map((c) => [
              c.name,
              <span className="tnum" key="j">{c.regNo}</span>,
              c.currentProgramme,
              c.suggestions.map((sug) => sug.name).join(", "),
              c.email ?? <span className="sub2" key="e">— none —</span>,
              c.notifiedAt ? <Pil kind="ok" key="t">{new Date(c.notifiedAt).toLocaleDateString("en-GB")}</Pil> : <Pil kind="grey" key="t">No</Pil>,
            ])}
            texts={candidates.map((c) => `${c.name} ${c.regNo} ${c.currentProgramme} ${c.suggestions.map((sug) => sug.name).join(" ")}`)}
          />
        ) : null}
      </PBody>
    </Panel>
  );
}
