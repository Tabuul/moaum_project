"use client";

/**
 * V654: a student's historical school fees — every session of the record with its semesters, the level of each, what is assessed and
 * where it comes from, what is paid and what is owed; the session's totals and the student's. The account is the database's; this
 * shows it. A period for review is never shown as owed. The officer's actions on a period (assess, correct) are passed in. V665: an
 * approved waiver or adjustment shows in its own column, and lowers what the period owes. V683: a period with a payment being checked (the
 * graduate's evidence, an archived school-fee payment, a payment under another purpose) says so beside its status.
 */
import { Fragment, useState, type ReactNode } from "react";
import { Pil } from "@/components/proto/ui";
import { bySession, naira, num, PERIOD_WORDS, reviewWords, semesterWords, totals, type Period } from "@/lib/historical-fees";

export function HistoricalTotals({ periods }: { periods: Period[] }) {
  const t = totals(periods);
  return (
    <div className="grid grid--4">
      <div className="tile"><span className="eyebrow">Assessed</span><span className="n tnum">{naira(t.assessed)}</span><span className="c">Across {bySession(periods).length} session{bySession(periods).length === 1 ? "" : "s"}{t.waived ? ` · ${naira(t.waived)} waived or adjusted` : ""}</span></div>
      <div className="tile"><span className="eyebrow">Paid (verified)</span><span className="n tnum ink-green">{naira(t.paid)}</span><span className="c">{t.credit >= 1 ? `${naira(t.credit)} beyond what is assessed` : "Confirmed school-fee payments"}</span></div>
      <div className="tile"><span className="eyebrow">Total historical school fees outstanding</span>
        <span className="n tnum" style={{ color: t.outstanding > 0 ? "var(--red-ink)" : "var(--green-ink)" }}>{naira(t.outstanding)}</span>
        <span className="c">{t.outstanding > 0 ? t.owing.join(", ") : "Nothing owed on what is assessed"}</span></div>
      <div className="tile"><span className="eyebrow">Being assessed</span><span className="n tnum" style={{ color: t.review ? "var(--amber-ink)" : undefined }}>{t.review}</span>
        <span className="c">{t.review ? "Semesters with no amount yet: never owed until the Bursar approves one" : "Every semester has an amount"}</span></div>
    </div>
  );
}

export function HistoricalAccount({ periods, studentView = false, actions }: {
  periods: Period[];
  /** the student's own view: no sources, a period being assessed shown as such */
  studentView?: boolean;
  /** the officer's actions on a period */
  actions?: (p: Period) => ReactNode;
}) {
  const groups = bySession(periods);
  const [open, setOpen] = useState<Record<string, boolean>>(() => Object.fromEntries(groups.map((g) => [g.session, g.outstanding > 0 || g.review > 0])));
  if (!groups.length) return <div className="sub2">No historical session to read: before the assessment start, or no admission or graduation session on the record.</div>;
  return (
    <div style={{ overflowX: "auto" }}>
      <table className="tbl tbl--data">
        <thead>
          <tr>
            <th>Session</th><th>Semester</th><th className="num">Level</th><th className="num">Assessed</th><th className="num">Adjustment</th><th className="num">Paid</th><th className="num">Outstanding</th><th>Status</th>
            {studentView ? null : <th>Source</th>}{actions ? <th className="num"><span className="sr-only">Actions</span></th> : null}
          </tr>
        </thead>
        <tbody>
          {groups.map((g) => (
            <Fragment key={g.session}>
              <tr style={{ background: "var(--chip)" }}>
                <th scope="row" colSpan={3}>
                  <button type="button" className="btn btn--ghost btn--sm" aria-expanded={!!open[g.session]} onClick={() => setOpen({ ...open, [g.session]: !open[g.session] })}>
                    {open[g.session] ? "▾" : "▸"} {g.session}
                  </button>
                </th>
                <td className="num tnum b700">{naira(g.assessed)}</td>
                <td className="num tnum b700">{g.waived ? `−${naira(g.waived)}` : "—"}</td>
                <td className="num tnum b700">{naira(g.paid)}</td>
                <td className="num tnum b700" style={{ color: g.outstanding > 0 ? "var(--red-ink)" : undefined }}>{naira(g.outstanding)}</td>
                <td colSpan={(studentView ? 1 : 2) + (actions ? 1 : 0)} className="sub2">
                  Session total{g.review ? ` · ${g.review} semester${g.review === 1 ? "" : "s"} being assessed` : ""}{g.credit >= 1 ? ` · ${naira(g.credit)} credit` : ""}
                </td>
              </tr>
              {open[g.session] ? g.periods.map((p) => (
                <tr key={`${p.session}-${p.semester}`}>
                  <td className="sub2">{p.session}</td>
                  <td>{semesterWords(p.semester)}</td>
                  <td className="num tnum">{p.level ?? "—"}</td>
                  <td className="num tnum">{p.assessed == null ? <span className="sub2">{p.pending_amount && !studentView ? `${naira(p.pending_amount)} pending` : "—"}</span> : naira(p.assessed)}</td>
                  <td className="num tnum">{num(p.waived) > 0 ? `−${naira(p.waived)}` : "—"}</td>
                  <td className="num tnum">{naira(p.paid)}{num(p.credit) >= 1 ? <span className="blk sub2">{naira(p.credit)} beyond</span> : null}</td>
                  <td className="num tnum" style={{ color: num(p.outstanding) > 0 ? "var(--red-ink)" : undefined }}>{p.outstanding == null ? "—" : naira(p.outstanding)}</td>
                  <td><Pil kind={PERIOD_WORDS[p.status]?.[1] ?? "grey"}>{PERIOD_WORDS[p.status]?.[0] ?? p.status}</Pil>
                    {/* V683: a payment for the period being checked: never read as plainly unpaid meanwhile */}
                    {p.review ? <><span className="blk mt-1"><Pil kind="warn">Payment under review</Pil></span>{reviewWords(p, studentView).map((w) => <span key={w} className="blk sub2">{w}</span>)}</> : null}</td>
                  {studentView ? null : (
                    <td className="sub2">{p.source === "ASSESSMENT" ? `Approved assessment ${p.source_ref ?? ""}` : p.source === "STRUCTURE" ? p.source_ref : "Historical fee structure not found"}
                      {p.pending_ref ? <span className="blk">Pending: {p.pending_ref}</span> : null}</td>
                  )}
                  {actions ? <td className="num">{actions(p)}</td> : null}
                </tr>
              )) : null}
            </Fragment>
          ))}
        </tbody>
      </table>
    </div>
  );
}
