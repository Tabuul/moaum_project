"use client";

/** staffTranscripts — proto/part5b.html: the production queue, oldest first, the SLA clock from payment. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { DESTINATION, type TranscriptQueue } from "@/lib/credentials";
import { Ico } from "@/components/proto/ui";
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
      const r = await fetch(`/api/bff/api/v1/credentials/transcript-requests/${id}/${action}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reason }, body: "{}" });
      if (!r.ok) setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText });
      else router.refresh();
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <div className="grid grid--4">
        <div className="tile"><span className="eyebrow">Open requests</span><span className="n tnum">{t.open}</span><span className="c">Across all destinations</span></div>
        <div className="tile"><span className="eyebrow">Held at clearance</span><span className="n tnum" style={{ color: "var(--red-ink)" }}>{t.heldAtClearance}</span><span className="c">Cannot be produced yet</span></div>
        <div className="tile"><span className="eyebrow">Breaching SLA</span><span className="n tnum" style={{ color: "var(--red-ink)" }}>{t.breachingSla}</span><span className="c">Over 5 working days</span></div>
        <div className="tile"><span className="eyebrow">Average turnaround</span><span className="n tnum">{t.averageTurnaroundDays === null ? "—" : `${t.averageTurnaroundDays} days`}</span><span className="c">Against a 10-day standard</span></div>
      </div>

      <div className="notice notice--info">
        <Ico name="alert" size={18} stroke="var(--chrome)" w={2} />
        <div>
          <div className="notice__t" style={{ color: "var(--chrome)" }}>Production is never manual re-typing</div>
          <p style={{ color: "#124A63" }}>Every transcript is generated from the approved academic record. Exams &amp; Records verifies it, the Registrar signs it — no one keys a grade at this stage.</p>
        </div>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <div className="card">
        <div className="card__head"><span className="card__title">Production queue</span><span className="sub2" style={{ marginLeft: "auto" }}>Oldest first · SLA clock runs from payment</span></div>
        <div className="tablewrap">
          <table style={{ minWidth: 940 }}>
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
                    <td className="mid tnum" style={breaching ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{slaDay === null ? "—" : actionStage === "VERIFICATION" ? "—" : `Day ${slaDay}${breaching ? " ⚠" : ""}`}</td>
                    <td><span className={`pill ${stage[1]}`}>{stage[0]}</span>{r.heldBy && actionStage === "BLOCKED" ? <div className="sub2" style={{ color: "var(--red-ink)" }}>{r.heldBy}: {r.heldReason ?? "not cleared"}</div> : null}{breaching ? <div className="sub2" style={{ color: "var(--red-ink)" }}>Past the 5-day standard</div> : null}</td>
                    <td className="num">
                      {actionStage === "NOT_PAYABLE" ? (signer ? <button className="btn btn--ghost btn--sm" disabled={busy !== null} onClick={() => void post(r.id, "mark-paid", `${r.ref} recorded as paid`)}>Record payment</button> : <button className="btn btn--sm" disabled>Not payable yet</button>)
                        : actionStage === "BLOCKED" ? <button className="btn btn--sm" disabled title={`${r.heldBy} has not cleared this student`}>Blocked — {r.heldBy}</button>
                        : actionStage === "PRODUCE" ? <button className="btn btn--primary btn--sm" disabled={busy !== null} onClick={() => void post(r.id, "produce", `${r.ref} produced and verified`)}>{busy === r.id ? "Producing…" : "Produce & verify"}</button>
                        : actionStage === "RELEASE" ? <button className="btn btn--go btn--sm" disabled={busy !== null || !signer} title={signer ? undefined : "The Registrar signs"} onClick={() => void post(r.id, "release", `${r.ref} signed and released`)}>{busy === r.id ? "Signing…" : "Sign & release"}</button>
                        : <button className="btn btn--ghost btn--sm">View verification</button>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}
