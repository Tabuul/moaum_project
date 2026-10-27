"use client";
/** V668: the requester's own view of a transcript request — the stage in words, the fee and how to pay it (the reference renewed once
 *  it has expired), the identity check or the graduate's consent where they apply, and the steps so far; nothing internal */
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Btn, Note } from "@/components/proto/ui";
import { TIMELINE_WORDS, longDay, naira, trnCall, whenAt, type TrnStatus } from "@/lib/transcripts-public";

interface Answer { request: string; pay: { url: string; biller_name?: string } | null }

const IDENTITY_WORDS: Record<string, string> = {
  CONFIRMED: "Confirmed by a code", AWAITING_REVIEW: "Your identity document is with the Transcript Desk", ACCEPTED: "Identity document accepted", REFUSED: "Identity document not accepted",
};
const CONSENT_WORDS: Record<string, string> = {
  AWAITING: "Waiting for the graduate to consent", GIVEN: "The graduate has consented", REFUSED: "The graduate did not consent", EXPIRED: "The graduate did not answer in time",
};

export function StatusView({ token }: { token: string }) {
  const [v, setV] = useState<{ s: TrnStatus; pay: Answer["pay"] } | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  const [note, setNote] = useState<{ kind: "ok" | "bad"; text: string } | null>(null);

  const read = useCallback(async (): Promise<{ view: { s: TrnStatus; pay: Answer["pay"] } } | { problem: string }> => {
    const r = await trnCall<Answer>("GET", `/status/${encodeURIComponent(token)}`);
    if (!r.ok) return { problem: r.code === "TRN_NOT_FOUND" ? "This link does not open a transcript request. Check that the whole link from your email was opened." : r.message };
    return { view: { s: JSON.parse(r.data.request) as TrnStatus, pay: r.data.pay } };
  }, [token]);
  useEffect(() => {
    let alive = true;
    void read().then((x) => { if (!alive) return; if ("view" in x) setV(x.view); else setProblem(x.problem); });
    return () => { alive = false; };
  }, [read]);

  async function renew() {
    setNote(null);
    const r = await trnCall<{ reference: string }>("POST", `/status/${encodeURIComponent(token)}/renew`, {});
    if (!r.ok) { setNote({ kind: "bad", text: r.message }); return; }
    setNote({ kind: "ok", text: `Your payment reference is ${r.data.reference}; it can be paid now.` });
    const x = await read();
    if ("view" in x) setV(x.view);
  }

  if (problem) return <><h1 className="trn-h1">Your transcript request</h1><Note kind="bad" title={problem} /><p><Link href="/transcripts/request">Request a transcript</Link></p></>;
  if (!v) return <p aria-live="polite">Opening your request…</p>;
  const s = v.s;
  const toPay = !s.paid && !s.closed && !!s.reference && !!s.fee;
  return (
    <>
      <h1 className="trn-h1">Your transcript request {s.ref}</h1>
      <Note kind={s.closed && ["REJECTED", "CANCELLED"].includes(s.stage) ? "bad" : s.paid || !s.fee ? "ok" : "info"} title={s.stageWords}>{s.closedReason ?? null}</Note>

      {toPay ? (
        <>
          <h2 className="trn-h2">Pay the fee</h2>
          {s.referenceExpired ? (
            <Note kind="info" title="The payment reference has expired." action={<Btn kind="primary" onClick={renew}>Get a new reference</Btn>}>A reference can be paid for 24 hours. A new one is made at once.</Note>
          ) : (
            <>
              <p>The fee is <strong>{naira(s.fee)}</strong>. Pay with the payment reference <strong className="tnum">{s.reference}</strong>{s.referenceExpiresAt ? ` before ${whenAt(s.referenceExpiresAt)}` : ""}, online or at any bank. The request moves on by itself once the payment is confirmed.</p>
              {v.pay?.url ? <div className="row row--tight"><a className="btn btn--primary btn--md" href={v.pay.url} target="_blank" rel="noopener noreferrer">Pay online</a></div> : null}
            </>
          )}
        </>
      ) : null}
      {note ? <Note kind={note.kind} title={note.text} /> : null}

      <h2 className="trn-h2">The request</h2>
      <dl className="trn-kv">
        <dt>Transcript of</dt><dd>{s.holder} ({s.matricNo})</dd>
        <dt>Asked by</dt><dd>{s.requesterName}{s.organisation ? `, ${s.organisation}` : ""} · {s.email}</dd>
        <dt>Goes to</dt><dd>{s.destination === "SELF" ? "The graduate" : s.destinationName ?? s.destination}{s.recipientEmail ? ` · ${s.recipientEmail}` : ""}</dd>
        <dt>How</dt><dd>{s.delivery === "DIGITAL" ? "By email, as a secure link" : s.delivery === "PHYSICAL" ? `Printed and posted (${s.copies} cop${s.copies === 1 ? "y" : "ies"})` : `By email, and printed and posted (${s.copies} cop${s.copies === 1 ? "y" : "ies"})`}{s.express ? " · urgent" : ""}</dd>
        {s.recipientAddress ? <><dt>Address</dt><dd style={{ whiteSpace: "pre-line" }}>{s.recipientAddress}</dd></> : null}
        <dt>Fee</dt><dd>{s.fee ? `${naira(s.fee)}${s.paid ? ` · paid ${longDay(s.paidAt)}` : " · not yet paid"}` : "No fee"}</dd>
        {IDENTITY_WORDS[s.identityState] ? <><dt>Identity</dt><dd>{IDENTITY_WORDS[s.identityState]}</dd></> : null}
        {CONSENT_WORDS[s.consentState] ? <><dt>Consent</dt><dd>{CONSENT_WORDS[s.consentState]}{s.consentState === "AWAITING" && s.consentExpiresAt ? ` (until ${longDay(s.consentExpiresAt)})` : ""}</dd></> : null}
        <dt>Received</dt><dd>{whenAt(s.requestedAt)}{s.slaDueOn && s.paid ? ` · expected by ${longDay(s.slaDueOn)}` : ""}</dd>
      </dl>

      {s.timeline?.length ? (
        <>
          <h2 className="trn-h2">So far</h2>
          <ol className="trn-steps">
            {s.timeline.map((e, i) => <li key={i}><time dateTime={e.at}>{whenAt(e.at)}</time><span>{TIMELINE_WORDS[e.action] ?? e.stage ?? e.action}</span></li>)}
          </ol>
        </>
      ) : null}
      <p className="sub2">Keep this link private: anyone who has it can see this page. The transcript itself is sent only to the email and address above.</p>
    </>
  );
}
