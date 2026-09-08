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
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { BiodataChange, ChangeQueue } from "@/lib/student";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, Pil, Tiles, Two } from "@/components/proto/ui";
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
        headers: { "Content-Type": "application/json", "X-Reason": `Biodata change: ${action}` },
        body: JSON.stringify(body ?? {}),
      });
      if (response.ok) {
        setDeciding(null);
        setDecision("");
        router.refresh();
        return;
      }
      const json = await response.json().catch(() => null);
      setProblem(
        json && typeof json === "object" && "status" in json
          ? (json as Problem)
          : { status: response.status, title: response.statusText },
      );
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
        <span style={{ display: "inline-flex", gap: 6, flexWrap: "wrap" }} key="a">
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
          Each of these alters something the University asserts about a person &mdash; their name, their state of origin,
          their photograph or their refund account. None of them is a typing correction, and none can be approved without
          seeing the document behind it.
        </Note>
      ) : (
        <Note kind="ok" title="Nothing is waiting on evidence">
          Every request that has reached the Registry has been decided. A field that changes only on evidence raises a
          request here the moment somebody asks for it.
        </Note>
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
          <div className="card__body">
            <Note kind="info" title="No request has been made">
              A request appears here when a field that changes only on evidence &mdash; nationality, state of origin, the
              refund account &mdash; is asked to change. Until one is, there is nothing to decide.
            </Note>
          </div>
        ) : (
          <DTable
            cols={["Student", "Field", "From", "To", "Evidence", "Action|num"]}
            rows={rows}
            texts={queue.rows.map((r) => `${r.surname} ${r.otherNames} ${r.matricNo ?? ""} ${r.label} ${r.toValue} ${r.state}`)}
            title="Change requests"
          />
        )}
      </Panel>

      <Note kind="bad" title="A refund account whose name does not match the student is refused, every time">
        It is the single commonest route by which a refund reaches somebody other than the person owed it. The Bursary
        verifies the account name against the name on the register before any refund is released, and a mismatch is
        refused rather than queried &mdash; the student can supply an account in their own name.
      </Note>

      <Note kind="info" title="A refusal is as much a decision as an approval">
        It is recorded with its reason, it appears in the student&rsquo;s own change history, and the student is notified.
        A request that simply sits unanswered is the failure mode this queue exists to prevent, which is why the oldest
        item is shown at the top of the screen.
      </Note>

      {deciding ? (
        <Modal
          title={deciding.act === "approve" ? "Approve with evidence" : "Refuse this change"}
          sub={`${deciding.row.surname}, ${deciding.row.otherNames} · ${deciding.row.label}`}
          onClose={() => setDeciding(null)}
          foot={
            <>
              <Link className="btn btn--ghost btn--sm" href={`/students/${deciding.row.studentId}`}>
                Open the record
              </Link>
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
          <div className="kv" style={{ marginBottom: 12 }}>
            <span className="k">From</span>
            <span className="v">{deciding.row.fromValue ?? "— nothing on the record"}</span>
          </div>
          <div className="kv" style={{ marginBottom: 12 }}>
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
          A biodata change is decided by the Academic Office or the Registry. Your office may see the queue so that it
          knows where a record stands.
        </Note>
      ) : null}
    </>
  );
}
