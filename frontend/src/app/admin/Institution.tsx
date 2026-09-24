"use client";

/** r/admin — the whole institution, at one desk (proto part18 rAdmin). Every figure below is the
 *  SAME measure at a different level: pick the University or a faculty and the tiles, the pipeline
 *  and the money all move to that scope. Nothing here is entered by hand — it is the overview record
 *  the desks work on, read once and counted, so it cannot drift from what each office sees.
 *  This desk reads every module and approves none of them; that is the point of it. */
import { useState } from "react";
import Link from "next/link";
import { Note, Panel, PBody, Tiles, Tick, WarnIcon, Ico } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar, money } from "@/components/proto/blocks";
import { PeriodPicker } from "@/components/proto/PeriodPicker";
import { Donut, HBars, VZ } from "@/components/proto/vz";
import type { OverviewData } from "../overview/Overview";

type Fac = {
  code: string; name: string;
  students: number; paid: number; owing: number;
  collected: number; due: number;
  expected: number; submitted: number; approved: number; published: number; inProgress: number;
};

const n = (x: unknown) => Number(x ?? 0);

export function Institution({ d, semester, session, sessions }: { d: OverviewData; semester: number; session: string; sessions: string[] }) {
  /* one row per faculty, the four measures merged from the three records */
  const facs: Fac[] = d.students.byFaculty.map((f) => {
    const col = d.collection.find((c) => c.faculty_code === f.code);
    const res = d.results.find((r) => r.code === f.code);
    const students = n(f.students);
    const paid = n(col?.paid_students);
    const submitted = res?.submitted != null ? n(res.submitted) : n(res?.published) + n(res?.in_progress);
    const approved = res?.approved != null ? n(res.approved) : n(res?.published);
    return {
      code: f.code, name: f.name,
      students, paid, owing: Math.max(0, students - paid),
      collected: n(col?.collected), due: n(col?.due),
      expected: n(res?.expected), submitted, approved, published: n(res?.published), inProgress: n(res?.in_progress),
    };
  });

  const [scope, setScope] = useState<string>("institution");
  const sel = scope === "institution" ? null : facs.find((f) => f.code === scope) ?? null;

  /* the scope's aggregate — the University, or the one faculty */
  const agg = sel ?? {
    code: "institution", name: "The University",
    students: d.students.total,
    paid: facs.reduce((a, f) => a + f.paid, 0),
    owing: facs.reduce((a, f) => a + f.owing, 0),
    collected: facs.reduce((a, f) => a + f.collected, 0),
    due: facs.reduce((a, f) => a + f.due, 0),
    expected: facs.reduce((a, f) => a + f.expected, 0),
    submitted: facs.reduce((a, f) => a + f.submitted, 0),
    approved: facs.reduce((a, f) => a + f.approved, 0),
    published: facs.reduce((a, f) => a + f.published, 0),
    inProgress: facs.reduce((a, f) => a + f.inProgress, 0),
  };
  const aPending = Math.max(0, agg.submitted - agg.approved);
  const aNever = Math.max(0, agg.expected - agg.submitted);
  const pubPct = agg.expected ? Math.round((100 * agg.approved) / agg.expected) : 0;
  const colPct = agg.due ? Math.min(100, Math.round((100 * agg.collected) / agg.due)) : 0;
  const subtitle = sel
    ? `${agg.students.toLocaleString()} students · ${agg.expected} result set${agg.expected === 1 ? "" : "s"} this semester`
    : `${d.students.total.toLocaleString()} students · ${facs.length} facult${facs.length === 1 ? "y" : "ies"}`;

  return (
    <>
      <PeriodPicker base="/admin" sessions={sessions} session={session} semester={semester} />
      <Panel title="Scope" right={subtitle}>
        <PBody>
          <div className="row">
            <button className={`btn btn--sm ${scope === "institution" ? "btn--primary" : "btn--ghost"}`} onClick={() => setScope("institution")}>The University</button>
            {facs.map((f) => (
              <button key={f.code} className={`btn btn--sm ${scope === f.code ? "btn--primary" : "btn--ghost"}`} onClick={() => setScope(f.code)}>{f.name}</button>
            ))}
          </div>
          <div className="sub2 mt-2">Every figure below is the same measure at a different level. An administrator who can only see the institution cannot tell a Dean why her faculty is behind.</div>
        </PBody>
      </Panel>

      <Tiles items={[
        ["Students on the register", agg.students.toLocaleString(), null, sel ? agg.name : `${facs.length} facult${facs.length === 1 ? "y" : "ies"}`],
        ["Result sets past Senate", agg.expected ? `${pubPct}%` : "—", agg.approved ? "var(--green-ink)" : null, `${agg.approved} of ${agg.expected} published`],
        ["Collected this session", money(agg.collected), agg.collected ? "var(--green-ink)" : null, agg.due ? `${colPct}% of what is charged` : "nothing charged yet"],
        ["Fees outstanding", agg.owing ? `${agg.owing.toLocaleString()}` : "0", agg.owing ? "var(--red-ink)" : "var(--green-ink)", agg.owing ? "students yet to pay in full" : "everyone on the register has paid"],
      ]} />

      <Note kind="info" title="This account can see everything and approve almost nothing">
        The administrator reads every module because somebody has to be able to answer &ldquo;where is it stuck.&rdquo; It cannot approve a result at any stage, post a payment, clear a candidate or sign a credential &mdash; those belong to the offices that own them. Every figure here is the same record those desks work on, read once and counted; it keeps no second copy, so it cannot drift from what they see.
      </Note>

      <div className="grid grid--2">
        <Panel title="Academic pipeline" right={`${sel ? agg.name : "All faculties"} · ${d.session} · ${semester === 1 ? "first" : "second"} semester`}>
          <PBody>
            {agg.expected ? (
              <>
                <Donut capLabel="past Senate" capValue={`${pubPct}%`} items={[
                  { l: "Approved by Senate", v: agg.approved, c: VZ.good, i: <Tick size={13} colour="#0a7a3b" /> },
                  { l: "Pending in the chain", v: aPending, c: VZ.warn, i: <Ico name="clock" size={13} stroke="var(--amber-ink)" w={2.2} /> },
                  { l: "Never submitted", v: aNever, c: VZ.crit, i: <WarnIcon size={13} /> },
                ]} />
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 4 }}>
                  <Link className="btn btn--ghost btn--sm" href="/results/chain">Chase the chain</Link>
                  <Link className="btn btn--ghost btn--sm" href="/results/senate">To Senate</Link>
                  <Link className="btn btn--ghost btn--sm" href="/results/sheets">Unraised sheets</Link>
                </div>
              </>
            ) : <div className="sub2">No score sheet exists for {d.session}, {semester === 1 ? "first" : "second"} semester in this scope yet. A sheet appears when a lecturer is allocated and the examination session is open.</div>}
          </PBody>
        </Panel>
        <Panel title="Money" right={`${sel ? agg.name : "The University"} · from the register`}>
          <DTable cols={["Measure", "Value|mid", "Action|num"]} rows={[
            [<span key="k">Collected this session</span>, <span className="tnum" key="v">{money(agg.collected)}</span>, <Link key="a" className="btn btn--ghost btn--sm" href="/finance/ledger">Ledger</Link>],
            [<span key="k">Outstanding</span>, <span className="tnum" key="v" style={{ color: agg.due - agg.collected > 0 ? "var(--red-ink)" : undefined }}>{money(Math.max(0, agg.due - agg.collected))}</span>, <Link key="a" className="btn btn--ghost btn--sm" href="/finance/hanging">Chase</Link>],
            [<span key="k">Collection rate</span>, <span className="tnum" key="v">{agg.due ? `${colPct}%` : "—"}</span>, <Link key="a" className="btn btn--ghost btn--sm" href="/reports">Report</Link>],
            [<span key="k">Students paid in full</span>, <span className="tnum" key="v">{agg.paid.toLocaleString()} of {agg.students.toLocaleString()}</span>, <Link key="a" className="btn btn--ghost btn--sm" href="/finance/reconcile">Reconcile</Link>],
          ]} />
        </Panel>
      </div>

      <Panel title="Students by faculty" right="On the register, all levels — the shape of the University">
        <PBody>
          {facs.length ? <HBars items={[...facs].sort((a, b) => b.students - a.students).map((f) => ({ l: f.name, v: f.students }))} /> : <div className="sub2">Nobody is on the register yet.</div>}
        </PBody>
      </Panel>

      <Panel title="By faculty" right="The same four measures, one row each — pick a row above to focus the figures">
        {facs.length ? (
          <DTable cols={["Faculty", "Students|mid", "Fees paid|mid", "Collected|mid", "Results published|num"]} rows={facs.map((f) => {
            const fPub = f.expected ? Math.round((100 * f.published) / f.expected) : 0;
            const fPaid = f.students ? Math.round((100 * f.paid) / f.students) : 0;
            const on = f.code === scope;
            return [
              <button key="f" onClick={() => setScope(on ? "institution" : f.code)} className="linklike" style={{ fontWeight: on ? 700 : 400, color: on ? "var(--chrome-ink)" : undefined, background: "none", border: 0, padding: 0, cursor: "pointer", textAlign: "left" }}>{f.name}</button>,
              <span className="tnum" key="s">{f.students.toLocaleString()}</span>,
              <span key="p" style={{ display: "flex", alignItems: "center", gap: 8 }}><Bar pct={fPaid} colour={fPaid < 60 ? "var(--red)" : "var(--green)"} /><span className="tnum sub2">{f.students ? `${fPaid}%` : "—"}</span></span>,
              <span className="tnum" key="c">{money(f.collected)}</span>,
              <span key="r" style={{ display: "flex", alignItems: "center", gap: 8 }}><Bar pct={fPub} colour={fPub < 55 ? "var(--red)" : "var(--green)"} /><span className="tnum sub2">{f.expected ? `${fPub}%` : "no sheet"}</span></span>,
            ];
          })} />
        ) : <PBody><div className="sub2">Nobody is on the register yet, so there is nothing to roll up.</div></PBody>}
      </Panel>

      <Note kind="info" title="Where to go from a figure">
        This desk is for finding where a thing is stuck, not for moving it. The institutional charts and their tables are on the <Link href="/overview">Institutional overview</Link>; the printable returns are on <Link href="/reports">Reports &amp; returns</Link>; and every action link above opens the desk that owns the number, where the office that owns it can act.
      </Note>
    </>
  );
}
