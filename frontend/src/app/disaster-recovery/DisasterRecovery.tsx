"use client";

/** tDr — disaster recovery: the objectives the University holds itself to, the log of
 *  drills actually run, and the runbook. The objectives are policy targets; the drill log
 *  is the record of real exercises. Live backup telemetry is not wired in yet, and this
 *  screen says so rather than showing a number it cannot stand behind. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Drill { id: string; kind: string; ran_on: string; rpo_minutes: number | null; rto_minutes: number | null; outcome: string; note: string | null }

const KIND: Record<string, string> = { RESTORE_VERIFY: "Restore verification", FULL_DR: "Full DR drill", FAILOVER: "Failover", BACKUP: "Backup" };
const OUT: Record<string, ["ok" | "info" | "bad" | "grey", string]> = { PASSED: ["ok", "Passed"], FAILED: ["bad", "Failed"], PARTIAL: ["info", "Partial"] };

export function DisasterRecovery({ drills, actingOffice }: { drills: Drill[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["ict", "super"].includes(actingOffice ?? "");
  const [f, setF] = useState({ kind: "RESTORE_VERIFY", ranOn: "", rpoMinutes: "", rtoMinutes: "", outcome: "PASSED", note: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const lastFull = drills.find((d) => d.kind === "FULL_DR");
  const lastRestore = drills.find((d) => d.kind === "RESTORE_VERIFY");

  async function record() {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch("/api/bff/api/v1/governance/dr", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Record ${f.kind} drill`) }, body: JSON.stringify({ kind: f.kind, ranOn: f.ranOn || null, rpoMinutes: f.rpoMinutes ? Number(f.rpoMinutes) : null, rtoMinutes: f.rtoMinutes ? Number(f.rtoMinutes) : null, outcome: f.outcome, note: f.note || null }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return; }
      setSaid("Drill recorded"); setF({ kind: "RESTORE_VERIFY", ranOn: "", rpoMinutes: "", rtoMinutes: "", outcome: "PASSED", note: "" }); router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="A backup that has never been restored is not a backup">
        These are the recovery objectives the University holds itself to, and the log of drills actually run against them. The objectives are targets; the log is the record. Continuous backup telemetry is not wired into the portal yet — where a live figure would go, this screen names the target and the last drill rather than a number it cannot verify.
      </Note>
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["Last restore verification", lastRestore ? day(lastRestore.ran_on) : "Not recorded", lastRestore ? null : "var(--chrome)", "Target: nightly"],
        ["Last full DR drill", lastFull ? day(lastFull.ran_on) : "Not recorded", lastFull ? null : "var(--chrome)", "Target: twice yearly"],
        ["Drills on record", String(drills.length), null, "All kinds"],
        ["Failed drills", String(drills.filter((d) => d.outcome === "FAILED").length), drills.filter((d) => d.outcome === "FAILED").length ? "var(--red-ink)" : null, "Investigated on failure"],
      ]} />

      <Panel title="Recovery objectives" right="The targets, not live measurements">
        <DTable cols={["Objective", "Target", "How it is met"]} rows={[
          [<b key="a">Recovery point (RPO)</b>, <span className="tnum" key="t">≤ 15 min · 5 min for results & finance</span>, <span className="sub2" key="h">Continuous replication to a standby</span>],
          [<b key="a">Recovery time (RTO)</b>, <span className="tnum" key="t">≤ 4 hours</span>, <span className="sub2" key="h">Rehearsed at the full DR drill</span>],
          [<b key="a">Restore verification</b>, <span className="tnum" key="t">Every night</span>, <span className="sub2" key="h">A restore runs into a scratch instance and is integrity-checked</span>],
          [<b key="a">Off-site replication</b>, <span className="tnum" key="t">Daily</span>, <span className="sub2" key="h">To a separate region</span>],
          [<b key="a">Full DR drill</b>, <span className="tnum" key="t">Twice yearly</span>, <span className="sub2" key="h">The system is stood up from backups and served</span>],
        ]} />
      </Panel>

      <Panel title="Drill log" right="Exercises actually run">
        {drills.length ? (
          <DTable cols={["Drill", "Run on|mid", "RPO (min)|num", "RTO (min)|num", "Outcome|num"]} rows={drills.map((d) => [
            <span key="k">{KIND[d.kind] ?? d.kind}{d.note ? <div className="sub2">{d.note}</div> : null}</span>,
            <span className="tnum sub2" key="r">{day(d.ran_on)}</span>,
            <span className="tnum sub2" key="rpo">{d.rpo_minutes ?? "—"}</span>,
            <span className="tnum sub2" key="rto">{d.rto_minutes ?? "—"}</span>,
            <Pil kind={OUT[d.outcome]?.[0] ?? "grey"} key="o">{OUT[d.outcome]?.[1] ?? d.outcome}</Pil>,
          ])} texts={drills.map((d) => `${d.kind} ${d.outcome}`)} />
        ) : <PBody><div className="sub2">No drill recorded yet. The Directorate of ICT records each exercise as it is run.</div></PBody>}
      </Panel>

      {may ? (
        <Panel title="Record a drill" right="As it is run">
          <PBody>
            <div className="grid grid--3">
              <Field id="dr-kind" label="Drill"><select id="dr-kind" className="ctl" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}>{Object.entries(KIND).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
              <Field id="dr-on" label="Run on"><input id="dr-on" className="ctl" type="date" value={f.ranOn} onChange={(e) => setF({ ...f, ranOn: e.target.value })} /></Field>
              <Field id="dr-out" label="Outcome"><select id="dr-out" className="ctl" value={f.outcome} onChange={(e) => setF({ ...f, outcome: e.target.value })}>{["PASSED", "PARTIAL", "FAILED"].map((o) => <option key={o} value={o}>{o.charAt(0) + o.slice(1).toLowerCase()}</option>)}</select></Field>
            </div>
            <div className="grid grid--3">
              <Field id="dr-rpo" label="RPO achieved (min)" hint="Optional"><input id="dr-rpo" className="ctl tnum" inputMode="numeric" value={f.rpoMinutes} onChange={(e) => setF({ ...f, rpoMinutes: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
              <Field id="dr-rto" label="RTO achieved (min)" hint="Optional"><input id="dr-rto" className="ctl tnum" inputMode="numeric" value={f.rtoMinutes} onChange={(e) => setF({ ...f, rtoMinutes: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
              <Field id="dr-note" label="Note" hint="Optional"><input id="dr-note" className="ctl" value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} /></Field>
            </div>
            <div><Btn kind="primary" disabled={busy} onClick={() => void record()}>Record the drill</Btn></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
