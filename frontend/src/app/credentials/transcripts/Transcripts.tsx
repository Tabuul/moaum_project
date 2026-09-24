"use client";

/** staffTranscripts — proto/part5b.html: the production queue, oldest first, the SLA clock from payment. */
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { DESTINATION, type TranscriptQueue } from "@/lib/credentials";
import { Btn, Ico, Note, Panel, Tiles } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

export function Transcripts({ queue, actingOffice }: { queue: TranscriptQueue; actingOffice: string | null }) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const t = queue.tiles;
  const signer = ["registrar", "dregistrar", "academic"].includes(actingOffice ?? "");

  async function post(id: string, action: string, reason: string) {
    setBusy(id);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/credentials/transcript-requests/${id}/${action}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: "{}" });
      if (!r.ok) setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
      else { notify(reason); router.refresh(); }
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <Tiles items={[
        ["Open requests", t.open, null, "Across all destinations"],
        ["Held at clearance", t.heldAtClearance, "var(--red-ink)", "Cannot be produced yet"],
        ["Breaching SLA", t.breachingSla, "var(--red-ink)", "Over 5 working days"],
        ["Average turnaround", t.averageTurnaroundDays === null ? "—" : `${t.averageTurnaroundDays} days`, null, "Against a 10-day standard"],
      ]} />

      <Note kind="info" title="Production is never manual re-typing">
        Every transcript is generated from the approved academic record. Exams &amp; Records verifies it, the Registrar signs it — no one keys a grade at this stage.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title="Production queue" right="Oldest first · SLA clock runs from payment">
        <div className="tablewrap">
          <table className="tbl--data" style={{ minWidth: 940 }}>
            <thead><tr><th>Request</th><th>Student</th><th>Destination</th><th className="mid">Clearance</th><th className="mid">SLA</th><th>Stage</th><th className="num">Action</th></tr></thead>
            <tbody>
              {queue.requests.length === 0 ? <tr><td colSpan={7} className="sub2">No transcript request is open. Requests arrive from students and alumni; the Academic Office can raise one on a student&rsquo;s behalf through the API.</td></tr> : null}
              {queue.requests.map(({ row: r, slaDay, breaching, actionStage }) => {
                const stage = actionStage === "NOT_PAYABLE" ? ["Awaiting payment", "pill--bad"]
                  : actionStage === "BLOCKED" ? ["Held at clearance", "pill--bad"]
                  : actionStage === "PRODUCE" ? ["Ready to produce", "pill--info"]
                  : actionStage === "RELEASE" ? ["Awaiting Registrar", "pill--info"]
                  : ["Released", "pill--ok"];
                const live = actionStage === "PRODUCE" || actionStage === "RELEASE";
                return (
                  <tr key={r.id} style={live ? { background: "var(--sky-bg)" } : undefined}>
                    <td className="tnum">{r.ref}</td>
                    <td>{r.surname}, {r.otherNames}<div className="sub2 tnum">{r.number}</div></td>
                    <td>{DESTINATION[r.destination] ?? r.destination}{r.destinationName ? ` — ${r.destinationName}` : ""}<div className="sub2">{r.mode === "SEALED" ? "Sealed hard copy" : "Digital"}{r.express ? " · express" : ""} · {r.copies} cop{r.copies > 1 ? "ies" : "y"}</div></td>
                    <td className="mid">{r.unitsCleared >= 3 ? <span className="pill pill--ok">3 of 3</span> : <span className="pill pill--bad">{r.unitsCleared} of 3</span>}</td>
                    <td className={`mid tnum${breaching ? " ink-red b700" : ""}`}>{slaDay === null ? "—" : actionStage === "VERIFICATION" ? "—" : <>Day {slaDay}{breaching ? <> <Ico name="alert" size={14} /></> : null}</>}</td>
                    <td><span className={`pill ${stage[1]}`}>{stage[0]}</span>{r.heldBy && actionStage === "BLOCKED" ? <div className="sub2 ink-red">{r.heldBy}: {r.heldReason ?? "not cleared"}</div> : null}{breaching ? <div className="sub2 ink-red">Past the 5-day standard</div> : null}</td>
                    <td className="num">
                      {actionStage === "NOT_PAYABLE" ? (signer ? <Btn kind="ghost" disabled={busy !== null} onClick={() => void post(r.id, "mark-paid", `${r.ref} recorded as paid`)}>Record payment</Btn> : <Btn kind="ghost" disabled>Not payable yet</Btn>)
                        : actionStage === "BLOCKED" ? <Btn kind="ghost" disabled title={`${r.heldBy} has not cleared this student`}>Blocked — {r.heldBy}</Btn>
                        : actionStage === "PRODUCE" ? <Btn kind="primary" disabled={busy !== null} onClick={() => void post(r.id, "produce", `${r.ref} produced and verified`)}>{busy === r.id ? "Producing…" : "Produce & verify"}</Btn>
                        : actionStage === "RELEASE" ? <Btn kind="go" disabled={busy !== null || !signer} title={signer ? undefined : "The Registrar signs"} onClick={() => void post(r.id, "release", `${r.ref} signed and released`)}>{busy === r.id ? "Signing…" : "Sign & release"}</Btn>
                        : <Btn kind="ghost">View verification</Btn>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </Panel>
    </>
  );
}
