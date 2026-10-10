"use client";

/**
 * The Bursary's JUPEB fees (V339): the application fee, the four school fees (Science or other, indigene or not), the first
 * semester's share, whether the whole fee may be paid at once, what activates a student, and the indigene state. The
 * applicant's programme (Science or Arts, V341) decides which school fee applies. A session takes its own rule or the default. A change reaches only fees charged after it — a
 * candidate's school fee is frozen when first charged. The JUPEB Office reads this page; only the Bursar saves it.
 */
import { useEffect, useState } from "react";
import Link from "next/link";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { jcall, naira, when } from "@/lib/jupeb";

interface Fees {
  session: string; currentSession: string; sessions: string[]; own: boolean;
  rule: { session: string; application_fee: number; checking_fee: number; acceptance_fee: number; first_percent: number; allow_full: boolean; activation: string; indigene_state: string; updated_at: string; updated_office: string | null; updated_by: string | null };
  schoolFees: { category: string; indigene: boolean; amount: number; own: boolean }[];
  faculties: { code: string; name: string; category: string; stated: boolean }[];
  /** V356: the latest earlier session with fees of its own, when this one has none */
  carryFrom?: string | null;
  history: { session: string; application_fee: number; checking_fee: number; acceptance_fee: number; first_percent: number; allow_full: boolean; activation: string; indigene_state: string; updated_at: string; updated_office: string | null }[];
}

const FEE_LABEL = (c: string, i: boolean) => `${c === "SCIENCE" ? "Science" : "Non-Science"} · ${i ? "indigene" : "non-indigene"}`;

export function JupebFees({ canWrite }: { canWrite: boolean }) {
  const [session, setSession] = useState("");
  const [d, setD] = useState<Fees | null>(null);
  const [f, setF] = useState<Record<string, string>>({});
  const [tick, setTick] = useState(0);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<Fees>(`/api/v1/jupeb/fees${session ? `?session=${encodeURIComponent(session)}` : ""}`).then((r) => {
      if (!live) return;
      if (!r.ok) { notifyProblem(r.problem); return; }
      setD(r.data);
      const x = r.data.rule;
      const sf = Object.fromEntries(r.data.schoolFees.map((s) => [`${s.category}_${s.indigene}`, String(Number(s.amount))]));
      setF({ applicationFee: String(Number(x.application_fee)), checkingFee: String(Number(x.checking_fee)), acceptanceFee: String(Number(x.acceptance_fee)), firstPercent: String(Number(x.first_percent)), allowFull: x.allow_full ? "yes" : "no", activation: x.activation, indigeneState: x.indigene_state, ...sf });
    });
    return () => { live = false; };
  }, [session, tick]);
  if (!d) return <Note kind="info" title="Loading the JUPEB fees…">One moment.</Note>;
  const target = session === "*" ? "*" : d.session;
  async function save() {
    setBusy(true);
    try {
      const schoolFees = [["OTHER", true], ["SCIENCE", true], ["OTHER", false], ["SCIENCE", false]].map(([c, i]) => ({ category: c, indigene: i, amount: Number(f[`${c}_${i}`] || 0) }));
      const r = await jcall("/api/v1/jupeb/fees", "PUT", {
        session: target, applicationFee: Number(f.applicationFee), checkingFee: Number(f.checkingFee), acceptanceFee: Number(f.acceptanceFee), firstPercent: Number(f.firstPercent), allowFull: f.allowFull === "yes", activation: f.activation, indigeneState: f.indigeneState, schoolFees,
      }, `JUPEB fees for ${target === "*" ? "every session" : target}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify("The JUPEB fees are saved. Fees already charged keep their amounts."); setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  async function carry(from: string) {
    if (!window.confirm(`Carry ${from}'s own fees and school fees, unchanged, into ${d!.session}? Change them after if they differ.`)) return;
    setBusy(true);
    try {
      const r = await jcall("/api/v1/jupeb/fees/carry", "POST", { from, to: d!.session }, `JUPEB fees of ${from} carried into ${d!.session}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${d!.session} now has its own fees, as ${from}'s.`); setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  const pct = Number(f.firstPercent || 0);
  const ro = !canWrite;
  return (
    <>
      <PageHead title="JUPEB fees" description="The Bursary's rule for the JUPEB programme. Only the Bursar changes it; a change reaches fees charged after it."
        actions={<span className="row">
          <select className="ctl" aria-label="Session" style={{ width: 210 }} value={session === "*" ? "*" : d.session} onChange={(e) => setSession(e.target.value)}>
            <option value="*">Default (every session without its own)</option>{d.sessions.map((s) => <option key={s} value={s}>{s}{s === d.currentSession ? " (current)" : ""}</option>)}
          </select>
          <Link href="/jupeb/payments">JUPEB payments</Link></span>} />
      <Note kind="info" title={session === "*" ? "The default rule" : d.own ? `${d.session} has its own rule` : `${d.session} takes the default rule`}>
        Last changed {when(d.rule.updated_at)}{d.rule.updated_by ? ` by ${d.rule.updated_by}` : ""}{d.rule.updated_office ? ` (${d.rule.updated_office})` : ""}.
        {session !== "*" && !d.own && canWrite ? " Saving here gives the session a rule of its own." : ""}
      </Note>
      {session !== "*" && !d.own && d.carryFrom ? (
        <Note kind="info" title={`${d.carryFrom} has fees of its own; ${d.session} has none`}
          action={canWrite ? <Btn kind="secondary" disabled={busy} onClick={() => void carry(d.carryFrom!)}>{`Carry ${d.carryFrom}'s fees`}</Btn> : undefined}>
          {`Until it has its own, ${d.session} takes the default below. Fees already charged keep their amounts.`}
        </Note>
      ) : null}
      <Panel title="Fees">
        <PBody>
          <div className="grid grid--3">
            <Field id="jf-app" label="Application fee (₦)"><input id="jf-app" className="ctl tnum" inputMode="decimal" value={f.applicationFee ?? ""} onChange={(e) => setF({ ...f, applicationFee: e.target.value })} disabled={ro} /></Field>
            <Field id="jf-chk" label="Admission status checking fee (₦)" hint="Paid once, while ICT has checking open"><input id="jf-chk" className="ctl tnum" inputMode="decimal" value={f.checkingFee ?? ""} onChange={(e) => setF({ ...f, checkingFee: e.target.value })} disabled={ro} /></Field>
            <Field id="jf-acc" label="Acceptance fee (₦)" hint="The acceptance letter follows its confirmation"><input id="jf-acc" className="ctl tnum" inputMode="decimal" value={f.acceptanceFee ?? ""} onChange={(e) => setF({ ...f, acceptanceFee: e.target.value })} disabled={ro} /></Field>
            <Field id="jf-pct" label="First semester share (%)" hint={`Second semester: ${Math.max(0, 100 - pct)}%`}><input id="jf-pct" className="ctl tnum" inputMode="decimal" value={f.firstPercent ?? ""} onChange={(e) => setF({ ...f, firstPercent: e.target.value })} disabled={ro} /></Field>
            <Field id="jf-full" label="Full payment at once"><select id="jf-full" className="ctl" value={f.allowFull} onChange={(e) => setF({ ...f, allowFull: e.target.value })} disabled={ro}><option value="yes">Allowed</option><option value="no">Not allowed</option></select></Field>
            <Field id="jf-act" label="A student is activated by"><select id="jf-act" className="ctl" value={f.activation} onChange={(e) => setF({ ...f, activation: e.target.value })} disabled={ro}><option value="FIRST_INSTALMENT">The first instalment</option><option value="FULL">The full fee</option></select></Field>
            <Field id="jf-ind" label="Indigene state" hint="Its indigenes pay the indigene fee"><input id="jf-ind" className="ctl" value={f.indigeneState ?? ""} onChange={(e) => setF({ ...f, indigeneState: e.target.value })} disabled={ro} /></Field>
          </div>
          <DTable noPrint pageSize={0} cols={["School fee", "Amount (₦)|num", "First semester|num", "Second semester|num", "Source"]} rows={d.schoolFees.map((s) => {
            const k = `${s.category}_${s.indigene}`;
            const total = Number(f[k] || 0);
            return [FEE_LABEL(s.category, s.indigene),
              <input key="a" className="ctl tnum" style={{ width: 140, textAlign: "right" }} aria-label={`${FEE_LABEL(s.category, s.indigene)} amount`} inputMode="decimal" value={f[k] ?? ""} onChange={(e) => setF({ ...f, [k]: e.target.value })} disabled={ro} />,
              naira(Math.round(total * pct) / 100), naira(total - Math.round(total * pct) / 100), s.own ? <Pil key="o" kind="info">This session</Pil> : <Pil key="o" kind="grey">Default</Pil>];
          })} />
          {canWrite ? <div className="row mt-3"><span className="grow" /><Btn kind="primary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : `Save for ${target === "*" ? "every session" : target}`}</Btn></div> : <p className="hint">Only the Bursar sets the JUPEB fees.</p>}
        </PBody>
      </Panel>
      <Panel title="Rules on record">
        <PBody><DTable pageSize={10} cols={["Session", "Application fee|num", "Checking fee|num", "Acceptance fee|num", "First share|num", "Full payment", "Activation", "Indigene state", "Changed"]}
          rows={d.history.map((h) => [h.session === "*" ? "Default" : h.session, naira(h.application_fee), naira(h.checking_fee), naira(h.acceptance_fee), `${Number(h.first_percent)}%`, h.allow_full ? "Allowed" : "No", h.activation === "FULL" ? "Full fee" : "First instalment", h.indigene_state, when(h.updated_at)])} /></PBody>
      </Panel>
    </>
  );
}
