"use client";
/** V766: the inter-university transfer application fee — the University's decision of 15 November 2026: a fee per session, stated and
 *  published by the Bursar, possibly nothing, paid online before the application is submitted. The Bursary states a figure for a session
 *  (the Bursar, the Students Account Officer, the Super Administrator) as a draft, and the Bursar publishes it; the published figure stays in
 *  force while a restatement waits beside it. A fee of nothing is published as such: the Academic Office's transfer window opens only once
 *  the session's fee is published (D4). A reference already drawn keeps its amount. Every change is kept on the fee's history. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { day } from "@/lib/format";
import { byWords, feeChange, feeStanding, type SiwesFeeView } from "@/lib/siwes";
import { FEE_PUBLISHERS, FEE_STATERS, naira, num } from "@/lib/transfer-application";

/** finance.iut_fee_view has the shape of finance.siwes_fee_view */
export type IutFeeView = SiwesFeeView;

const amountWords = (m: unknown) => (num(m as number) > 0 ? naira(m as number) : "₦0 (no fee)");

export function IutFeePanel({ session, data, actingOffice }: { session: string; data: IutFeeView | null; actingOffice: string | null }) {
  const router = useRouter();
  const mayState = FEE_STATERS.includes(actingOffice ?? "");
  const mayPublish = FEE_PUBLISHERS.includes(actingOffice ?? "");
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const { inForce, draft } = feeStanding(data);

  async function send(key: string, method: "PUT" | "POST", path: string, body: unknown, reason: string, done: string): Promise<boolean> {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/finance/transfer-applications${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return false; }
      notify(done);
      router.refresh();
      return true;
    } finally {
      setBusy(null);
    }
  }
  function state() {
    const n = Number(amount);
    if (amount.trim() === "" || Number.isNaN(n) || n < 0) { notifyProblem({ status: 422, title: "State the transfer application fee in naira: nothing (0) or more." }); return; }
    void send("state", "PUT", "/fee", { session, amount: n, note: note.trim() || null }, `Transfer application fee stated for ${session}: ${n} (a draft)`,
      `Transfer application fee for ${session} stated as a draft: ${amountWords(n)}`)
      .then((ok) => { if (ok) { setAmount(""); setNote(""); } });
  }
  function publish() {
    if (!draft) return;
    const ask = inForce
      ? `Publish ${amountWords(draft.amount)} as the transfer application fee for ${session}, in place of ${amountWords(inForce.amount)}? References already drawn keep their amount.`
      : `Publish the transfer application fee of ${amountWords(draft.amount)} for ${session}? The Academic Office can then open the transfer window.`;
    if (!window.confirm(ask)) return;
    void send("publish", "POST", "/fee/publish", { session }, `Transfer application fee published for ${session}: ${draft.amount}`, `Transfer application fee for ${session} published: ${amountWords(draft.amount)}`);
  }
  const history = (data?.history ?? []).map(feeChange);
  return (
    <Panel title="Inter-university transfer application fee" right={<span className="row row--inline row--tight">
      {inForce ? <><b className="tnum">{amountWords(inForce.amount)}</b><Pil kind="ok">PUBLISHED</Pil></> : <Pil kind="grey">NOT PUBLISHED</Pil>}
      {draft ? <Pil kind="warn">DRAFT WAITING</Pil> : null}
      <span className="sub2">{session}</span>
    </span>}>
      <PBody>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <div className="sub2">
          Paid online by a student of another university applying for transfer, before the application is submitted; not refunded when an application is declined or
          withdrawn (only a second payment for the same application is owed back). A fee of nothing is published as such; the transfer window opens only once the
          session&rsquo;s fee is published. A figure stated is a draft until the Bursar publishes it. A reference already drawn keeps its amount.
        </div>
        {!inForce ? <Note kind="info" title={`No transfer application fee published for ${session}`}>Until one is published (nothing included), the Academic Office cannot open the transfer window.</Note> : null}
        <div className="grid grid--2 mt-2">
          <div>
            <div className="eyebrow mb-1">Published</div>
            {inForce ? (
              <KvGrid pairs={[
                ["Amount", <b key="a" className="tnum">{amountWords(inForce.amount)}</b>],
                ["Published", [inForce.at ? day(inForce.at) : null, inForce.byName].filter(Boolean).join(" · ") || "—"],
              ]} />
            ) : <div className="sub2">Nothing published.</div>}
          </div>
          <div>
            <div className="eyebrow mb-1">Waiting to be published</div>
            {draft ? (
              <>
                <KvGrid pairs={[
                  ["Amount", <b key="a" className="tnum">{amountWords(draft.amount)}</b>],
                  ["Note", draft.note || "—"],
                  ["Stated by", byWords(draft.byName, null) || "—"],
                  ["Stated", draft.at ? day(draft.at) : "—"],
                ]} />
                {mayPublish ? (
                  <div className="mt-1">
                    <Btn kind="primary" size="sm" busy={busy === "publish"} busyLabel="Publishing…" disabled={busy !== null} onClick={publish}>Publish {amountWords(draft.amount)}</Btn>
                  </div>
                ) : <div className="sub2 mt-1">The Bursar publishes it.</div>}
              </>
            ) : <div className="sub2">No draft.</div>}
          </div>
        </div>
        {mayState ? (
          <div className="grid grid--4 mt-2">
            <Field id="if-amount" label={inForce || draft ? "A new figure (₦)" : "Transfer application fee (₦)"} required hint="0 for no fee">
              <input id="if-amount" type="number" min={0} step="0.01" className="ctl tnum" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder={draft ? String(num(draft.amount)) : inForce ? String(num(inForce.amount)) : "0"} />
            </Field>
            <Field id="if-note" label="Note"><input id="if-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Council approval, memo reference…" /></Field>
            <div className="row row--inline row--tight" style={{ alignItems: "flex-end" }}>
              <Btn kind="secondary" busy={busy === "state"} busyLabel="Stating…" disabled={busy !== null} onClick={state}>State as a draft for {session}</Btn>
            </div>
          </div>
        ) : <div className="sub2 mt-2">The Bursary states and publishes the transfer application fee.</div>}
        <div className="row mt-2" style={{ flexWrap: "wrap" }}>
          <LinkBtn kind="ghost" size="sm" href={`/finance/transfer-application-payments?session=${encodeURIComponent(session)}`}>Transfer application payments</LinkBtn>
        </div>
      </PBody>
      {history.length ? (
        <PBody>
          <details><summary className="sub2">The fee&rsquo;s history for {session} ({history.length})</summary>
            <DTable cols={["S/N|num", "When", "Change", "Amount|num", "By", "Note"]} rows={history.map((h, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>, <span key="t" className="tnum sub2">{h.at ? day(h.at) : "—"}</span>, <span key="w">{h.what || "—"}</span>,
              <span key="a" className="tnum">{h.amount != null ? naira(h.amount) : "—"}{h.was != null && h.was !== h.amount ? <span className="blk sub2">was {naira(h.was)}</span> : null}</span>,
              <span key="b" className="sub2">{h.by || "—"}</span>, <span key="o" className="sub2">{h.note}</span>,
            ])} />
          </details>
        </PBody>
      ) : null}
    </Panel>
  );
}
