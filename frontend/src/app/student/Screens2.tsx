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
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { Passport } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { PayByCard, naira, onDay, useAct, when } from "./common";
import { ProblemNotice } from "@/components/ProblemNotice";

export function FeesScreen({ s, fees, paid }: { s: Me; fees: Fees; paid: string | null }) {
  const { act, busy, problem } = useAct();
  const [now] = useState(() => new Date().getTime());
  const [sel, setSel] = useState<number>(fees.balance);
  // the school-fee reference awaiting payment; the GST fee (V314) has a reference of its own, paid from GST & EPS and offered below
  const isGst = (purpose: string | null | undefined) => (purpose ?? "").startsWith("GST fee");
  const open = fees.references.find((r) => !r.confirmed_at && new Date(r.expires_at).getTime() > now && r.session === fees.session && !isGst(r.purpose)) ?? null;
  const openGst = fees.references.find((r) => !r.confirmed_at && new Date(r.expires_at).getTime() > now && r.session === fees.session && isGst(r.purpose)) ?? null;
  const justPaid = paid ? fees.references.find((r) => r.reference === paid) ?? null : null;
  // V361: "no charge" is a charge not yet stated; a ₦0 charge the Bursary stated on purpose is a charge
  const noCharge = fees.stated === false || (fees.stated === undefined && fees.due === 0);
  const w = fees.window ?? null;   // V288: the portal's school-fees window
  const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
  const canPay = !w || w.state === "OPEN";
  return (
    <>
      {justPaid && !justPaid.confirmed_at ? (
        <div className="card"><div className="card__body" style={{ alignItems: "center", textAlign: "center", gap: "var(--s-4)", padding: "var(--s-6) var(--s-5)" }}>
          <div><div className="t-lg b700" style={{ letterSpacing: "-.3px" }}>Confirming your payment</div>
            <p className="sub2" style={{ margin: "6px auto 0", maxWidth: "44ch", lineHeight: 1.55 }}>Reference {justPaid.reference}. This page updates when the payment is confirmed.</p></div>
          <Btn kind="ghost" onClick={() => window.location.reload()}>Check again</Btn>
        </div></div>
      ) : null}
      <div className="grid grid--3">
        <div className="tile"><span className="eyebrow">Session charge</span><span className="n tnum">{noCharge ? "—" : naira(fees.due)}</span><span className="c">{fees.session} · {s.level} Level</span></div>
        <div className="tile"><span className="eyebrow">Paid</span><span className="n tnum ink-green">{naira(fees.paid)}</span><span className="c">{fees.paidInFull && !noCharge ? "Settled in full" : fees.instalmentsPaid === 1 ? "Instalment 1 of 2" : "Nothing yet"}</span></div>
        <div className="tile"><span className="eyebrow">Outstanding</span><span className="n tnum" style={{ color: fees.balance > 0 ? "var(--red-ink)" : "var(--green-ink)" }}>{naira(fees.balance)}</span><span className="c">{noCharge ? "No charge stated yet" : fees.balance > 0 ? "Due this session" : "Cleared"}</span></div>
      </div>
      {noCharge ? (
        <Note kind="info" title={`No charge is stated for ${fees.session} yet`}>Your charge appears when the Bursar states the fee schedule. Course registration opens once it is stated and paid.{fees.sessions.filter((x) => x !== fees.session).length ? <span className="blk">A charge is stated for {fees.sessions.filter((x) => x !== fees.session).map((x, i) => <span key={x}>{i ? ", " : ""}<Link href={`/student/fees?session=${encodeURIComponent(x)}`}>{x}</Link></span>)} &mdash; open it to pay.</span> : null}</Note>
      ) : fees.schemeProblem ? (
        <Note kind="info" title="What a payment releases is not yet stated">{fees.schemeProblem}</Note>
      ) : fees.clearsRegistration ? (
        <Note kind="ok" title="Payment confirmed">{fees.paidInFull ? "Proceed and register your semester courses." : `Proceed and register your semester courses. ${naira(fees.balance)} of the session's charge still remains.`}</Note>
      ) : (
        <Note kind="bad" title="Course registration waits on this semester’s school fees">{fees.hasArrears ? "Arrears from an earlier session stand against you, and block everything while they do." : "Course registration for a semester opens once that semester’s school fees are paid in full; the examination waits on the session paid in full."}</Note>
      )}
      {justPaid && justPaid.confirmed_at && isGst(justPaid.purpose) ? (
        <Note kind="ok" title="GST fee payment confirmed">Reference {justPaid.reference} confirmed. It covers GST and EPS; register your GST/EPS courses on Course registration.</Note>
      ) : null}
      {openGst ? (
        <Panel title="GST fee awaiting payment" right={<LinkBtn kind="ghost" size="sm" href={`/student/gst?session=${encodeURIComponent(fees.session)}`}>GST &amp; EPS</LinkBtn>}>
          <PBody>
            <div className="sub2">Reference <b className="tnum">{openGst.reference}</b> · {naira(openGst.amount)} · expires {when(openGst.expires_at)}. Separate from school fees; covers GST and EPS.</div>
            <div className="row mt-2"><PayByCard reference={openGst.reference} amount={Number(openGst.amount)} /></div>
          </PBody>
        </Panel>
      ) : null}
      <Panel title="The charge" right={fees.session}>
        <DTable cols={["Item", "Amount|num"]} rows={[
          ...fees.charges.map((c) => [<span key="i">{c.item}</span>, <span className="tnum" key="a">{naira(c.amount)}</span>]),
          [<strong key="t">Total</strong>, <strong className="tnum t-md" key="a">{naira(fees.due)}</strong>],
        ]} />
      </Panel>
      {!noCharge && fees.balance > 0 ? (
        <Panel title="Pay" right="Against a reference this portal generates">
          <PBody>
            {w && w.state !== "OPEN" ? (
              <Note kind="bad" title={w.state === "SCHEDULED" ? "School fees payment is not yet open" : "SCHOOL FEES PAYMENT IS CURRENTLY CLOSED"}>
                {w.state === "SCHEDULED" ? `Payment for ${fees.session} opens on ${whenAt(w.opens_at)}.` : `School fees payment for ${fees.session} is currently closed.`}
                {w.opens_at || w.closes_at ? <span className="blk">Payment window: {w.opens_at ? whenAt(w.opens_at) : "—"} – {w.closes_at ? whenAt(w.closes_at) : "no closing date"}{w.late_until ? ` · late payment until ${whenAt(w.late_until)}` : ""}.</span> : null}
                {w.reason ? <span className="blk">{w.reason}</span> : null}
                <span className="blk">{w.state === "SCHEDULED" ? "Check again when the window opens." : "The University has not currently opened the payment portal; please check again when it is reopened. A reference already generated is still paid and confirmed."}</span>
              </Note>
            ) : null}
            {w && w.state === "OPEN" && w.phase === "LATE" ? (
              <Note kind="info" title="LATE PAYMENT PERIOD">The normal window closed on {whenAt(w.closes_at)}; payment is accepted until {whenAt(w.late_until)}{w.late_fee_enabled ? ", and the late payment fee the Bursar stated is in your charge above" : ""}.</Note>
            ) : null}
            {open ? (
              <>
                <div className="eyebrow">Reference</div>
                <div className="tnum b700" style={{ fontSize: "var(--t-2xl)", letterSpacing: ".5px" }}>{open.reference}</div>
                <div className="sub2">{naira(open.amount)} · expires {when(open.expires_at)}. Pay with this reference only: at a bank branch, by transfer, or by card below.</div>
                <div className="row mt-2"><PayByCard reference={open.reference} amount={Number(open.amount)} /></div>
              </>
            ) : (
              (() => {
                const first = fees.firstSemesterOutstanding;
                const second = fees.secondSemesterOutstanding;
                // payments are cumulative: the first semester must clear before the second.
                // Offer the instalment that is due now, and always the whole session.
                const opts: { key: string; label: string; amount: number }[] = [];
                if (first > 0 && second > 0) {
                  opts.push({ key: "first", label: "First semester", amount: first });
                  opts.push({ key: "full", label: "Full session · both semesters", amount: fees.balance });
                } else if (first > 0) {
                  // no distinct second-semester portion: the first semester is the whole charge
                  opts.push({ key: "first", label: "First semester", amount: fees.balance });
                } else {
                  // the first semester is settled; what remains is the second semester
                  opts.push({ key: "second", label: "Second semester", amount: fees.balance });
                }
                const chosen = opts.find((o) => o.amount === sel) ?? opts[0];
                return (
                  <>
                    <div className="sub2">{opts.length > 1
                      ? "Pay this semester, or the whole session at once. Pick one, then generate the reference."
                      : "Pay the outstanding school fees. Generate the reference, then pay against it."}</div>
                    <div className="row">
                      {opts.map((o) => (
                        <Btn key={o.key} kind={chosen.key === o.key ? "primary" : "ghost"} disabled={busy !== null} onClick={() => setSel(o.amount)}>{o.label} · {naira(o.amount)}</Btn>
                      ))}
                    </div>
                    <div className="row">
                      <Btn kind="primary" disabled={busy !== null || !canPay} onClick={() => void act("ref", "POST", "/me/fees/references", { session: fees.session, amount: chosen.amount }, `Fee reference generated by the student for ${fees.session}`)}>{busy === "ref" ? "Generating…" : `Generate a reference for ${naira(chosen.amount)}`}</Btn>
                    </div>
                  </>
                );
              })()
            )}
            {problem ? <ProblemNotice problem={problem} /> : null}
          </PBody>
        </Panel>
      ) : null}
      <Panel title="Payment History" right={fees.references.length ? `${fees.references.length}` : "none yet"}>
        <DTable cols={["Reference", "Purpose", "Amount|num", "Status", "|num"]} rows={fees.references.map((r) => [
          <span className="tnum t-xs ink-muted" key="r" style={{ letterSpacing: "-.2px" }}>{r.reference}</span>,
          <Two key="p" a={r.purpose} b={r.confirmed_at ? `Confirmed ${when(r.confirmed_at)} · ${r.channel}` : `Generated ${when(r.generated_at)}`} />,
          <span className="tnum" key="a">{naira(r.amount)}</span>,
          r.confirmed_at ? <Pil kind="ok" key="s">Paid</Pil> : new Date(r.expires_at).getTime() > now ? <Pil kind="info" key="s">Awaiting confirmation</Pil> : <Pil kind="grey" key="s">Expired</Pil>,
          r.receipt_no ? <LinkBtn key="x" kind="ghost" href={`/student/receipt/${encodeURIComponent(r.reference)}`}>Receipt</LinkBtn> : <span key="x" />,
        ])} />
        {!fees.references.length ? <PBody><div className="sub2">No payments yet.</div></PBody> : null}
      </Panel>
      {fees.sessions.some((x) => x !== fees.session) ? (
        <div className="sub2">Sessions with a charge: {fees.sessions.map((x) => <Link key={x} href={`/student/fees?session=${encodeURIComponent(x)}`} style={{ marginRight: "var(--s-2)" }}>{x}</Link>)}</div>
      ) : null}
    </>
  );
}

export function ReceiptScreen({ r, qr, verifyUrl, token, photoSrc }: { r: Receipt; qr?: string | null; verifyUrl?: string | null; token?: string | null; photoSrc?: string | null }) {
  if (!r.confirmed_at) {
    return <Note kind="info" title="This payment is not confirmed yet">A receipt is issued the moment the Bursary or the gateway confirms it. Reference {r.reference}.</Note>;
  }
  return (
    <>
      <Note kind="ok" title={`Payment confirmed on ${onDay(r.confirmed_at)}`} />
      <div className="doc" style={{ maxWidth: 660 }}>
        <div className="doc__head">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 46, height: 48, objectFit: "contain" }} />
          <div className="u">REV. FR. MOSES ORSHIO ADASU<br />UNIVERSITY, MAKURDI</div>
          <div className="eyebrow">Official Payment Receipt</div>
        </div>
        <div className="row row--between" style={{ gap: "var(--s-5)", marginBottom: "var(--s-5)" }}>
          <div className="kv"><span className="k">Receipt number</span><span className="v tnum">{r.receipt_no}</span></div>
          <div className="kv"><span className="k">Date</span><span className="v tnum">{onDay(r.confirmed_at)}</span></div>
        </div>
        <div className="row row--top" style={{ gap: "var(--s-6)", marginBottom: "var(--s-5)" }}>
          <Passport w={62} h={77} radius={3} src={photoSrc ?? null} />
          <div className="kv"><span className="k">Received from</span><span className="v">{r.name}</span></div>
          <div className="kv"><span className="k">Matriculation number</span><span className="v tnum">{r.matricNo}</span></div>
          <div className="kv"><span className="k">Programme</span><span className="v">{r.programme} · {r.level} Level</span></div>
          <div className="kv"><span className="k">Session</span><span className="v tnum">{r.session}</span></div>
          {r.term ? <div className="kv"><span className="k">Semester</span><span className="v">{r.term}</span></div> : null}
        </div>
        <div className="tablewrap"><table className="tbl--data" style={{ minWidth: 400 }}>
          <thead><tr><th style={{ background: "var(--chrome)", color: "var(--surface)" }}>Being payment for</th><th className="num" style={{ background: "var(--chrome)", color: "var(--surface)" }}>Amount</th></tr></thead>
          <tbody>
            <tr><td>{receiptPurpose(r.purpose)}<div className="sub2 tnum">Against reference {r.reference}</div></td><td className="num tnum b600">{naira(r.amount)}</td></tr>
            <tr style={{ background: "var(--bg)" }}><td className="b700">TOTAL RECEIVED</td><td className="num tnum b700 t-md">{naira(r.amount)}</td></tr>
          </tbody>
        </table></div>
        <div className="row" style={{ gap: "var(--s-6)", margin: "var(--s-5) 0" }}>
          <div className="kv"><span className="k">Channel</span><span className="v">{r.channel}</span></div>
          <div className="kv"><span className="k">Gateway or teller reference</span><span className="v tnum">{r.note ?? "—"}</span></div>
        </div>
        <div className="row" style={{ gap: "var(--s-4)", paddingTop: 6, borderTop: "1px solid var(--line-2)" }}>
          <div className="kv grow" style={{ minWidth: 200 }}><span className="k">Verification</span><span className="v tnum">{r.receipt_no}</span><span className="sub2">Scan the QR code or use the check code to verify this receipt.{token ? ` Check code ${token}.` : ""}</span>
            {verifyUrl ? <a href={verifyUrl} target="_blank" rel="noopener" className="sub2 ink-chrome">Open the verification page</a> : null}</div>
          {qr ? (
            <div style={{ textAlign: "center" }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={qr} alt="Scan to verify this receipt" style={{ width: 108, height: 108, display: "block" }} />
              <span className="sub2" style={{ fontSize: 10, letterSpacing: ".08em" }}>SCAN TO VERIFY</span>
            </div>
          ) : null}
        </div>
      </div>
      <div className="row">
        <a href={`/student/receipt/${encodeURIComponent(r.reference)}/pdf`} target="_blank" rel="noopener" className="btn btn--primary">Download PDF</a>
        <LinkBtn kind="ghost" size="md" href="/student/fees">Back to payments</LinkBtn>
      </div>
    </>
  );
}
