"use client";

/**
 * V647: school-fees history, JAMB number to matriculation number. An old-portal payment named by a JAMB registration number (paid
 * before matriculation) is the student's: the import resolves it, and one whose number names no student yet, or several, is held
 * here. The held payments are read as their numbers resolve now; the Students Account Officer or a Bursary officer initiates a
 * PAY-RECON batch of the matched (Match JAMB payments, or those ticked), and a Bursar officer who did not initiate it approves — each
 * payment recorded once, its number kept — or rejects it. Nothing is reconciled in the browser: every rule is the database's.
 */
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tabs, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import {
  CATEGORY_HELP, CATEGORY_WORDS, IDENTIFIER_WORDS, PURPOSE_WORDS, STATE_WORDS, batchPath,
  type Batch, type BatchPayment, type Category, type Figures, type HeldPage,
} from "@/lib/fee-history-recon";

const BASE = "/api/bff/api/v1/finance/fee-history-reconciliation";

async function call<T>(method: string, path: string, body: unknown, reason: string): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const r = await fetch(`${BASE}${path}`, {
    method, cache: "no-store",
    headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
    body: method === "GET" ? undefined : JSON.stringify(body ?? {}),
  });
  const j = await r.json().catch(() => null);
  return r.ok ? { ok: true, data: j as T } : { ok: false, problem: (j && typeof j === "object" && "status" in j ? j : { status: r.status, title: r.statusText }) as Problem };
}

const naira = (v: unknown) => (v == null || v === "" ? "—" : `₦${Number(v).toLocaleString("en-NG", { maximumFractionDigits: 2 })}`);
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export function FeeHistoryRecon({ figures, batches, office, me }: { figures: Figures; batches: Batch[]; office: string | null; me: string | null }) {
  const router = useRouter();
  const [tab, setTab] = useState<"held" | "batches">("held");
  const [f, setF] = useState({ session: "", category: "MATCHED", purpose: "SCHOOL_FEES", q: "" });
  const [pageNo, setPageNo] = useState(0);
  const [held, setHeld] = useState<HeldPage | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [chosen, setChosen] = useState<Set<string>>(new Set());
  const [matching, setMatching] = useState<null | { all: boolean }>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState<Batch | null>(null);
  const mayInitiate = office === "studentaccounts" || office === "bursar";
  const mayDecide = office === "bursar";

  const qs = useMemo(() => {
    const p = new URLSearchParams();
    Object.entries(f).forEach(([k, v]) => { if (v.trim()) p.set(k, v.trim()); });
    p.set("page", String(pageNo));
    p.set("size", "50");
    return p.toString();
  }, [f, pageNo]);

  useEffect(() => {
    let live = true;
    const t = setTimeout(() => {
      void call<HeldPage>("GET", `/held?${qs}`, null, "Held payments read").then((r) => {
        if (!live) return;
        if (r.ok) { setHeld(r.data); setProblem(null); } else setProblem(r.problem);
      });
    }, 250);
    return () => { live = false; clearTimeout(t); };
  }, [qs]);

  const matchedHere = held?.byCategory.find((c) => c.category === "MATCHED");
  const cat = (k: Category) => figures.byCategory[k] ?? 0;

  async function initiate() {
    if (!matching) return;
    setBusy(true);
    try {
      const body = matching.all
        ? { allMatched: true, session: f.session || null, purpose: f.purpose || null, q: f.q || null, reason: reason.trim() }
        : { heldIds: Array.from(chosen), reason: reason.trim() };
      const r = await call<Batch>("POST", "/batches", body, "School-fees history reconciliation initiated");
      if (r.ok) {
        notify(`${r.data.ref} · ${r.data.matched} payment${r.data.matched === 1 ? "" : "s"} sent to the Bursar for approval`);
        setMatching(null); setReason(""); setChosen(new Set()); setTab("batches"); router.refresh();
      } else notifyProblem(r.problem);
    } finally { setBusy(false); }
  }

  async function openBatch(ref: string) {
    const r = await call<Batch>("GET", `/batches/${batchPath(ref)}`, null, "Reconciliation read");
    if (r.ok) setOpen(r.data); else notifyProblem(r.problem);
  }

  return (
    <>
      <Note kind="info" title="A school-fees payment made before matriculation is the student's">
        The old portal named a payer by the number they had: a JAMB registration number before matriculation. The old-fees upload now finds the student by
        that number and records the payment under them, the number kept beside it. A payment whose number names no student yet, or several, is held here
        until it can be reconciled. A name never matches a payment.
      </Note>
      <Tiles cls="grid--4" items={[
        ["Held", String(figures.held), null, `${naira(figures.heldAmount)} not yet under a student`],
        ["Matched now", String(cat("MATCHED")), cat("MATCHED") ? "var(--green-ink)" : null, "Ready to reconcile"],
        ["Ambiguous · no match", `${cat("AMBIGUOUS")} · ${cat("NO_MATCH")}`, null, "Several students · none on the register"],
        ["Resolved by JAMB number", String(figures.resolvedByJamb), null, `${figures.reconciled} reconciled · ${figures.pending} awaiting the Bursar`],
      ]} />
      <Tabs look="line" label="Reconciliation" value={tab} onChange={setTab} items={[{ id: "held", label: "Held payments" }, { id: "batches", label: "Reconciliations", count: batches.length }]} />

      {tab === "held" ? (
        <Panel title="Held payments" right={held ? `${held.total} payment${held.total === 1 ? "" : "s"} · ${naira(held.amount)}` : ""}>
          <PBody>
            <div className="grid grid--4">
              <Field id="fh-cat" label="Match status">
                <select id="fh-cat" className="ctl" value={f.category} onChange={(e) => { setF({ ...f, category: e.target.value }); setPageNo(0); setChosen(new Set()); }}>
                  <option value="">Any</option>
                  {(Object.keys(CATEGORY_WORDS) as Category[]).map((c) => <option key={c} value={c}>{CATEGORY_WORDS[c][0]}</option>)}
                </select>
              </Field>
              <Field id="fh-pur" label="Payment type">
                <select id="fh-pur" className="ctl" value={f.purpose} onChange={(e) => { setF({ ...f, purpose: e.target.value }); setPageNo(0); }}>
                  <option value="">Any</option>
                  {Object.entries(PURPOSE_WORDS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </Field>
              <Field id="fh-ses" label="Session"><input id="fh-ses" className="ctl" placeholder="2025/2026" value={f.session} onChange={(e) => { setF({ ...f, session: e.target.value }); setPageNo(0); }} /></Field>
              <Field id="fh-q" label="JAMB number or payment reference"><input id="fh-q" className="ctl" value={f.q} onChange={(e) => { setF({ ...f, q: e.target.value }); setPageNo(0); }} /></Field>
            </div>
            {held && held.byCategory.length ? (
              <div className="row row--inline mt-2" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
                {held.byCategory.map((c) => <Pil key={c.category} kind={CATEGORY_WORDS[c.category][1]} title={CATEGORY_HELP[c.category]}>{CATEGORY_WORDS[c.category][0]} {c.n}</Pil>)}
              </div>
            ) : null}
            {mayInitiate ? (
              <div className="row mt-2">
                <Btn kind="primary" disabled={!matchedHere || !matchedHere.n} onClick={() => setMatching({ all: true })}>Match JAMB payments{matchedHere?.n ? ` (${matchedHere.n})` : ""}</Btn>
                <Btn kind="ghost" disabled={!chosen.size} onClick={() => setMatching({ all: false })}>Reconcile the {chosen.size || ""} ticked</Btn>
                <span className="sub2">Matched payments only; a Bursar officer who did not initiate it approves.</span>
              </div>
            ) : null}
          </PBody>
          {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : !held ? <PBody><div className="sub2">Reading the held payments…</div></PBody> : held.rows.length ? (
            <>
              <DTable pageSize={0} cols={["|mid", "S/N|num", "Number paid under", "Student", "Current matric no.", "Payment ref", "Payment type", "Amount|num", "Session", "Match status"]}
                rows={held.rows.map((r, i) => [
                  r.category === "MATCHED" && mayInitiate
                    ? <input key="c" type="checkbox" aria-label={`Choose ${r.original_identifier}`} checked={chosen.has(r.id)} onChange={(e) => { const n = new Set(chosen); if (e.target.checked) n.add(r.id); else n.delete(r.id); setChosen(n); }} />
                    : <span key="c" />,
                  <span key="n" className="tnum sub2">{pageNo * 50 + i + 1}</span>,
                  <Two key="i" a={<span className="tnum">{r.original_identifier}</span>} b={IDENTIFIER_WORDS[r.identifier_type] ?? r.identifier_type} />,
                  r.student_name ? <Two key="s" a={r.student_name} b={r.programme ?? ""} /> : <span key="s" className="sub2">{r.candidates > 1 ? `${r.candidates} students share this number` : "—"}</span>,
                  <span key="m" className="tnum">{r.matric_no ?? "—"}</span>, <span key="p" className="tnum">{r.payref ?? "—"}</span>, PURPOSE_WORDS[r.purpose] ?? r.purpose,
                  <span key="a" className="tnum">{naira(r.amount)}</span>, `${r.session ?? "—"}${r.semester ? ` · sem ${r.semester}` : ""}`,
                  <Pil key="st" kind={CATEGORY_WORDS[r.category][1]} title={CATEGORY_HELP[r.category]}>{CATEGORY_WORDS[r.category][0]}</Pil>,
                ])} />
              <PBody>
                <div className="row">
                  <Btn kind="ghost" disabled={pageNo === 0} onClick={() => setPageNo(pageNo - 1)}>Previous</Btn>
                  <span className="sub2">Page {pageNo + 1} of {Math.max(1, Math.ceil(held.total / 50))}</span>
                  <Btn kind="ghost" disabled={(pageNo + 1) * 50 >= held.total} onClick={() => setPageNo(pageNo + 1)}>Next</Btn>
                </div>
              </PBody>
            </>
          ) : <PBody><div className="sub2">No held payment matches.</div></PBody>}
        </Panel>
      ) : (
        <Panel title="Reconciliations" right={<span className="sub2">PAY-RECON batches</span>}>
          {batches.length ? <DTable pageSize={10} cols={["Reference", "State|mid", "Payments|num", "Amount|num", "Reconciled|num", "Initiated", "Decided", "|num"]} rows={batches.map((b) => [
            <span key="r" className="tnum">{b.ref}</span>, <Pil key="s" kind={STATE_WORDS[b.state][1]}>{STATE_WORDS[b.state][0]}</Pil>, b.matched, <span key="a" className="tnum">{naira(b.amount)}</span>,
            b.reconciled ?? "—", <Two key="i" a={b.initiated_by ?? "—"} b={when(b.initiated_at)} />, <Two key="d" a={b.decided_by ?? "—"} b={when(b.decided_at)} />,
            <Btn key="o" kind="ghost" size="sm" onClick={() => void openBatch(b.ref)}>Open</Btn>,
          ])} /> : <PBody><div className="sub2">No reconciliation yet.</div></PBody>}
        </Panel>
      )}

      {matching ? (
        <Modal title={matching.all ? "Match JAMB payments" : `Reconcile ${chosen.size} payment${chosen.size === 1 ? "" : "s"}`}
          sub={matching.all ? `${matchedHere?.n ?? 0} matched payment${matchedHere?.n === 1 ? "" : "s"} under the filters · ${naira(matchedHere?.amount)}` : "The ticked payments"}
          onClose={() => setMatching(null)}
          foot={<><Btn kind="ghost" onClick={() => setMatching(null)}>Cancel</Btn><Btn kind="primary" busy={busy} busyLabel="Sending…" disabled={reason.trim().length < 10} onClick={() => void initiate()}>Send to the Bursar</Btn></>}>
          <Note kind="info" title="Each payment is recorded once, under the student its number names">
            The payment keeps its old payment number, amount, date and session; the number it was paid under is kept beside it. Payments already on record are
            not recorded again. Nothing changes until a Bursar officer who did not initiate this approves it.
          </Note>
          <Field id="fh-reason" label="Reason" required full hint="Ten characters or more">
            <textarea id="fh-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Old-portal school fees paid under JAMB numbers before matriculation" />
          </Field>
        </Modal>
      ) : null}

      {open ? <BatchModal batch={open} mayDecide={mayDecide && open.initiated_by_id !== me} mayWithdraw={open.initiated_by_id === me}
        onClose={() => setOpen(null)} onDone={() => { setOpen(null); router.refresh(); }} /> : null}
    </>
  );
}

function BatchModal({ batch, mayDecide, mayWithdraw, onClose, onDone }: { batch: Batch; mayDecide: boolean; mayWithdraw: boolean; onClose: () => void; onDone: () => void }) {
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const payments = Array.isArray(batch.payments) ? (batch.payments as BatchPayment[]) : [];
  const pending = batch.state === "PENDING_APPROVAL";
  async function act(path: string, body: unknown, what: string) {
    setBusy(what);
    try {
      const r = await call<unknown>("POST", `/batches/${batchPath(batch.ref)}/${path}`, body, `${batch.ref} ${what}`);
      if (r.ok) { notify(`${batch.ref} ${what}`); onDone(); } else notifyProblem(r.problem);
    } finally { setBusy(null); }
  }
  return (
    <Modal wide title={batch.ref} sub={`${STATE_WORDS[batch.state][0]} · ${batch.matched} payment${batch.matched === 1 ? "" : "s"} · ${naira(batch.amount)}`} onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Close</Btn>
        {pending && mayWithdraw ? <Btn kind="ghost" busy={busy === "withdrawn"} onClick={() => void act("withdraw", { reason: note || null }, "withdrawn")}>Withdraw</Btn> : null}
        {pending && mayDecide ? <>
          <Btn kind="ghost" busy={busy === "rejected"} disabled={note.trim().length < 10} onClick={() => void act("decide", { approve: false, note }, "rejected")}>Reject</Btn>
          <Btn kind="primary" busy={busy === "approved"} busyLabel="Reconciling…" onClick={() => void act("decide", { approve: true, note: note || null }, "approved")}>Approve and reconcile</Btn>
        </> : null}
      </>}>
      <div className="sub2">Initiated by {batch.initiated_by ?? "—"} ({batch.initiated_office}) on {when(batch.initiated_at)}: {batch.reason}</div>
      {batch.decided_at ? <div className="sub2">{STATE_WORDS[batch.state][0]} by {batch.decided_by ?? "—"} on {when(batch.decided_at)}{batch.decision_note ? `: ${batch.decision_note}` : ""}</div> : null}
      {batch.state === "APPROVED" ? <Note kind="ok" title={`${batch.reconciled ?? 0} payment${batch.reconciled === 1 ? "" : "s"} reconciled · ${naira(batch.reconciled_amount)}`}>Each is the student&rsquo;s now, on their payment history and fee position, counted once.</Note> : null}
      {pending && !mayDecide && !mayWithdraw ? <Note kind="info" title="Awaiting a Bursar officer">A Bursar officer who did not initiate it approves or rejects it.</Note> : null}
      <DTable pageSize={10} cols={["Number paid under", "Student", "Current matric no.", "Payment ref", "Amount|num", "Session", "Status", "Recorded as"]} rows={payments.map((p) => [
        <span key="i" className="tnum">{p.original_identifier}</span>, p.student_name ?? "—", <span key="m" className="tnum">{p.matric_no ?? "—"}</span>, <span key="p" className="tnum">{p.payref ?? "—"}</span>,
        <span key="a" className="tnum">{naira(p.amount)}</span>, `${p.session ?? "—"}${p.semester ? ` · sem ${p.semester}` : ""}`, p.status === "RECONCILED" ? "Reconciled" : "Held",
        p.payment_reference && p.student_id ? <LinkBtn key="r" kind="ghost" href={`/students/${p.student_id}?tab=finance`}>{p.payment_reference}</LinkBtn> : <span key="r" className="sub2">—</span>,
      ])} />
      {pending && (mayDecide || mayWithdraw) ? (
        <Field id="fh-note" label={mayDecide ? "Note (a rejection says why, in ten characters or more)" : "Why it is withdrawn"} full>
          <textarea id="fh-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
      ) : null}
    </Modal>
  );
}
