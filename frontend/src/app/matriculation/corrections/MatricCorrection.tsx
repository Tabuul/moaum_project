"use client";

/** V579: a matriculation number corrected, the old number kept. The student is found by the current or a former number, the
 *  name, the JAMB, admission or application number, within a faculty, department, programme or level; the number the
 *  configuration gives is proposed, and the number given is checked as it is typed (another student's number, a former number,
 *  one reserved or proposed elsewhere: MATRICULATION NUMBER ALREADY ASSIGNED). One officer prepares the correction with its
 *  reason and evidence; another decides it — approved and made at once, or rejected. Every correction is listed, and the record
 *  keeps the old number, which still finds the student. */
import { useCallback, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tabs, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { Problem } from "@/lib/api";
import {
  EVENT, KINDS, STATE, evidenceProblem, kindWord, narrow, normalNo, partsLine, prepareBlock,
  type Check, type Correction, type CorrectionDetail, type FoundStudent, type Place, type StudentView,
} from "@/lib/matric-correction";

const BASE = "/api/bff/api/v1/matriculation/corrections";
const PREPARERS = ["academic", "records", "registrar", "dregistrar", "ict", "super"];
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const LEVELS = [100, 200, 300, 400, 500, 600, 700, 800, 900];

async function get<T>(path: string): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const r = await fetch(`${BASE}${path}`, { cache: "no-store" });
  const j = await r.json().catch(() => null);
  return r.ok ? { ok: true, data: j as T } : { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
}

async function post<T>(path: string, body: unknown, why: string): Promise<T | null> {
  const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
  return j as T;
}

function asDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => { const fr = new FileReader(); fr.onload = () => resolve(String(fr.result)); fr.onerror = () => reject(fr.error); fr.readAsDataURL(file); });
}

export function MatricCorrection({ places, corrections, office, me, initialView }: {
  places: Place[]; corrections: Correction[]; office: string | null; me: string | null; initialView: StudentView | null;
}) {
  const router = useRouter();
  const mayPrepare = PREPARERS.includes(office ?? "");
  const [tab, setTab] = useState<"find" | "waiting" | "all">(initialView ? "find" : corrections.some((c) => c.state === "PENDING_REVIEW") ? "waiting" : "find");

  // ── find ──
  const [q, setQ] = useState("");
  const [fac, setFac] = useState("");
  const [dept, setDept] = useState("");
  const [prog, setProg] = useState("");
  const [level, setLevel] = useState("");
  const [found, setFound] = useState<FoundStudent[] | null>(null);
  const choices = useMemo(() => narrow(places, fac, dept), [places, fac, dept]);

  async function search() {
    const sp = new URLSearchParams();
    if (q.trim()) sp.set("q", q.trim());
    if (fac) sp.set("faculty", fac);
    if (dept) sp.set("department", dept);
    if (prog) sp.set("programme", prog);
    if (level) sp.set("level", level);
    if (![...sp.keys()].length) { setFound([]); return; }
    const r = await get<FoundStudent[]>(`/search?${sp.toString()}`);
    if (r.ok) setFound(r.data); else notifyProblem(r.problem);
  }

  // ── one student ──
  const [view, setView] = useState<StudentView | null>(initialView);
  const [newNo, setNewNo] = useState("");
  const [check, setCheck] = useState<Check | null>(null);
  const [checking, setChecking] = useState(false);
  const [kind, setKind] = useState("");
  const [reason, setReason] = useState("");
  const [approvalRef, setApprovalRef] = useState("");
  const seq = useRef(0);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // ── a correction ──
  const [detail, setDetail] = useState<CorrectionDetail | null>(null);
  const [note, setNote] = useState("");
  const [cancelWhy, setCancelWhy] = useState("");
  const [file, setFile] = useState<File | null>(null);

  const openStudent = useCallback(async (id: string) => {
    const r = await get<StudentView>(`/students/${id}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    setView(r.data);
    setNewNo(""); setCheck(null); setKind(""); setReason(""); setApprovalRef("");
  }, []);

  /** the number typed or chosen, checked a moment after the last key; the latest answer only */
  function typed(value: string) {
    setNewNo(value);
    if (timer.current) clearTimeout(timer.current);
    const n = normalNo(value);
    const mine = ++seq.current;
    if (!view || n.length < 6) { setCheck(null); setChecking(false); return; }
    const student = view.student.id;
    setChecking(true);
    timer.current = setTimeout(async () => {
      const r = await fetch(`${BASE}/check`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ student, newNo: n }) });
      const j = await r.json().catch(() => null);
      if (mine !== seq.current) return;
      setChecking(false);
      setCheck(r.ok ? (j as Check) : null);
    }, 450);
  }

  const pendingOfStudent = view?.corrections.find((c) => c.state === "PENDING_REVIEW") ?? null;
  const block = prepareBlock(checking ? null : check, kind, reason);

  async function prepare() {
    if (!view) return;
    const d = await post<CorrectionDetail>("", { student: view.student.id, newNo: normalNo(newNo), kind, reason: reason.trim(), approvalRef: approvalRef.trim() || null },
      `Matriculation number of ${view.student.matricNo} to be corrected to ${normalNo(newNo)}`);
    if (!d) return;
    notify(`${d.ref} prepared: it waits for another officer's decision`);
    setDetail(d);
    await openStudent(view.student.id);
    router.refresh();
  }

  async function openCorrection(id: string) {
    const r = await get<CorrectionDetail>(`/${id}`);
    if (r.ok) { setDetail(r.data); setNote(""); setCancelWhy(""); setFile(null); } else notifyProblem(r.problem);
  }

  async function after(d: CorrectionDetail | null, words: string) {
    if (!d) return;
    notify(words);
    setDetail(d);
    if (view && view.student.id === d.student_id) await openStudent(d.student_id);
    router.refresh();
  }

  async function decide(approve: boolean) {
    if (!detail) return;
    const d = await post<CorrectionDetail>(`/${detail.id}/decide`, { approve, note: note.trim() || null },
      `${detail.ref} ${approve ? "approved" : "rejected"}${note.trim() ? `: ${note.trim()}` : ""}`);
    await after(d, approve ? `${detail.ref}: the number is now ${detail.new_no}; ${detail.old_no} is kept as a former number` : `${detail.ref} rejected`);
  }

  async function cancel() {
    if (!detail) return;
    const d = await post<CorrectionDetail>(`/${detail.id}/cancel`, { reason: cancelWhy.trim() }, `${detail.ref} cancelled: ${cancelWhy.trim()}`);
    await after(d, `${detail.ref} cancelled`);
  }

  async function addEvidence() {
    if (!detail || !file) return;
    const d = await post<CorrectionDetail>(`/${detail.id}/evidence`, { filename: file.name, dataUrl: await asDataUrl(file) }, `Evidence for ${detail.ref}`);
    if (d) { setFile(null); setDetail(d); notify(`${file.name} added to ${detail.ref}`); }
  }

  const waiting = corrections.filter((c) => c.state === "PENDING_REVIEW");
  async function excel(rows: Correction[], title: string) {
    downloadBlob(await brandedXlsx(title, ["Reference", "Student", "Programme", "Level", "Old number", "New number", "Kind", "Reason", "Approval reference", "State",
      "Prepared by", "Prepared", "Decided by", "Decided", "Note"],
    rows.map((c) => [c.ref, `${c.surname}, ${c.other_names}`, c.programme ?? "", c.current_level ?? "", c.old_no, c.new_no, kindWord(c.kind), c.reason, c.approval_ref ?? "",
      STATE[c.state].label, c.prepared_by_name ?? c.prepared_office ?? "", when(c.prepared_at), c.decided_by_name ?? c.cancelled_by_name ?? "", when(c.decided_at ?? c.cancelled_at),
      c.decision_note ?? c.cancel_reason ?? ""]), { serial: docSerial("MCR") }), `matriculation-corrections-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  const listTable = (rows: Correction[]) => (
    <DTable cols={["Reference", "Student", "Number", "Kind", "State", "Prepared", "|num"]} rows={rows.map((c) => [
      <span key="r" className="tnum b600">{c.ref}</span>,
      <Two key="s" a={`${c.surname}, ${c.other_names}`} b={`${c.programme ?? ""}${c.current_level ? ` · ${c.current_level} Level` : ""}`} />,
      <Two key="n" a={<span className="tnum">{c.old_no}</span>} b={<span className="tnum">→ {c.new_no}</span>} />,
      <span key="k" className="sub2">{kindWord(c.kind)}</span>,
      <Pil key="st" kind={STATE[c.state].tone}>{STATE[c.state].label}</Pil>,
      <span key="p" className="sub2">{when(c.prepared_at)}<div>{c.prepared_by_name ?? c.prepared_office ?? ""}</div></span>,
      <Btn key="o" kind="ghost" size="sm" onClick={() => openCorrection(c.id)}>Open</Btn>,
    ])} texts={rows.map((c) => `${c.ref} ${c.surname} ${c.other_names} ${c.old_no} ${c.new_no}`)} />
  );

  return (
    <>
      <Note kind="info" title="A wrong number, corrected — the old one kept">
        A correction changes the student&rsquo;s matriculation number and nothing else: the record, the portal account, registrations, results, payments and
        receipts stay as they are. The old number is kept as a former number, still finds the student, and is never given to anyone again. One officer
        prepares the correction; another decides it. The student signs in with the new number from the moment it is approved, and is told.
      </Note>
      <Tiles items={[
        ["Waiting for a decision", String(waiting.length), waiting.length ? "var(--amber-ink)" : null, "Prepared, not yet decided"],
        ["Corrected", String(corrections.filter((c) => c.state === "COMPLETED").length), null, "Numbers changed, the old ones kept"],
        ["Rejected", String(corrections.filter((c) => c.state === "REJECTED").length), null, "With the reason"],
        ["Cancelled", String(corrections.filter((c) => c.state === "CANCELLED").length), null, "Withdrawn before a decision"],
      ]} />
      <Tabs label="Matriculation correction" value={tab} onChange={setTab} items={[
        { id: "find", label: "Find a student" },
        { id: "waiting", label: "Waiting for a decision", count: waiting.length },
        { id: "all", label: "Every correction", count: corrections.length },
      ]} />

      {tab === "find" ? (
        <>
          <Panel title="Find the student">
            <PBody>
              <form className="row row--tight" style={{ flexWrap: "wrap", gap: 8, alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); void search(); }}>
                <Field id="mc-q" label="Number or name" hint="Current or former matriculation number, name, JAMB, admission or application number">
                  <input id="mc-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} style={{ minWidth: 280 }} placeholder="MOAU/AD/BUS/25/12939" />
                </Field>
                <Field id="mc-fac" label="Faculty">
                  <select id="mc-fac" className="ctl" value={fac} onChange={(e) => { setFac(e.target.value); setDept(""); setProg(""); }}>
                    <option value="">Any faculty</option>
                    {choices.faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}
                  </select>
                </Field>
                <Field id="mc-dept" label="Department">
                  <select id="mc-dept" className="ctl" value={dept} onChange={(e) => { setDept(e.target.value); setProg(""); }}>
                    <option value="">Any department</option>
                    {choices.departments.map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}
                  </select>
                </Field>
                <Field id="mc-prog" label="Programme">
                  <select id="mc-prog" className="ctl" value={prog} onChange={(e) => setProg(e.target.value)} style={{ maxWidth: 260 }}>
                    <option value="">Any programme</option>
                    {choices.programmes.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
                  </select>
                </Field>
                <Field id="mc-level" label="Level">
                  <select id="mc-level" className="ctl" value={level} onChange={(e) => setLevel(e.target.value)}>
                    <option value="">Any level</option>
                    {LEVELS.map((l) => <option key={l} value={l}>{l}</option>)}
                  </select>
                </Field>
                <Btn kind="primary" busyLabel="Searching…" onClick={() => search()}>Search</Btn>
              </form>
            </PBody>
            {found ? (found.length ? (
              <DTable cols={["Student", "Matriculation number", "Programme", "Level|num", "Status", "|num"]} rows={found.map((s) => [
                <Two key="n" a={`${s.surname}, ${s.other_names}`} b={[s.jamb_reg_no, s.admission_no].filter(Boolean).join(" · ") || "—"} />,
                <span key="m"><span className="tnum b600">{s.matric_no ?? "—"}</span>
                  {s.former_no ? <div><Pil kind="info">This number was corrected</Pil> <span className="sub2 tnum">formerly {s.former_no} ({s.corrected_by})</span></div> : null}
                  {s.pending_ref ? <div><Pil kind="warn">{s.pending_ref} waits for a decision</Pil></div> : null}</span>,
                <Two key="p" a={s.programme ?? "—"} b={[s.department, s.faculty].filter(Boolean).join(" · ")} />,
                <span key="l" className="tnum">{s.current_level ?? "—"}</span>,
                <span key="st" className="sub2">{s.status}</span>,
                <Btn key="o" kind="ghost" size="sm" onClick={() => openStudent(s.student_id)}>Open</Btn>,
              ])} texts={found.map((s) => `${s.surname} ${s.other_names} ${s.matric_no ?? ""} ${s.former_no ?? ""}`)} />
            ) : <PBody><div className="sub2">No student found. Try the number as it is on the identity card, or the name.</div></PBody>) : null}
          </Panel>

          {view ? (
            <>
              <Panel title={`${view.student.surname}, ${view.student.otherNames}`} right={<Pil kind="grey">{view.student.status}</Pil>}>
                <PBody>
                  <div className="eyebrow">Current matriculation number</div>
                  <div className="t-lg b700 tnum mb-2">{view.student.matricNo ?? "Not yet issued"}</div>
                  <KvGrid cls="grid--3" pairs={[
                    ["Faculty", view.student.faculty ?? "—"], ["Department", view.student.department ?? "—"], ["Programme", view.student.programme ?? "—"],
                    ["Level", view.student.level ?? "—"], ["Entry session", view.student.entrySession ?? "—"], ["JAMB / admission", [view.student.jambRegNo, view.student.admissionNo].filter(Boolean).join(" · ") || "—"],
                  ]} />
                  {view.history.length ? (
                    <div className="mt-2"><div className="eyebrow mb-1">The number through time</div>
                      {view.history.map((h, i) => (
                        <div key={i} className="sub2">{when(h.at)} · {EVENT[h.event]}: {h.previous_no ? <><span className="tnum">{h.previous_no}</span> → </> : null}<b className="tnum">{h.matric_no}</b>
                          {h.ref ? ` · ${h.ref}` : ""}{h.by_name ? ` · ${h.by_name}` : ""}{h.reason && h.event === "CORRECTED" ? ` · ${h.reason}` : ""}</div>
                      ))}
                    </div>
                  ) : null}
                </PBody>
                {view.corrections.length ? listTable(view.corrections) : null}
              </Panel>

              {pendingOfStudent ? (
                <Note kind="info" title={`${pendingOfStudent.ref} waits for a decision`} action={<Btn kind="ghost" size="sm" onClick={() => openCorrection(pendingOfStudent.id)}>Open it</Btn>}>
                  {pendingOfStudent.old_no} → {pendingOfStudent.new_no}. One correction at a time: decide or cancel it before preparing another.
                </Note>
              ) : mayPrepare && view.student.matricNo ? (
                <Panel title="Correct the number">
                  <PBody>
                    {view.suggestions.length ? (
                      <div className="mb-2"><div className="eyebrow mb-1">What the configuration gives</div>
                        {view.suggestions.map((s) => (
                          <div key={s.matric_no} className="row row--tight" style={{ gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                            <Btn kind="ghost" size="sm" onClick={() => typed(s.matric_no)}>{`Use ${s.matric_no}`}</Btn>
                            <span className="sub2">{s.label}{s.taken ? ` — ${s.taken}` : ""}</span>
                          </div>
                        ))}
                      </div>
                    ) : null}
                    <Field id="mc-new" label="The correct matriculation number" required hint="Typed or chosen above; checked as you type">
                      <input id="mc-new" className="ctl tnum" value={newNo} onChange={(e) => typed(e.target.value.toUpperCase())} style={{ maxWidth: 320 }} autoComplete="off" />
                    </Field>
                    {checking ? <div className="sub2">Checking…</div> : check ? (
                      <div className="mt-1">
                        {check.parts ? <div className="sub2">Reads: <b className="tnum">{partsLine(check.parts)}</b>{check.configured && !check.configured.problem
                          ? <> · the configuration gives <span className="tnum">{partsLine({ university: check.configured.university, faculty: check.configured.faculty, programme: check.configured.programme, year: check.configured.year, sequence: null })}</span> (series {check.configured.series})</> : null}</div> : null}
                        {check.problems.length ? (
                          <Note kind="bad" title={check.problems[0].message.startsWith("MATRICULATION NUMBER ALREADY ASSIGNED") ? "MATRICULATION NUMBER ALREADY ASSIGNED" : "This number cannot be given"}>
                            {check.problems.map((p) => <div key={p.code}>{p.message.replace(/^MATRICULATION NUMBER ALREADY ASSIGNED: /, "")}</div>)}
                          </Note>
                        ) : <Note kind="ok" title="The number is free">Nothing stands in the way. Look at the points below before preparing.</Note>}
                        {check.points.length ? <Note kind="info" title="To look at">{check.points.map((p) => <div key={p.code}>{p.message}</div>)}</Note> : null}
                      </div>
                    ) : null}
                    <div className="grid grid--2 mt-2">
                      <Field id="mc-kind" label="What was wrong" required>
                        <select id="mc-kind" className="ctl" value={kind} onChange={(e) => setKind(e.target.value)}>
                          <option value="">Choose…</option>
                          {KINDS.map(([k, w]) => <option key={k} value={k}>{w}</option>)}
                        </select>
                      </Field>
                      <Field id="mc-ref" label="Approval reference" hint="The Registrar's memo or the register's page, if any">
                        <input id="mc-ref" className="ctl" value={approvalRef} onChange={(e) => setApprovalRef(e.target.value)} maxLength={200} />
                      </Field>
                    </div>
                    <Field id="mc-reason" label="Reason" required hint="Ten characters or more; kept with the correction">
                      <textarea id="mc-reason" className="ctl" rows={3} maxLength={2000} value={reason} onChange={(e) => setReason(e.target.value)}
                        placeholder="e.g. Imported from the old portal with the Administration code; the student is in Computer Science" />
                    </Field>
                    <div className="row row--tight" style={{ gap: 8, alignItems: "center", flexWrap: "wrap" }}>
                      <Btn kind="primary" disabled={!!block} busyLabel="Preparing…" onClick={() => prepare()}>Prepare the correction</Btn>
                      {block ? <span className="sub2">{block}</span> : <span className="sub2">Another officer decides it; nothing changes until then.</span>}
                    </div>
                  </PBody>
                </Panel>
              ) : !view.student.matricNo ? (
                <Note kind="info" title="No number to correct">The student has no matriculation number yet: one is issued under Matriculation Management.</Note>
              ) : null}
            </>
          ) : null}
        </>
      ) : tab === "waiting" ? (
        <Panel title="Waiting for a decision" right={<Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={() => excel(waiting, "Matriculation corrections: waiting")}>Excel</Btn>}>
          {waiting.length ? listTable(waiting) : <PBody><div className="sub2">No correction waits for a decision.</div></PBody>}
        </Panel>
      ) : (
        <Panel title="Every correction" right={<Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={() => excel(corrections, "Matriculation corrections")}>Excel</Btn>}>
          {corrections.length ? listTable(corrections) : <PBody><div className="sub2">No matriculation number has been corrected yet.</div></PBody>}
        </Panel>
      )}

      {detail ? (
        <Modal title={`${detail.ref} · ${STATE[detail.state].label}`} onClose={() => setDetail(null)}
          foot={detail.state === "PENDING_REVIEW" ? (
            <>
              {detail.mayDecide ? <>
                <Btn kind="ghost" disabled={note.trim().length < 10} busyLabel="Rejecting…" onClick={() => decide(false)}>Reject</Btn>
                <Btn kind="primary" disabled={!!detail.check?.problems.length} busyLabel="Correcting…" onClick={() => decide(true)}>Approve and correct</Btn>
              </> : null}
              {mayPrepare ? <Btn kind="ghost" disabled={cancelWhy.trim().length < 10} busyLabel="Cancelling…" onClick={() => cancel()}>Cancel it</Btn> : null}
              <Btn kind="ghost" onClick={() => setDetail(null)}>Close</Btn>
            </>
          ) : <Btn kind="ghost" onClick={() => setDetail(null)}>Close</Btn>}>
          <KvGrid cls="grid--2" pairs={[
            ["Student", `${detail.surname}, ${detail.other_names}`], ["Programme", `${detail.programme ?? "—"}${detail.current_level ? ` · ${detail.current_level} Level` : ""}`],
            ["Number as it was", <span key="o" className="tnum">{detail.old_no}</span>], ["Number as it should be", <b key="n" className="tnum">{detail.new_no}</b>],
            ["What was wrong", kindWord(detail.kind)], ["Approval reference", detail.approval_ref ?? "—"],
            ["Prepared", `${when(detail.prepared_at)} · ${detail.prepared_by_name ?? detail.prepared_office ?? ""}`],
            ["Decided", detail.decided_at ? `${when(detail.decided_at)} · ${detail.decided_by_name ?? detail.decided_office ?? ""}` : detail.cancelled_at ? `Cancelled ${when(detail.cancelled_at)} · ${detail.cancelled_by_name ?? ""}` : "Not yet"],
          ]} />
          <div className="mt-2"><div className="eyebrow mb-1">Reason</div><div>{detail.reason}</div></div>
          {detail.decision_note || detail.cancel_reason ? <div className="mt-2"><div className="eyebrow mb-1">{detail.cancel_reason ? "Why it was cancelled" : "The decision's note"}</div><div>{detail.cancel_reason ?? detail.decision_note}</div></div> : null}
          {detail.check?.problems.length ? <Note kind="bad" title="It cannot be approved as it stands">{detail.check.problems.map((p) => <div key={p.code}>{p.message}</div>)}</Note> : null}
          {(detail.check?.points ?? detail.check_points)?.length ? <Note kind="info" title="To look at">{(detail.check?.points ?? detail.check_points).map((p) => <div key={p.code}>{p.message}</div>)}</Note> : null}
          <div className="mt-2"><div className="eyebrow mb-1">Evidence</div>
            {detail.evidence.length ? detail.evidence.map((e) => (
              <div key={e.id} className="sub2"><a href={`${BASE}/${detail.id}/evidence/${e.id}`} target="_blank" rel="noreferrer">{e.filename}</a> ({Math.ceil(e.size_bytes / 1024)} KB, {when(e.added_at)}{e.added_by ? `, ${e.added_by}` : ""})</div>
            )) : <div className="sub2">None attached.</div>}
            {detail.state === "PENDING_REVIEW" && mayPrepare ? (
              <div className="row row--tight mt-1" style={{ gap: 8, alignItems: "flex-end", flexWrap: "wrap" }}>
                <Field id="mc-file" label="Add evidence" hint="PDF, JPEG or PNG, up to 5 MB" error={file ? evidenceProblem(file) ?? undefined : undefined}>
                  <input id="mc-file" type="file" accept=".pdf,.jpg,.jpeg,.png" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
                </Field>
                <Btn kind="ghost" size="sm" disabled={!file || !!evidenceProblem(file)} busyLabel="Adding…" onClick={() => addEvidence()}>Add</Btn>
              </div>
            ) : null}
          </div>
          {detail.state === "PENDING_REVIEW" ? (
            <div className="mt-2">
              {detail.mayDecide ? (
                <Field id="mc-note" label="Note on the decision" hint="Required to reject (ten characters or more); kept with the decision">
                  <textarea id="mc-note" className="ctl" rows={2} maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} />
                </Field>
              ) : <div className="sub2">{me && detail.prepared_by === me ? "You prepared this correction: another officer decides it." : "Decided by another officer of the Academic Office or the Registry (the Director of ICT decides a legacy migration correction)."}</div>}
              {mayPrepare ? (
                <Field id="mc-cancel" label="To cancel it, say why" hint="Ten characters or more">
                  <input id="mc-cancel" className="ctl" value={cancelWhy} onChange={(e) => setCancelWhy(e.target.value)} maxLength={2000} />
                </Field>
              ) : null}
            </div>
          ) : null}
        </Modal>
      ) : null}
    </>
  );
}
