"use client";

/** V779 · the Academic Office's verification queue: every course a student selected for the Summer, with what the results say of it
 *  and where its payment stands, to be confirmed, found not outstanding, rejected or reopened — one at a time or in bulk — each
 *  decision with its reason (the student reads it). A paid course found not outstanding or rejected is taken off the registration
 *  and its fee is held as a Summer credit for the Bursar to settle; nothing is refunded automatically. The list is paged and
 *  filtered by the server (the offices that only read see it without the bars; a Head of Department sees their department's, a
 *  Dean their faculty's). */
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { Btn, Note, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import {
  BASIS_WORD, DECISION_WORD, FLAG_FILTER_WORD, STATE_FILTER_WORD, VERIFICATIONS, categoryPill, chunk, decisionPreview, defaultQueueState, deskHref, evidenceTone, evidenceWord, failedInWord, naira,
  num, plural, reasonOk, registrationCategoryWord, reviewReasonWord, sessionPath, verificationTone, verificationWord, viaWord,
  type SummerDecideAnswer, type SummerReconcileAnswer, type SummerSelectionRow, type SummerSelectionsView,
} from "@/lib/summer";
import { call, read, saveFile, type DeskResult } from "./deskApi";
import { OrgFilters, orgFromFacets } from "./OrgFilters";
import { SelectionDetail } from "./SelectionDetail";

type Decision = "CONFIRM" | "NOT_OUTSTANDING" | "REJECT" | "REOPEN";
interface Pending { decision: Decision; ids: string[]; rows: SummerSelectionRow[]; all: boolean }
interface Outcome { decision: Decision; decided: number; unchanged: number; credited: number; withdrawn: number; batches: string[]; refused: { id: string; code: string; message: string }[]; of: number }

/** the payment of a row, in a word */
function PaymentPill({ r }: { r: SummerSelectionRow }) {
  if (r.charge_state === "PAID") {
    return r.entry_live === false ? <Pil kind="bad" title="Paid, but no entry stands on the registration: see the Period and acts tab">PAID · NOT REGISTERED</Pil> : <Pil kind="ok">PAID</Pil>;
  }
  if (r.charge_state === "DUE") return <Pil kind="warn">UNPAID</Pil>;
  return <span className="sub2">—</span>;
}

/** confirms a decision on the rows ticked: the reason the student reads, a note only staff read, and what the decision holds */
function DecideDialog({ session, pending, onClose, onDone }: { session: string; pending: Pending; onClose: () => void; onDone: (o: Outcome) => void }) {
  const word = DECISION_WORD[pending.decision];
  const [reason, setReason] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(0);
  const [problem, setProblem] = useState<Problem | null>(null);
  const money = pending.decision === "NOT_OUTSTANDING" || pending.decision === "REJECT";
  const preview = decisionPreview(pending.rows);
  const ok = !word.needsReason || reasonOk(reason);
  async function run() {
    setBusy(true);
    setProblem(null);
    const chunks = chunk(pending.ids, 200);
    const out: Outcome = { decision: pending.decision, decided: 0, unchanged: 0, credited: 0, withdrawn: 0, batches: [], refused: [], of: pending.ids.length };
    try {
      for (let i = 0; i < chunks.length; i++) {
        const r = await call<SummerDecideAnswer>("POST", `/summer/${sessionPath(session)}/selections/decide`,
          { ids: chunks[i], decision: pending.decision, reason: word.needsReason ? reason.trim() : null, note: note.trim() || null },
          `Summer Semester ${session}: ${plural(chunks[i].length, "selection")} ${word.done}`);
        if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); if (out.decided + out.unchanged + out.refused.length > 0) onDone(out); return; }
        out.decided += r.data.decided; out.unchanged += r.data.unchanged; out.credited += num(r.data.credited); out.withdrawn += r.data.withdrawn;
        out.batches.push(r.data.batch); out.refused.push(...(r.data.refused ?? []));
        setDone(i + 1);
      }
      onDone(out);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title={`${word.label}${money ? "…" : ""}`} sub={plural(pending.ids.length, "selection")} onClose={onClose}
      foot={<>
        <Btn kind="ghost" size="md" disabled={busy} onClick={onClose}>Cancel</Btn>
        <Btn kind={pending.decision === "REJECT" ? "urgent" : "primary"} size="md" busy={busy} busyLabel="Deciding…" disabled={busy || !ok} onClick={() => void run()}>{word.label}</Btn>
      </>}>
      {money ? (
        <>
          <p className="sub2" style={{ marginTop: 0 }}>
            {pending.decision === "NOT_OUTSTANDING"
              ? "Use this when a published result shows the student does not owe the course. The student is told the reason."
              : "Use this when the course is not one the student may take in the Summer (for example it is not theirs to owe). The student is told the reason."}
          </p>
          <Field id="dd-reason" label="Reason the student will read" hint={`At least ten characters. ${reason.trim().length} so far.`} required>
            <textarea id="dd-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} />
          </Field>
        </>
      ) : null}
      <Field id="dd-note" label="Staff note (optional; the student does not see it)">
        <textarea id="dd-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} />
      </Field>
      {money ? (
        <Note kind="info" title="What this holds">
          {pending.all
            ? `${plural(pending.ids.length, "course")}: a paid course is taken off the student's registration and its fee is held as a Summer credit for the Bursary to apply or refund; a student's paid programme fee is held too when the decision takes their last Summer course. Nothing is refunded automatically.`
            : `${preview.sentence} Nothing is refunded automatically; the Bursary settles each credit.`}
        </Note>
      ) : pending.decision === "CONFIRM" ? (
        <div className="sub2">The selection is confirmed outstanding against the record. A course with a pass on record cannot be confirmed.</div>
      ) : (
        <div className="sub2">The selection goes back to pending verification. A course already decided and paid cannot be reopened.</div>
      )}
      {busy && pending.ids.length > 200 ? <div className="sub2 mt-1" role="status">{done} of {chunk(pending.ids, 200).length} groups of 200 decided…</div> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}

export function SummerQueue({ session, view, filters, page, maySet }: { session: string; view: SummerSelectionsView; filters: Record<string, string>; page: number; maySet: boolean }) {
  const router = useRouter();
  const go = useQueryNav();
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [pickedAll, setPickedAll] = useState<{ total: number } | null>(null);
  const [pending, setPending] = useState<Pending | null>(null);
  const [detail, setDetail] = useState<string | null>(null);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [progress, setProgress] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const q = filters.q ?? "";

  function nav(patch: Record<string, string>, toPage = 1) {
    const next: Record<string, string> = { ...filters, ...patch };
    for (const k of Object.keys(next)) if (!next[k]) delete next[k];
    go(deskHref(session, "review", next, toPage));
  }
  const filtered = Object.keys(filters).some((k) => filters[k] && !(k === "state" && filters[k] === defaultQueueState(maySet)));
  const rowsById = new Map(view.rows.map((r) => [r.selection_id, r]));
  const pageIds = view.rows.map((r) => r.selection_id);
  const allOnPage = pageIds.length > 0 && pageIds.every((id) => checked.has(id));

  function toggle(id: string) {
    setPickedAll(null);
    setChecked((x) => { const n = new Set(x); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  }
  function selectPage() {
    setPickedAll(null);
    setChecked((x) => { const n = new Set(x); for (const id of pageIds) { if (allOnPage) n.delete(id); else n.add(id); } return n; });
  }
  async function selectAllMatching() {
    setBusy("ids");
    setProblem(null);
    try {
      const qs = new URLSearchParams(filters).toString();
      const r = await read<{ ids: string[]; total: number }>(`/summer/${sessionPath(session)}/selections/ids${qs ? `?${qs}` : ""}`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      setChecked(new Set(r.data.ids));
      setPickedAll({ total: r.data.total });
    } finally {
      setBusy(null);
    }
  }
  function decide(decision: Decision) {
    const ids = [...checked];
    setPending({ decision, ids, rows: ids.map((id) => rowsById.get(id)).filter((r): r is SummerSelectionRow => !!r), all: pickedAll !== null || ids.some((id) => !rowsById.has(id)) });
  }
  function decideOne(decision: Decision, row: SummerSelectionRow) {
    setDetail(null);
    // the drawer reads the selection live; the queue's row for it brings the charge columns the drawer's answer may not carry (the
    // programme fee paid, how many of the student's courses stand), so the dialog can say what the decision holds
    const listed = rowsById.get(row.selection_id);
    const merged: SummerSelectionRow = {
      ...row,
      charge_amount: row.charge_amount ?? listed?.charge_amount,
      programme_fee_paid: row.programme_fee_paid !== undefined ? row.programme_fee_paid : listed?.programme_fee_paid,
      courses_standing: row.courses_standing !== undefined ? row.courses_standing : listed?.courses_standing,
    };
    setPending({ decision, ids: [row.selection_id], rows: [merged], all: false });
  }
  function decided(o: Outcome) {
    setPending(null);
    setOutcome(o);
    setChecked(new Set());
    setPickedAll(null);
    notify(`${plural(o.decided, "selection")} ${DECISION_WORD[o.decision].done}${o.credited > 0 ? `; ${naira(o.credited)} held as Summer credit` : ""}`);
    router.refresh();
  }
  /** the queue for the filters as a CSV the API makes (and records on the export log) */
  async function exportCsv() {
    setBusy("export");
    setProblem(null);
    try {
      const qs = new URLSearchParams(filters).toString();
      const p = await saveFile(`/summer/${sessionPath(session)}/selections/export${qs ? `?${qs}` : ""}`, `summer-${session.replace("/", "-")}-selections.csv`, `Summer Semester ${session}: selections exported`);
      if (p) { setProblem(p); notifyProblem(p); return; }
      notify("The selections are downloaded");
    } finally {
      setBusy(null);
    }
  }
  async function reconcile() {
    setBusy("reconcile");
    setProblem(null);
    setProgress(null);
    const total = { read: 0, confirmed: 0, takenBack: 0, flagged: 0, reverted: 0 };
    try {
      let since: string | null = null;
      for (let i = 0; i < 200; i++) {
        const r: DeskResult<SummerReconcileAnswer> = await call<SummerReconcileAnswer>("POST", `/summer/${sessionPath(session)}/reconcile`, { since, limit: 2000 }, `Summer Semester ${session}: selections read against the published results`);
        if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
        since = r.data.since ?? since;
        total.read += r.data.read; total.confirmed += r.data.confirmed; total.takenBack += r.data.takenBack; total.flagged += r.data.flagged; total.reverted += r.data.reverted;
        setProgress(`${total.read} students read · ${total.confirmed} confirmed by results · ${total.takenBack} taken back · ${total.flagged} flagged · ${total.reverted} sent back to pending · ${r.data.left} left`);
        if (r.data.left === 0 || r.data.read === 0) break;
      }
      notify("The selections are read against the published results");
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  const c = view.counts;
  const first = view.total ? (page - 1) * view.size + 1 : 0;
  const last = Math.min(view.total, page * view.size);
  const pages = Math.max(1, Math.ceil(view.total / view.size));
  return (
    <>
      <form className="filterbar" role="search" onSubmit={(e) => { e.preventDefault(); nav({ q: String(new FormData(e.currentTarget).get("q") ?? "").trim() }); }}>
        <div className="row" style={{ width: "100%" }}>
          <OrgFilters idp="sq" filters={filters} onChange={(p) => nav(p)} org={orgFromFacets(view.facets)} levels={view.facets.levels} />
          <Field id="sq-evidence" label="Result evidence" style={{ flex: "0 1 190px" }}>
            <select id="sq-evidence" className="ctl" value={filters.evidence ?? ""} onChange={(e) => nav({ evidence: e.target.value })}>
              <option value="">Any</option><option value="RESULT_FAILED">Confirmed by results (failed)</option><option value="RESULT_PASSED">Result on record: passed</option>
              <option value="RESULT_AWAITED">Result awaited</option><option value="NO_RESULT">No result on record</option>
            </select>
          </Field>
          <Field id="sq-flag" label="Flag" style={{ flex: "0 1 190px" }}>
            <select id="sq-flag" className="ctl" value={filters.flag ?? ""} onChange={(e) => nav({ flag: e.target.value })}>
              <option value="">Any</option>
              <option value="REVIEW">{FLAG_FILTER_WORD.REVIEW} ({c.review})</option>
              <option value="CLARIFICATION">{FLAG_FILTER_WORD.CLARIFICATION} ({c.clarification})</option>
            </select>
          </Field>
          <Field id="sq-basis" label="Basis" style={{ flex: "0 1 150px" }}>
            <select id="sq-basis" className="ctl" value={filters.basis ?? ""} onChange={(e) => nav({ basis: e.target.value })}>
              <option value="">Any</option>
              {(Object.keys(BASIS_WORD) as (keyof typeof BASIS_WORD)[]).map((k) => <option key={k} value={k}>{BASIS_WORD[k]}</option>)}
            </select>
          </Field>
          <Field id="sq-paid" label="Payment" style={{ flex: "0 1 120px" }}>
            <select id="sq-paid" className="ctl" value={filters.paid ?? ""} onChange={(e) => nav({ paid: e.target.value })}>
              <option value="">Any</option><option value="PAID">Paid</option><option value="UNPAID">Unpaid</option>
            </select>
          </Field>
          <Field id="sq-q" label="Search" style={{ flex: "2 1 220px" }}>
            <input id="sq-q" name="q" className="ctl" type="search" defaultValue={q} key={q} placeholder="Number, name or course" autoComplete="off" />
          </Field>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
            <Btn kind="primary" type="submit">Search</Btn>
            {filtered ? <Btn kind="ghost" onClick={() => go(deskHref(session, "review", {}))}>Clear</Btn> : null}
          </div>
        </div>
      </form>

      <Tabs label="Verification status" value={(filters.state || "ANY") as string} onChange={(s) => nav({ state: s })}
        items={[
          ...VERIFICATIONS.map((v) => ({ id: v as string, label: STATE_FILTER_WORD[v], count: String(c[v]) })),
          { id: "ANY", label: STATE_FILTER_WORD.ANY, count: String(VERIFICATIONS.reduce((s, v) => s + c[v], 0)) },
        ]} />

      {outcome ? (
        <Note kind={outcome.refused.length ? "bad" : "ok"} title={`${plural(outcome.decided, "selection")} ${DECISION_WORD[outcome.decision].done}${outcome.unchanged ? `, ${outcome.unchanged} already so` : ""}`}>
          {outcome.credited > 0 ? <>{naira(outcome.credited)} is held as Summer credit for the Bursary to settle; {plural(outcome.withdrawn, "entry", "entries")} taken off the registration. </> : null}
          {outcome.batches.length ? <span className="sub2">Batch {outcome.batches.join(", ")}. </span> : null}
          {outcome.refused.length ? (
            <>
              <b>{outcome.refused.length} of {outcome.of} could not be decided:</b>
              <ul className="list" style={{ marginTop: 4 }}>
                {outcome.refused.slice(0, 50).map((x) => {
                  const row = rowsById.get(x.id);
                  return <li key={x.id}><span className="tnum">{row ? `${row.matric_no ?? ""} ${row.course_code}` : x.id}</span>: {x.message} <span className="sub2">({x.code})</span></li>;
                })}
                {outcome.refused.length > 50 ? <li>… and {outcome.refused.length - 50} more</li> : null}
              </ul>
            </>
          ) : null}
        </Note>
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title="Selections to verify" right={<span className="row row--inline row--tight">
        <span>{view.total ? `${first}–${last} of ${view.total.toLocaleString()}` : "None"}</span>
        <Btn kind="ghost" size="sm" busy={busy === "export"} busyLabel="Preparing…" disabled={busy !== null || !view.total} onClick={() => void exportCsv()}>Export CSV</Btn>
      </span>}>
        {maySet ? (
          <PBody>
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
              <Btn kind="ghost" size="sm" disabled={!view.rows.length} onClick={selectPage}>{allOnPage ? "Unselect this page" : "Select this page"}</Btn>
              {view.total > view.rows.length && !pickedAll ? (
                <Btn kind="ghost" size="sm" busy={busy === "ids"} busyLabel="Reading…" disabled={busy !== null} onClick={() => void selectAllMatching()}>Select all {view.total.toLocaleString()} matching</Btn>
              ) : null}
              <span className="grow" />
              <Btn kind="ghost" size="sm" busy={busy === "reconcile"} busyLabel="Reading results…" disabled={busy !== null} onClick={() => void reconcile()}>Reconcile with results</Btn>
            </div>
            {progress ? <div className="sub2 mt-1" role="status">{progress}</div> : null}
            {checked.size > 0 ? (
              <div className="row mt-2" role="region" aria-label="Decide the selections ticked" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
                <b>{pickedAll ? `All ${checked.size.toLocaleString()}${pickedAll.total > checked.size ? ` of ${pickedAll.total.toLocaleString()} (the first ${checked.size.toLocaleString()})` : ""} matching selected` : `${checked.size.toLocaleString()} selected`}</b>
                <Btn kind="primary" size="sm" disabled={busy !== null} onClick={() => decide("CONFIRM")}>Confirm</Btn>
                <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => decide("NOT_OUTSTANDING")}>Not outstanding…</Btn>
                <Btn kind="urgent" size="sm" disabled={busy !== null} onClick={() => decide("REJECT")}>Reject…</Btn>
                <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => decide("REOPEN")}>Reopen</Btn>
                <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => { setChecked(new Set()); setPickedAll(null); }}>Clear</Btn>
              </div>
            ) : null}
          </PBody>
        ) : (
          <PBody><div className="sub2">Your office reads the queue; the Academic Office and the Registry decide the selections.</div></PBody>
        )}
        {view.rows.length ? (
          <DTable pageSize={0} noPrint title="Summer Semester selections to verify"
            cols={[...(maySet ? ["|mid"] : []), "Student", "Programme · level · category", "Course", "Owed in · registration category", "Result evidence", "Status", "Payment · flag", "|mid"]}
            rows={view.rows.map((r) => {
              const id = r.selection_id;
              const flagged = r.needs_review && r.review_flag;
              return [
                ...(maySet ? [<input key={`k${id}`} type="checkbox" aria-label={`Select ${r.matric_no ?? r.name}, ${r.course_code}`} checked={checked.has(id)} onChange={() => toggle(id)} />] : []),
                <span key={`n${id}`}><Link className="lnk b600" href={`/students/${r.student_id}`}>{r.name}</Link><span className="blk sub2 tnum">{r.matric_no ?? "—"}</span></span>,
                <span key={`p${id}`}>
                  <span className="sub2">{r.programme ?? "—"}</span>
                  <span className="blk sub2 tnum">{r.level ?? "—"} Level{r.summer_level && r.summer_level !== r.level ? ` · Summer level ${r.summer_level}` : ""}</span>
                  {r.category ? <span className="blk"><Pil kind="info">{categoryPill(r.category)}</Pil></span> : null}
                </span>,
                <span key={`o${id}`}><b className="tnum">{r.course_code}</b><span className="blk">{r.title ?? ""}</span><span className="blk sub2 tnum">{plural(r.units ?? 0, "unit")}</span></span>,
                <span key={`f${id}`}><span className="sub2">{failedInWord(r)}</span><span className="blk">{registrationCategoryWord(r.basis)}</span></span>,
                r.evidence ? <Pil key={`e${id}`} kind={evidenceTone(r.evidence)}>{evidenceWord(r.evidence)}</Pil> : <span key={`e${id}`} className="sub2">—</span>,
                <span key={`s${id}`}><Pil kind={verificationTone(r.state)}>{verificationWord(r.state)}</Pil>{r.verified_via ? <span className="blk sub2">{viaWord(r.verified_via)}</span> : null}</span>,
                <span key={`y${id}`}>
                  <PaymentPill r={r} />
                  {flagged ? <span className="blk"><Pil kind="warn" title={reviewReasonWord(r.review_flag, r.basis)}>NEEDS REVIEW</Pil><span className="blk sub2">{reviewReasonWord(r.review_flag, r.basis)}</span></span> : null}
                  {r.clarification_open ? <span className="blk"><Pil kind="info">CLARIFICATION ASKED</Pil></span> : null}
                </span>,
                <Btn key={`d${id}`} kind="ghost" size="sm" onClick={() => setDetail(id)}>Details</Btn>,
              ];
            })} />
        ) : (
          <PBody>
            <div className="sub2">{filtered ? "No selection matches these filters." : "No selection is waiting."}</div>
          </PBody>
        )}
        <PBody>
          <div className="row row--base">
            <span className="sub2">Page {page} of {pages}</span>
            <span className="grow" />
            <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => nav({}, page - 1)}>Previous</Btn>
            <Btn kind="ghost" size="sm" disabled={page >= pages} onClick={() => nav({}, page + 1)}>Next</Btn>
          </div>
        </PBody>
      </Panel>

      {detail ? <SelectionDetail session={session} id={detail} maySet={maySet} onClose={() => setDetail(null)} onDecide={decideOne} onChanged={() => router.refresh()} /> : null}
      {pending ? <DecideDialog session={session} pending={pending} onClose={() => setPending(null)} onDone={decided} /> : null}
    </>
  );
}
