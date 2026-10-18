"use client";

/**
 * V547: clearing the schedule shown with its effect first, as an upload is — the lines of each faculty and programme it would
 * end, the faculties and programmes left with no fee, and the live students who would owe nothing until a new structure is
 * stated — worked out on the server and undone. "Clear the schedule" stays off until the Bursary ticks that it means it.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

interface ClearEffect {
  result: { ended: number; students: number };
  linesBefore: number; linesAfter: number;
  groups: { faculty: string; programme: string | null; ended: number; losesAll: boolean }[];
}

const count = (n: number) => Number(n).toLocaleString("en-NG");
const named = (s: string | null | undefined) =>
  (s ?? "").toLowerCase().replace(/(^|\s)\S/g, (c) => c.toUpperCase()).replace(/ (And|Of|For|In|The) /g, (m) => m.toLowerCase());

export function FeeClearPreview({ session, kind, busy, onClose, onClear }: {
  session: string; kind: string; busy: boolean; onClose: () => void; onClear: () => void;
}) {
  const [effect, setEffect] = useState<ClearEffect | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [meant, setMeant] = useState(false);
  const which = kind === "CCE" ? "CCE " : kind === "FULL_TIME" ? "full-time " : "";

  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch(`/api/bff/api/v1/finance/sessions/${session}/schedule/clear/preview?kind=${kind === "CCE" || kind === "FULL_TIME" ? kind : "ALL"}`, { method: "POST" });
      const j = await r.json().catch(() => null);
      if (!alive) return;
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setEffect(j as ClearEffect);
    })();
    return () => { alive = false; };
  }, [session, kind]);

  const ended = effect?.groups.filter((g) => g.ended > 0) ?? [];
  const losing = ended.filter((g) => g.losesAll);

  return (
    <Modal wide title={`Clear the ${session} ${which}schedule`}
      sub={effect ? `${count(effect.result.ended)} line${effect.result.ended === 1 ? "" : "s"} would be ended` : "Working out what clearing would end…"}
      onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
        <span className="grow" />
        <Btn kind="urgent" disabled={busy || !effect || !effect.result.ended || !meant} onClick={onClear}>{busy ? "Clearing…" : "Clear the schedule"}</Btn>
      </>}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!effect ? (problem ? null : <div className="sub2">Working out what clearing would end…</div>) : !effect.result.ended ? (
        <Note kind="info" title="Nothing to clear">No {which}fee line is in force for {session}.</Note>
      ) : (
        <>
          <Tiles items={[
            ["Lines in force", `${count(effect.linesBefore)} → ${count(effect.linesAfter)}`, null, session],
            ["Ended", count(effect.result.ended), "var(--red-ink)", "Lines no longer charged"],
            ["Left with no fee", count(losing.length), losing.length ? "var(--red-ink)" : null, "Faculties and programmes"],
            ["Students who would owe no fee", count(effect.result.students), effect.result.students ? "var(--red-ink)" : null, `${which ? `${which}students` : "Students"} admitted, active or on probation`],
          ]} />
          <Note kind="bad" title={`Every ${which}fee line for ${session} will be ended`}>
            {count(effect.result.students)} {which}student{effect.result.students === 1 ? "" : "s"} on {session} will owe nothing until a new structure is stated. Payments already made are untouched.
            <label className="row row--inline row--tight mt-1">
              <input type="checkbox" className="pchk" checked={meant} onChange={(e) => setMeant(e.target.checked)} /> I mean to end these {count(effect.result.ended)} line{effect.result.ended === 1 ? "" : "s"}
            </label>
          </Note>
          <DTable title="Lines ended by faculty and programme" pageSize={10} cols={["Faculty", "Programme", "Ended|num"]}
            rows={ended.map((g) => [
              <span key="f">{named(g.faculty)}</span>,
              <span key="p">{g.programme ?? <span className="sub2">Every programme</span>}{g.losesAll ? <> <Pil kind="bad">No fee left</Pil></> : null}</span>,
              <span key="e" className="tnum">{count(g.ended)}</span>,
            ])} />
        </>
      )}
    </Modal>
  );
}
