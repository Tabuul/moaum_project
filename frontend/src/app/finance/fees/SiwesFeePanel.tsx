"use client";
/** V752: the SIWES registration fee — the University's master prompt of 12 November 2026 set it at ₦4,000. The Bursary states a figure
 *  for a session (the Bursar, the Students Account Officer, the Super Administrator) as a draft, and the Bursar publishes it; the
 *  published figure stays in force while a restatement waits beside it, so stating a new figure never stops students paying. V777 (the
 *  user's word of 22 November 2026, "yes charge every siwes course"): every SIWES course carries it — it is paid once a session by every
 *  student who registers one, whatever the programme, level or semester, before the course is registered, through the gateways every fee
 *  uses (nothing is registered while no fee is published); students who registered a SIWES course before the rule are asked it now, and
 *  their list is on the SIWES desk's Unpaid courses. It is never a school fee
 *  and never counted with one or with the GST fee. A reference already drawn keeps its amount until it expires or is renewed: a new
 *  amount applies to the references drawn after it is published. Every change is kept on the fee's history. */
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
import { FEE_PUBLISHERS, FEE_STATERS, SIWES_DESK_READERS, byWords, feeChange, feeStanding, naira, siwesFeeScopeWords, type SiwesFeeView } from "@/lib/siwes";

export function SiwesFeePanel({ session, data, actingOffice }: { session: string; data: SiwesFeeView | null; actingOffice: string | null }) {
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
      const r = await fetch(`/api/bff/api/v1/finance/siwes${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
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
    if (!amount || Number.isNaN(n) || n <= 0) { notifyProblem({ status: 422, title: "State the SIWES registration fee in naira, more than zero." }); return; }
    void send("state", "PUT", "/fee", { session, amount: n, note: note.trim() || null }, `SIWES registration fee stated for ${session}: ${n} (a draft)`,
      `SIWES registration fee for ${session} stated as a draft: ${naira(n)}`)
      .then((ok) => { if (ok) { setAmount(""); setNote(""); } });
  }
  function publish() {
    if (!draft) return;
    const ask = inForce
      ? `Publish ${naira(draft.amount)} as the SIWES registration fee for ${session}, in place of ${naira(inForce.amount)}? References already drawn keep their amount.`
      : `Publish the SIWES registration fee of ${naira(draft.amount)} for ${session}? Students can pay it at once.`;
    if (!window.confirm(ask)) return;
    void send("publish", "POST", "/fee/publish", { session }, `SIWES registration fee published for ${session}: ${draft.amount}`, `SIWES registration fee for ${session} published: ${naira(draft.amount)}`);
  }
  const history = (data?.history ?? []).map(feeChange);
  return (
    <Panel title="SIWES registration fee" right={<span className="row row--inline row--tight">
      {inForce ? <><b className="tnum">{naira(inForce.amount)}</b><Pil kind="ok">IN FORCE</Pil></> : <Pil kind="grey">NOT IN FORCE</Pil>}
      {draft ? <Pil kind="warn">DRAFT WAITING</Pil> : null}
      <span className="sub2">{session}</span>
    </span>}>
      <PBody>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <div className="sub2">
          {siwesFeeScopeWords(inForce?.amount)} A payment of its own: never a school fee, never with the GST fee. A figure stated is a draft until the Bursar publishes it; the
          published figure stays in force meanwhile. A reference already drawn keeps its amount until it expires or is renewed. A SIWES payment made on
          the old portal for the session counts, of either semester.
        </div>
        {!inForce ? <Note kind="info" title={`No SIWES registration fee in force for ${session}`}>Until one is published, no student can pay it, and no SIWES course can be registered.</Note> : null}
        <div className="grid grid--2 mt-2">
          <div>
            <div className="eyebrow mb-1">In force</div>
            {inForce ? (
              <KvGrid pairs={[
                ["Amount", <b key="a" className="tnum">{naira(inForce.amount)}</b>],
                ["Published", [inForce.at ? day(inForce.at) : null, inForce.byName].filter(Boolean).join(" · ") || "—"],
              ]} />
            ) : <div className="sub2">Nothing published.</div>}
          </div>
          <div>
            <div className="eyebrow mb-1">Waiting to be published</div>
            {draft ? (
              <>
                <KvGrid pairs={[
                  ["Amount", <b key="a" className="tnum">{naira(draft.amount)}</b>],
                  ["Note", draft.note || "—"],
                  ["Stated by", byWords(draft.byName, null) || "—"],
                  ["Stated", draft.at ? day(draft.at) : "—"],
                ]} />
                {mayPublish ? (
                  <div className="mt-1">
                    <Btn kind="primary" size="sm" busy={busy === "publish"} busyLabel="Publishing…" disabled={busy !== null} onClick={publish}>Publish {naira(draft.amount)}</Btn>
                  </div>
                ) : <div className="sub2 mt-1">The Bursar publishes it.</div>}
              </>
            ) : <div className="sub2">No draft.</div>}
          </div>
        </div>
        {mayState ? (
          <div className="grid grid--4 mt-2">
            <Field id="sf-amount" label={inForce || draft ? "A new figure (₦)" : "SIWES registration fee (₦)"} required><input id="sf-amount" type="number" min={1} step="0.01" className="ctl tnum" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder={draft ? String(Number(draft.amount)) : inForce ? String(Number(inForce.amount)) : "4000"} /></Field>
            <Field id="sf-note" label="Note"><input id="sf-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Council approval, memo reference…" /></Field>
            <div className="row row--inline row--tight" style={{ alignItems: "flex-end" }}>
              <Btn kind="secondary" busy={busy === "state"} busyLabel="Stating…" disabled={busy !== null} onClick={state}>State as a draft for {session}</Btn>
            </div>
          </div>
        ) : <div className="sub2 mt-2">The Bursary states and publishes the SIWES registration fee.</div>}
        <div className="row mt-2" style={{ flexWrap: "wrap" }}>
          <LinkBtn kind="ghost" size="sm" href={`/finance/siwes-payments?session=${encodeURIComponent(session)}`}>SIWES fee payments</LinkBtn>
          {/* V777: the SIWES courses held on a registration with no SIWES fee paid — those who registered one before the rule; linked only for
              the offices that read the desk (the Administrator, who reads this panel, and the auditors do not: the page would refuse them) */}
          {SIWES_DESK_READERS.includes(actingOffice ?? "")
            ? <LinkBtn kind="ghost" size="sm" href={`/siwes/registration?${new URLSearchParams({ session, tab: "unpaid" }).toString()}`}>SIWES courses held without the fee</LinkBtn> : null}
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
