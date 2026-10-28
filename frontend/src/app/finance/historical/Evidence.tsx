"use client";

/**
 * V683: payment evidence graduates submit for past semesters their history shows as unpaid — a receipt, a bank teller, an old-portal
 * receipt. The Students Account Officer or the Bursar checks it against the payments on record: the payment its number names (anyone's),
 * the graduate's payments of the session, their archived ones, or one found by another number. Verified, it is linked to that payment and
 * never counts by itself: the desk says where the payment stands (counted, archived, another student's, another purpose or session) and
 * which desk puts it right, each with its own approval. More information or a rejection says why; the graduate is told. Every rule is
 * the database's.
 */
import { useEffect, useState } from "react";
import Link from "next/link";
import { Btn, Note, Pil, Spinner } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import {
  can, CHANNEL_WORDS, EVIDENCE_WORDS, naira, PAYMENT_STATE_DESK, PAYMENT_STATE_WORDS, PERIOD_WORDS, semesterWords, WHY_WORDS,
  type Candidate, type Desk, type Evidence, type EvidenceState, type PaymentState, type Period,
} from "@/lib/historical-fees";
import { HF, hfCall } from "./hf-call";

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const onDay = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "Africa/Lagos" }) : "—");

interface Row extends Omit<Evidence, "files"> {
  student_id: string; surname: string; other_names: string; matric_no: string | null; student_status: string; programme: string; files: number | string;
  payment: string | null; payment_state: PaymentState | null; assessed?: number | string | null; paid?: number | string; outstanding?: number | string | null;
  period_status?: string;
}
interface One extends Omit<Row, "files"> {
  jamb_reg_no: string | null; decided_office: string | null; decided_by_name: string | null; payment_id: string | null; period: Period | null;
  files: { id: string; filename: string; content_type: string; size_bytes: number; added_at: string; added_office: string | null }[];
  events: { action: string; at: string; office: string | null; note: string | null; by_name: string | null }[];
  candidates: Candidate[]; held: { payref: string; original_identifier: string | null; purpose: string | null; session: string | null; amount: number | string | null; status: string }[];
  decided?: { state: string; paymentState: PaymentState | null };
}

const ACTION_WORDS: Record<string, string> = {
  SUBMITTED: "Submitted", FILE_ADDED: "File added", RESUBMITTED: "Sent again", WITHDRAWN: "Withdrawn", MORE_INFORMATION_REQUIRED: "More information asked",
  VERIFIED: "Verified", REJECTED: "Rejected",
};

/** where a payment stands against the graduate's session, and the desk that puts it right */
function PaymentStanding({ state }: { state: PaymentState | null | undefined }) {
  if (!state) return null;
  const [word, tone, what] = PAYMENT_STATE_WORDS[state];
  const desk = PAYMENT_STATE_DESK[state];
  return (
    <span><Pil kind={tone}>{word}</Pil><span className="blk sub2">{what}{desk ? <> <Link className="lnk" href={desk[1]}>{desk[0]}</Link></> : null}</span></span>
  );
}

/** one evidence: what the graduate said, the files, the period, the candidates, and the decision */
export function EvidenceView({ id, desk, onClose, onChanged, onOpenStudent }: {
  id: string; desk: Desk; onClose: () => void; onChanged: () => void; onOpenStudent?: (student: string) => void;
}) {
  const [e, setE] = useState<One | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [note, setNote] = useState("");
  const [ref, setRef] = useState("");
  const [found, setFound] = useState<Candidate[] | null>(null);
  useEffect(() => {
    let alive = true;
    void hfCall<One>(`/evidence/${id}`).then((r) => { if (!alive) return; if (r.ok) setE(r.data); else setProblem(r.problem); });
    return () => { alive = false; };
  }, [id]);
  if (!e) return <Modal title="Payment evidence" onClose={onClose}>{problem ? <ProblemNotice problem={problem} /> : <div className="row row--tight sub2"><Spinner /> Reading…</div>}</Modal>;
  const deciding = e.state === "SUBMITTED" && can(desk, "REVIEW_PAYMENT_EVIDENCE");

  async function decide(decision: "VERIFY" | "MORE_INFORMATION" | "REJECT", payment?: Candidate) {
    setProblem(null);
    const r = await hfCall<One>(`/evidence/${id}/decide`, { method: "POST", body: { decision, note: note.trim() || null, payment: payment?.payment_id ?? null },
      reason: decision === "VERIFY" ? `${e!.reference} verified against payment ${payment?.reference}` : decision === "MORE_INFORMATION" ? `More information asked for ${e!.reference}` : `${e!.reference} rejected` });
    if (!r.ok) { setProblem(r.problem); return; }
    const ps = r.data.decided?.paymentState;
    notify(decision === "VERIFY" ? `${e!.reference} verified${ps && ps !== "COUNTED" ? ` — ${PAYMENT_STATE_WORDS[ps][0].toLowerCase()}: put it right next` : ""}` : decision === "MORE_INFORMATION" ? "The graduate is asked for more" : `${e!.reference} rejected`);
    setNote("");
    setE(r.data);
    onChanged();
  }

  async function search() {
    const r = await hfCall<Candidate[]>(`/evidence/${id}/search?ref=${encodeURIComponent(ref.trim())}`);
    if (!r.ok) { setProblem(r.problem); return; }
    setFound(r.data);
  }

  const candidateRows = (list: Candidate[]) => list.map((c, i) => [
    <span key="n" className="tnum sub2">{i + 1}</span>,
    <span key="r"><strong className="tnum">{c.reference}</strong><span className="blk sub2">{WHY_WORDS[c.why] ?? c.why}</span></span>,
    <span key="w">{c.name ?? "—"}<span className="blk sub2 tnum">{c.matric_no ?? "—"}{c.student_id && c.student_id !== e.student_id ? " · another student" : ""}</span></span>,
    <span key="p" className="sub2">{c.purpose}<span className="blk">{c.session ?? "—"} · {c.channel ?? "—"} · {onDay(c.confirmed_at)}</span></span>,
    <span key="a" className="tnum">{naira(c.amount)}</span>,
    <PaymentStanding key="s" state={c.state} />,
    c.verified_for ? <span key="b" className="sub2">Backs {c.verified_for}</span>
      : deciding ? <Btn key="b" kind="primary" size="sm" busyLabel="Verifying…" onClick={() => decide("VERIFY", c)}>Verify against this</Btn> : <span key="b" />,
  ]);

  return (
    <Modal wide title={`${e.reference} · ${EVIDENCE_WORDS[e.state]?.[0] ?? e.state}`} sub={`${e.surname}, ${e.other_names} · ${e.matric_no ?? "—"} · ${e.programme}`} onClose={onClose}
      foot={<>
        {onOpenStudent ? <Btn kind="ghost" onClick={() => onOpenStudent(e.student_id)}>Open the graduate&rsquo;s account</Btn> : null}
        <span className="grow" />
        {deciding ? <Btn kind="urgent" disabled={note.trim().length < 10} busyLabel="Rejecting…" onClick={() => decide("REJECT")}>Reject</Btn> : null}
        {deciding ? <Btn kind="secondary" disabled={note.trim().length < 10} busyLabel="Asking…" onClick={() => decide("MORE_INFORMATION")}>Ask for more information</Btn> : null}
      </>}>
      <Note kind="info" title="Evidence never counts by itself">
        Verify it against the payment on record it shows. Only that payment counts, once it is the graduate&rsquo;s confirmed school fees of the session; a payment archived,
        on another student&rsquo;s record or under another purpose is put right on its own desk, with its own approval. Nothing is ever recorded as paid from a document alone.
      </Note>
      <div className="grid grid--4">
        <div className="kv"><span className="k">Semester</span><span className="v">{e.session} · {semesterWords(e.semester)}</span></div>
        <div className="kv"><span className="k">Amount the graduate paid</span><span className="v tnum">{naira(e.amount)}</span></div>
        <div className="kv"><span className="k">How, and when</span><span className="v">{CHANNEL_WORDS[e.channel] ?? e.channel}{e.paid_on ? ` · ${onDay(e.paid_on)}` : ""}</span></div>
        <div className="kv"><span className="k">Receipt, teller or transaction number</span><span className="v tnum">{e.payment_reference}</span></div>
        <div className="kv"><span className="k">Assessed</span><span className="v tnum">{e.period?.assessed == null ? "—" : naira(e.period.assessed)}</span></div>
        <div className="kv"><span className="k">Paid towards the semester</span><span className="v tnum">{naira(e.period?.paid)}</span></div>
        <div className="kv"><span className="k">Outstanding now</span><span className="v tnum">{e.period?.outstanding == null ? "—" : naira(e.period.outstanding)}</span></div>
        <div className="kv"><span className="k">The semester now</span><span className="v">{e.period ? <Pil kind={PERIOD_WORDS[e.period.status]?.[1] ?? "grey"}>{PERIOD_WORDS[e.period.status]?.[0] ?? e.period.status}</Pil> : "—"}</span></div>
      </div>
      {e.note ? <div className="mt-2"><span className="sub2">The graduate&rsquo;s note</span><div>{e.note}</div></div> : null}
      <div className="mt-2"><strong>Files</strong></div>
      {e.files.length ? (
        <ul className="m-0">{e.files.map((f) => (
          <li key={f.id}><a href={`${HF}/evidence/${id}/files/${f.id}`} target="_blank" rel="noreferrer">{f.filename}</a> <span className="sub2">· {Math.ceil(f.size_bytes / 1024)} KB · {when(f.added_at)}</span></li>
        ))}</ul>
      ) : <div className="sub2">No file attached.</div>}
      {e.state === "VERIFIED" ? (
        <Note kind={e.payment_state === "COUNTED" ? "ok" : "bad"} title={`Verified against payment ${e.payment ?? "—"} by ${e.decided_by_name ?? e.decided_office ?? "the Bursary"} · ${when(e.decided_at)}`}>
          <PaymentStanding state={e.payment_state} />{e.decision_note ? <span className="blk mt-1">{e.decision_note}</span> : null}
        </Note>
      ) : e.decided_at && e.state !== "SUBMITTED" ? (
        <Note kind={e.state === "REJECTED" ? "bad" : "info"} title={`${EVIDENCE_WORDS[e.state]?.[0]} · ${e.decided_by_name ?? e.decided_office ?? "the Bursary"} · ${when(e.decided_at)}`}>{e.decision_note ?? "No note."}</Note>
      ) : null}
      <div className="mt-2"><strong>Payments on record it may be</strong></div>
      {e.candidates.length ? (
        <DTable cols={["S/N|num", "Payment", "Whose", "Purpose and session", "Amount|num", "Where it stands", "|num"]} rows={candidateRows(e.candidates)} />
      ) : <div className="sub2">No payment on record carries the number on the evidence, and the graduate has none in the session.</div>}
      {e.held.length ? (
        <Note kind="info" title="Held old-portal records carry this number">
          {e.held.map((h) => `${h.payref} (${h.original_identifier ?? "no number"}, ${h.purpose ?? "—"}, ${h.session ?? "—"}, ${naira(h.amount)}) — ${h.status.toLowerCase()}`).join("; ")}.
          Match them to the graduate on <Link className="lnk" href="/finance/fee-history-reconciliation">School Fees History Reconciliation</Link> first; the payment then appears above.
        </Note>
      ) : null}
      {deciding ? (
        <>
          <div className="row row--end mt-2" style={{ flexWrap: "wrap" }}>
            <Field id="hpe-search" label="Find a payment by another number" hint="A payment reference or receipt number from a bank statement or the old portal">
              <input id="hpe-search" className="ctl tnum" value={ref} maxLength={80} onChange={(ev) => setRef(ev.target.value)} />
            </Field>
            <Btn kind="ghost" disabled={ref.trim().length < 4} busyLabel="Searching…" onClick={search}>Find</Btn>
          </div>
          {found ? (found.length ? <DTable cols={["S/N|num", "Payment", "Whose", "Purpose and session", "Amount|num", "Where it stands", "|num"]} rows={candidateRows(found)} />
            : <div className="sub2">No confirmed payment carries that number. If the graduate paid on the old portal and it never came over, record it on Old-Portal Payments first.</div>) : null}
          <Field id="hpe-note" label="Note" className="mt-2" hint="Required to ask for more or to reject (ten characters at least); the graduate reads it">
            <textarea id="hpe-note" className="ctl" rows={2} value={note} maxLength={2000} onChange={(ev) => setNote(ev.target.value)} />
          </Field>
        </>
      ) : null}
      <div className="mt-2"><strong>Timeline</strong></div>
      <ul className="m-0">{e.events.map((v, i) => (
        <li key={i} className="sub2">{when(v.at)} · {ACTION_WORDS[v.action] ?? v.action} · {v.by_name ?? v.office ?? "—"}{v.note ? ` — ${v.note}` : ""}</li>
      ))}</ul>
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}

/** the evidence by state — what awaits the Bursary first */
export function EvidenceQueue({ desk, tick, onChanged, onOpenStudent }: { desk: Desk; tick: number; onChanged: () => void; onOpenStudent?: (student: string) => void }) {
  const [state, setState] = useState<EvidenceState | "ALL">("SUBMITTED");
  const [q, setQ] = useState("");
  const [term, setTerm] = useState("");
  const [rows, setRows] = useState<{ total: number; rows: Row[] } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [viewing, setViewing] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    const qs = new URLSearchParams({ state });
    if (term) qs.set("q", term);
    void hfCall<{ total: number; rows: Row[] }>(`/evidence?${qs}`).then((r) => { if (!alive) return; if (r.ok) { setRows(r.data); setProblem(null); } else setProblem(r.problem); });
    return () => { alive = false; };
  }, [state, term, tick]);
  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div className="row row--end mb-1" style={{ flexWrap: "wrap" }}>
        <Field id="hpe-state" label="State">
          <select id="hpe-state" className="ctl" value={state} onChange={(ev) => setState(ev.target.value as EvidenceState | "ALL")}>
            {(Object.keys(EVIDENCE_WORDS) as EvidenceState[]).map((k) => <option key={k} value={k}>{EVIDENCE_WORDS[k][0]}</option>)}
            <option value="ALL">Every state</option>
          </select>
        </Field>
        <Field id="hpe-q" label="Search" hint="Reference, number on the evidence, name, matric or JAMB number">
          <input id="hpe-q" className="ctl" value={q} maxLength={80} onChange={(ev) => setQ(ev.target.value)} onKeyDown={(ev) => { if (ev.key === "Enter") setTerm(q.trim()); }} />
        </Field>
        <Btn kind="ghost" onClick={() => setTerm(q.trim())}>Search</Btn>
      </div>
      {!rows ? <div className="row row--tight sub2"><Spinner /> Reading…</div> : rows.rows.length ? (
        <DTable cols={["S/N|num", "Graduate", "Semester", "Amount|num", "Number on the evidence", "Files|num", "Outstanding now|num", "Sent", "State", "|num"]}
          rows={rows.rows.map((r, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>,
            <span key="s"><strong>{r.surname}, {r.other_names}</strong><span className="blk sub2 tnum">{r.reference} · {r.matric_no ?? "—"}</span></span>,
            <span key="pe" className="tnum">{r.session} · S{r.semester}</span>,
            <span key="a" className="tnum">{naira(r.amount)}</span>,
            <span key="r" className="tnum">{r.payment_reference}<span className="blk sub2">{CHANNEL_WORDS[r.channel] ?? r.channel}</span></span>,
            <span key="f" className="tnum">{Number(r.files ?? 0)}</span>,
            <span key="o" className="tnum">{r.outstanding == null ? "—" : naira(r.outstanding)}</span>,
            <span key="d" className="sub2">{when(r.submitted_at)}</span>,
            <span key="st"><Pil kind={EVIDENCE_WORDS[r.state]?.[1] ?? "grey"}>{EVIDENCE_WORDS[r.state]?.[0] ?? r.state}</Pil>
              {r.state === "VERIFIED" && r.payment_state ? <span className="blk sub2">{r.payment} · {PAYMENT_STATE_WORDS[r.payment_state][0]}</span> : null}</span>,
            <Btn key="v" kind="secondary" onClick={() => setViewing(r.id)}>{r.state === "SUBMITTED" && can(desk, "REVIEW_PAYMENT_EVIDENCE") ? "Review" : "View"}</Btn>,
          ])} />
      ) : <div className="sub2">No payment evidence {state === "SUBMITTED" ? "awaits the Bursary" : "in this state"}.</div>}
      {viewing ? <EvidenceView id={viewing} desk={desk} onClose={() => setViewing(null)} onChanged={() => { onChanged(); }}
        onOpenStudent={onOpenStudent ? (s) => { setViewing(null); onOpenStudent(s); } : undefined} /> : null}
    </>
  );
}
