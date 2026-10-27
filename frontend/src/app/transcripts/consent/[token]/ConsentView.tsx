"use client";
/** V668: what an institution asked for, shown to the graduate, who consents or refuses (a refusal cancels the request) */
import { useCallback, useEffect, useState } from "react";
import { Btn, Note } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { longDay, trnCall, type TrnConsent } from "@/lib/transcripts-public";

export function ConsentView({ token }: { token: string }) {
  const [c, setC] = useState<TrnConsent | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [msg, setMsg] = useState<{ kind: "ok" | "bad"; text: string } | null>(null);

  const read = useCallback(async (): Promise<{ view: TrnConsent } | { problem: string }> => {
    const r = await trnCall<{ consent: string }>("GET", `/consent/${encodeURIComponent(token)}`);
    if (!r.ok) return { problem: r.code === "TRN_NOT_FOUND" ? "This link does not open a request for your consent. Check that the whole link from your email or text was opened." : r.message };
    return { view: JSON.parse(r.data.consent) as TrnConsent };
  }, [token]);
  useEffect(() => {
    let alive = true;
    void read().then((x) => { if (!alive) return; if ("view" in x) setC(x.view); else setProblem(x.problem); });
    return () => { alive = false; };
  }, [read]);

  async function answer(give: boolean) {
    setMsg(null);
    const r = await trnCall<{ consent: string }>("POST", `/consent/${encodeURIComponent(token)}`, { give, note: note.trim() || null });
    if (!r.ok) { setMsg({ kind: "bad", text: r.message }); return; }
    setMsg({ kind: "ok", text: give ? "Thank you. The Transcript Desk will prepare your transcript once the fee is paid." : "The request has been cancelled and the organisation told." });
    const x = await read();
    if ("view" in x) setC(x.view);
  }

  if (problem) return <><h1 className="trn-h1">Consent to a transcript request</h1><Note kind="bad" title={problem} /></>;
  if (!c) return <p aria-live="polite">Opening the request…</p>;
  const open = c.state === "AWAITING" && !c.requestClosed;
  return (
    <>
      <h1 className="trn-h1">Consent to a transcript request</h1>
      <p>{c.holder}, an organisation has asked the University for your academic transcript. It is not prepared or sent unless you agree.</p>
      <dl className="trn-kv">
        <dt>Asked by</dt><dd>{c.requesterName}{c.organisation ? `, ${c.organisation}` : ""} · {c.email}</dd>
        {c.purpose ? <><dt>Purpose</dt><dd>{c.purpose}</dd></> : null}
        <dt>Sent to</dt><dd>{[c.recipientName, c.recipientEmail].filter(Boolean).join(" · ") || c.organisation}</dd>
        {c.recipientAddress ? <><dt>Address</dt><dd style={{ whiteSpace: "pre-line" }}>{c.recipientAddress}</dd></> : null}
        <dt>Request</dt><dd className="tnum">{c.ref}</dd>
      </dl>
      {open ? (
        <>
          <Field id="c-note" label="A note, if you wish" full><textarea id="c-note" className="ctl" rows={2} maxLength={1000} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          <div className="row row--tight">
            <Btn kind="primary" size="md" onClick={() => answer(true)}>I agree: send my transcript</Btn>
            <Btn kind="ghost" size="md" onClick={() => answer(false)}>I do not agree</Btn>
          </div>
          {c.expiresAt ? <p className="sub2">Answer by {longDay(c.expiresAt)}; after that the request lapses.</p> : null}
        </>
      ) : (
        <Note kind={c.state === "GIVEN" ? "ok" : "info"} title={c.state === "GIVEN" ? `You consented${c.decidedAt ? ` on ${longDay(c.decidedAt)}` : ""}.` : c.state === "REFUSED" ? `You did not consent${c.decidedAt ? ` (${longDay(c.decidedAt)})` : ""}; the request was cancelled.` : c.state === "EXPIRED" ? "The time to answer has passed; the request lapsed." : "This request is closed."} />
      )}
      {msg ? <Note kind={msg.kind} title={msg.text} /> : null}
      <p className="sub2">Did not expect this? Choose &ldquo;I do not agree&rdquo;; nothing is sent.</p>
    </>
  );
}
