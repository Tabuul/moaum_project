"use client";
/**
 * V720: every outstanding school fee of the student's record on the dashboard and the fees page — each past session and semester as
 * the Bursary's historical engine assesses it, the current session as the fees position reads it — with a summary, a status and a
 * Pay now on each row. A past session is paid through the historical door (any student, up to the balance; a session's payments
 * settle its first semester first), the current session through the fees page's own. A row whose session already has an open
 * reference offers that reference, never a second. The button is disabled while a reference is being made.
 */
import { useState } from "react";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { BREAKDOWN_HEAD, STATUS_WORDS, attentionRows, breakdownRows, expiresWords, naira, num, payWords, settledRows, summaryWords, type OutstandingFees as Data, type OutstandingRow } from "@/lib/outstanding-fees";
import { PayByCard, useAct } from "./common";

function Row({ r, d, busy, onPay, made }: { r: OutstandingRow; d: Data; busy: boolean; onPay: (r: OutstandingRow) => void; made: { session: string; reference: string; amount: number } | null }) {
  const words = STATUS_WORDS[r.status] ?? [r.status, "grey" as const];
  const pay = payWords(r, d);
  const open = made && made.session === r.session && num(r.balance) > 0 ? { reference: made.reference, amount: made.amount } : r.reference ? { reference: r.reference.reference, amount: num(r.reference.amount) } : null;
  return (
    <div className="of-row" style={{ display: "grid", gridTemplateColumns: "minmax(140px, 1.3fr) minmax(110px, 1fr) minmax(90px, 1fr) minmax(90px, 1fr) minmax(100px, 1fr) minmax(120px, 1fr) minmax(150px, 1.2fr)", gap: 8, alignItems: "center", padding: "8px 0", borderBottom: "1px solid var(--line-2)" }}>
      <div><b className="tnum">{r.session}</b><div className="sub2">{r.period}{r.level ? ` · ${r.level} Level` : ""}{r.kind === "CURRENT" ? " · this session" : ""}</div></div>
      <div className="sub2">{r.description}</div>
      <div className="tnum">{r.due == null ? "—" : naira(r.due)}</div>
      <div className="tnum">{naira(r.paid)}</div>
      <div className={`tnum${num(r.balance) > 0 ? " b700" : ""}`}>{r.balance == null ? "—" : naira(r.balance)}</div>
      <div><Pil kind={words[1]}>{words[0]}</Pil>{r.review ? <div className="sub2">Payment under review</div> : null}</div>
      <div>
        {open ? (
          <div className="stack" style={{ gap: 4 }}>
            <div className="sub2 tnum">{open.reference}{r.reference?.expires_at ? ` · ${expiresWords(r.reference.expires_at)}` : ""}</div>
            <PayByCard reference={open.reference} amount={open.amount} />
          </div>
        ) : r.payable && pay ? (
          <Btn kind="urgent" size="sm" disabled={busy} onClick={() => onPay(r)}>{busy ? "Generating…" : "Pay now"}</Btn>
        ) : pay ? <span className="sub2">{pay}</span> : null}
      </div>
    </div>
  );
}

export function OutstandingFeesCard({ data: initial, compact = false, generatedBy = null }: { data: Data; compact?: boolean; generatedBy?: string | null }) {
  const [data, setData] = useState(initial);
  const [made, setMade] = useState<{ session: string; reference: string; amount: number } | null>(null);
  const [showSettled, setShowSettled] = useState(false);
  const { act, busy, problem } = useAct();
  const owed = attentionRows(data.rows);
  const settled = settledRows(data.rows);
  const total = num(data.summary.outstanding);

  async function pay(r: OutstandingRow) {
    const amount = num(r.payAmount ?? r.balance);
    const j = await act(`pay:${r.session}:${r.semester ?? 0}`, "POST", "/me/outstanding-fees/references", { session: r.session, amount },
      `Outstanding school fees reference for ${r.session}${r.semester ? ` semester ${r.semester}` : ""}`, "");
    if (j && typeof j.reference === "string") {
      setMade({ session: r.session, reference: j.reference, amount });
      if (Array.isArray(j.rows) && j.summary) setData(j as unknown as Data);
    }
  }

  if (!owed.length && !settled.length) return null;
  const head = (
    <div className="of-row sub2" style={{ display: "grid", gridTemplateColumns: "minmax(140px, 1.3fr) minmax(110px, 1fr) minmax(90px, 1fr) minmax(90px, 1fr) minmax(100px, 1fr) minmax(120px, 1fr) minmax(150px, 1.2fr)", gap: 8, padding: "4px 0", borderBottom: "1px solid var(--line)" }}>
      <div>Session · period</div><div>Fee</div><div>Due</div><div>Paid</div><div>Balance</div><div>Status</div><div>Action</div>
    </div>
  );
  const serial = () => docSerial("OSF");
  const meta = (): [string, string][] => [["Current session", data.session], ["Outstanding", naira(total)], ["Sessions owed", String(data.summary.sessions)]];

  return (
    <Panel title="Outstanding school fees" right={<span className="row row--inline row--tight">
      {!compact ? <>
        <Btn kind="ghost" size="sm" onClick={async () => downloadBlob(await brandedXlsx("Outstanding School Fees", BREAKDOWN_HEAD, breakdownRows(data.rows), { sheetName: "Outstanding fees", serial: serial(), meta: meta() }), "outstanding-school-fees.xlsx")}>Excel</Btn>
        <Btn kind="ghost" size="sm" onClick={() => brandedPrint("Outstanding School Fees", "Every session and semester of the record: due, paid, outstanding", BREAKDOWN_HEAD, breakdownRows(data.rows), serial(), { meta: meta(), generatedBy: generatedBy ?? undefined })}>PDF</Btn>
      </> : null}
      {compact ? <LinkBtn kind="ghost" href="/student/fees">View payment breakdown</LinkBtn> : null}
    </span>}>
      <PBody>
        <Note kind={total > 0 ? "bad" : "ok"} title={total > 0 ? `${naira(total)} outstanding` : "No outstanding school fees"}>
          {summaryWords(data)}{" "}
          {data.graduated ? "Your academic status does not change because of a balance; the Bursary clears you financially once every session is settled." : total > 0 ? "A past session is paid here at any time; this session's school fees follow its payment window." : null}
          {data.unassessedBefore && data.assessedFrom ? ` Sessions before ${data.assessedFrom} are not yet assessed by the Bursary and are not listed.` : null}
        </Note>
        <Tiles items={[
          ["Outstanding", naira(total), total > 0 ? "var(--red-ink)" : "var(--green-ink)", `${data.summary.items} fee item${data.summary.items === 1 ? "" : "s"}`],
          ["Sessions owed", String(data.summary.sessions), null, `${data.summary.periods} fee period${data.summary.periods === 1 ? "" : "s"}`],
          ["Paid on record", naira(data.summary.paid), null, "School fees confirmed"],
          ["Awaiting payment", naira(data.summary.pending), num(data.summary.pending) > 0 ? "var(--amber-ink)" : null, num(data.summary.pending) > 0 ? "A reference started, not yet confirmed" : "No payment started"],
        ]} />
        {owed.length ? (
          <div className="mt-2" style={{ overflowX: "auto" }}>
            {head}
            {owed.map((r) => <Row key={`${r.session}-${r.semester ?? 0}-${r.kind}`} r={r} d={data} busy={busy !== null} onPay={pay} made={made} />)}
          </div>
        ) : null}
        {made ? <div className="sub2 mt-2">Reference <b className="tnum">{made.reference}</b> for {made.session} · {naira(made.amount)}: pay by card now, or at a bank with this reference within 24 hours. A session&rsquo;s payments settle its first semester first.</div> : null}
        {problem ? <ProblemNotice problem={problem} /> : null}
        {settled.length && !compact ? (
          <div className="mt-2">
            <Btn kind="ghost" size="sm" onClick={() => setShowSettled((v) => !v)}>{showSettled ? "Hide settled periods" : `Show ${settled.length} settled period${settled.length === 1 ? "" : "s"}`}</Btn>
            {showSettled ? <div className="mt-1" style={{ overflowX: "auto" }}>{head}{settled.map((r) => <Row key={`${r.session}-${r.semester ?? 0}-${r.kind}-s`} r={r} d={data} busy={false} onPay={pay} made={null} />)}</div> : null}
          </div>
        ) : null}
      </PBody>
    </Panel>
  );
}
