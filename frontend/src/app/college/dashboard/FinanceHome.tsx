import { LinkBtn, PageHead, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { StatsPanel } from "@/components/stats/StatsPanel";
import { FinancePanel } from "@/components/stats/FinancePanel";
import type { PayTotals } from "../payments/PaymentReport";

/**
 * V603: the Finance Controller's home — the College's fees position this session, its figures by programme, and the College's
 * student and financial analytics (StatsPanel, FinancePanel: the one analytics engine, held to the College on the server). It
 * replaced the whole Student Payment Report as the home page: that sent every College student (8,193 on the live-shaped copy,
 * 4.3 MB) to the browser to show twenty, after the College's academic dashboard was read and thrown away — 10 to 18 seconds
 * before anything showed. The report itself is a click away.
 */
export interface PaySummary { session: string; semester: number | null; summary: PayTotals; byProgramme: (PayTotals & { programme_code: string; programme: string; department: string })[] }
/** 22 Oct 2026: the College's newest confirmed payments — the Bursary's payments query, held to the College on the server */
export interface RecentPayment { reference: string; confirmed_at: string; payer: string; number: string | null; programme: string | null; dept: string | null; purpose: string | null; channel: string | null; amount: number | string; receipt_no: string | null }
export interface RecentPayments { rows: RecentPayment[]; count: number; total: number | string }

const naira = (n: number | string) => "₦" + Number(n).toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 2 });
const count = (n: number) => Number(n).toLocaleString("en-NG");
const pc = (n: number, of: number) => (of ? `${Math.round((100 * n) / of)}%` : "—");

const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });

export function FinanceHome({ name, pay, recent }: { name: string | null; pay: PaySummary; recent?: RecentPayments | null }) {
  const t = pay.summary;
  return (
    <>
      <PageHead
        title={`Welcome${name ? `, ${name}` : ""}`}
        description={`Finance Controller, College of Health Sciences · ${pay.session}`}
        actions={<>
          <LinkBtn kind="primary" href="/college/payments">Student Payment Report</LinkBtn>
          <LinkBtn href="/finance/payments">Payments Query</LinkBtn>
          <LinkBtn href="/finance/fee-report">School Fees Report</LinkBtn>
          <LinkBtn href="/finance/analytics">Financial Analytics</LinkBtn>
          <LinkBtn href="/student-query">Student Query</LinkBtn>
        </>}
      />
      <Tiles items={[
        ["Students", count(t.students), null, "Active, on probation or admitted, this session"],
        ["School fees payable", naira(t.payable), null, `${count(t.students - t.noCharge)} with a charge`],
        ["Paid", naira(t.paid), "var(--green-ink)", `${count(t.fullyPaid)} fully paid · ${pc(Number(t.paid), Number(t.payable))} of payable`],
        ["Outstanding", naira(t.outstanding), Number(t.outstanding) > 0 ? "var(--red-ink)" : null, `${count(t.withBalance)} with a balance · ${count(t.notPaid)} not paid`],
      ]} />
      <Panel title={`School fees by programme · ${pay.session}`} right={<LinkBtn size="sm" href="/college/payments">Every student</LinkBtn>}>
        {pay.byProgramme.length ? (
          <DTable pageSize={0} cols={["Programme", "Students|num", "Payable|num", "Paid|num", "Outstanding|num", "Fully paid|num", "Part payment|num", "Not paid|num", ""]}
            rows={pay.byProgramme.map((p) => [
              <span key="p">{p.programme}<div className="sub2">{p.department}</div></span>,
              <span key="s" className="tnum">{count(p.students)}</span>,
              <span key="y" className="tnum" style={{ whiteSpace: "nowrap" }}>{naira(p.payable)}</span>,
              <span key="d" className="tnum" style={{ whiteSpace: "nowrap" }}>{naira(p.paid)}</span>,
              <span key="o" className={`tnum${Number(p.outstanding) > 0 ? " ink-red" : ""}`} style={{ whiteSpace: "nowrap" }}>{naira(p.outstanding)}</span>,
              <span key="f" className="tnum">{count(p.fullyPaid)}</span>,
              <span key="r" className="tnum">{count(p.partPayment)}</span>,
              <span key="n" className="tnum">{count(p.notPaid)}</span>,
              <LinkBtn key="a" size="sm" href={`/college/payments?programme=${encodeURIComponent(p.programme_code)}`}>Students</LinkBtn>,
            ])} />
        ) : <PBody><span className="sub2">No College student has a fee position for {pay.session}.</span></PBody>}
      </Panel>
      {/* 22 Oct 2026: every College payment reaches the Controller — the newest here, every one by date, department, programme,
          level, category and channel in the Payments Query, as the Bursary reads the University's */}
      {recent ? (
        <Panel title="Recent payments" right={<LinkBtn kind="ghost" href="/finance/payments">Query all payments</LinkBtn>}>
          {recent.rows.length ? (
            <DTable pageSize={0} cols={["When", "Payer", "Programme", "Purpose", "Channel", "Amount|num", "Receipt|num"]}
              rows={recent.rows.map((r) => [
                <span key="w" className="tnum sub2" style={{ whiteSpace: "nowrap" }}>{when(r.confirmed_at)}</span>,
                <span key="p">{r.payer}<div className="sub2 tnum">{r.number ?? "—"}</div></span>,
                <span key="g">{r.programme ?? "—"}<div className="sub2">{r.dept ?? ""}</div></span>,
                <span key="u" className="sub2">{r.purpose ?? "—"}</span>,
                <span key="c" className="sub2">{r.channel ?? "—"}</span>,
                <span key="a" className="tnum" style={{ whiteSpace: "nowrap" }}>{naira(r.amount)}</span>,
                <span key="r" className="tnum sub2">{r.receipt_no ?? "—"}</span>,
              ])} />
          ) : <PBody><span className="sub2">No College student payment is confirmed yet.</span></PBody>}
        </Panel>
      ) : null}
      <StatsPanel session={pay.session} title="College student statistics" />
      <FinancePanel title="College financial analytics" />
    </>
  );
}
