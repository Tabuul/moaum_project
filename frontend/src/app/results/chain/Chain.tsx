"use client";

/** staffChain — proto/part15.html: one sheet, every desk it passes, and the marks as they stand. */
import { reasonHeader } from "@/lib/reason";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { RS_STAGES, STAGE_LABEL, type SheetDetail } from "@/lib/results";
import { roleLabel, roleUnit } from "@/lib/offices";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Gate, Gates, Modal, Field, Step, TwoCol } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

const DESK_OF: Record<string, string> = {
  ENTRY: "lecturer", VERIFICATION: "exams", DEPT_BOARD: "hod", FACULTY_SCRUTINY: "facultyexams",
  FACULTY_COMPILATION: "facultyofficer", FACULTY_BOARD: "dean", RECORDS: "records", SENATE: "registrar",
};

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "long" }) + ", " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function Chain({ detail, actingOffice }: { detail: SheetDetail; actingOffice: string | null }) {
  const router = useRouter();
  const s = detail.sheet;
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [ask, setAsk] = useState<"return" | "minute" | null>(null);
  const [text, setText] = useState("");

  async function post(path: string, body: unknown, reason: string) {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) {
        setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
        return false;
      }
      router.refresh();
      return true;
    } finally {
      setBusy(false);
    }
  }

  const st = s.spineStage - 1;
  const published = s.stage === "PUBLISHED";
  const need = DESK_OF[s.stage];
  const mine = s.mayAct;
  const [, holder] = STAGE_LABEL[s.stage] ?? ["", ""];
  const returned = detail.chain.filter((d) => d.kind === "RETURN");
  const lastReturn = returned[returned.length - 1];

  /* the ladder: every decision as it was taken */
  const ladder: ["done" | "now" | "todo", string, string][] = [];
  ladder.push([detail.marks.length ? "done" : "todo", "Scores entered", detail.marks.length ? `${s.lecturer ?? "The lecturer"} · ${detail.marks.length} of ${s.candidates} marks` : "No marks yet"]);
  for (const d of detail.chain) {
    const what = d.kind === "RETURN" ? `Returned by ${roleLabel(d.actorOffice)}` : d.kind === "SUBMIT" ? "Submitted for verification" : `${STAGE_LABEL[d.toStage]?.[0] ?? d.toStage}`;
    ladder.push(["done", what, `${d.actor ?? roleLabel(d.actorOffice)} · ${when(d.decidedAt)}${d.comment ? ` · “${d.comment}”` : ""}`]);
  }
  if (!published) ladder.push(["now", `${STAGE_LABEL[s.stage]?.[0] ?? s.stage}`, `With ${holder || roleLabel(need)}`]);

  return (
    <>
      <Panel title="You are signed in as" right="The chain is read from every desk; the action belongs to one">
        <PBody>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button className="btn btn--primary btn--sm" style={{ flexDirection: "column", alignItems: "flex-start", gap: 1, textAlign: "left" }}>
              <span>{roleLabel(actingOffice)}</span>
              <span style={{ fontWeight: 400, opacity: 0.8, fontSize: 11 }}>{roleUnit(actingOffice) || "The University"}</span>
            </button>
          </div>
        </PBody>
      </Panel>

      <Tiles items={[
        ["Course", s.courseCode, null, `${s.courseTitle} · ${s.units} units`],
        ["Students", String(s.candidates), null, `${detail.marks.length} of ${s.candidates} marks entered`],
        ["Fail rate", s.failRate === null ? "—" : `${s.failRate}%`, s.failRate !== null && s.failRate > 50 ? "var(--red-ink)" : "var(--green-ink)", s.failRate === null ? "No graded marks yet" : "Over the graded candidates"],
        ["Stage", `${s.spineStage} of 6`, published ? "var(--green-ink)" : "var(--chrome)", RS_STAGES[st][0]],
      ]} />

      {problem ? <ProblemNotice problem={problem} /> : null}

      {published ? (
        <Note kind="ok" title="Senate has approved this result set and it is published" action={<><Btn kind="ghost">Raise an amendment</Btn> <Btn kind="ghost">View as a student</Btn></>}>
          {s.candidates} students can now see their marks. Nothing on this sheet can be changed by anyone; a correction from this point is an amendment, which opens its own record and is reported to Senate at its next sitting. Minute <b>{detail.senateMinute}</b>.
        </Note>
      ) : mine && !s.blockedForYou ? (
        <Note kind="info" title={`This stage is yours: ${RS_STAGES[st][2] || "Approve"}`} action={<>
          <Btn kind="go" disabled={busy} onClick={() => (s.stage === "SENATE" ? setAsk("minute") : void post(`/api/bff/api/v1/results/sheets/${s.id}/advance`, {}, `${s.courseCode}: ${RS_STAGES[st][2]}`))}>{RS_STAGES[st][2] || "Approve"}</Btn>{" "}
          {s.stage !== "ENTRY" ? <Btn kind="urgent" disabled={busy} onClick={() => { setAsk("return"); setText(""); }}>Return to the lecturer</Btn> : null}
        </>}>
          Approving is a signature. Your name, the time and the exact figures you approved are written to the audit trail and cannot afterwards be edited or deleted by anyone, including the Directorate of ICT.
        </Note>
      ) : s.blockedForYou ? (
        <Note kind="bad" title="You performed the previous stage, so this one is not open to you">
          You recorded the last approval on this sheet. The rule is not a matter of trust — it is that a single person must never be able to move a result from entry to publication alone. Another holder of the {roleLabel(need)} office must act.
        </Note>
      ) : (
        <Note kind="info" title={`This sheet is with ${holder || roleLabel(need)}`}>
          You are signed in as {roleLabel(actingOffice)}. You can read the sheet and the chain, but the action at this stage belongs to another desk.
        </Note>
      )}

      {s.returnedTimes > 0 && lastReturn ? (
        <Note kind="info" title={`This sheet was returned ${s.returnedTimes === 1 ? "once" : `${s.returnedTimes} times`} and corrected`}>
          {roleLabel(lastReturn.actorOffice)} sent it back on {when(lastReturn.decidedAt)}: “{lastReturn.comment}”. Every amendment is on the record with the reason, and the sheet re-entered the chain at verification — not at the stage it was returned from.
        </Note>
      ) : null}

      <TwoCol>
        <Panel title="Approval chain" right={RS_STAGES[st][0]}>
          <div style={{ padding: "4px 0" }}>
            {ladder.map((e, i) => (
              <div key={i} style={{ padding: "10px 16px", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
                <Step state={e[0]} title={e[1]} sub={e[2]} />
              </div>
            ))}
          </div>
        </Panel>
        <Panel title="What the rules require" right="BR-004 · BR-006">
          <PBody>
            <Gates>
              <Gate state="done" title="Four approvals, four desks" sub="Verification, department, faculty, Senate. None can be skipped and none can be reordered." />
              <Gate state="done" title="No two consecutive stages by one person" sub="The system refuses it even where one person holds both offices." />
              <Gate state="done" title="A mark is never overwritten" sub="An amendment writes a new value and keeps the old one, with the reason and the author." />
              <Gate state="done" title="Nothing reaches a student before Senate" sub="There is no preview, no provisional release and no departmental leak path." />
              <Gate state={published ? "done" : "todo"} title="The engine version is stored with the result" sub={`Grades were computed by ${detail.engineVersion ?? "GpaCalculator 2.1"}. If the grading scheme changes, this result still recomputes to what Senate approved.`} last />
            </Gates>
          </PBody>
        </Panel>
      </TwoCol>

      <Panel title="Marks on this sheet" right="CA and examination are recorded; total, grade and point are computed">
        <DTable
          cols={["Student", "CA|mid", "Exam|mid", "Total|mid", "Grade|mid", "Point|mid", "Amended|num"]}
          rows={detail.marks.map((m) => [
            <Two key="s" a={`${m.surname}, ${m.otherNames}`} b={m.number} />,
            <span className="tnum" key="ca">{m.ca ?? "—"}</span>,
            <span className="tnum" key="ex">{m.exam ?? "—"}</span>,
            <b className="tnum" key="t">{m.total ?? m.outcome}</b>,
            m.grade ? <Pil kind={(m.points ?? 0) >= 4 ? "ok" : (m.points ?? 0) >= 1 ? "info" : "bad"} key="g">{m.grade}</Pil> : <span className="sub2" key="g">—</span>,
            <span className="tnum" key="p">{m.points ?? "—"}</span>,
            m.amended ? <Pil kind="bad" key="a">Amended — version {m.version}</Pil> : <span className="sub2" key="a">—</span>,
          ])}
          texts={detail.marks.map((m) => `${m.surname} ${m.otherNames} ${m.number}`)}
        />
      </Panel>

      <Note kind={published ? "ok" : "bad"} title={published ? "What the student sees: their mark, their grade and the date Senate approved it" : "What the student sees right now: nothing at all"}>
        {published
          ? "Along with the engine version that produced the grade, so a query years later can be answered exactly."
          : `The result page shows “awaiting Senate approval” for this course. ${s.candidates} students will ask their lecturer, and the honest answer is that it is at stage ${s.spineStage} of 6 — which this chain lets the lecturer say precisely.`}
      </Note>

      {ask ? (
        <Modal title={ask === "return" ? "Return the sheet to the lecturer" : "Approve for Senate"} sub={ask === "return" ? "The reason goes on the record" : "Cite the Senate minute"} onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind={ask === "return" ? "urgent" : "go"} disabled={!text.trim() || busy} onClick={async () => {
            const ok = ask === "return"
              ? await post(`/api/bff/api/v1/results/sheets/${s.id}/return`, { comment: text }, `${s.courseCode} returned`)
              : await post(`/api/bff/api/v1/results/sheets/${s.id}/advance`, { minute: text }, `${s.courseCode} approved for Senate under ${text}`);
            if (ok) setAsk(null);
          }}>{ask === "return" ? "Return it" : "Approve and publish"}</Btn></>}>
          <Field id="chain-text" label={ask === "return" ? "Why it is returned" : "Senate minute"} hint={ask === "return" ? "It re-enters the chain at verification." : "The result reaches the student under this minute."}>
            <input id="chain-text" className="ctl" value={text} onChange={(e) => setText(e.target.value)} autoComplete="off" placeholder={ask === "minute" ? "SEN/2026/…" : ""} />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
