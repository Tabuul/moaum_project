"use client";

/** Hostel discipline and room swaps (V291). The incidents of the session, each with the student's own account, the sanction
 *  decided and its appeal; the Dean decides a warning, a fine paid through the Bursary, loss of accommodation (a stay not begun
 *  cancelled, a stay checked in given notice to vacate, a bar until a date) or another measure, dismisses with a reason, and
 *  answers appeals. The housing desk reports incidents but does not sanction. The swaps tab holds the exchanges of beds two
 *  students have agreed; approved, both beds move at once. Every rule is the database's; this page carries the words. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, PageHead, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import {
  APPEAL_STATE, HOSTEL_OFFICERS, INCIDENT_STATE, SANCTION_KINDS, SANCTION_LABEL, SWAP_STATE, callHostel, dayOf, naira, whenAt,
  type DisciplineData, type IncidentRow, type SanctionRow, type SwapRow,
} from "@/lib/hostel";

/** who decides a sanction, an appeal or a waiver: the Dean and those above, not the housing desk */
const DECIDERS = ["dsa", "services", "registrar", "admin", "super"];

function sanctionLine(x: SanctionRow): string {
  const what = x.kind === "FINE" ? `${SANCTION_LABEL.FINE} ${naira(x.amount)}${x.settled_at ? " · paid" : x.waived_at ? " · waived" : " · unpaid"}`
    : x.kind === "EVICTION" ? `${SANCTION_LABEL.EVICTION}${x.barred_until ? ` · barred to ${dayOf(x.barred_until)}` : ""}`
    : SANCTION_LABEL[x.kind] ?? x.kind;
  return `${x.reference} · ${what}${x.state === "QUASHED" ? " · quashed" : ""}${x.appeal_state === "LODGED" ? " · appeal lodged" : ""}`;
}

export function Discipline({ data, swaps, session: s, sessions, state, tab, office }: { data: DisciplineData; swaps: SwapRow[]; session: string; sessions: string[]; state: string; tab: string; office: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const mayReport = !!office && HOSTEL_OFFICERS.includes(office);
  const mayDecide = !!office && DECIDERS.includes(office);
  const [s1, s2] = s.split("/");
  const [busy, setBusy] = useState(false);
  const [report, setReport] = useState<null | { studentNumber: string; kind: string; occurredAt: string; place: string; description: string; witnesses: string }>(null);
  const [openId, setOpenId] = useState<string | null>(null);
  const [decide, setDecide] = useState({ kind: "WARNING", amount: "", barredUntil: "", vacateBy: "", reason: "", dismissNote: "" });
  const [appeal, setAppeal] = useState<null | { id: string; reference: string; kind: string; decision: string; amount: string; barredUntil: string; note: string }>(null);
  const [waive, setWaive] = useState<null | { id: string; reference: string; reason: string }>(null);
  const [swapAct, setSwapAct] = useState<null | { id: string; reference: string; decision: "APPROVED" | "REJECTED"; note: string }>(null);
  const open = data.incidents.find((i) => i.incident_id === openId) ?? null;
  const go = (next: { state?: string; tab?: string }) => { const qs = new URLSearchParams(); qs.set("session", s); const f = { state, tab, ...next }; for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/hostel/discipline?${qs}`); };

  async function run<T>(method: "POST" | "PUT", path: string, body: unknown, reason: string, done: string): Promise<T | null> {
    setBusy(true);
    try {
      const r = await callHostel<T>(method, path, body, reason);
      if (!r.ok) { notifyProblem(r.problem); return null; }
      notify(done); router.refresh(); return r.data;
    } finally { setBusy(false); }
  }

  async function submitReport() {
    if (!report) return;
    const r = await run<{ reference: string }>("POST", `/hostel/sessions/${s1}/${s2}/incidents`, {
      studentNumber: report.studentNumber.trim(), kind: report.kind, occurredAt: report.occurredAt || null, place: report.place.trim() || null, description: report.description.trim(), witnesses: report.witnesses.trim() || null,
    }, `Hostel incident reported against ${report.studentNumber.trim()}`, "Incident reported; the student is told and may answer it.");
    if (r) setReport(null);
  }
  async function sanction(i: IncidentRow) {
    const r = await run("POST", `/hostel/incidents/${i.incident_id}/sanction`, {
      kind: decide.kind, amount: decide.kind === "FINE" ? Number(decide.amount) : null, barredUntil: decide.kind === "EVICTION" && decide.barredUntil ? decide.barredUntil : null,
      vacateBy: decide.kind === "EVICTION" && decide.vacateBy ? decide.vacateBy : null, reason: decide.reason.trim(),
    }, `Hostel sanction on ${i.reference}: ${decide.kind.toLowerCase()}`, "Sanction decided; the student is told and may appeal.");
    if (r) setDecide({ kind: "WARNING", amount: "", barredUntil: "", vacateBy: "", reason: "", dismissNote: "" });
  }
  async function dismiss(i: IncidentRow) {
    const r = await run("POST", `/hostel/incidents/${i.incident_id}/dismiss`, { note: decide.dismissNote.trim() }, `Hostel incident ${i.reference} dismissed`, "Incident dismissed.");
    if (r) { setDecide({ ...decide, dismissNote: "" }); setOpenId(null); }
  }
  async function decideAppeal() {
    if (!appeal) return;
    const r = await run("POST", `/hostel/sanctions/${appeal.id}/appeal-decision`, {
      decision: appeal.decision, amount: appeal.decision === "VARIED" && appeal.kind === "FINE" ? Number(appeal.amount) : null,
      barredUntil: appeal.decision === "VARIED" && appeal.kind === "EVICTION" ? appeal.barredUntil || null : null, note: appeal.note.trim(),
    }, `Appeal against ${appeal.reference} ${appeal.decision.toLowerCase()}`, `Appeal ${appeal.decision.toLowerCase()}; the student is told.`);
    if (r) setAppeal(null);
  }
  async function waiveFine() {
    if (!waive) return;
    const r = await run("POST", `/hostel/sanctions/${waive.id}/waive`, { reason: waive.reason.trim() }, `Hostel fine ${waive.reference} waived`, "Fine waived.");
    if (r) setWaive(null);
  }
  async function decideSwap() {
    if (!swapAct) return;
    const r = await run("POST", `/hostel/swaps/${swapAct.id}/decide`, { decision: swapAct.decision, note: swapAct.note.trim() || null },
      `Room swap ${swapAct.reference} ${swapAct.decision.toLowerCase()}`, swapAct.decision === "APPROVED" ? "Swap approved; both beds have moved." : "Swap not approved; both students are told.");
    if (r) setSwapAct(null);
  }

  const HEAD = ["S/N", "Reference", "Student ID", "Student Name", "Hostel", "Room", "Incident", "Occurred", "Reported by", "Status", "Sanctions", "Student's account"];
  const sorted = [...data.incidents].sort((a, b) => b.reported_at.localeCompare(a.reported_at));
  const body = () => sorted.map((i, n) => [n + 1, i.reference, i.student_number ?? "", i.student_name, i.hall_name ?? "", i.room_no ? `${i.block}-${i.room_no}` : "", i.kind_label, dayOf(i.occurred_at), i.reported_by || (i.reported_office ?? ""),
    INCIDENT_STATE[i.state]?.[0] ?? i.state, i.sanctions.map(sanctionLine).join("; "), i.statement ?? ""]);
  async function excel() { const blob = await brandedXlsx("Hostel Discipline Register", HEAD, body(), { sheetName: "Discipline", serial: docSerial("HST"), sub: s }); downloadBlob(blob, `hostel-discipline-${s.replace("/", "-")}.xlsx`); }
  const waiting = swaps.filter((w) => w.state === "AGREED").length;

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/hostel?session=${encodeURIComponent(s)}`}>Accommodation</Link><span>›</span><strong>Discipline &amp; room swaps</strong></div>
      <PageHead title="Discipline and room swaps" description={`${s}. An incident is reported, the student answers it, the Dean decides; a sanction is appealed once. A swap moves only when both students agree and the Dean approves.`}
        actions={<>
          <Field id="dc-session" label="Session"><select id="dc-session" className="ctl" value={s} onChange={(e) => queryNav(`/hostel/discipline?session=${encodeURIComponent(e.target.value)}&tab=${tab}`)}>{(sessions.includes(s) ? sessions : [s, ...sessions]).map((x) => <option key={x} value={x}>{x}</option>)}</select></Field>
          {tab === "incidents" ? <><Btn kind="ghost" onClick={() => void excel()} disabled={!sorted.length}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Hostel Discipline Register", s, HEAD, body(), docSerial("HST"))} disabled={!sorted.length}>PDF</Btn></> : null}
          {mayReport ? <Btn kind="primary" onClick={() => setReport({ studentNumber: "", kind: data.kinds.find((k) => k.active)?.code ?? "OTHER", occurredAt: "", place: "", description: "", witnesses: "" })}>Report an incident</Btn> : null}
        </>} />
      <Tiles items={[
        ["AWAITING DECISION", data.counts.reported, data.counts.reported ? "var(--red-ink)" : null, "Reported, not yet sanctioned or dismissed"],
        ["APPEALS WAITING", data.counts.appeals_waiting, data.counts.appeals_waiting ? "var(--red-ink)" : null, "Lodged by students, for the Dean"],
        ["FINES OUTSTANDING", naira(data.counts.fines_outstanding), null, "Unpaid and not waived; they bar the next bed where hostel debt is refused"],
        ["SWAPS TO APPROVE", waiting, waiting ? "var(--red-ink)" : null, `${data.counts.barred} student(s) barred from a bed`],
      ]} />
      <Tabs value={tab} onChange={(t) => go({ tab: t })} items={[{ id: "incidents", label: `Incidents (${data.incidents.length})` }, { id: "swaps", label: `Room swaps (${swaps.length})` }]} />

      {tab === "incidents" ? (
        <>
          <div className="scope">
            <div className="scope__f"><Field id="dc-state" label="Status"><select id="dc-state" className="ctl" value={state} onChange={(e) => go({ state: e.target.value })}><option value="">Every incident</option><option value="REPORTED">Awaiting decision</option><option value="SANCTIONED">Sanctioned</option><option value="DISMISSED">Dismissed</option></select></Field></div>
          </div>
          <Panel title={`${sorted.length} incident(s)`} right="Newest first">
            {sorted.length ? <DTable cols={["S/N|num", "Reference|mid", "Student", "Where", "Incident", "Occurred|mid", "Status|mid", "Sanctions", "|num"]}
              texts={sorted.map((i) => `${i.reference} ${i.student_name} ${i.student_number ?? ""} ${i.kind_label} ${i.hall_name ?? ""}`)}
              rows={sorted.map((i, n) => [
                <span key="sn" className="tnum sub2">{n + 1}</span>, <span key="r" className="tnum">{i.reference}</span>,
                <span key="s"><strong>{i.student_name}</strong><div className="sub2 tnum">{i.student_number}{i.prior_incidents ? ` · ${i.prior_incidents} earlier` : ""}</div></span>,
                <span key="w">{i.hall_name ?? "—"}<div className="sub2">{i.room_no ? `${i.block}-${i.room_no}` : "no stay this session"}{i.place ? ` · ${i.place}` : ""}</div></span>,
                <span key="k">{i.kind_label}<div className="sub2">{i.statement ? "Student has answered" : "No answer yet"}</div></span>,
                <span key="o" className="tnum sub2">{whenAt(i.occurred_at)}</span>,
                <Pil key="st" kind={INCIDENT_STATE[i.state]?.[1] ?? "grey"}>{INCIDENT_STATE[i.state]?.[0] ?? i.state}</Pil>,
                <span key="sa" className="sub2">{i.sanctions.length ? i.sanctions.map(sanctionLine).join("; ") : "—"}</span>,
                <Btn key="op" kind={i.state === "REPORTED" || i.sanctions.some((x) => x.appeal_state === "LODGED") ? "primary" : "ghost"} onClick={() => setOpenId(i.incident_id)}>{i.state === "REPORTED" ? "Decide" : "Open"}</Btn>,
              ])} /> : <PBody><div className="sub2">No incident{state ? " in that state" : ""} for {s}.</div></PBody>}
          </Panel>
        </>
      ) : (
        <Panel title={`${swaps.length} swap request(s)`} right="Waiting for the Dean first">
          {swaps.length ? <DTable cols={["Reference|mid", "Proposed by", "Their bed", "With", "Their bed", "Reason", "Status|mid", "|num"]}
            texts={swaps.map((w) => `${w.reference} ${w.student_name} ${w.partner_name}`)}
            rows={swaps.map((w) => [
              <span key="r" className="tnum">{w.reference}<div className="sub2">{dayOf(w.proposed_at)}</div></span>,
              <span key="a"><strong>{w.student_name}</strong><div className="sub2 tnum">{w.student_number}</div></span>, <span key="ab" className="sub2">{w.student_room} · {w.student_bed ?? ""}</span>,
              <span key="b"><strong>{w.partner_name}</strong><div className="sub2 tnum">{w.partner_number}</div></span>, <span key="bb" className="sub2">{w.partner_room} · {w.partner_bed ?? ""}</span>,
              <span key="why" className="sub2">{w.reason}{w.partner_note ? ` · reply: ${w.partner_note}` : ""}{w.decision_note ? ` · decision: ${w.decision_note}` : ""}</span>,
              <Pil key="st" kind={SWAP_STATE[w.state]?.[1] ?? "grey"}>{SWAP_STATE[w.state]?.[0] ?? w.state}</Pil>,
              w.state === "AGREED" && mayReport ? <span key="act" className="row row--inline row--tight"><Btn kind="primary" onClick={() => setSwapAct({ id: w.id, reference: w.reference, decision: "APPROVED", note: "" })}>Approve</Btn><Btn kind="ghost" onClick={() => setSwapAct({ id: w.id, reference: w.reference, decision: "REJECTED", note: "" })}>Refuse</Btn></span> : <span key="act" />,
            ])} /> : <PBody><div className="sub2">No swap has been proposed for {s}. A student proposes one from their Hostel page, naming the other student; the other agrees; it then waits here.</div></PBody>}
        </Panel>
      )}

      {report ? (
        <Modal title="Report a hostel incident" sub={`${s} · the student is told and may give their own account before any decision`} onClose={() => setReport(null)} wide
          foot={<><Btn kind="ghost" onClick={() => setReport(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || !report.studentNumber.trim() || !report.description.trim()} onClick={() => void submitReport()}>{busy ? "Reporting…" : "Report"}</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="ir-no" label="Student number"><input id="ir-no" className="ctl tnum" value={report.studentNumber} onChange={(e) => setReport({ ...report, studentNumber: e.target.value })} placeholder="Matriculation or admission number" /></Field>
            <Field id="ir-kind" label="Incident"><select id="ir-kind" className="ctl" value={report.kind} onChange={(e) => setReport({ ...report, kind: e.target.value })}>{data.kinds.filter((k) => k.active).map((k) => <option key={k.code} value={k.code}>{k.label}</option>)}</select></Field>
            <Field id="ir-when" label="When it happened" hint="Blank: now"><input id="ir-when" type="datetime-local" className="ctl" value={report.occurredAt} onChange={(e) => setReport({ ...report, occurredAt: e.target.value })} /></Field>
            <Field id="ir-place" label="Where"><input id="ir-place" className="ctl" value={report.place} onChange={(e) => setReport({ ...report, place: e.target.value })} placeholder="Room, corridor, common room" /></Field>
            <Field id="ir-desc" label="What happened, as it will read in the record" full><textarea id="ir-desc" className="ctl" rows={4} value={report.description} onChange={(e) => setReport({ ...report, description: e.target.value })} /></Field>
            <Field id="ir-wit" label="Witnesses" hint="Seen by the desk and the Dean, never by the student" full><input id="ir-wit" className="ctl" value={report.witnesses} onChange={(e) => setReport({ ...report, witnesses: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}

      {open ? (
        <Modal title={`${open.reference} · ${open.kind_label}`} sub={`${open.student_name} (${open.student_number ?? ""}) · ${INCIDENT_STATE[open.state]?.[0] ?? open.state}`} onClose={() => setOpenId(null)} wide
          foot={<Btn kind="ghost" onClick={() => setOpenId(null)}>Close</Btn>}>
          <PBody>
            <div className="sub2">Occurred {whenAt(open.occurred_at)}{open.place ? ` · ${open.place}` : ""}{open.hall_name ? ` · ${open.hall_name}${open.room_no ? ` ${open.block}-${open.room_no}` : ""}` : ""} · reported {whenAt(open.reported_at)} by {open.reported_by || open.reported_office || "the desk"}{open.prior_incidents ? ` · ${open.prior_incidents} earlier incident(s) against this student` : ""}</div>
            <p>{open.description}</p>
            {open.witnesses ? <div className="sub2">Witnesses: {open.witnesses}</div> : null}
          </PBody>
          <Note kind={open.statement ? "info" : "bad"} title={open.statement ? `The student's account (${whenAt(open.statement_at)})` : "The student has not answered yet"}>{open.statement ?? "The student was told when the incident was reported and may answer from their Hostel page. A decision need not wait for it, but reads better with it."}</Note>
          {open.decision_note && open.state === "DISMISSED" ? <Note kind="ok" title="Dismissed">{open.decision_note}</Note> : null}
          {open.sanctions.map((x) => (
            <Note key={x.id} kind={x.state === "QUASHED" ? "ok" : "info"} title={`${x.reference} · ${SANCTION_LABEL[x.kind] ?? x.kind}${x.state === "QUASHED" ? " · quashed" : ""}`}
              action={<span className="row row--inline row--tight">
                {mayDecide && x.appeal_state === "LODGED" ? <Btn kind="primary" onClick={() => setAppeal({ id: x.id, reference: x.reference, kind: x.kind, decision: "UPHELD", amount: String(x.amount ?? ""), barredUntil: x.barred_until ?? "", note: "" })}>Decide the appeal</Btn> : null}
                {mayDecide && x.kind === "FINE" && x.state === "IN_FORCE" && !x.settled_at && !x.waived_at ? <Btn kind="ghost" onClick={() => setWaive({ id: x.id, reference: x.reference, reason: "" })}>Waive</Btn> : null}
              </span>}>
              {x.reason}. {x.effect ?? ""}.{x.appeal_state ? ` ${APPEAL_STATE[x.appeal_state]?.[0] ?? x.appeal_state}${x.appeal_ground ? `: “${x.appeal_ground}”` : ""}${x.appeal_note ? ` — ${x.appeal_note}` : ""}.` : ` Appeal open to ${dayOf(x.appeal_by)}.`}
            </Note>
          ))}
          {mayDecide && open.state !== "DISMISSED" ? (
            <Panel title={open.sanctions.length ? "Add a sanction" : "Decide"}>
              <PBody>
                <div className="grid grid--2 rfgrid">
                  <Field id="dc-kind" label="Sanction"><select id="dc-kind" className="ctl" value={decide.kind} onChange={(e) => setDecide({ ...decide, kind: e.target.value })}>{SANCTION_KINDS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
                  {decide.kind === "FINE" ? <Field id="dc-amt" label="Fine (₦)"><input id="dc-amt" type="number" min={1} className="ctl tnum" value={decide.amount} onChange={(e) => setDecide({ ...decide, amount: e.target.value })} /></Field> : <span />}
                  {decide.kind === "EVICTION" ? <>
                    <Field id="dc-vac" label="Vacate by" hint="A student checked in leaves through inspection and clearance; blank: today"><input id="dc-vac" type="date" className="ctl" value={decide.vacateBy} onChange={(e) => setDecide({ ...decide, vacateBy: e.target.value })} /></Field>
                    <Field id="dc-bar" label="Barred from a bed until" hint="Blank: the end of the session"><input id="dc-bar" type="date" className="ctl" value={decide.barredUntil} onChange={(e) => setDecide({ ...decide, barredUntil: e.target.value })} /></Field>
                  </> : null}
                  <Field id="dc-why" label="Reason, as the student will read it" full><input id="dc-why" className="ctl" value={decide.reason} onChange={(e) => setDecide({ ...decide, reason: e.target.value })} /></Field>
                </div>
                <div className="row row--tight mt-2"><Btn kind="primary" disabled={busy || !decide.reason.trim() || (decide.kind === "FINE" && !(Number(decide.amount) > 0))} onClick={() => void sanction(open)}>Decide the sanction</Btn></div>
                {open.state === "REPORTED" ? (
                  <div className="grid grid--2 rfgrid mt-2">
                    <Field id="dc-dis" label="Or dismiss it, saying why" full><input id="dc-dis" className="ctl" value={decide.dismissNote} onChange={(e) => setDecide({ ...decide, dismissNote: e.target.value })} /></Field>
                    <div><Btn kind="ghost" disabled={busy || !decide.dismissNote.trim()} onClick={() => void dismiss(open)}>Dismiss the incident</Btn></div>
                  </div>
                ) : null}
              </PBody>
            </Panel>
          ) : null}
        </Modal>
      ) : null}

      {appeal ? (
        <Modal title={`Appeal against ${appeal.reference}`} sub={SANCTION_LABEL[appeal.kind] ?? appeal.kind} onClose={() => setAppeal(null)}
          foot={<><Btn kind="ghost" onClick={() => setAppeal(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || !appeal.note.trim()} onClick={() => void decideAppeal()}>Decide</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="ap-dec" label="Decision"><select id="ap-dec" className="ctl" value={appeal.decision} onChange={(e) => setAppeal({ ...appeal, decision: e.target.value })}><option value="UPHELD">Upheld — the sanction stands</option>{appeal.kind === "FINE" || appeal.kind === "EVICTION" ? <option value="VARIED">Varied</option> : null}<option value="QUASHED">Quashed — the sanction is lifted</option></select></Field>
            {appeal.decision === "VARIED" && appeal.kind === "FINE" ? <Field id="ap-amt" label="The fine becomes (₦)"><input id="ap-amt" type="number" min={0} className="ctl tnum" value={appeal.amount} onChange={(e) => setAppeal({ ...appeal, amount: e.target.value })} /></Field> : null}
            {appeal.decision === "VARIED" && appeal.kind === "EVICTION" ? <Field id="ap-bar" label="The bar runs to"><input id="ap-bar" type="date" className="ctl" value={appeal.barredUntil} onChange={(e) => setAppeal({ ...appeal, barredUntil: e.target.value })} /></Field> : null}
            <Field id="ap-note" label="Reason, as the student will read it" full><input id="ap-note" className="ctl" value={appeal.note} onChange={(e) => setAppeal({ ...appeal, note: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}

      {waive ? (
        <Modal title={`Waive fine ${waive.reference}`} onClose={() => setWaive(null)}
          foot={<><Btn kind="ghost" onClick={() => setWaive(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || !waive.reason.trim()} onClick={() => void waiveFine()}>Waive</Btn></>}>
          <Field id="wv-why" label="Reason" full><input id="wv-why" className="ctl" value={waive.reason} onChange={(e) => setWaive({ ...waive, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}

      {swapAct ? (
        <Modal title={`${swapAct.decision === "APPROVED" ? "Approve" : "Refuse"} swap ${swapAct.reference}`} sub={swapAct.decision === "APPROVED" ? "Every rule is checked again; both beds move at once and both students are told." : "Both students are told why."} onClose={() => setSwapAct(null)}
          foot={<><Btn kind="ghost" onClick={() => setSwapAct(null)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || (swapAct.decision === "REJECTED" && !swapAct.note.trim())} onClick={() => void decideSwap()}>{swapAct.decision === "APPROVED" ? "Approve the swap" : "Refuse the swap"}</Btn></>}>
          <Field id="sw-note" label={swapAct.decision === "APPROVED" ? "Note (optional)" : "Reason"} full><input id="sw-note" className="ctl" value={swapAct.note} onChange={(e) => setSwapAct({ ...swapAct, note: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
