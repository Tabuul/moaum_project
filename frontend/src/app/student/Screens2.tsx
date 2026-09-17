"use client";

/**
 * Fees and payments, and the receipt — proto/part4.html studentFees,
 * studentPay and proto/part4c.html studentReceipt, as drawn — from the
 * Bursary's ledger: the charge computed from the schedule, the references
 * generated here, the receipts issued on confirmation, and what the scheme
 * in force says the position releases.
 */
import { useState } from "react";
import Link from "next/link";
import { type Fees, type Me, type Receipt, receiptPurpose } from "@/lib/student-portal";
import { Btn, Note, Panel, PBody, Pil, Tick, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { PayByCard, naira, onDay, useAct, when } from "./common";
import { ProblemNotice } from "@/components/ProblemNotice";

export function FeesScreen({ s, fees, paid }: { s: Me; fees: Fees; paid: string | null }) {
  const { act, busy, problem } = useAct();
  const [now] = useState(() => new Date().getTime());
  const [amount, setAmount] = useState("");
  const open = fees.references.find((r) => !r.confirmed_at && new Date(r.expires_at).getTime() > now && r.session === fees.session) ?? null;
  const justPaid = paid ? fees.references.find((r) => r.reference === paid) ?? null : null;
  const noCharge = fees.due === 0;
  return (
    <>
      {justPaid && !justPaid.confirmed_at ? (
        <div className="card"><div className="card__body" style={{ alignItems: "center", textAlign: "center", gap: 14, padding: "26px 18px" }}>
          <div><div style={{ fontSize: 18, fontWeight: 700, letterSpacing: "-.3px" }}>Confirming your payment</div>
            <p className="sub2" style={{ margin: "6px auto 0", maxWidth: "44ch", lineHeight: 1.55 }}>The gateway tells the University directly when the money lands, and this page updates itself. Reference {justPaid.reference}.</p></div>
          <Btn kind="ghost" onClick={() => window.location.reload()}>Check again</Btn>
        </div></div>
      ) : null}
      <div className="grid grid--3">
        <div className="tile"><span className="eyebrow">Session charge</span><span className="n tnum">{noCharge ? "—" : naira(fees.due)}</span><span className="c">{fees.session} · {s.level} Level</span></div>
        <div className="tile"><span className="eyebrow">Paid</span><span className="n tnum" style={{ color: "var(--green-ink)" }}>{naira(fees.paid)}</span><span className="c">{fees.paidInFull && !noCharge ? "Settled in full" : fees.instalmentsPaid === 1 ? "Instalment 1 of 2" : "Nothing yet"}</span></div>
        <div className="tile"><span className="eyebrow">Outstanding</span><span className="n tnum" style={{ color: fees.balance > 0 ? "var(--red-ink)" : "var(--green-ink)" }}>{naira(fees.balance)}</span><span className="c">{noCharge ? "No charge stated yet" : fees.balance > 0 ? "Due this session" : "Cleared"}</span></div>
      </div>
      {noCharge ? (
        <Note kind="info" title={`No charge is stated for ${fees.session} yet`}>The Bursar states the session&rsquo;s fee schedule; your charge is computed from it the moment it is stated. Nothing is paid against a charge that does not exist.</Note>
      ) : fees.schemeProblem ? (
        <Note kind="info" title="What a payment releases is not yet stated">{fees.schemeProblem}</Note>
      ) : fees.clearsRegistration ? (
        <Note kind="ok" title="Payment confirmed">{fees.paidInFull ? "Proceed and register your semester courses." : `Proceed and register your semester courses. ${naira(fees.balance)} of the session's charge still remains.`}</Note>
      ) : (
        <Note kind="bad" title="Course registration waits on this semester’s school fees">{fees.hasArrears ? "Arrears from an earlier session stand against you, and block everything while they do." : "Course registration for a semester opens once that semester’s school fees are paid in full; the examination waits on the session paid in full."}</Note>
      )}
      <Panel title="The charge" right={fees.session}>
        <DTable cols={["Item", "Amount|num"]} rows={[
          ...fees.charges.map((c) => [<span key="i">{c.item}</span>, <span className="tnum" key="a">{naira(c.amount)}</span>]),
          [<strong key="t">Total</strong>, <strong className="tnum" key="a" style={{ fontSize: 15 }}>{naira(fees.due)}</strong>],
        ]} />
      </Panel>
      {!noCharge && fees.balance > 0 ? (
        <Panel title="Pay" right="Against a reference this portal generates">
          <PBody>
            {open ? (
              <>
                <div className="eyebrow">Reference</div>
                <div className="tnum" style={{ fontSize: 22, fontWeight: 700, letterSpacing: ".5px" }}>{open.reference}</div>
                <div className="sub2">{naira(open.amount)} · expires {when(open.expires_at)}. Quote this reference and nothing else: at a bank branch, by transfer, or by card below. The Bursary confirms it against the bank&rsquo;s record; a gateway confirms it the moment the money lands.</div>
                <div style={{ display: "flex", gap: 9, flexWrap: "wrap", marginTop: 8 }}><PayByCard reference={open.reference} amount={Number(open.amount)} /></div>
              </>
            ) : (
              <>
                <div className="sub2">Pay the outstanding balance — or type any amount. Pick an option, then generate the reference.</div>
                <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center" }}>
                  <Btn kind={amount === String(fees.balance) ? "primary" : "ghost"} disabled={busy !== null} onClick={() => setAmount(String(fees.balance))}>Pay the outstanding · {naira(fees.balance)}</Btn>
                </div>
                <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center" }}>
                  <input className="tnum ws__in" style={{ width: 140 }} value={amount} placeholder={String(fees.balance)} inputMode="numeric" onChange={(e) => setAmount(e.target.value)} aria-label="Amount to pay" />
                  <Btn kind="primary" disabled={busy !== null} onClick={() => void act("ref", "POST", "/me/fees/references", { session: fees.session, amount: amount ? Number(amount) : undefined }, `Fee reference generated by the student for ${fees.session}`)}>{busy === "ref" ? "Generating…" : `Generate a reference for ${naira(amount ? Number(amount) : fees.balance)}`}</Btn>
                </div>
              </>
            )}
            {problem ? <ProblemNotice problem={problem} /> : null}
          </PBody>
        </Panel>
      ) : null}
      <Panel title="Payment History" right={fees.references.length ? `${fees.references.length}` : "none yet"}>
        <DTable cols={["Reference", "Purpose", "Amount|num", "Status", "|num"]} rows={fees.references.map((r) => [
          <span className="tnum" key="r" style={{ fontSize: 11, letterSpacing: "-.2px", color: "var(--muted)" }}>{r.reference}</span>,
          <Two key="p" a={r.purpose} b={r.confirmed_at ? `Confirmed ${when(r.confirmed_at)} · ${r.channel}` : `Generated ${when(r.generated_at)}`} />,
          <span className="tnum" key="a">{naira(r.amount)}</span>,
          r.confirmed_at ? <Pil kind="ok" key="s">Paid</Pil> : new Date(r.expires_at).getTime() > now ? <Pil kind="info" key="s">Awaiting confirmation</Pil> : <Pil kind="grey" key="s">Expired</Pil>,
          r.receipt_no ? <Link key="x" href={`/student/receipt/${encodeURIComponent(r.reference)}`} className="btn btn--ghost btn--sm">Receipt</Link> : <span key="x" />,
        ])} />
        {!fees.references.length ? <PBody><div className="sub2">Every payment against a reference this portal generated appears here, with its receipt. Nothing is released against a payment the bank has not confirmed.</div></PBody> : null}
      </Panel>
      {fees.sessions.length > 1 ? (
        <div className="sub2">Sessions with a charge: {fees.sessions.map((x) => <Link key={x} href={`/student/fees?session=${encodeURIComponent(x)}`} style={{ marginRight: 8 }}>{x}</Link>)}</div>
      ) : null}
    </>
  );
}

export function ReceiptScreen({ r, qr, verifyUrl, token }: { r: Receipt; qr?: string | null; verifyUrl?: string | null; token?: string | null }) {
  if (!r.confirmed_at) {
    return <Note kind="info" title="This payment is not confirmed yet">A receipt is issued the moment the Bursary or the gateway confirms it. Reference {r.reference}.</Note>;
  }
  return (
    <>
      <div className="notice notice--ok"><Tick size={18} colour="var(--green-ink)" /><div><p style={{ color: "var(--green-ink)", fontWeight: 600 }}>Payment confirmed on {onDay(r.confirmed_at)}</p></div></div>
      <div className="doc" style={{ maxWidth: 660 }}>
        <div className="doc__head">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 46, height: 48, objectFit: "contain" }} />
          <div className="u">REV. FR. MOSES ORSHIO ADASU<br />UNIVERSITY, MAKURDI</div>
          <div className="eyebrow">Official Payment Receipt</div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", gap: 20, flexWrap: "wrap", marginBottom: 18 }}>
          <div className="kv"><span className="k">Receipt number</span><span className="v tnum" style={{ fontSize: 13, overflowWrap: "anywhere" }}>{r.receipt_no}</span></div>
          <div className="kv"><span className="k">Date</span><span className="v tnum">{onDay(r.confirmed_at)}</span></div>
        </div>
        <div style={{ display: "flex", gap: 24, flexWrap: "wrap", marginBottom: 18 }}>
          <div className="kv"><span className="k">Received from</span><span className="v">{r.name}</span></div>
          <div className="kv"><span className="k">Matriculation number</span><span className="v tnum">{r.matricNo}</span></div>
          <div className="kv"><span className="k">Programme</span><span className="v">{r.programme} · {r.level} Level</span></div>
          <div className="kv"><span className="k">Session</span><span className="v tnum">{r.session}</span></div>
          {r.term ? <div className="kv"><span className="k">Semester</span><span className="v">{r.term}</span></div> : null}
        </div>
        <div className="tablewrap"><table style={{ minWidth: 400 }}>
          <thead><tr><th style={{ background: "var(--chrome)", color: "#fff" }}>Being payment for</th><th className="num" style={{ background: "var(--chrome)", color: "#fff" }}>Amount</th></tr></thead>
          <tbody>
            <tr><td>{receiptPurpose(r.purpose)}<div className="sub2 tnum">Against reference {r.reference}</div></td><td className="num tnum" style={{ fontWeight: 600 }}>{naira(r.amount)}</td></tr>
            <tr style={{ background: "var(--bg)" }}><td style={{ fontWeight: 700 }}>TOTAL RECEIVED</td><td className="num tnum" style={{ fontWeight: 700, fontSize: 16 }}>{naira(r.amount)}</td></tr>
          </tbody>
        </table></div>
        <div style={{ display: "flex", gap: 24, flexWrap: "wrap", margin: "18px 0" }}>
          <div className="kv"><span className="k">Channel</span><span className="v">{r.channel}</span></div>
          <div className="kv"><span className="k">Gateway or teller reference</span><span className="v tnum">{r.note ?? "—"}</span></div>
        </div>
        <div style={{ display: "flex", gap: 16, alignItems: "center", flexWrap: "wrap", paddingTop: 6, borderTop: "1px solid var(--line-2)" }}>
          <div className="kv" style={{ flexGrow: 1, minWidth: 200 }}><span className="k">Verification</span><span className="v tnum" style={{ fontSize: 13, overflowWrap: "anywhere" }}>{r.receipt_no}</span><span className="sub2">Scan the QR code to verify this payment, or use the check code to confirm the authenticity of this receipt against the Bursary&rsquo;s ledger.{token ? ` Check code ${token}.` : ""}</span>
            {verifyUrl ? <a href={verifyUrl} target="_blank" rel="noopener" className="sub2 tnum" style={{ color: "var(--blue-ink)", overflowWrap: "anywhere" }}>{verifyUrl.replace(/^https?:\/\//, "")}</a> : null}</div>
          {qr ? (
            <div style={{ textAlign: "center" }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={qr} alt="Scan to verify this receipt" style={{ width: 108, height: 108, display: "block" }} />
              <span className="sub2" style={{ fontSize: 10, letterSpacing: ".08em" }}>SCAN TO VERIFY</span>
            </div>
          ) : null}
        </div>
      </div>
      <div style={{ display: "flex", gap: 9, flexWrap: "wrap" }}>
        <a href={`/student/receipt/${encodeURIComponent(r.reference)}/pdf`} target="_blank" rel="noopener" className="btn btn--primary">Download PDF</a>
        <Link href="/student/fees" className="btn btn--ghost">Back to payments</Link>
      </div>
    </>
  );
}
