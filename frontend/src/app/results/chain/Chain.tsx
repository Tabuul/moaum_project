"use client";

/** staffChain — proto/part15.html: one sheet, every desk it passes, and the marks as they stand. */
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { RS_STAGES, STAGE_LABEL, type SheetDetail } from "@/lib/results";
import { roleLabel, roleUnit } from "@/lib/offices";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Gate, Gates, Modal, Field, Step, TwoCol } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Amendments } from "./Amendments";

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
  const [ask, setAsk] = useState<"return" | "minute" | "behalf" | null>(null);
  const [text, setText] = useState("");
  // V318: a submission from entry by someone who does not teach the course is on the lecturer's behalf and says why
  const onBehalf = s.stage === "ENTRY" && !detail.youTeach && (actingOffice === "exams" || actingOffice === "academic");
  const uploads = detail.uploads ?? [];

  async function post(path: string, body: unknown, reason: string) {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) {
        { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); }
        return false;
      }
      notify(reason);
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
  /* the decisions and the uploads on behalf (V318), in the order they were taken */
  const events: { at: string; what: string; sub: string }[] = [];
  for (const d of detail.chain) {
    const what = d.kind === "RETURN" ? `Returned by ${roleLabel(d.actorOffice)}` : d.kind === "SUBMIT" ? "Submitted for verification" : `${STAGE_LABEL[d.toStage]?.[0] ?? d.toStage}`;
    events.push({ at: d.decidedAt, what, sub: `${d.actor ?? roleLabel(d.actorOffice)} · ${when(d.decidedAt)}${d.comment ? ` · “${d.comment}”` : ""}` });
  }
  for (const u of uploads) {
    events.push({ at: u.uploadedAt, what: `Marks uploaded on behalf of ${u.owner ?? s.lecturer ?? "the lecturer"}`, sub: `${u.uploadedBy ?? "Unnamed"} (${roleLabel(u.uploaderOffice)}) · ${when(u.uploadedAt)} · ${u.rowsWritten} mark${u.rowsWritten === 1 ? "" : "s"} · “${u.reason}”` });
  }
  events.sort((a, b) => a.at.localeCompare(b.at));
  for (const e of events) ladder.push(["done", e.what, e.sub]);
  if (!published) ladder.push(["now", `${STAGE_LABEL[s.stage]?.[0] ?? s.stage}`, `With ${holder || roleLabel(need)}`]);

  return (
    <>
      <Panel title="You are signed in as" right="The chain is read from every desk; the action belongs to one">
        <PBody>
          <div className="row">
            <Btn kind="primary" style={{ flexDirection: "column", alignItems: "flex-start", gap: 1, textAlign: "left" }}>
              <span>{roleLabel(actingOffice)}</span>
              <span className="t-xs" style={{ fontWeight: 400, opacity: 0.8 }}>{roleUnit(actingOffice) || "The University"}</span>
            </Btn>
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
        <Note kind="ok" title="Senate has approved this result set and it is published" >
          {s.candidates} students can see their marks. A correction from now is an amendment, reported to Senate. Minute <b>{detail.senateMinute}</b>.
        </Note>
      ) : mine && !s.blockedForYou ? (
        <Note kind="info" title={onBehalf ? `This sheet is at entry: you may submit it on ${s.lecturer ?? "the lecturer"}'s behalf` : `This stage is yours: ${RS_STAGES[st][2] || "Approve"}`} action={<>
          {onBehalf ? <LinkBtn kind="primary" href={`/results/sheets/${s.id}`}>Enter marks on their behalf</LinkBtn> : null}
          <Btn kind="go" disabled={busy} onClick={() => (s.stage === "SENATE" ? setAsk("minute") : onBehalf ? (setAsk("behalf"), setText("")) : void post(`/api/bff/api/v1/results/sheets/${s.id}/advance`, {}, `${s.courseCode}: ${RS_STAGES[st][2]}`))}>{onBehalf ? "Submit on their behalf" : RS_STAGES[st][2] || "Approve"}</Btn>{" "}
          {s.stage !== "ENTRY" ? <Btn kind="urgent" disabled={busy} onClick={() => { setAsk("return"); setText(""); }}>Return to the lecturer</Btn> : null}
        </>}>
          Approving is a signature: your name, the time and the figures go on the audit trail and cannot be edited.
        </Note>
      ) : s.blockedForYou ? (
        <Note kind="bad" title="You performed the previous stage, so this one is not open to you">
          No one moves a result through two stages alone. Another holder of the {roleLabel(need)} office must act.
        </Note>
      ) : (
        <Note kind="info" title={`This sheet is with ${holder || roleLabel(need)}`}>
          You are signed in as {roleLabel(actingOffice)}; this stage belongs to another desk.
        </Note>
      )}

      {s.returnedTimes > 0 && lastReturn ? (
        <Note kind="info" title={`This sheet was returned ${s.returnedTimes === 1 ? "once" : `${s.returnedTimes} times`} and corrected`}>
          {roleLabel(lastReturn.actorOffice)} sent it back on {when(lastReturn.decidedAt)}: “{lastReturn.comment}”. It re-entered the chain at verification.
        </Note>
      ) : null}

      <TwoCol>
        <Panel title="Approval chain" right={RS_STAGES[st][0]}>
          <div style={{ padding: "var(--s-1) 0" }}>
            {ladder.map((e, i) => (
              <div key={i} style={{ padding: "10px var(--s-4)", borderTop: i ? "1px solid var(--line-2)" : undefined }}>
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
              <Gate state={published ? "done" : "todo"} title="The engine version is stored with the result" sub={`Grades computed by ${detail.engineVersion ?? "GpaCalculator 2.1"}`} last />
            </Gates>
          </PBody>
        </Panel>
      </TwoCol>

      <Panel title="Marks on this sheet" right="CA and examination are recorded; total, grade and point are computed">
        <DTable
          cols={["Student", "CA|mid", "Exam|mid", "Total|mid", "Grade|mid", "Point|mid", "Entered by", "Amended|num"]}
          rows={detail.marks.map((m) => [
            <Two key="s" a={`${m.surname}, ${m.otherNames}`} b={m.number} />,
            <span className="tnum" key="ca">{m.ca ?? "—"}</span>,
            <span className="tnum" key="ex">{m.exam ?? "—"}</span>,
            <b className="tnum" key="t">{m.total ?? m.outcome}</b>,
            m.grade ? <Pil kind={(m.points ?? 0) >= 4 ? "ok" : (m.points ?? 0) >= 1 ? "info" : "bad"} key="g">{m.grade}</Pil> : <span className="sub2" key="g">—</span>,
            <span className="tnum" key="p">{m.points ?? "—"}</span>,
            <span className="sub2" key="by">{m.enteredBy ?? "—"}{m.onBehalf ? <> <Pil kind="info">on behalf</Pil></> : null}</span>,
            m.amended ? <Pil kind="bad" key="a">Amended — version {m.version}</Pil> : <span className="sub2" key="a">—</span>,
          ])}
          texts={detail.marks.map((m) => `${m.surname} ${m.otherNames} ${m.number}`)}
        />
      </Panel>

      {/* V358: a published mark is corrected only by an amendment through the chain */}
      <Amendments sheetId={s.id} courseCode={s.courseCode} caMax={typeof s.caMax === "number" ? s.caMax : 40} published={published} actingOffice={actingOffice} marks={detail.marks} />

      <Note kind={published ? "ok" : "bad"} title={published ? "Students see their mark, grade and Senate approval date" : "Students see nothing yet"}>
        {published ? null : `Their result page shows “awaiting Senate approval”; the sheet is at stage ${s.spineStage} of 6.`}
      </Note>

      {ask ? (
        <Modal title={ask === "return" ? "Return the sheet to the lecturer" : ask === "behalf" ? "Submit on the lecturer's behalf" : "Approve for Senate"}
          sub={ask === "return" ? "The reason goes on the record" : ask === "behalf" ? `${s.lecturer ?? "The lecturer"} remains the academic owner; your reason goes on the record` : "Cite the Senate minute"} onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><span className="grow" /><Btn kind={ask === "return" ? "urgent" : "go"} disabled={!text.trim() || busy} onClick={async () => {
            const ok = ask === "return"
              ? await post(`/api/bff/api/v1/results/sheets/${s.id}/return`, { comment: text }, `${s.courseCode} returned`)
              : ask === "behalf"
                ? await post(`/api/bff/api/v1/results/sheets/${s.id}/advance`, { comment: text }, `${s.courseCode} submitted on behalf of ${s.lecturer ?? "the lecturer"}`)
                : await post(`/api/bff/api/v1/results/sheets/${s.id}/advance`, { minute: text }, `${s.courseCode} approved for Senate under ${text}`);
            if (ok) setAsk(null);
          }}>{ask === "return" ? "Return it" : ask === "behalf" ? "Submit on their behalf" : "Approve and publish"}</Btn></>}>
          <Field id="chain-text" label={ask === "return" ? "Why it is returned" : ask === "behalf" ? "Why the lecturer is not submitting it themselves" : "Senate minute"}
            hint={ask === "return" ? "It re-enters the chain at verification." : ask === "behalf" ? "It goes to verification in your name, on their behalf; another person must verify it." : "The result reaches the student under this minute."}>
            <input id="chain-text" className="ctl" value={text} onChange={(e) => setText(e.target.value)} autoComplete="off" placeholder={ask === "minute" ? "SEN/2026/…" : ""} />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
