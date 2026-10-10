"use client";
/** The Bursar's GST fee (V314): the fee per session, for everyone or for a level, an entry mode, a faculty or a programme — a new
 *  statement supersedes the old and never touches a payment already made — and the rule it enforces: whether it gates GST/EPS
 *  registration, whether it gates the whole registration, and that one payment covers EPS. The GST and EPS offices read it here
 *  through their dashboards; they do not change it.
 *  V366: the standing — who owes the fee because a GST or EPS course requires it (the programme's offering at their level, a
 *  carryover), who does not (never counted unpaid), and the payments no course requires, listed for the Bursary's review. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { GstGapsNote } from "@/components/gst/GstGapsNote";
import { ProblemNotice } from "@/components/ProblemNotice";
import { dayOf, naira, num, pct, reasonWord, type GstFeePage, type GstFeeRule } from "@/lib/gst";

interface ReviewRow { student_id: string; number: string; surname: string; other_names: string; programme: string; level: number; paid: number; reference: string | null; paid_at: string | null; gst_reason: string; eps_reason: string; payments?: string }
interface Decided { reference: string; decision: "KEEP" | "REFUND"; note: string; decided_at: string; decided_by: string | null; number: string; surname: string; other_names: string; paid: number; refund_reference: string | null; refund_state: string | null; refund_amount: number | null }
const REFUND_WORD: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = { PROPOSED: ["Proposed — awaiting a second officer", "warn"], APPROVED: ["Approved", "info"], PAID: ["Refunded", "ok"], REJECTED: ["Rejected — back in review", "bad"] };

const MODE: Record<string, string> = { UTME: "UTME", DIRECT_ENTRY: "Direct Entry", TRANSFER: "Transfer", JUPEB: "JUPEB", SANDWICH: "Sandwich" };
const scopeOf = (r: GstFeeRule) => [r.programme ? `Programme: ${r.programme}` : null, r.faculty ? `Faculty: ${r.faculty}` : null, r.level ? `${r.level} Level` : null, r.entry_mode ? MODE[r.entry_mode] ?? r.entry_mode : null].filter(Boolean).join(" · ") || "Every undergraduate";

export function GstFeePanel({ session, data, faculties, programmes, may }: {
  session: string; data: GstFeePage | null; faculties: { code: string; name: string }[]; programmes: { code: string; name: string; category?: string }[]; may: boolean;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [form, setForm] = useState({ amount: "", level: "", entryMode: "", facultyCode: "", programmeCode: "", effectiveFrom: "", note: "" });
  const [setting, setSetting] = useState({ gstEps: data?.setting.required_for_gst_eps ?? true, all: data?.setting.required_for_all ?? false, covers: data?.setting.covers_eps ?? true });
  const rules = data?.rules ?? [];
  const general = rules.find((r) => !r.level && !r.entry_mode && !r.faculty_code && !r.programme_code);
  const st = data?.standing ?? null;
  const [review, setReview] = useState<ReviewRow[] | null>(null);
  const [decided, setDecided] = useState<Decided[]>([]);
  const [decide, setDecide] = useState<{ row: ReviewRow; reference: string; amount: number; decision: "KEEP" | "REFUND"; note: string; payer: string; bank: string; accountName: string; last4: string } | null>(null);
  async function loadReview(force = false) {
    if (review && !force) return;
    const r = await fetch(`/api/bff/api/v1/gst/fee/review?session=${encodeURIComponent(session)}`, { cache: "no-store" }).catch(() => null);
    const j = r ? await r.json().catch(() => null) : null;
    if (!r || !r.ok) { notifyProblem((j as Problem) ?? { status: 503, title: "The list could not be read just now." }); return; }
    setReview((j?.rows ?? []) as ReviewRow[]);
    setDecided((j?.decided ?? []) as Decided[]);
  }
  /* V367: the Bursary's decision on a payment no course requires — kept with its reason, or a refund raised through the refunds desk */
  async function submitDecision() {
    if (!decide) return;
    if (!decide.note.trim()) { notifyProblem({ status: 422, title: "Give the reason for the decision." }); return; }
    setBusy("decide");
    try {
      const r = await fetch(`/api/bff/api/v1/gst/fee/review/${encodeURIComponent(decide.reference)}`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`GST payment ${decide.reference}: ${decide.decision.toLowerCase()} — ${decide.note}`) },
        body: JSON.stringify({ decision: decide.decision, note: decide.note, payer: decide.payer || null, bank: decide.bank || null, accountName: decide.accountName || null, accountLast4: decide.last4 || null }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify(decide.decision === "KEEP" ? `${decide.reference} kept` : `Refund ${j?.refund?.reference ?? ""} proposed for ${decide.reference}; a second officer approves it on Refunds & Credits`);
      setDecide(null);
      await loadReview(true);
      router.refresh();
    } finally { setBusy(null); }
  }
  const paymentsOf = (x: ReviewRow): { reference: string; amount: number; paid_at: string }[] => {
    try { return x.payments ? JSON.parse(x.payments) : []; } catch { return []; }
  };

  async function send(method: string, path: string, body: unknown, reason: string, done: string, key: string) {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/gst${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return; }
      notify(done); router.refresh();
    } finally { setBusy(null); }
  }
  const state = () => {
    const amount = Number(form.amount);
    if (!form.amount || Number.isNaN(amount) || amount < 0) { notifyProblem({ status: 422, title: "State the GST fee in naira, zero or more." }); return; }
    void send("PUT", "/fee", { session, amount, level: form.level ? Number(form.level) : null, entryMode: form.entryMode || null, facultyCode: form.facultyCode || null, programmeCode: form.programmeCode || null, effectiveFrom: form.effectiveFrom || null, note: form.note || null },
      `GST fee stated for ${session}: ${amount}`, `GST fee for ${session} stated: ${naira(amount)}`, "fee").then(() => setForm({ amount: "", level: "", entryMode: "", facultyCode: "", programmeCode: "", effectiveFrom: "", note: "" }));
  };

  return (
    <Panel title="GST fee · General Studies & Entrepreneurship" right={general ? `${naira(general.amount)} for ${session}${rules.length > 1 ? ` · ${rules.length} rules` : ""}` : `Not yet stated for ${session}`}>
      <PBody>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <div className="sub2">Paid once per session, owed only where a GST or EPS course requires it (never by level alone). One payment covers GST and EPS. Unpaid, the student&rsquo;s GST and EPS courses are locked at registration. Confirmed payments keep their amount.{data ? ` Paid so far for ${session}: ${num(data.paid.students)} students, ${naira(data.paid.amount)}.` : ""}</div>
        <div className="mt-2"><GstGapsNote gaps={data?.gaps} session={session} office={null} may={false} /></div>
        {st ? (
          <div className="mt-2">
            <Tiles items={[
              ["GST/EPS APPLICABLE", num(st.applicable), null, `${num(st.gst_required)} for GST · ${num(st.eps_required)} for EPS · ${num(st.carryover)} through a carryover`],
              ["PAID", num(st.paid), "var(--green-ink)", `${pct(st.paid, st.applicable)} of the applicable${Number(st.exempt) ? ` · ${num(st.exempt)} with no fee` : ""}`],
              ["OWING", num(st.owing), st.owing ? "var(--red-ink)" : null, `${naira(st.outstanding)} outstanding${Number(st.not_stated) ? ` · ${num(st.not_stated)} with no fee stated` : ""}`],
              ["NOT APPLICABLE", num(st.not_applicable), null, `of ${num(st.undergraduates)} undergraduates — owe nothing, never counted unpaid`],
              ["PAID, NOT REQUIRED", num(st.review), st.review ? "var(--red-ink)" : null, "For the Bursary's review: nothing is deleted or refunded automatically"],
            ]} />
            {Number(st.review) ? (
              <details className="mt-1" onToggle={(e) => { if ((e.target as HTMLDetailsElement).open) void loadReview(); }}>
                <summary className="sub2">The {num(st.review)} payment{Number(st.review) === 1 ? "" : "s"} no GST or EPS course requires this session</summary>
                {review === null ? <div className="sub2">Reading…</div> : review.length ? (
                  <DTable cols={["S/N|num", "Student", "Programme", "Level|num", "Paid|num", "Why not required", "Payment · decision"]} rows={review.map((x, i) => [
                    <span key="n" className="tnum sub2">{i + 1}</span>, <span key="s"><b>{x.surname}, {x.other_names}</b><div className="sub2 tnum">{x.number}</div></span>,
                    <span key="p">{x.programme}</span>, <span key="l" className="tnum">{x.level}</span>, <span key="a" className="tnum">{naira(x.paid)}</span>,
                    <span key="w" className="sub2">{reasonWord(x.gst_reason)}</span>,
                    <span key="d">{paymentsOf(x).map((p) => (
                      <span key={p.reference} className="blk"><span className="tnum sub2">{p.reference} · {naira(p.amount)}{p.paid_at ? ` · ${dayOf(p.paid_at)}` : ""}</span>
                        {may ? <span className="row row--inline row--tight">
                          <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => setDecide({ row: x, reference: p.reference, amount: Number(p.amount), decision: "KEEP", note: "", payer: `${x.surname}, ${x.other_names}`, bank: "", accountName: "", last4: "" })}>Keep</Btn>
                          <Btn kind="secondary" size="sm" disabled={busy !== null} onClick={() => setDecide({ row: x, reference: p.reference, amount: Number(p.amount), decision: "REFUND", note: "", payer: `${x.surname}, ${x.other_names}`, bank: "", accountName: "", last4: "" })}>Refund</Btn>
                        </span> : null}
                      </span>
                    ))}</span>,
                  ])} />
                ) : <div className="sub2">None awaiting a decision.</div>}
              </details>
            ) : null}
            {decided.length ? (
              <details className="mt-1">
                <summary className="sub2">Decided for {session} ({decided.length})</summary>
                <DTable cols={["Student", "Payment", "Decision|mid", "Reason", "Refund|mid", "Decided"]} rows={decided.map((x) => [
                  <span key="s"><b>{x.surname}, {x.other_names}</b><div className="sub2 tnum">{x.number}</div></span>,
                  <span key="p" className="tnum sub2">{x.reference} · {naira(x.paid)}</span>,
                  <Pil key="d" kind={x.decision === "KEEP" ? "grey" : "info"}>{x.decision === "KEEP" ? "Kept" : "Refund"}</Pil>,
                  <span key="n" className="sub2">{x.note}</span>,
                  x.refund_state ? <span key="r"><Pil kind={(REFUND_WORD[x.refund_state] ?? [x.refund_state, "grey"])[1]}>{(REFUND_WORD[x.refund_state] ?? [x.refund_state])[0]}</Pil><div className="sub2 tnum">{x.refund_reference} · {naira(x.refund_amount)}</div></span> : <span key="r" className="sub2">—</span>,
                  <span key="t" className="sub2">{x.decided_by ?? ""} · {dayOf(x.decided_at)}</span>,
                ])} />
              </details>
            ) : null}
            {decide ? (
              <Modal title={decide.decision === "KEEP" ? `Keep ${decide.reference}` : `Refund ${decide.reference}`} sub={`${decide.row.surname}, ${decide.row.other_names} · ${naira(decide.amount)}`} onClose={() => setDecide(null)}
                foot={<><Btn kind="ghost" onClick={() => setDecide(null)}>Back</Btn><Btn kind="primary" disabled={busy !== null} onClick={() => void submitDecision()}>{busy === "decide" ? "Saving…" : decide.decision === "KEEP" ? "Keep the payment" : "Propose the refund"}</Btn></>}>
                <div className="sub2 mb-1">{decide.decision === "KEEP"
                  ? "The payment stands as paid and leaves the review list. Say why — a programme change pending, a course the student owes next session."
                  : "A refund of what is left of this payment is proposed on Refunds & Credits against this payment. A second officer approves it there and it is paid there; until it is approved the payment still stands."}</div>
                <div className="grid grid--2">
                  <Field id="gr-note" label="Reason" required><input id="gr-note" className="ctl" value={decide.note} onChange={(e) => setDecide({ ...decide, note: e.target.value })} /></Field>
                  {decide.decision === "REFUND" ? <>
                    <Field id="gr-payer" label="Paid to"><input id="gr-payer" className="ctl" value={decide.payer} onChange={(e) => setDecide({ ...decide, payer: e.target.value })} /></Field>
                    <Field id="gr-bank" label="Bank"><input id="gr-bank" className="ctl" value={decide.bank} onChange={(e) => setDecide({ ...decide, bank: e.target.value })} /></Field>
                    <Field id="gr-acct" label="Account name"><input id="gr-acct" className="ctl" value={decide.accountName} onChange={(e) => setDecide({ ...decide, accountName: e.target.value })} /></Field>
                    <Field id="gr-last4" label="Account number, last four digits"><input id="gr-last4" className="ctl tnum" maxLength={4} value={decide.last4} onChange={(e) => setDecide({ ...decide, last4: e.target.value.replace(/\D/g, "") })} /></Field>
                  </> : null}
                </div>
              </Modal>
            ) : null}
          </div>
        ) : null}
        {!general && rules.length === 0 ? <Note kind="info" title={`No GST fee for ${session}`}>Until it is stated nothing is owed and nothing is locked.</Note> : null}
        {may ? (
          <>
            <div className="grid grid--4 mt-2">
              <Field id="gf-amount" label="GST fee (₦)" required><input id="gf-amount" type="number" min={0} step="0.01" className="ctl tnum" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} placeholder="10000" /></Field>
              <Field id="gf-level" label="Level" hint="Blank = every level"><select id="gf-level" className="ctl" value={form.level} onChange={(e) => setForm({ ...form, level: e.target.value })}><option value="">All levels</option>{[100, 200, 300, 400, 500, 600].map((l) => <option key={l} value={l}>{l} Level</option>)}</select></Field>
              <Field id="gf-mode" label="Entry mode" hint="Blank = all entrants"><select id="gf-mode" className="ctl" value={form.entryMode} onChange={(e) => setForm({ ...form, entryMode: e.target.value })}><option value="">All entrants</option>{Object.entries(MODE).map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select></Field>
              <Field id="gf-from" label="Effective from" hint="Blank = today"><input id="gf-from" type="date" className="ctl" value={form.effectiveFrom} onChange={(e) => setForm({ ...form, effectiveFrom: e.target.value })} /></Field>
              <Field id="gf-fac" label="Faculty" hint="Blank = every faculty"><select id="gf-fac" className="ctl" value={form.facultyCode} onChange={(e) => setForm({ ...form, facultyCode: e.target.value })}><option value="">All faculties</option>{faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}</select></Field>
              <Field id="gf-prog" label="Programme" hint="Blank = every programme"><select id="gf-prog" className="ctl" value={form.programmeCode} onChange={(e) => setForm({ ...form, programmeCode: e.target.value })}><option value="">All programmes</option>{programmes.filter((p) => !p.category || p.category === "UNDER GRADUATE").map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}</select></Field>
              <Field id="gf-note" label="Note"><input id="gf-note" className="ctl" value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} placeholder="Council approval, memo reference…" /></Field>
              <div className="row row--inline row--tight" style={{ alignItems: "flex-end" }}><Btn kind="primary" disabled={busy !== null} onClick={state}>{busy === "fee" ? "Stating…" : `State the GST fee for ${session}`}</Btn></div>
            </div>
            <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }}>
              <label className="row row--inline row--tight"><input type="checkbox" checked={setting.gstEps} onChange={(e) => setSetting({ ...setting, gstEps: e.target.checked })} /> GST payment required to register GST/EPS courses</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={setting.all} onChange={(e) => setSetting({ ...setting, all: e.target.checked })} /> GST payment required for the whole course registration</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={setting.covers} onChange={(e) => setSetting({ ...setting, covers: e.target.checked })} /> GST payment covers EPS</label>
              <Btn kind="secondary" size="sm" disabled={busy !== null} onClick={() => void send("PUT", `/setting?session=${encodeURIComponent(session)}`, { requiredForGstEps: setting.gstEps, requiredForAll: setting.all, coversEps: setting.covers }, "GST rule changed", "GST rule saved", "setting")}>{busy === "setting" ? "Saving…" : "Save the rule"}</Btn>
            </div>
          </>
        ) : <Note kind="info" title="Read only">The Bursar states the GST fee; the GST and EPS offices read it on their dashboards.</Note>}
      </PBody>
      {rules.length ? <DTable cols={["S/N|num", "Applies to", "Fee|num", "Effective|mid", "Stated by", "Note", may ? "Withdraw|mid" : "|mid"]} rows={rules.map((r, i) => [
        <span key="n" className="tnum sub2">{i + 1}</span>, <span key="s">{scopeOf(r)}</span>, <b key="a" className="tnum">{naira(r.amount)}</b>, <span key="e" className="tnum sub2">{dayOf(r.effective_from)}</span>,
        <span key="b" className="sub2">{r.stated_by ?? ""}{r.stated_office ? ` (${r.stated_office})` : ""} · {dayOf(r.stated_at)}</span>, <span key="o" className="sub2">{r.note ?? ""}</span>,
        may ? <Btn key="w" kind="ghost" size="sm" disabled={busy !== null} onClick={() => { if (window.confirm(`Withdraw this GST fee rule (${scopeOf(r)}, ${naira(r.amount)})? Students it priced fall back to the next rule, or to no fee.`)) void send("POST", `/fee/${r.id}/end?session=${encodeURIComponent(session)}`, {}, `GST fee rule withdrawn: ${scopeOf(r)}`, "GST fee rule withdrawn", r.id); }}>Withdraw</Btn> : <span key="w" />,
      ])} /> : null}
      {data?.history.length ? (
        <PBody>
          <details><summary className="sub2">Superseded rules for {session} ({data.history.length}) — payments made under them keep their amounts</summary>
            <DTable cols={["S/N|num", "Applied to", "Fee|num", "Stated|mid", "Superseded|mid"]} rows={data.history.map((r, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>, <span key="s">{scopeOf(r)}</span>, <span key="a" className="tnum">{naira(r.amount)}</span>, <span key="d" className="tnum sub2">{dayOf(r.stated_at)}</span>, <Pil key="x" kind="grey">{dayOf(r.superseded_at)}</Pil>,
            ])} />
          </details>
        </PBody>
      ) : null}
    </Panel>
  );
}
