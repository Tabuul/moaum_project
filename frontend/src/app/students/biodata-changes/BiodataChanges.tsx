"use client";

/**
 * The Registry side of a biodata change — proto/part23.html tBioChanges:
 * the tiles, the queue, and the two notes that say why a refusal is a
 * decision and why a mismatched refund account is refused every time.
 *
 * Every action here is a decision, so every action asks for the words that
 * go on the record with it: the database refuses a blank one, and so does
 * the modal.
 */
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { BiodataChange, ChangeQueue } from "@/lib/student";
import type { Problem } from "@/lib/api";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

const WRITERS = ["academic", "registrar", "dregistrar"];
const OPEN = ["PENDING", "EVIDENCE_ASKED"];

type Act = "approve" | "refuse";

export function BiodataChanges({
  queue,
  state,
  actingOffice,
}: {
  queue: ChangeQueue;
  state: string;
  actingOffice: string | null;
}) {
  const router = useRouter();
  const [deciding, setDeciding] = useState<{ row: BiodataChange; act: Act } | null>(null);
  const [decision, setDecision] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);

  const may = actingOffice !== null && WRITERS.includes(actingOffice);
  const counts = queue.counts;

  async function send(id: string, action: string, body: unknown, key: string) {
    setBusy(key);
    setProblem(null);
    try {
      const response = await fetch(`/api/bff/api/v1/student/biodata-changes/${id}/${action}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Biodata change: ${action}`) },
        body: JSON.stringify(body ?? {}),
      });
      if (response.ok) {
        setDeciding(null);
        setDecision("");
        notify(`Biodata change ${action}`);
        router.refresh();
        return;
      }
      const json = await response.json().catch(() => null);
      setProblem(
        json && typeof json === "object" && "status" in json
          ? (json as Problem)
          : { status: response.status, title: response.statusText },
      ); notifyProblem(json && typeof json === "object" && "status" in json
          ? (json as Problem)
          : { status: response.status, title: response.statusText },);
    } finally {
      setBusy(null);
    }
  }

  const rows = queue.rows.map((r) => {
    const open = OPEN.includes(r.state);
    return [
      <Two a={`${r.surname}, ${r.otherNames}`} b={r.matricNo ?? r.admissionNo ?? "Not yet matriculated"} key="s" />,
      r.label,
      <span className="sub2" key="f">
        {r.fromValue ?? "— nothing on the record"}
      </span>,
      <span className="sub2" key="t">
        {r.toValue}
      </span>,
      r.evidence ? (
        <Pil kind="ok" key="e">
          {r.evidence}
        </Pil>
      ) : r.state === "EVIDENCE_ASKED" ? (
        <Pil kind="warn" key="e">
          Evidence asked
        </Pil>
      ) : (
        <Pil kind="bad" key="e">
          None attached
        </Pil>
      ),
      open ? (
        <span className="row row--inline row--tight" key="a">
          <Btn kind="go" disabled={!may || busy !== null} onClick={() => { setDecision(""); setDeciding({ row: r, act: "approve" }); }}>
            Approve with evidence
          </Btn>
          <Btn kind="urgent" disabled={!may || busy !== null} onClick={() => { setDecision(""); setDeciding({ row: r, act: "refuse" }); }}>
            Refuse
          </Btn>
          {r.state === "PENDING" ? (
            <Btn kind="ghost" disabled={!may || busy !== null} onClick={() => send(r.id, "ask-evidence", {}, r.id)}>
              Ask for evidence
            </Btn>
          ) : null}
        </span>
      ) : (
        <span className="sub2" key="a">
          {r.state === "APPROVED" ? "Approved" : "Refused"} {day(r.decidedAt)} &middot; {r.decision}
        </span>
      ),
    ];
  });

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}

      {counts.pending > 0 ? (
        <Note
          kind="bad"
          title={`${counts.pending} biodata ${counts.pending === 1 ? "change is" : "changes are"} waiting on evidence`}
        >
          None can be approved without seeing the document behind it.
        </Note>
      ) : (
        <Note kind="ok" title="Nothing is waiting on evidence" />
      )}

      <Tiles
        items={[
          ["Awaiting evidence", counts.pending, counts.pending ? "var(--red-ink)" : null, counts.pending ? `Oldest ${counts.oldestDays} ${counts.oldestDays === 1 ? "day" : "days"}` : "Nothing outstanding"],
          ["Approved", counts.approved, "var(--green-ink)", "Value written onto the record"],
          ["Refused", counts.refused, null, "Reason recorded on each"],
          ["Self-service changes", counts.selfService.toLocaleString(), null, "No approval needed"],
        ]}
      />

      <Panel
        title="Change requests"
        right={state ? `${state.replace("_", " ").toLowerCase()} only` : "Every one carries its evidence, or it waits"}
      >
        {queue.rows.length === 0 ? (
          <PBody>
            <Note kind="info" title="No request has been made" />
          </PBody>
        ) : (
          <DTable
            cols={["Student", "Field", "From", "To", "Evidence", "Action|num"]}
            rows={rows}
            texts={queue.rows.map((r) => `${r.surname} ${r.otherNames} ${r.matricNo ?? ""} ${r.label} ${r.toValue} ${r.state}`)}
            title="Change requests"
          />
        )}
      </Panel>

      <Note kind="info" title="A refusal is as much a decision as an approval">
        It is recorded with its reason in the student&rsquo;s change history, and the student is notified.
      </Note>

      {deciding ? (
        <Modal
          title={deciding.act === "approve" ? "Approve with evidence" : "Refuse this change"}
          sub={`${deciding.row.surname}, ${deciding.row.otherNames} · ${deciding.row.label}`}
          onClose={() => setDeciding(null)}
          foot={
            <>
              <LinkBtn kind="ghost" href={`/students/${deciding.row.studentId}`}>
                Open the record
              </LinkBtn>
              <Btn kind="ghost" onClick={() => setDeciding(null)}>
                Cancel
              </Btn>
              <Btn
                kind={deciding.act === "approve" ? "go" : "urgent"}
                disabled={busy !== null || !decision.trim()}
                onClick={() => send(deciding.row.id, deciding.act, { decision: decision.trim() }, deciding.row.id)}
              >
                {deciding.act === "approve" ? "Approve and write it on" : "Refuse, with this reason"}
              </Btn>
            </>
          }
        >
          <div className="kv mb-3">
            <span className="k">From</span>
            <span className="v">{deciding.row.fromValue ?? "— nothing on the record"}</span>
          </div>
          <div className="kv mb-3">
            <span className="k">To</span>
            <span className="v">{deciding.row.toValue}</span>
          </div>
          <Field
            id="decision"
            label="The decision, in words"
            hint="What was seen, or why the request is refused. The student sees this in their change history."
            full
          >
            <textarea
              id="decision"
              className="ctl"
              rows={3}
              value={decision}
              onChange={(e) => setDecision(e.target.value)}
            />
          </Field>
        </Modal>
      ) : null}

      {!may ? (
        <Note kind="info" title="You are reading this queue, not deciding on it">
          A biodata change is decided by the Academic Office or the Registry.
        </Note>
      ) : null}
    </>
  );
}
