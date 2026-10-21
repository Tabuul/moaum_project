import Link from "next/link";
import { api } from "@/lib/api";
import type { BursaryView } from "@/lib/bursary";
import type { FinSummary } from "@/lib/analytics";
import { presetRange } from "@/lib/analytics";
import { LinkBtn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/lib/format";

import type { ReconFigures } from "@/lib/legacy-reconciliation";

/** the NELFUND desk's figures as the Bursary reads them (finance.nelfund_desk_figures, V327) */
interface NelfundFigures { session: string; figures: { students_funded: number; nelfund_credited: number; students_shortfall: number; shortfall_amount: number } }

const vz = (n: number | null | undefined) => Number(n ?? 0).toLocaleString("en-GB");

/**
 * The Students Account Officer's dashboard (V520) — a Bursary sub-office for students' money. Every figure is the portal's own,
 * read from the engines the Bursary reads: the payments of today, this week, this month and this year from the Financial
 * Analytics summary (transactions, unique paying students and the amount kept apart, as the engine counts them), the session's
 * collected and due by faculty and the hanging payments from the Bursary's view, and the NELFUND figures from the NELFUND desk.
 * The quick actions open those same screens; nothing is computed here.
 */
export async function StudentAccountsDashboard({ session }: { session: string }) {
  const windows = (["today", "this_week", "this_month", "this_year"] as const).map((k) => ({ key: k, r: presetRange(k)! }));
  const sum = (from: string, to: string) => api<FinSummary>(`/api/v1/analytics/finance/summary?from=${from}&to=${to}&compare=false`);
  const [[today, week, month, year], [inSession, v, nel, recon]] = await Promise.all([
    Promise.all(windows.map((w) => sum(w.r.from, w.r.to))),
    Promise.all([
      api<FinSummary>(`/api/v1/analytics/finance/summary?session=${encodeURIComponent(session)}&compare=false`),
      api<BursaryView>(`/api/v1/finance/bursary?session=${encodeURIComponent(session)}`),
      api<NelfundFigures>(`/api/v1/nelfund/figures?session=${encodeURIComponent(session)}`),
      api<ReconFigures>("/api/v1/finance/legacy-reconciliation/figures"),
    ] as const),
  ]);
  // V625: legacy financial reconciliation — the student liabilities and the student credits, never combined
  const rc = recon.ok ? recon.data : null;
  const t = (s: typeof today) => (s.ok ? s.data.totals : null);
  const ses = t(inSession);
  // the session's outstanding: what is due less what is collected, faculty by faculty, as the Bursary's view states them
  const outstanding = v.ok ? v.data.byFaculty.reduce((n, f) => n + Math.max(0, Number(f.due) - Number(f.collected)), 0) : null;
  const report = (preset: string) => `/finance/analytics?preset=${preset}`;
  return (
    <>
      <Note kind="info" title={`Students Account Officer · Bursary · ${session}`}>
        Payment reports, school fees setup, NELFUND, students&rsquo; accounts and hanging payments. The figures are the portal&rsquo;s own; a payment
        counts once it is confirmed, and transactions, paying students and amounts are kept apart.
      </Note>

      <Tiles items={[
        ["Today", t(today) ? money(Number(t(today)!.amount)) : "—", null, t(today) ? `${vz(t(today)!.transactions)} transactions · ${vz(t(today)!.payers)} students` : "Not read"],
        ["This week", t(week) ? money(Number(t(week)!.amount)) : "—", null, t(week) ? `${vz(t(week)!.transactions)} transactions · ${vz(t(week)!.payers)} students` : "Not read"],
        ["This month", t(month) ? money(Number(t(month)!.amount)) : "—", null, t(month) ? `${vz(t(month)!.transactions)} transactions · ${vz(t(month)!.payers)} students` : "Not read"],
        ["This year", t(year) ? money(Number(t(year)!.amount)) : "—", null, t(year) ? `${vz(t(year)!.transactions)} transactions · ${vz(t(year)!.payers)} students` : "Not read"],
      ]} />
      <Tiles items={[
        [`Paid in ${session}`, ses ? money(Number(ses.amount)) : "—", null, ses ? `${vz(ses.transactions)} transactions · ${vz(ses.payers)} paying students` : "Not read"],
        ["Outstanding", outstanding == null ? "—" : money(outstanding), outstanding ? "var(--red-ink)" : null, `School fees due less collected, ${session}`],
        ["NELFUND", nel.ok ? money(Number(nel.data.figures.nelfund_credited)) : "—", null, nel.ok ? `${vz(nel.data.figures.students_funded)} students funded` : "Not read"],
        ["Hanging payments", v.ok ? vz(v.data.tiles.hanging) : "—", v.ok && v.data.tiles.hanging ? "var(--red-ink)" : null, "Opened, not yet settled"],
      ]} />
      <Tiles items={[
        ["Successful", ses ? vz(ses.transactions) : "—", null, ses ? money(Number(ses.revenue)) : ""],
        ["Pending", ses ? vz(ses.pending_count) : "—", null, ses ? money(Number(ses.pending_amount)) : ""],
        ["Failed", ses ? vz(ses.failed_count) : "—", null, "Not successful at the gateway"],
        ["Refunded", ses ? vz(ses.refunded_count) : "—", null, ses ? money(Number(ses.refunded_amount)) : ""],
      ]} />

      {rc ? (
        <>
          <div className="eyebrow">Legacy financial reconciliation · {rc.session} · liabilities and credits kept apart</div>
          <Tiles items={[
            ["Students who owe", vz(rc.outstanding.owes), rc.outstanding.owes ? "var(--red-ink)" : null, `${money(Number(rc.outstanding.owesAmount))} legacy outstanding (liabilities)`, "/finance/legacy-reconciliation?tab=outstanding&state=OWES"],
            ["Credits held", vz(rc.outstanding.credit), rc.outstanding.credit ? "var(--amber-ink)" : null, `${money(Number(rc.outstanding.creditAmount))} eligible for wallet credit, not yet requested`, "/finance/legacy-reconciliation?tab=outstanding&state=CREDIT"],
            ["Pending Bursar approval", vz(rc.requests.pending + rc.wallet.verified), rc.requests.pending + rc.wallet.verified ? "var(--amber-ink)" : null, `${money(Number(rc.requests.pendingAmount) + Number(rc.wallet.verifiedAmount))} · ${vz(rc.requests.returned + rc.wallet.returned)} returned for correction`, "/finance/legacy-reconciliation?tab=requests"],
            ["Credited to wallets", vz(rc.requests.credited + rc.wallet.posted), "var(--green-ink)", `${money(Number(rc.requests.creditedAmount) + Number(rc.wallet.postedAmount))} · ${vz(rc.wallet.computed)} e-wallet balances to verify · ${vz(rc.wallet.review)} require review`, "/finance/legacy-reconciliation?tab=history"],
          ]} />
        </>
      ) : null}
      <Panel title="Quick actions">
        <PBody>
          <div className="row row--tight" style={{ flexWrap: "wrap" }}>
            <LinkBtn kind="primary" href={report("this_month")}>Payment reports</LinkBtn>
            <LinkBtn kind="secondary" href="/finance/fees">Fee setup</LinkBtn>
            <LinkBtn kind="secondary" href="/finance/fees">Bind school fees</LinkBtn>
            <LinkBtn kind="secondary" href="/finance/nelfund">NELFUND reports</LinkBtn>
            <LinkBtn kind="secondary" href="/student-query">Students</LinkBtn>
            <LinkBtn kind="secondary" href="/finance/hanging">Hanging payments</LinkBtn>
            <LinkBtn kind="secondary" href="/finance/legacy-reconciliation">Legacy reconciliation</LinkBtn>
          </div>
          <div className="row row--tight mt-2" style={{ flexWrap: "wrap" }}>
            <span className="sub2">Reports:</span>
            <Link className="lnk" href={report("today")}>Daily</Link>
            <Link className="lnk" href={report("this_week")}>Weekly</Link>
            <Link className="lnk" href={report("this_month")}>Monthly</Link>
            <Link className="lnk" href={report("this_year")}>Yearly</Link>
            <Link className="lnk" href="/finance/payments">Payments query</Link>
            <Link className="lnk" href="/finance/unpaid-registrations">Unpaid registrations</Link>
          </div>
        </PBody>
      </Panel>

      {v.ok && v.data.byFaculty.length ? (
        <Panel title={`School fees by faculty, ${session}`} right="from the Bursary's view">
          <DTable pageSize={0} cols={["S/N|num", "Faculty", "Students|num", "Paid|num", "Due|num", "Collected|num", "Outstanding|num"]}
            rows={v.data.byFaculty.map((f, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>,
              <Link key="f" className="lnk" href={`/finance/analytics?session=${encodeURIComponent(session)}&fac=${encodeURIComponent(f.faculty_code)}`}>{f.faculty_name}</Link>,
              <span key="s" className="tnum">{vz(f.students)}</span>, <span key="p" className="tnum">{vz(f.paid_students)}</span>,
              <span key="d" className="tnum">{money(Number(f.due))}</span>, <span key="c" className="tnum">{money(Number(f.collected))}</span>,
              <span key="o" className="tnum">{money(Math.max(0, Number(f.due) - Number(f.collected)))}</span>,
            ])} />
        </Panel>
      ) : null}
    </>
  );
}
