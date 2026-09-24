"use client";

/** tAuditPayroll — the variance of a month's payroll against the one before it: who
 *  joined, who left, and whose net changed. The audit directorate reads it to see
 *  that every movement in the total is explained by a movement in the establishment. */
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import type { PayRun } from "../Payroll";
import { Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface VarianceRow {
  kind: string; staff_no: string; name: string; grade: string;
  this_net: number | null; prev_net: number | null; delta: number;
}

const KIND: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  JOINED: ["ok", "Joined"], LEFT: ["bad", "Left"], CHANGED: ["warn", "Changed"], SAME: ["grey", "Unchanged"],
};

function monthLabel(period: string): string {
  const d = new Date(period.length === 7 ? period + "-01" : period);
  return d.toLocaleDateString("en-GB", { month: "long", year: "numeric" });
}

export function Variance({ runs, period, rows, problem }: { runs: PayRun[]; period: string | null; rows: VarianceRow[]; problem: Problem | null }) {
  const queryNav = useQueryNav();
  const moved = rows.filter((r) => r.kind !== "SAME");
  const joined = rows.filter((r) => r.kind === "JOINED").length;
  const left = rows.filter((r) => r.kind === "LEFT").length;
  const changed = rows.filter((r) => r.kind === "CHANGED").length;
  const netDelta = rows.reduce((n, r) => n + Number(r.delta), 0);

  return (
    <>
      <Note kind="info" title="Every move in the total is explained by a move in the establishment">
        A month&rsquo;s net against the month before it: a staff member who joined, one who left, and one whose net changed — a promotion, a step, a suspension. A change in the payroll total that no row here explains is the thing to ask about.
      </Note>
      <div className="card"><div className="card__body row row--end">
        <div style={{ minWidth: 200 }}><Field id="v-period" label="Month">
          <select id="v-period" className="ctl" value={period ?? ""} onChange={(e) => queryNav(`/payroll/variance?period=${e.target.value}`)}>
            {runs.length ? runs.map((r) => <option key={r.id} value={r.period.slice(0, 7)}>{monthLabel(r.period)}</option>) : <option value="">No runs yet</option>}
          </select>
        </Field></div>
      </div></div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Tiles items={[
        ["Joined", String(joined), joined ? "var(--green-ink)" : null, "New on the establishment"],
        ["Left", String(left), left ? "var(--red-ink)" : null, "Off the establishment"],
        ["Changed", String(changed), changed ? "var(--chrome)" : null, "Net differs from last month"],
        ["Net change", (netDelta >= 0 ? "+" : "") + money(netDelta), netDelta ? "var(--chrome)" : null, period ? `vs the month before ${monthLabel(period)}` : ""],
      ]} />
      <Panel title="What moved" right={period ? monthLabel(period) : "No month selected"}>
        {moved.length ? (
          <DTable cols={["Staff", "Grade|mid", "Movement", "Last month|num", "This month|num", "Change|num"]} rows={moved.map((r) => [
            <Two key="p" a={r.name} b={r.staff_no} />,
            <span className="sub2" key="g">{r.grade}</span>,
            <Pil kind={KIND[r.kind]?.[0] ?? "grey"} key="k">{KIND[r.kind]?.[1] ?? r.kind}</Pil>,
            <span className="tnum sub2" key="pv">{r.prev_net == null ? "—" : money(Number(r.prev_net))}</span>,
            <span className="tnum sub2" key="tn">{r.this_net == null ? "—" : money(Number(r.this_net))}</span>,
            <b className={`tnum${Number(r.delta) > 0 ? " ink-green" : Number(r.delta) < 0 ? " ink-red" : ""}`} key="d">{(Number(r.delta) >= 0 ? "+" : "") + money(Number(r.delta))}</b>,
          ])} texts={moved.map((r) => `${r.name} ${r.staff_no} ${r.kind}`)} />
        ) : <PBody><div className="sub2">{period ? "Nothing moved: the establishment is unchanged from the previous run, or there is no previous run to compare." : "Select a month."}</div></PBody>}
      </Panel>
    </>
  );
}
