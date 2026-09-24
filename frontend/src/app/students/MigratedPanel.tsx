"use client";

/**
 * The students migrated from the old portal (a matriculation number, no matriculation run) at 100–400
 * level: how many are on the register, how many stand cleared at every unit for every purpose, how many
 * do not — and the act that clears the rest. V231 cleared them once at deploy and V232 clears each
 * import as it lands; this is where the Registry sees that it held, and repeats it after an upload that
 * came in by another road. The clearance entered is the old portal's, carried over: no officer, a note.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";

export interface MigratedSummary { migrated: number; cleared: number; uncleared: number }

export function MigratedPanel({ summary, reload }: { summary: MigratedSummary; reload?: () => void }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [done, setDone] = useState<{ students: number; positions: number } | null>(null);
  const n = (v: number) => Number(v ?? 0);

  async function clearNow() {
    if (!window.confirm(`Clear ${n(summary.uncleared).toLocaleString()} migrated student${n(summary.uncleared) === 1 ? "" : "s"} at every unit for every purpose? The entry says it is the old portal's clearance carried over, with no officer; a unit may still hold any of them later.`)) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/student/students/migrated/clear?from=100&to=400", {
        method: "POST", headers: { "X-Reason": reasonHeader("Migrated students cleared on arrival, carried over from the old portal") },
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setDone({ students: n(j.students), positions: n(j.positions) });
      notify(`${n(j.students).toLocaleString()} migrated students cleared`);
      if (reload) reload(); else router.refresh();
    } finally { setBusy(false); }
  }

  const allClear = n(summary.migrated) > 0 && n(summary.uncleared) === 0;

  return (
    <Panel title="Migrated from the old portal" right="100 to 400 level · a matriculation number, no matriculation run here">
      <PBody>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {done ? <Note kind="ok" title={`${done.students.toLocaleString()} student${done.students === 1 ? "" : "s"} cleared`}>{done.positions.toLocaleString()} unit positions entered as cleared — the old portal&rsquo;s clearance, carried over.</Note> : null}
        <Tiles cls="grid--3" items={[
          ["On the register", n(summary.migrated).toLocaleString(), null, "students migrated from the old portal"],
          ["Cleared everywhere", n(summary.cleared).toLocaleString(), n(summary.cleared) ? "var(--green-ink)" : null, "every unit, every purpose"],
          ["Not yet cleared", n(summary.uncleared).toLocaleString(), n(summary.uncleared) ? "var(--red-ink)" : "var(--green-ink)", n(summary.uncleared) ? "a unit's word is missing or held" : "nothing to clear"],
        ]} />
        <div className="row mt-1">
          <Btn kind={n(summary.uncleared) ? "primary" : "ghost"} disabled={busy || !n(summary.uncleared)} onClick={() => void clearNow()}>
            {busy ? "Clearing…" : n(summary.uncleared) ? `Clear the ${n(summary.uncleared).toLocaleString()} not yet cleared` : "Nothing to clear"}
          </Btn>
          <span className="sub2">
            {n(summary.migrated) === 0
              ? "No student on the register came from the old portal at these levels — or every one has since been matriculated here."
              : allClear
                ? "Every migrated student stands cleared. A student a unit holds afterwards is counted here again, and this act will not lift that hold."
                : "A migrated student not yet cleared is refused at registration, the identity card, the hostel, the Library and the examination hall until this is done."}
          </span>
        </div>
      </PBody>
    </Panel>
  );
}

/** the same panel where the page cannot read the summary on the server (the migration desk): it reads it itself */
export function MigratedPanelLive() {
  const [summary, setSummary] = useState<MigratedSummary | null>(null);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    (async () => {
      const r = await fetch("/api/bff/api/v1/student/students/migrated?from=100&to=400", { cache: "no-store" });
      if (live && r.ok) setSummary((await r.json()) as MigratedSummary);
    })();
    return () => { live = false; };
  }, [tick]);
  if (!summary) return <Note kind="info" title="Counting the migrated students…">One moment.</Note>;
  return <MigratedPanel summary={summary} reload={() => setTick((t) => t + 1)} />;
}
