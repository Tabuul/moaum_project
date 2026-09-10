"use client";

/** tNelfund, tNelMatch, tNelStatus — proto/part37, part49: remittances split against the register, suspense that is owned, the Fund's decisions. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { parseRows, type NelfundDesk } from "@/lib/wallet";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, day, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

interface LedgerEntry { id: string; at: string; session: string; kind: string; amount: number; reference: string | null; note: string | null; balance: number }
interface StudentLedger { student: { name: string; number: string; matric_no: string | null; admission_no: string | null; status: string }; session: string; balance: number; statement: LedgerEntry[]; position: { balance: number; paid_in_full: boolean } }

const LKIND: Record<string, [string, "ok" | "info" | "bad" | "grey"]> = { CREDIT: ["NELFUND credit", "ok"], TOPUP: ["Top-up", "ok"], APPLIED: ["Applied to fees", "info"], REVERSED: ["Reversed to the Fund", "bad"], REFUND: ["Refund", "grey"] };

export function Nelfund({ d, tab, sessions, actingOffice }: { d: NelfundDesk; tab: string; sessions: string[]; actingOffice: string | null }) {
  const router = useRouter();
  const bursary = ["bursar", "admin", "super"].includes(actingOffice ?? "");
  const registry = ["registrar", "dregistrar", "academic", "super", "bursar"].includes(actingOffice ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [batch, setBatch] = useState({ ref: "", receivedOn: "", note: "", text: "" });
  const [credit, setCredit] = useState({ number: "", amount: "", reason: "" });
  const [lookup, setLookup] = useState("");
  const [ledger, setLedger] = useState<StudentLedger | null>(null);
  const [statusText, setStatusText] = useState("");
  const [fix, setFix] = useState<Record<string, { number: string; note: string }>>({});
  const t = d.tiles;
  const s = d.status;

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      router.refresh();
      return j;
    } finally {
      setBusy(false);
    }
  }
  const go = (next: string, session = d.session) => router.push(`/finance/nelfund?tab=${next}&session=${encodeURIComponent(session)}`);

  async function lookUp(number: string) {
    const n = number.trim();
    if (!n) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/nelfund/students/${encodeURIComponent(n)}/statement?session=${encodeURIComponent(d.session)}`);
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); setLedger(null); return; }
      setLedger(j as StudentLedger);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, alignItems: "flex-end", flexWrap: "wrap" }}>
        <div className="field" style={{ minWidth: 160 }}><label htmlFor="nf-s">Session</label>
          <select id="nf-s" className="ctl" value={d.session} onChange={(e) => go(tab, e.target.value)}>{(sessions.includes(d.session) ? sessions : [d.session, ...sessions]).map((x) => <option key={x} value={x}>{x}</option>)}</select></div>
        <div className="role-tabs" role="tablist" style={{ marginBottom: 2 }}>
          {[["batches", "Remittances"], ["match", `Suspense${t.unmatched_rows ? ` (${t.unmatched_rows})` : ""}`], ["status", "The Fund's decisions"]].map(([k, l]) => <button key={k} type="button" role="tab" aria-selected={tab === k ? "true" : "false"} onClick={() => go(k)}>{l}</button>)}
        </div>
      </div></div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}

      {tab === "batches" ? (
        <>
          <Tiles items={[
            ["Received this session", money(Number(t.received)), null, `${t.batches} batch${t.batches === 1 ? "" : "es"}, ${t.students} students`],
            ["Allocated to students", money(Number(t.allocated)), null, "Credited to a named wallet"],
            ["Unallocated", money(Number(t.unallocated)), Number(t.unallocated) ? "var(--red-ink)" : null, `${t.unmatched_rows} row${t.unmatched_rows === 1 ? "" : "s"} not yet matched`],
            ["Reversed to the Fund", money(Number(t.reversed)), null, "Withdrawn, or not on the register"],
          ]} />
          {t.unmatched_rows ? (
            <Note kind="bad" title={`${t.unmatched_rows} row${t.unmatched_rows === 1 ? " is" : "s are"} money the University is holding that a student cannot see`} action={<Btn kind="primary" onClick={() => go("match")}>Match the {t.unmatched_rows} outstanding</Btn>}>
              A remittance is received in bulk and must be split across named students. Until it is, a student whose loan was approved and paid still shows as owing. Every naira either sits on a student&rsquo;s wallet or sits here, and this figure is the queue.
            </Note>
          ) : <Note kind="ok" title="Every naira received is on a named wallet">There is nothing in suspense.</Note>}
          <Panel title="Remittance batches" right="From the Fund, newest first">
            {d.batches.length ? (
              <DTable cols={["Reference|mid", "Received|mid", "Amount|num", "Rows|num", "Matched|num", "Unmatched|num", "Reversed|num"]} rows={d.batches.map((b) => [
                <span className="tnum" key="r">{b.ref}</span>, <span className="sub2" key="d">{day(b.received_on)}</span>, <span className="tnum" key="a">{money(Number(b.amount))}</span>,
                <span className="tnum" key="n">{b.rows_read}</span>, <span className="tnum" key="m">{b.matched}</span>,
                b.unmatched ? <b className="tnum" key="u" style={{ color: "var(--red-ink)" }}>{b.unmatched}</b> : <span className="sub2" key="u">—</span>,
                b.reversed ? <span className="tnum" key="v">{b.reversed}</span> : <span className="sub2" key="v">—</span>,
              ])} />
            ) : <PBody><div className="sub2">No remittance loaded for {d.session}.</div></PBody>}
          </Panel>
          {bursary ? (
            <Panel title="Load a remittance" right="Matched on matriculation number against the register, the same register the class list is drawn from">
              <PBody>
                <div className="grid grid--3">
                  <Field id="nb-ref" label="The Fund's reference"><input id="nb-ref" className="ctl tnum" value={batch.ref} onChange={(e) => setBatch({ ...batch, ref: e.target.value })} placeholder="NLF/2026/0918" /></Field>
                  <Field id="nb-on" label="Received on"><input id="nb-on" className="ctl" type="date" value={batch.receivedOn} onChange={(e) => setBatch({ ...batch, receivedOn: e.target.value })} /></Field>
                  <Field id="nb-note" label="Note"><input id="nb-note" className="ctl" value={batch.note} onChange={(e) => setBatch({ ...batch, note: e.target.value })} /></Field>
                </div>
                <Field id="nb-rows" label="The rows" hint="Paste the Fund's schedule: matriculation number, name, amount — one student per line, comma- or tab-separated, with or without a header."><textarea id="nb-rows" className="ctl tnum" rows={6} value={batch.text} onChange={(e) => setBatch({ ...batch, text: e.target.value })} /></Field>
                <div><Btn kind="primary" disabled={busy || !batch.ref.trim() || !batch.text.trim()} onClick={async () => { const rows = parseRows(batch.text, ["matric", "name", "amount"]).map((r) => ({ matricNo: r.matric, name: r.name, amount: r.amount })); const j = await send("/api/bff/api/v1/nelfund/batches", { ref: batch.ref, session: d.session, receivedOn: batch.receivedOn || null, note: batch.note || null, rows }, `NELFUND remittance ${batch.ref} loaded`); if (j) { setSaid(`${batch.ref}: ${j.matched} matched, ${j.unmatched} in suspense, ${money(Number(j.amount))}`); setBatch({ ref: "", receivedOn: "", note: "", text: "" }); } }}>Load and match</Btn></div>
              </PBody>
            </Panel>
          ) : null}
          {bursary ? (
            <Panel title="Credit a student's wallet" right="A correction, a sponsor's payment off the gateway, a goodwill credit">
              <PBody>
                <div className="grid grid--3">
                  <Field id="cw-num" label="Matriculation or admission number"><input id="cw-num" className="ctl tnum" value={credit.number} onChange={(e) => setCredit({ ...credit, number: e.target.value })} placeholder="MOAUM/CSC/26/0001" /></Field>
                  <Field id="cw-amt" label="Amount"><input id="cw-amt" className="ctl tnum" inputMode="decimal" value={credit.amount} onChange={(e) => setCredit({ ...credit, amount: e.target.value.replace(/[^0-9.]/g, "") })} placeholder="50000" /></Field>
                  <Field id="cw-why" label="Reason" hint="The student sees this on their wallet statement."><input id="cw-why" className="ctl" value={credit.reason} onChange={(e) => setCredit({ ...credit, reason: e.target.value })} placeholder="Sponsor payment received by bank transfer" /></Field>
                </div>
                <div><Btn kind="primary" disabled={busy || !credit.number.trim() || !Number(credit.amount) || !credit.reason.trim()} onClick={async () => { const j = await send("/api/bff/api/v1/nelfund/credit", { number: credit.number.trim(), session: d.session, amount: Number(credit.amount), reason: credit.reason.trim() }, `Wallet credited: ${credit.number.trim()}`); if (j) { setSaid(`${money(Number(credit.amount))} credited to ${credit.number.trim()} — wallet balance ${money(Number(j.balance))}`); setCredit({ number: "", amount: "", reason: "" }); } }}>Credit the wallet</Btn></div>
                <div className="sub2" style={{ marginTop: 6 }}>This is an attributed credit against the named student&rsquo;s wallet. It counts toward what the wallet can apply to their charges, and the reason travels on the statement.</div>
              </PBody>
            </Panel>
          ) : null}
          <Panel title="Look up a student's wallet" right="The whole transaction history — credits, top-ups, what was applied, reversals and refunds">
            <PBody>
              <div style={{ display: "flex", gap: 8, alignItems: "flex-end", flexWrap: "wrap" }}>
                <Field id="lk-num" label="Matriculation or admission number"><input id="lk-num" className="ctl tnum" value={lookup} onChange={(e) => setLookup(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void lookUp(lookup); }} placeholder="MOAUM/CSC/26/0001" /></Field>
                <Btn kind="primary" disabled={busy || !lookup.trim()} onClick={() => void lookUp(lookup)}>Show the history</Btn>
                {ledger ? <Btn kind="ghost" onClick={() => { setLedger(null); setLookup(""); }}>Clear</Btn> : null}
              </div>
              {ledger ? (
                <div style={{ marginTop: 12 }}>
                  <div style={{ display: "flex", gap: 16, flexWrap: "wrap", alignItems: "baseline", marginBottom: 8 }}>
                    <b>{ledger.student.name}</b>
                    <span className="tnum sub2">{ledger.student.number}</span>
                    <Pil kind="grey">{ledger.student.status}</Pil>
                    <span className="sub2">Wallet balance <b className="tnum">{money(Number(ledger.balance))}</b></span>
                    <span className="sub2">Outstanding for {ledger.session} <b className="tnum" style={{ color: Number(ledger.position.balance) ? "var(--red-ink)" : undefined }}>{money(Number(ledger.position.balance))}</b></span>
                  </div>
                  {ledger.statement.length ? (
                    <DTable cols={["Date|mid", "Entry", "Reference|mid", "In|num", "Out|num", "Balance|num"]} rows={ledger.statement.map((e) => [
                      <span className="sub2 tnum" key="d">{day(e.at)}</span>,
                      <Two key="e" a={<Pil kind={LKIND[e.kind]?.[1] ?? "grey"}>{LKIND[e.kind]?.[0] ?? e.kind}</Pil>} b={e.note ?? ""} />,
                      <span className="tnum sub2" key="r">{e.reference ?? "—"}</span>,
                      e.kind === "CREDIT" || e.kind === "TOPUP" ? <span className="tnum" key="i" style={{ color: "var(--green-ink)", fontWeight: 600 }}>{money(Number(e.amount))}</span> : <span className="sub2" key="i">—</span>,
                      e.kind === "CREDIT" || e.kind === "TOPUP" ? <span className="sub2" key="o">—</span> : <span className="tnum" key="o">{money(Number(e.amount))}</span>,
                      <b className="tnum" key="b">{money(Number(e.balance))}</b>,
                    ])} />
                  ) : <div className="sub2">No movement on this student&rsquo;s wallet yet.</div>}
                </div>
              ) : null}
            </PBody>
          </Panel>
          <Note kind="info" title="The reconciliation runs against the register, not against a spreadsheet">A number that is not on the register is refused rather than created — which is why an unmatched row is the Registry&rsquo;s to answer, not this office&rsquo;s to force.</Note>
        </>
      ) : tab === "match" ? (
        <>
          {d.unmatched.length ? (
            <Note kind="bad" title={`${d.unmatched.length} remittance${d.unmatched.length === 1 ? " is" : "s are"} held in suspense`}>
              Each row is money the Fund has paid and the University is holding. None of it may be credited on a guess: a wallet credited to the wrong student is money the Fund will later reclaim from someone who never received it. {d.unmatched.filter((r) => r.owner === "Registry").length} are the Registry&rsquo;s to resolve, {d.unmatched.filter((r) => r.owner === "Bursary").length} this office&rsquo;s.
            </Note>
          ) : <Note kind="ok" title="Suspense is empty">Every row of every remittance for {d.session} is on a named wallet or reversed to the Fund.</Note>}
          <Panel title="Unmatched remittances" right="Suspense is owned, not parked">
            {d.unmatched.length ? (
              <DTable cols={["Matriculation number|mid", "Name on the remittance", "Amount|num", "Why it failed", "Owner|mid", "What resolves it|num"]} rows={d.unmatched.map((r) => [
                <span className="tnum" key="m">{r.matric_no}</span>, <Two key="n" a={r.name_on_remit ?? "—"} b={r.batch_ref} />, <span className="tnum" key="a">{money(Number(r.amount))}</span>,
                <span key="w">{r.why}{r.student_name ? <div className="sub2">{r.student_name} · {r.student_status}</div> : null}</span>,
                <Pil kind="grey" key="o">{r.owner ?? "—"}</Pil>,
                <span key="x" style={{ display: "flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
                  {registry ? <><input className="ctl tnum" style={{ width: 150 }} placeholder="Number on the register" value={fix[r.id]?.number ?? ""} onChange={(e) => setFix({ ...fix, [r.id]: { number: e.target.value, note: fix[r.id]?.note ?? "" } })} /><input className="ctl" style={{ width: 170 }} placeholder="Evidence, one line" value={fix[r.id]?.note ?? ""} onChange={(e) => setFix({ ...fix, [r.id]: { number: fix[r.id]?.number ?? "", note: e.target.value } })} /><Btn kind="go" disabled={busy || !fix[r.id]?.number || !fix[r.id]?.note} onClick={async () => { if (await send(`/api/bff/api/v1/nelfund/rows/${r.id}/match`, { number: fix[r.id].number, note: fix[r.id].note }, `Remittance row ${r.matric_no} matched by hand`)) setSaid("Matched and credited"); }}>Credit</Btn></> : null}
                  {bursary ? <Btn kind="ghost" disabled={busy} onClick={async () => { const why = window.prompt("Why is it reversed to the Fund? It goes on the record."); if (why && await send(`/api/bff/api/v1/nelfund/rows/${r.id}/reverse`, { why }, `Remittance row ${r.matric_no} reversed to the Fund`)) setSaid("Reversed to the Fund"); }}>Reverse</Btn> : null}
                </span>,
              ])} texts={d.unmatched.map((r) => `${r.matric_no} ${r.name_on_remit ?? ""} ${r.why ?? ""}`)} />
            ) : null}
          </Panel>
          <Note kind="info" title="Suspense is owned, not parked">Every row carries an office. A suspense account nobody owns is how money sits for a session and a student carries a debt they were never told about.</Note>
        </>
      ) : (
        <>
          <Note kind="info" title="The Fund decides, the University records, and the student must be able to see which">
            Nothing on this screen is the University&rsquo;s decision. What is the University&rsquo;s responsibility is that a student knows where they stand <b>before</b> registration rather than at it — and that the ones refused for a reason they can fix are told which field to fix, by name.
          </Note>
          <Tiles items={[
            ["Applied", s.applied.toLocaleString(), null, `${d.session} session`],
            ["Approved", s.approved.toLocaleString(), "var(--green-ink)", `${money(Number(t.received))} received`],
            ["Not approved", s.not_approved.toLocaleString(), s.not_approved ? "var(--red-ink)" : null, "Each told, by name"],
            ["Still with the Fund", s.pending.toLocaleString(), null, "No decision yet — and told that too"],
          ]} />
          {s.correctable ? <Note kind="bad" title={`${s.correctable} of the ${s.not_approved} refusals can be fixed by the student`}>A refusal for a wrong institution code or a name that does not match a BVN is a typing error, and the Fund reissues on correction. Each student concerned sees the field to fix on their wallet screen.</Note> : null}
          <Panel title={`Why the ${s.not_approved} were refused`} right="And which of them is the University's to help with">
            {d.refusals.length ? (
              <DTable cols={["Reason", "Students|mid", "Correctable|num"]} rows={d.refusals.map((r) => [<strong key="r">{r.reason}</strong>, <b className="tnum" key="n">{r.students}</b>, r.correctable ? <Pil kind="ok" key="c">Yes</Pil> : <Pil kind="info" key="c">No</Pil>])} />
            ) : <PBody><div className="sub2">No refusal on the Fund&rsquo;s list for {d.session}.</div></PBody>}
          </Panel>
          {bursary ? (
            <Panel title="Load the Fund's list" right="All applicants, with the decision and the reason">
              <PBody>
                <Field id="ns-rows" label="The rows" hint="Paste: number (matriculation or JAMB), name, decision (approved / not approved / pending), reason — one per line, with or without a header."><textarea id="ns-rows" className="ctl tnum" rows={6} value={statusText} onChange={(e) => setStatusText(e.target.value)} /></Field>
                <div><Btn kind="primary" disabled={busy || !statusText.trim()} onClick={async () => { const rows = parseRows(statusText, ["number", "name", "state", "reason"]); const j = await send("/api/bff/api/v1/nelfund/status", { session: d.session, rows }, `NELFUND decision list loaded for ${d.session}`); if (j) { setSaid(`${j.loaded} loaded: ${j.approved} approved, ${j.not_approved} not approved, ${j.pending} pending`); setStatusText(""); } }}>Load the list</Btn> <Link href="/finance/nelfund?tab=batches" className="btn btn--ghost btn--sm">Remittances</Link></div>
              </PBody>
            </Panel>
          ) : null}
        </>
      )}
    </>
  );
}
