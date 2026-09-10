"use client";

/** tTransfers — inter-departmental transfer: the SAIC considers each case, Senate approves
 *  the recommended ones, the candidate pays the non-refundable fee, and the registry effects
 *  the change. The two memos (recommended list, withdrawal) print from this same queue. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface TransferRow {
  id: string; student_id: string; name: string; matric_no: string | null;
  from_programme: string; from_level: number; to_programme: string; mode_of_entry: string;
  utme_score: number | null; cgpa: number | null; reason: string; state: string;
  recommended_level: number | null; committee_note: string | null; senate_note: string | null; withdrawn_why: string | null;
  applied_at: string; reviewed_at: string | null; senate_at: string | null; effected_at: string | null;
  fee_reference: string | null; fee_confirmed_at: string | null; session: string;
}
export interface Programme { code: string; name: string; faculty: string }

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  APPLIED: ["warn", "Awaiting the committee"],
  RECOMMENDED: ["info", "Recommended · at Senate"],
  NOT_RECOMMENDED: ["grey", "Not recommended"],
  APPROVED: ["info", "Approved by Senate"],
  DECLINED: ["grey", "Declined by Senate"],
  EFFECTED: ["ok", "Effected on the register"],
  WITHDRAWN: ["grey", "Withdrawn"],
};

export function Transfers({ rows, programmes, actingOffice }: { rows: TransferRow[]; programmes: Programme[]; actingOffice: string | null }) {
  const router = useRouter();
  const o = actingOffice ?? "";
  const maySaic = ["academic", "registrar", "dregistrar", "dvc", "super"].includes(o);
  const maySenate = ["registrar", "dregistrar", "vc", "dvc", "super"].includes(o);
  const mayOfficer = ["academic", "registrar", "dregistrar", "super"].includes(o);
  const mayEffect = ["academic", "registrar", "dregistrar", "ict", "super"].includes(o);

  const [tab, setTab] = useState("APPLIED");
  const [rec, setRec] = useState({ number: "", programme: "", reason: "", utme: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const count = (s: string) => rows.filter((r) => r.state === s).length;
  const shown = tab === "ALL" ? rows : rows.filter((r) => r.state === tab);

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/transfers${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return null; }
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="One application at a time, considered by the committee and approved by Senate">
        A matriculated student applies to move to another department. The Special Admissions and Admission Irregularities Committee recommends the case for a level, or does not; Senate approves the recommended cases; the candidate pays the non-refundable {money(10000)} processing fee and prints an approval letter; the registry then effects the change — the programme and level move, the matriculation number does not.
      </Note>
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["Awaiting the committee", String(count("APPLIED")), count("APPLIED") ? "var(--red-ink)" : null, "To recommend or not"],
        ["At Senate", String(count("RECOMMENDED")), count("RECOMMENDED") ? "var(--chrome)" : null, "Recommended cases"],
        ["Approved, to effect", String(count("APPROVED")), count("APPROVED") ? "var(--chrome)" : null, "Awaiting fee / registry"],
        ["Effected", String(count("EFFECTED")), "var(--green-ink)", "Moved on the register"],
      ]} />

      <div className="card"><div className="card__body">
        <div className="role-tabs" role="tablist">
          {[["APPLIED", "Awaiting committee"], ["RECOMMENDED", "At Senate"], ["APPROVED", "Approved"], ["EFFECTED", "Effected"], ["NOT_RECOMMENDED", "Not recommended"], ["ALL", "All"]].map(([k, l]) => (
            <button key={k} type="button" role="tab" aria-selected={tab === k ? "true" : "false"} onClick={() => setTab(k)}>{l}{k !== "ALL" && count(k) ? ` (${count(k)})` : ""}</button>
          ))}
        </div>
      </div></div>

      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", margin: "0 0 10px" }}>
        <Link href="/transfers/memo?type=recommended" className="btn btn--ghost btn--sm">Recommended-list memo</Link>
        <Link href="/transfers/memo?type=withdrawn" className="btn btn--ghost btn--sm">Withdrawal memo</Link>
      </div>

      <Panel title="Transfer applications" right={`${shown.length} shown`}>
        {shown.length ? (
          <DTable cols={["Student", "From → To", "Entry · UTME · CGPA|mid", "Reason", "Stage", "Action|num"]} rows={shown.map((r) => [
            <Two key="s" a={r.name} b={r.matric_no ?? ""} />,
            <span key="ft"><span className="sub2">{r.from_programme} · {r.from_level}L</span><div><b>→ {r.to_programme}</b>{r.recommended_level ? <span className="sub2"> · {r.recommended_level}L</span> : null}</div></span>,
            <span className="sub2 tnum" key="e">{r.mode_of_entry}{r.utme_score != null ? ` · ${r.utme_score}` : ""}{r.cgpa != null ? ` · ${Number(r.cgpa).toFixed(2)}` : ""}</span>,
            <span className="sub2" key="r">{r.reason}{r.committee_note ? <div className="sub2">Committee: {r.committee_note}</div> : null}{r.withdrawn_why ? <div className="sub2">Withdrawn: {r.withdrawn_why}</div> : null}</span>,
            <span key="st"><Pil kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>{r.fee_reference ? <div className="sub2 tnum">{r.fee_reference}{r.fee_confirmed_at ? " · paid" : " · unpaid"}</div> : null}</span>,
            <span key="ac" style={{ display: "inline-flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
              {maySaic && r.state === "APPLIED" ? <Btn kind="go" disabled={busy} onClick={() => { const lv = window.prompt("Recommend for which level? (100, 200, 300, 400, 500, 600)"); if (!lv) return; const note = window.prompt("Committee's note (optional)") ?? ""; void send(`/${r.id}/review`, { recommend: true, level: Number(lv), note }, `Recommend transfer for ${r.name}`).then((j) => { if (j) setSaid(`${r.name} recommended`); }); }}>Recommend</Btn> : null}
              {maySaic && r.state === "APPLIED" ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Why is it not recommended? The reason is recorded."); if (w && w.trim()) void send(`/${r.id}/review`, { recommend: false, note: w.trim() }, `Do not recommend transfer for ${r.name}`).then((j) => { if (j) setSaid(`${r.name} not recommended`); }); }}>Not recommend</Btn> : null}
              {maySenate && r.state === "RECOMMENDED" ? <Btn kind="go" disabled={busy} onClick={() => { if (window.confirm(`Senate approves ${r.name}'s transfer to ${r.to_programme}?`)) void send(`/${r.id}/senate`, { approve: true, note: null }, `Senate approves transfer for ${r.name}`).then((j) => { if (j) setSaid(`${r.name} approved`); }); }}>Approve</Btn> : null}
              {maySenate && r.state === "RECOMMENDED" ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Senate's reason for declining (optional)") ?? ""; if (window.confirm("Decline this case?")) void send(`/${r.id}/senate`, { approve: false, note: w }, `Senate declines transfer for ${r.name}`); }}>Decline</Btn> : null}
              {mayOfficer && (r.state === "RECOMMENDED" || r.state === "APPROVED") ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Withdraw this case — why? (recorded on the withdrawal memo)"); if (w && w.trim()) void send(`/${r.id}/withdraw`, { why: w.trim() }, `Withdraw transfer for ${r.name}`).then((j) => { if (j) setSaid(`${r.name} withdrawn`); }); }}>Withdraw</Btn> : null}
              {mayEffect && r.state === "APPROVED" ? <Btn kind="primary" disabled={busy || !r.fee_confirmed_at} onClick={() => { if (window.confirm(`Effect the transfer? ${r.name} moves to ${r.to_programme} at ${r.recommended_level}L.`)) void send(`/${r.id}/effect`, {}, `Effect transfer for ${r.name}`).then((j) => { if (j) setSaid(`${r.name} moved to ${r.to_programme}`); }); }}>{r.fee_confirmed_at ? "Effect" : "Awaiting fee"}</Btn> : null}
            </span>,
          ])} texts={shown.map((r) => `${r.name} ${r.matric_no ?? ""} ${r.from_programme} ${r.to_programme} ${r.state}`)} />
        ) : <PBody><div className="sub2">No application in this stage.</div></PBody>}
      </Panel>

      {mayOfficer ? (
        <Panel title="Record an application" right="For a case brought to the office on paper">
          <PBody>
            <div className="grid grid--2">
              <Field id="tr-num" label="Student number"><input id="tr-num" className="ctl tnum" value={rec.number} onChange={(e) => setRec({ ...rec, number: e.target.value })} placeholder="MOAUM/CSC/23/0001" /></Field>
              <Field id="tr-prog" label="Course applied for"><select id="tr-prog" className="ctl" value={rec.programme} onChange={(e) => setRec({ ...rec, programme: e.target.value })}><option value="">Select a programme…</option>{programmes.map((p) => <option key={p.code} value={p.code}>{p.name} — {p.faculty}</option>)}</select></Field>
            </div>
            <div className="grid grid--2">
              <Field id="tr-reason" label="Reason for seeking transfer"><input id="tr-reason" className="ctl" value={rec.reason} onChange={(e) => setRec({ ...rec, reason: e.target.value })} /></Field>
              <Field id="tr-utme" label="UTME score" hint="Optional"><input id="tr-utme" className="ctl tnum" inputMode="numeric" value={rec.utme} onChange={(e) => setRec({ ...rec, utme: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            </div>
            <div><Btn kind="primary" disabled={busy || !rec.number.trim() || !rec.programme || !rec.reason.trim()} onClick={async () => { const j = await send("", { number: rec.number.trim(), toProgramme: rec.programme, reason: rec.reason.trim(), utme: rec.utme ? Number(rec.utme) : null }, `Record transfer application for ${rec.number.trim()}`); if (j) { setSaid("Application recorded — it goes to the committee"); setRec({ number: "", programme: "", reason: "", utme: "" }); } }}>Record the application</Btn></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
