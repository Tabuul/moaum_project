"use client";

/** V576: what a level change does to the students' fees for the current session, read before it is made — the levels raised and
 *  undone on the server (nothing is changed): the charges now and after, how many owe more or less, and how many would have no
 *  fee line at all. Shown in Level corrections and in Reconciliation's preview. */
import { useState } from "react";
import { Btn, Note } from "@/components/proto/ui";
import { notifyProblem } from "@/components/proto/Toast";

export interface FeeEffectResult {
  session: string; basis: "LEVEL" | "COHORT"; students: number; chargedNow: number; chargedAfter: number; more: number; less: number; same: number; noneAfter: number;
  largest: { student_id: string; name: string; number: string | null; current_level: number; new_level: number; charged_now: number; charged_after: number }[];
  levelsRaised?: number; readFor?: number; leavingActiveStudy?: number;
}

const naira = (n: number) => `₦${Number(n ?? 0).toLocaleString("en-NG", { maximumFractionDigits: 2 })}`;
const fmt = (n: number) => Number(n ?? 0).toLocaleString("en-NG");

/** the button and, once read, the effect; `request` posts the selection to the endpoint that reads it */
export function FeeEffect({ label, request }: { label: string; request: () => Promise<Response> }) {
  const [busy, setBusy] = useState(false);
  const [e, setE] = useState<FeeEffectResult | null>(null);

  async function read() {
    setBusy(true);
    try {
      const r = await request();
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The fee effect could not be read just now." }); return; }
      setE(j as FeeEffectResult);
    } finally { setBusy(false); }
  }

  if (!e) return <Btn kind="ghost" size="sm" busy={busy} busyLabel="Working out the fees…" onClick={() => void read()}>{label}</Btn>;
  const diff = e.chargedAfter - e.chargedNow;
  const partial = e.readFor != null && e.levelsRaised != null && e.readFor < e.levelsRaised;
  return (
    <Note kind={e.noneAfter ? "bad" : "info"} title={`Fees for ${e.session}: ${naira(e.chargedNow)} now, ${naira(e.chargedAfter)} after (${diff >= 0 ? "+" : "−"}${naira(Math.abs(diff))})`}>
      <div className="stack" style={{ gap: 4 }}>
        <span>
          {e.students === 0 ? "No level would change." : <>For the {fmt(e.students)} student{e.students === 1 ? "" : "s"} whose level would rise{partial ? ` (the first ${fmt(e.readFor ?? 0)} of ${fmt(e.levelsRaised ?? 0)})` : ""},
          {" "}charged {e.basis === "COHORT" ? "by the cohort" : "by the level"}: {fmt(e.more)} would owe more, {fmt(e.less)} less and {fmt(e.same)} the same.</>}
          {e.noneAfter ? <> <b>{fmt(e.noneAfter)}</b> would have no fee line stated at their new level — state it on the Fee Schedule first, or they owe nothing and cannot register.</> : null}
          {e.leavingActiveStudy ? <> {fmt(e.leavingActiveStudy)} leave active study (dormant or withdrawn) and are not read here.</> : null}
        </span>
        {e.largest.length ? (
          <details>
            <summary className="sub2">The largest changes</summary>
            <table className="tbl" style={{ marginTop: 4 }}>
              <thead><tr><th>Student</th><th className="num">Level</th><th className="num">Now</th><th className="num">After</th></tr></thead>
              <tbody>{e.largest.slice(0, 15).map((r) => (
                <tr key={r.student_id}><td>{r.name}<div className="sub2 tnum">{r.number ?? ""}</div></td><td className="num tnum">{r.current_level} → {r.new_level}</td>
                  <td className="num tnum">{naira(r.charged_now)}</td><td className="num tnum">{naira(r.charged_after)}</td></tr>
              ))}</tbody>
            </table>
          </details>
        ) : null}
      </div>
    </Note>
  );
}
