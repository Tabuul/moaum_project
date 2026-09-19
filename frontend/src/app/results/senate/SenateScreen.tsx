"use client";

/** tSenate and tPublish — proto/part26.html: the schedule by faculty, the minute, and what a release does, in order. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import type { Senate } from "@/lib/results";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Note, Panel, PBody, Pil, RoleLine, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Steps } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) + ", " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function SenateScreen({ scope, structure, sessions, senate, actingOffice, publish }: { scope: Scope; structure: ScopeStructure; sessions: string[]; senate: Senate; actingOffice: string | null; publish: boolean }) {
  const router = useRouter();
  const [minute, setMinute] = useState("");
  const [fac, setFac] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [outcome, setOutcome] = useState<{ published: { id: string }[]; refused: { id: string; why: string }[]; minute: string } | null>(null);
  const may = actingOffice === "registrar" || actingOffice === "dregistrar";
  const latest = senate.minutes[0] ?? null;
  const semester = senate.semester === 1 ? "First" : "Second";

  async function record() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/results/senate/minute", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Senate minute ${minute} recorded for ${senate.session} semester ${senate.semester}`) }, body: JSON.stringify({ session: senate.session, sem: senate.semester, fac: fac || null, minute }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j ?? { status: r.status, title: r.statusText });
        return;
      }
      setOutcome(j);
      notify(`Senate minute ${minute} recorded`);
      setMinute("");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <RoleLine allowed={["registrar", "dregistrar"]} actingOffice={actingOffice} canAct={may}
        action="Publishing result sets on a Senate minute" />
      <ScopeBar scope={scope} structure={structure} sessions={sessions} what="result sets" count={senate.sets} of={senate.sets} />
      {publish ? (
        <Note kind={senate.published ? "ok" : "bad"} title={senate.published ? `${senate.published} set${senate.published === 1 ? " is" : "s are"} live to their candidates` : "Publication is held: there is no Senate minute"}>
          {senate.published
            ? `Released under ${senate.minutes.map((m) => m.minute).join(", ")}; the latest at ${latest ? when(latest.lastPublishedAt) : ""}. A candidate whose set was withheld sees that it was withheld and why, rather than an empty screen.`
            : "There is no minute to publish under, so there is nothing to release: the embargo lives in the data, and a database that has no approved set has nothing to show a student."}
        </Note>
      ) : (
        <Note kind={latest ? "ok" : "info"} title={latest ? `Senate minute ${latest.minute} is recorded` : "Nothing is published before the minute exists"}>
          {latest
            ? `${senate.published} result set${senate.published === 1 ? "" : "s"} carr${senate.published === 1 ? "ies" : "y"} a minute of Senate. Every one of them is now visible to its candidates, appears on a statement of results, and is available to the transcript compiler. The minute number is on the face of each document.`
            : "Senate approves results as a body, on a schedule prepared by the Registry. Until the minute is recorded, a result set that has passed every other desk is still not a result: the student sees nothing, the statement of results cannot be issued, and the transcript compiler does not see the set at all."}
        </Note>
      )}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {outcome ? (
        <Note kind={outcome.refused.length ? "bad" : "ok"} title={`${outcome.published.length} set${outcome.published.length === 1 ? "" : "s"} published under ${outcome.minute}${outcome.refused.length ? `, ${outcome.refused.length} refused` : ""}`}>
          {outcome.refused.map((r) => <div key={r.id}>{r.why}</div>)}
          {outcome.refused.length ? "A refused set stays at Senate for another holder of the office; the rule that no one person takes two consecutive stages applies to the Registrar as it applies to a lecturer." : "Each set carries the minute for the rest of its life, and so does every document generated from it."}
        </Note>
      ) : null}
      <Tiles items={publish ? [
        ["Sets released", String(senate.published), senate.published ? "var(--green-ink)" : "var(--red-ink)", latest ? when(latest.lastPublishedAt) : "Held"],
        ["Candidates affected", String(senate.candidatesPublished), null, "Registrations on the released sets"],
        ["Awaiting the minute", String(senate.atSenate), senate.atSenate ? "var(--chrome)" : null, "Validated, at Senate"],
        ["Not yet at Senate", String(senate.outstanding), senate.outstanding ? "var(--red-ink)" : null, "Still in the chain"],
      ] : [
        ["On the schedule", String(senate.atSenate), null, "Validated sets, awaiting the minute"],
        ["Published", String(senate.published), "var(--green-ink)", "Carrying a minute"],
        ["Sets not at Senate", String(senate.outstanding), senate.outstanding ? "var(--red-ink)" : null, "Named as outstanding"],
        ["Minute", latest ? latest.minute : "Not yet", latest ? "var(--green-ink)" : "var(--chrome)", latest ? when(latest.firstPublishedAt) : "When Senate has risen"],
      ]} />
      <Panel title={`Senate schedule — ${senate.session} ${semester} semester`} right="Prepared from the sheets, by faculty">
        {senate.faculties.length === 0 ? <div className="card__body sub2">No score sheet exists for {senate.session} {semester.toLowerCase()} semester. The schedule is empty until an examination session is opened and the sheets move.</div> : (
          <DTable cols={["Faculty", "Sets|mid", "Candidates|mid", "At Senate|mid", "Published|mid", "Outstanding|mid", "Recommendation|num"]}
            rows={senate.faculties.map((f) => [
              <strong key="f">{f.facultyName}</strong>,
              <span className="tnum" key="s">{f.sets}</span>,
              <span className="tnum" key="c">{f.candidates}</span>,
              <span className="tnum" key="a">{f.atSenate}</span>,
              <span className="tnum" key="p" style={{ color: "var(--green-ink)" }}>{f.published}</span>,
              <span className="tnum" key="o" style={f.outstanding ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{f.outstanding}</span>,
              f.atSenate === 0 ? <Pil kind="grey" key="r">{f.published === f.sets ? "All published" : "Nothing at Senate"}</Pil> : f.outstanding ? <Pil kind="ok" key="r">Approve, outstanding named</Pil> : <Pil kind="ok" key="r">Approve</Pil>,
            ])} />
        )}
      </Panel>
      {publish ? (
        <Panel title="What a release does, in order">
          <PBody>
            <Steps list={[
              [senate.published ? "done" : senate.atSenate ? "now" : "todo", "The minute is recorded against every set in the schedule", "Not against a batch job or a date. A set carries its minute number for the rest of its life, and so does every document generated from it."],
              [senate.published ? "done" : "todo", "The results become visible to their candidates", "Grade, GPA, CGPA and standing. A withheld set shows as withheld, with the reason the Board recorded."],
              [senate.published ? "done" : "todo", "Statements of results become issuable", "With the minute number, stating on the face that it is not a transcript."],
              [senate.published ? "done" : "todo", "The transcript compiler can see the set", "A transcript is compiled from Senate-approved sets only. Before the minute, the set does not exist to it."],
              [senate.published ? "done" : "todo", "The result-query window opens for seven days", "A query is against a mark, routed to the department that owns the course, and answered on the record."],
            ]} />
          </PBody>
        </Panel>
      ) : null}
      <Panel title={publish ? "Release control" : "Record the resolution"} right={publish ? (senate.atSenate ? "Held at the embargo" : "Nothing waiting") : "The Registrar, after Senate has risen"}>
        <PBody>
          {may ? (
            <>
              <div className="grid grid--3">
                <Field id="sen-no" label="Minute number" hint="The result reaches the student under this minute.">
                  <input id="sen-no" className="ctl tnum" value={minute} onChange={(e) => setMinute(e.target.value)} placeholder="SEN/2026/…" autoComplete="off" />
                </Field>
                <Field id="sen-fac" label="Faculty" hint="Every faculty on the schedule, or one.">
                  <select id="sen-fac" className="ctl" value={fac} onChange={(e) => setFac(e.target.value)}>
                    <option value="">Every faculty</option>
                    {senate.faculties.map((f) => <option key={f.facultyCode} value={f.facultyCode}>{f.facultyName}</option>)}
                  </select>
                </Field>
              </div>
              <div style={{ display: "flex", gap: 9, flexWrap: "wrap" }}>
                <button className="btn btn--primary" disabled={busy || !minute.trim() || senate.atSenate === 0} onClick={() => void record()}>{busy ? "Recording…" : publish ? "Release to candidates on the minute" : "Record the minute and release"}</button>
                {senate.atSenate === 0 ? <span className="sub2">Nothing is waiting at Senate in this scope.</span> : null}
                <Link href={publish ? "/results/senate" : "/results/publish"} className="btn btn--ghost">{publish ? "Go to Senate" : "Open publication"}</Link>
              </div>
            </>
          ) : (
            <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center" }}>
              <button className="btn btn--primary" disabled>{publish ? "Release to candidates" : "Record the minute"}</button>
              <span className="sub2">The Registrar records the minute; this office reads the schedule.</span>
            </div>
          )}
          <Note kind="info" title="Two people, not one">The minute is recorded by the Registry against sets Exams and Records validated. The office that validated a set does not also record the minute on it — BR-006 applies to a minute exactly as it applies to a mark, and the portal refuses the second act by the same person.</Note>
        </PBody>
      </Panel>
      {senate.minutes.length ? (
        <Panel title="Minutes recorded" right="Newest first">
          <DTable cols={["Minute", "Sets|mid", "Candidates|mid", "First release", "Last release"]}
            rows={senate.minutes.map((m) => [<b className="tnum" key="m">{m.minute}</b>, <span className="tnum" key="s">{m.sets}</span>, <span className="tnum" key="c">{m.candidates}</span>, <span className="sub2" key="f">{when(m.firstPublishedAt)}</span>, <span className="sub2" key="l">{when(m.lastPublishedAt)}</span>])} />
        </Panel>
      ) : null}
    </>
  );
}
