"use client";

/** One allocation (V261): the student with the photograph, the placing and every date of the stay; the porter's check-in with
 *  the condition of the room; a transfer to a named free bed; the checkout inspection; damage assessed and charged or waived;
 *  the clearance item by item, completed or reopened; a transfer request decided; the trail. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, Passport } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { ALLOC_STATE, CLEAR_STATE, TRANSFER_STATE, callHostel, dayOf, naira, whenAt, type FreeBed } from "@/lib/hostel";
import type { AllocationFull } from "./page";

const OFFICERS = ["services", "housing", "registrar", "admin", "super"];

export function Allocation({ a, session: s, office }: { a: AllocationFull; session: string; office: string | null }) {
  const router = useRouter();
  const may = !!office && OFFICERS.includes(office);
  const [busy, setBusy] = useState(false);
  const [ask, setAsk] = useState<"checkin" | "transfer" | "cancel" | "inspect" | "charge" | "item" | "decideTransfer" | null>(null);
  const [note, setNote] = useState("");
  const [cond, setCond] = useState("GOOD");
  const [beds, setBeds] = useState<FreeBed[]>([]);
  const [bed, setBed] = useState("");
  const [insp, setInsp] = useState({ condition: "GOOD", cleanliness: "CLEAN", damages: "", keysReturned: true, cardReturned: true, remarks: "" });
  const [charge, setCharge] = useState({ assetId: "", description: "", repairCost: "", replacementCost: "", charge: "" });
  const [item, setItem] = useState<{ id: string; label: string; state: string } | null>(null);
  const [transferReq, setTransferReq] = useState<{ id: string; decision: string } | null>(null);
  const live = !["LAPSED", "DECLINED", "CANCELLED", "TRANSFERRED", "CHECKED_OUT"].includes(a.state);
  const q = `?session=${encodeURIComponent(s)}`;
  const [s1, s2] = a.session.split("/");

  async function run<T>(p: Promise<{ ok: true; data: T } | { ok: false; problem: import("@/lib/api").Problem }>, done: string): Promise<T | null> {
    setBusy(true);
    try { const r = await p; if (!r.ok) { notifyProblem(r.problem); return null; } notify(done); setAsk(null); setNote(""); router.refresh(); return r.data; } finally { setBusy(false); }
  }
  async function loadBeds() { const r = await callHostel<FreeBed[]>("GET", `/hostel/sessions/${s1}/${s2}/free-beds${a.sex ? `?sex=${a.sex}` : ""}`, undefined, "Free beds for a transfer"); setBeds(r.ok ? r.data : []); }
  const checkin = () => run(callHostel("POST", `/hostel/allocations/${a.id}/checkin`, { note: note || null, condition: cond }, `Check in ${a.student_number} to ${a.hall_name} ${a.block}-${a.room_no}`), "Checked in");
  const transfer = () => { if (!bed || !note.trim()) { notifyProblem({ status: 422, title: "Choose the bed and say why." }); return; } return run<{ allocationId: string }>(callHostel("POST", `/hostel/allocations/${a.id}/transfer`, { bedId: bed, reason: note.trim() }, `Transfer ${a.student_number}: ${note.trim()}`), "Transferred; the student is told").then((r) => { if (r) router.push(`/hostel/allocations/${r.allocationId}${q}`); }); };
  const cancel = () => { if (!note.trim()) { notifyProblem({ status: 422, title: "Say why." }); return; } return run(callHostel("POST", `/hostel/allocations/${a.id}/cancel`, { reason: note.trim() }, `Cancel allocation ${a.reference_no}: ${note.trim()}`), "Allocation cancelled"); };
  const inspect = () => run(callHostel("POST", `/hostel/allocations/${a.id}/inspect`, { ...insp, damages: insp.damages || null, remarks: insp.remarks || null }, `Checkout inspection of ${a.reference_no}: ${insp.condition}`), "Inspection recorded; clearance opened");
  const raiseCharge = () => { if (!charge.description.trim() || charge.charge === "") { notifyProblem({ status: 422, title: "Say what was damaged and the charge." }); return; } return run(callHostel("POST", `/hostel/allocations/${a.id}/charge`, { assetId: charge.assetId || null, description: charge.description.trim(), repairCost: charge.repairCost ? Number(charge.repairCost) : null, replacementCost: charge.replacementCost ? Number(charge.replacementCost) : null, charge: Number(charge.charge) }, `Damage charge on ${a.reference_no}: ${charge.description.trim()}`), "Charge raised; the student is told"); };
  const waive = (id: string, reason: string) => run(callHostel("POST", `/hostel/charges/${id}/waive`, { reason }, `Waive a hostel damage charge: ${reason}`), "Charge waived");
  const startClearance = () => run(callHostel("POST", `/hostel/allocations/${a.id}/clearance`, {}, `Start hostel clearance for ${a.reference_no}`), "Clearance started");
  const decideItem = () => { if (!item) return; if (["NOT_CLEARED", "WAIVED"].includes(item.state) && !note.trim()) { notifyProblem({ status: 422, title: "Say why." }); return; } return run(callHostel("POST", `/hostel/clearance-items/${item.id}`, { state: item.state, remarks: note || null }, `Hostel clearance item ${item.label}: ${item.state}`), "Requirement updated"); };
  const complete = () => run<{ state: string }>(callHostel("POST", `/hostel/clearances/${a.clearance_id}/complete`, { note: note || null }, `Complete hostel clearance ${a.clearance_ref}`), "Clearance decided");
  const reopen = () => run(callHostel("POST", `/hostel/clearances/${a.clearance_id}/reopen`, { note: note || null }, `Reopen hostel clearance ${a.clearance_ref}`), "Clearance reopened");
  const decideTransfer = () => { if (!transferReq) return; if (transferReq.decision === "APPROVED" && !bed) { notifyProblem({ status: 422, title: "Choose the bed." }); return; } if (transferReq.decision === "REJECTED" && !note.trim()) { notifyProblem({ status: 422, title: "Say why." }); return; } return run<{ newAllocationId: string | null }>(callHostel("POST", `/hostel/transfers/${transferReq.id}`, { decision: transferReq.decision, bedId: bed || null, note: note || null }, `Transfer request ${transferReq.decision.toLowerCase()}`), `Transfer ${transferReq.decision.toLowerCase()}`).then((r) => { if (r?.newAllocationId) router.push(`/hostel/allocations/${r.newAllocationId}${q}`); }); };

  const pendingTransfer = a.transfers.find((t) => ["SUBMITTED", "UNDER_REVIEW"].includes(t.state));
  const chargesDue = a.charges.filter((c) => !c.settled_at && !c.waived_at).reduce((x, c) => x + Number(c.charge), 0);
  const allDecided = a.clearanceItems.length > 0 && a.clearanceItems.every((i) => i.state !== "PENDING");

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/hostel${q}`}>Accommodation</Link><span>›</span><Link className="lnk" href={`/hostel/occupancy${q}&view=students`}>Occupancy</Link><span>›</span><strong>{a.reference_no}</strong></div>
      <PageHead title={<>{a.student_name} <Pil kind={ALLOC_STATE[a.state]?.[1] ?? "grey"}>{ALLOC_STATE[a.state]?.[0] ?? a.state}</Pil></>} description={`${a.student_number} · ${a.programme ?? "—"} · ${a.department ?? "—"} · ${a.faculty ?? "—"} · ${a.level} Level · ${a.sex === "F" ? "Female" : a.sex === "M" ? "Male" : "—"}. Allocation ${a.reference_no} for ${a.session}: ${a.hall_name}, Block ${a.block}, floor ${a.floor}, Room ${a.room_no}, ${a.bed_label ?? `bed ${a.bed}`}.`}
        actions={<>
          {may && live && ["CONFIRMED", "ACCEPTED"].includes(a.state) ? <Btn kind="primary" onClick={() => { setNote(""); setCond("GOOD"); setAsk("checkin"); }}>Check in</Btn> : null}
          {may && live ? <Btn kind="secondary" onClick={() => { setNote(""); setBed(""); void loadBeds(); setAsk("transfer"); }}>Transfer</Btn> : null}
          {may && a.state === "CHECKED_IN" && !a.clearance_id ? <Btn kind="secondary" onClick={() => setAsk("inspect")}>Checkout inspection</Btn> : null}
          {may && a.state === "CHECKED_IN" ? <Btn kind="ghost" onClick={() => setAsk("charge")}>Raise a damage charge</Btn> : null}
          {may && live && a.state !== "CHECKED_IN" ? <Btn kind="ghost" onClick={() => { setNote(""); setAsk("cancel"); }}>Cancel</Btn> : null}
          <LinkBtn kind="ghost" href={`/hostel/students/${a.student_id}${q}`}>Accommodation history</LinkBtn>
        </>} />

      {a.state === "HELD" ? <Note kind="bad" title={`Held for payment until ${whenAt(a.held_until)}`}>The fee of {naira(a.fee)} is not yet confirmed; nobody checks in on a hold. Reference {a.reference ?? "not yet generated by the student"}.</Note> : null}
      {a.state === "CONFIRMED" && a.rules ? <Note kind="info" title="Paid; the student has not yet accepted under the rules">Check-in waits for the student&rsquo;s acknowledgement of the hostel rules on the portal.</Note> : null}
      {a.checkout_requested_at && a.state === "CHECKED_IN" ? <Note kind="info" title={`Checkout requested for ${dayOf(a.checkout_on)}`} action={may && !a.clearance_id ? <Btn kind="primary" onClick={() => setAsk("inspect")}>Inspect the room</Btn> : null}>{a.checkout_reason ?? "The student asks to leave."} The inspection opens the clearance; the bed is released when it completes.</Note> : null}
      {pendingTransfer ? <Note kind="info" title="A transfer request waits" action={may ? <span className="row row--inline row--tight"><Btn kind="primary" onClick={() => { setTransferReq({ id: pendingTransfer.id, decision: "APPROVED" }); setBed(""); setNote(""); void loadBeds(); setAsk("decideTransfer"); }}>Approve and move</Btn><Btn kind="ghost" onClick={() => { setTransferReq({ id: pendingTransfer.id, decision: "REJECTED" }); setNote(""); setAsk("decideTransfer"); }}>Reject</Btn></span> : null}>Asked for {pendingTransfer.requested_hall_name ?? "any hall"}{pendingTransfer.requested_type_label ? ` · ${pendingTransfer.requested_type_label}` : ""}: {pendingTransfer.reason}</Note> : null}
      {a.ended_reason ? <Note kind="info" title={`This stay ended: ${a.ended_reason}`}>{a.moved_from_ref ? `Moved from ${a.moved_from_ref}. ` : ""}The record is kept.</Note> : a.moved_from_ref ? <Note kind="info" title={`Moved here from ${a.moved_from_ref}`}>The earlier stay is on the history.</Note> : null}

      <div className="grid grid--2">
        <Panel title="The stay" right={a.application_ref}>
          <PBody>
            <div className="row row--top" style={{ gap: "var(--s-4)" }}>
              <Passport w={84} h={104} src={`/api/bff/api/v1/student/students/${a.student_id}/passport`} alt={a.student_name} />
              <div className="grow">
                <KvGrid cls="grid--2" pairs={[
                  ["Hostel", `${a.hall_name} (${a.hall_sex === "F" ? "female" : a.hall_sex === "M" ? "male" : "mixed"})`], ["Block · floor", `${a.block} · ${a.floor}`], ["Room", `${a.room_no}${a.room_type ? ` · ${a.room_type}` : ""}`], ["Bed", a.bed_label ?? `Bed ${a.bed}`],
                  ["Basis", a.basis === "PRIORITY" ? "Priority / manual" : a.basis === "RESERVE" ? `Waiting list, position ${a.draw_position}` : `Ballot, position ${a.draw_position}`], ["Allocated", whenAt(a.allocated_at)],
                  ["Fee", a.confirmed_at ? `${naira(a.fee)} paid ${dayOf(a.confirmed_at)}` : `${naira(a.fee)} unpaid`], ["Accepted", a.accepted_at ? `${dayOf(a.accepted_at)}${a.rules_version ? ` · rules v${a.rules_version}` : ""}` : "—"],
                  ["Checked in", a.checked_in_at ? `${whenAt(a.checked_in_at)}${a.checkin_note ? ` · ${a.checkin_note}` : ""}` : "—"], ["Checked out", a.checked_out_at ? whenAt(a.checked_out_at) : "—"],
                  ["Stay", `${dayOf(a.start_on)} – ${dayOf(a.end_on)}`], ["Student status", a.student_status.toLowerCase().replace("_", " ")],
                ]} />
                {a.category !== "NONE" ? <div className="sub2 mt-1">Priority category: {a.category} — {a.category_note}</div> : null}
                {a.special_need ? <div className="sub2">Special need: {a.special_need}</div> : null}
              </div>
            </div>
          </PBody>
        </Panel>
        <Panel title="Roommates" right={`${a.roommates.length} other(s) in the room`}>
          {a.roommates.length ? <DTable cols={["Bed|mid", "Name", "Number", "Programme", "Status|mid"]} rows={a.roommates.map((r) => [<span key="b" className="tnum">{r.bed ?? "—"}</span>, r.name, <span key="n" className="tnum sub2">{r.number}</span>, <span key="p" className="sub2">{r.programme ?? "—"}</span>, <Pil key="s" kind={ALLOC_STATE[r.state]?.[1] ?? "grey"}>{ALLOC_STATE[r.state]?.[0] ?? r.state}</Pil>])} /> : <PBody><div className="sub2">The other beds are free.</div></PBody>}
        </Panel>
      </div>

      {a.inspections.length ? (
        <Panel title="Inspections">
          <DTable cols={["When|mid", "Kind|mid", "Condition|mid", "Cleanliness|mid", "Keys|mid", "Card|mid", "Damages / remarks", "Officer"]} rows={a.inspections.map((i) => [<span key="w" className="tnum sub2">{whenAt(i.inspected_at)}</span>, <span key="k" className="sub2">{i.kind.toLowerCase()}</span>, <Pil key="c" kind={i.condition === "GOOD" ? "ok" : i.condition === "FAIR" ? "warn" : "bad"}>{i.condition.toLowerCase()}</Pil>, <span key="cl" className="sub2">{i.cleanliness?.toLowerCase() ?? "—"}</span>, <span key="ky">{i.keys_returned === null ? "—" : i.keys_returned ? "Yes" : "No"}</span>, <span key="cd">{i.card_returned === null ? "—" : i.card_returned ? "Yes" : "No"}</span>, <span key="d" className="sub2">{i.damages ?? ""}{i.remarks ? ` · ${i.remarks}` : ""}</span>, <span key="o" className="sub2">{i.officer ?? "—"}</span>])} />
        </Panel>
      ) : null}

      {a.charges.length || a.state === "CHECKED_IN" ? (
        <Panel title="Damage charges" right={chargesDue ? `${naira(chargesDue)} outstanding` : "Nothing outstanding"}>
          {a.charges.length ? <DTable cols={["Damage", "Asset|mid", "Repair|num", "Replacement|num", "Charge|num", "Reference|mid", "Status|mid", "|num"]} rows={a.charges.map((c) => [c.description, <span key="a" className="tnum sub2">{c.asset_tag ?? "—"}</span>, <span key="r" className="tnum">{c.repair_cost ? naira(c.repair_cost) : "—"}</span>, <span key="rp" className="tnum">{c.replacement_cost ? naira(c.replacement_cost) : "—"}</span>, <strong key="c" className="tnum">{naira(c.charge)}</strong>, <span key="rf" className="tnum sub2">{c.reference ?? "—"}</span>, <Pil key="s" kind={c.waived_at ? "info" : c.settled_at ? "ok" : "bad"}>{c.waived_at ? "Waived" : c.settled_at ? "Settled" : "Outstanding"}</Pil>, may && !c.settled_at && !c.waived_at ? <Btn key="w" kind="ghost" onClick={() => { const r = window.prompt("Reason for the waiver"); if (r && r.trim()) void waive(c.id, r.trim()); }}>Waive</Btn> : <span key="w" className="sub2">{c.waived_reason ?? ""}</span>])} /> : <PBody><div className="sub2">No damage charge raised.</div></PBody>}
        </Panel>
      ) : null}

      {a.clearance_id ? (
        <Panel title={`Hostel clearance ${a.clearance_ref}`} right={<span className="row row--inline row--tight"><Pil kind={CLEAR_STATE[a.clearance_state ?? "PENDING"]?.[1] ?? "grey"}>{CLEAR_STATE[a.clearance_state ?? "PENDING"]?.[0] ?? a.clearance_state}</Pil>{may && a.clearance_state === "PENDING" ? <Btn kind="primary" onClick={() => void complete()} disabled={busy || !allDecided} title={allDecided ? undefined : "Every requirement must be decided first"}>Complete clearance</Btn> : null}{may && a.clearance_state === "NOT_CLEARED" ? <Btn kind="secondary" onClick={() => void reopen()} disabled={busy}>Reopen</Btn> : null}</span>}>
          <DTable cols={["Requirement", "Status|mid", "Officer", "Decided|mid", "Remarks", "|num"]} rows={a.clearanceItems.map((i) => [i.label, <Pil key="s" kind={CLEAR_STATE[i.state]?.[1] ?? "grey"}>{CLEAR_STATE[i.state]?.[0] ?? i.state}</Pil>, <span key="o" className="sub2">{i.officer ?? "—"}</span>, <span key="d" className="tnum sub2">{i.decided_at ? dayOf(i.decided_at) : "—"}</span>, <span key="r" className="sub2">{i.remarks ?? ""}</span>, may && a.clearance_state !== "CLEARED" ? <span key="a" className="row row--inline row--tight"><Btn kind="ghost" onClick={() => { setItem({ id: i.id, label: i.label, state: "CLEARED" }); setNote(""); setAsk("item"); }}>Clear</Btn><Btn kind="ghost" onClick={() => { setItem({ id: i.id, label: i.label, state: "NOT_CLEARED" }); setNote(""); setAsk("item"); }}>Hold</Btn><Btn kind="ghost" onClick={() => { setItem({ id: i.id, label: i.label, state: "WAIVED" }); setNote(""); setAsk("item"); }}>Waive</Btn><Btn kind="ghost" onClick={() => { setItem({ id: i.id, label: i.label, state: "NOT_APPLICABLE" }); setNote(""); setAsk("item"); }}>N/A</Btn></span> : <span key="a" />])} />
          {a.clearance_state === "CLEARED" ? <PBody><div className="sub2">Completed {whenAt(a.clearance_completed_at)}; the bed was released and the hostel unit of the graduation clearance signed.</div></PBody> : null}
        </Panel>
      ) : a.state === "CHECKED_IN" && may ? <Note kind="info" title="No clearance yet" action={<Btn kind="ghost" onClick={() => void startClearance()} disabled={busy}>Start clearance without inspection</Btn>}>The checkout inspection opens the clearance with the requirements it answers; the rest are cleared one by one.</Note> : null}

      {a.transfers.length ? (
        <Panel title="Transfer requests">
          <DTable cols={["Submitted|mid", "Asked for", "Reason", "Status|mid", "Decision"]} rows={a.transfers.map((t) => [<span key="s" className="tnum sub2">{dayOf(t.submitted_at)}</span>, <span key="a">{t.requested_hall_name ?? "Any hall"}{t.requested_type_label ? ` · ${t.requested_type_label}` : ""}</span>, t.reason, <Pil key="st" kind={TRANSFER_STATE[t.state]?.[1] ?? "grey"}>{TRANSFER_STATE[t.state]?.[0] ?? t.state}</Pil>, <span key="d" className="sub2">{t.decision_note ?? ""}</span>])} />
        </Panel>
      ) : null}

      <Panel title="Trail" right={`${a.events.length} event(s)`}>
        {a.events.length ? <DTable cols={["When|mid", "What", "Note", "By"]} rows={a.events.map((e) => [<span key="w" className="tnum sub2">{whenAt(e.at)}</span>, <span key="a">{e.action.replace(/_/g, " ").toLowerCase()}{e.from_value || e.to_value ? <span className="sub2"> · {e.from_value ?? "—"} → {e.to_value ?? "—"}</span> : null}</span>, <span key="n" className="sub2">{e.note ?? ""}</span>, <span key="b" className="sub2">{e.actor ?? e.actor_office ?? "portal"}</span>])} pageSize={15} /> : <PBody><div className="sub2">Nothing on the trail.</div></PBody>}
      </Panel>

      {ask === "checkin" ? (
        <Modal title={`Check in ${a.student_name}`} sub={`${a.hall_name} · Block ${a.block} · Room ${a.room_no} · ${a.bed_label ?? `bed ${a.bed}`}`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void checkin()} disabled={busy}>Confirm check-in</Btn></>}>
          <p>Confirm the student&rsquo;s identity against the photograph and the allocation letter, then record the condition of the room and its assets as handed over.</p>
          <div className="grid grid--2">
            <Field id="ci-cond" label="Condition of room and assets"><select id="ci-cond" className="ctl" value={cond} onChange={(e) => setCond(e.target.value)}><option value="GOOD">Good</option><option value="FAIR">Fair</option><option value="DAMAGED">Damaged (note what)</option></select></Field>
            <Field id="ci-note" label="Remarks"><input id="ci-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          </div>
        </Modal>
      ) : ask === "transfer" ? (
        <Modal title={`Transfer ${a.student_name}`} sub="The current stay closes and a new allocation opens; the history keeps both" onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void transfer()} disabled={busy || !bed || !note.trim()}>Move the student</Btn></>}>
          <Field id="tr-bed" label="Free bed" required full><select id="tr-bed" className="ctl" value={bed} onChange={(e) => setBed(e.target.value)}><option value="">{beds.length ? "Choose a bed" : "Reading free beds…"}</option>{beds.map((b) => <option key={b.bed_id} value={b.bed_id}>{b.hall_name} · {b.block}-{b.room_no} · bed {b.bed}{b.room_type_label ? ` · ${b.room_type_label}` : ""}</option>)}</select></Field>
          <Field id="tr-note" label="Reason" required full><textarea id="tr-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : ask === "cancel" ? (
        <Modal title={`Cancel allocation ${a.reference_no}`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Keep it</Btn><Btn kind="urgent" onClick={() => void cancel()} disabled={busy || !note.trim()}>Cancel the allocation</Btn></>}>
          <p>The bed is released and the student told. A student checked in leaves through inspection and clearance instead.</p>
          <Field id="cn-note" label="Reason" required full><textarea id="cn-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : ask === "inspect" ? (
        <Modal title="Checkout inspection" sub={`${a.hall_name} · ${a.block}-${a.room_no} · ${a.bed_label ?? ""}`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void inspect()} disabled={busy}>Record and open clearance</Btn></>}>
          <div className="grid grid--2">
            <Field id="in-cond" label="Room, bed, furniture and assets"><select id="in-cond" className="ctl" value={insp.condition} onChange={(e) => setInsp({ ...insp, condition: e.target.value })}><option value="GOOD">Good</option><option value="FAIR">Fair</option><option value="DAMAGED">Damaged</option></select></Field>
            <Field id="in-clean" label="Cleanliness"><select id="in-clean" className="ctl" value={insp.cleanliness} onChange={(e) => setInsp({ ...insp, cleanliness: e.target.value })}><option value="CLEAN">Clean</option><option value="ACCEPTABLE">Acceptable</option><option value="DIRTY">Dirty</option></select></Field>
            <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={insp.keysReturned} onChange={(e) => setInsp({ ...insp, keysReturned: e.target.checked })} /> Keys returned</label>
            <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={insp.cardReturned} onChange={(e) => setInsp({ ...insp, cardReturned: e.target.checked })} /> Access card returned</label>
            <Field id="in-dam" label="Damages found" full><textarea id="in-dam" className="ctl" rows={2} value={insp.damages} onChange={(e) => setInsp({ ...insp, damages: e.target.value })} placeholder="Assets damaged, what and how — a charge is raised separately" /></Field>
            <Field id="in-rem" label="Remarks" full><input id="in-rem" className="ctl" value={insp.remarks} onChange={(e) => setInsp({ ...insp, remarks: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : ask === "charge" ? (
        <Modal title="Damage assessment and charge" onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void raiseCharge()} disabled={busy}>Raise the charge</Btn></>}>
          <p>A charge above zero becomes a payment reference on the student&rsquo;s fees page; clearance completes when it is settled or waived. Zero records the damage without a charge.</p>
          <div className="grid grid--2">
            <Field id="ch-asset" label="Asset"><select id="ch-asset" className="ctl" value={charge.assetId} onChange={(e) => setCharge({ ...charge, assetId: e.target.value })}><option value="">Not a tagged asset</option>{a.assets.map((x) => <option key={x.id} value={x.id}>{x.tag} · {x.kind} ({x.condition.toLowerCase()})</option>)}</select></Field>
            <Field id="ch-desc" label="Damage" required><input id="ch-desc" className="ctl" value={charge.description} onChange={(e) => setCharge({ ...charge, description: e.target.value })} /></Field>
            <Field id="ch-rep" label="Estimated repair cost (₦)"><input id="ch-rep" type="number" min={0} className="ctl" value={charge.repairCost} onChange={(e) => setCharge({ ...charge, repairCost: e.target.value })} /></Field>
            <Field id="ch-rpl" label="Replacement cost (₦)"><input id="ch-rpl" type="number" min={0} className="ctl" value={charge.replacementCost} onChange={(e) => setCharge({ ...charge, replacementCost: e.target.value })} /></Field>
            <Field id="ch-chg" label="Charge to the student (₦)" required><input id="ch-chg" type="number" min={0} className="ctl" value={charge.charge} onChange={(e) => setCharge({ ...charge, charge: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : ask === "item" && item ? (
        <Modal title={`${item.label}: ${CLEAR_STATE[item.state]?.[0] ?? item.state}`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void decideItem()} disabled={busy}>Save</Btn></>}>
          <Field id="it-note" label="Remarks" required={["NOT_CLEARED", "WAIVED"].includes(item.state)} full><textarea id="it-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : ask === "decideTransfer" && transferReq ? (
        <Modal title={transferReq.decision === "APPROVED" ? "Approve the transfer and move the student" : "Reject the transfer request"} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind={transferReq.decision === "APPROVED" ? "primary" : "urgent"} onClick={() => void decideTransfer()} disabled={busy}>Confirm</Btn></>}>
          {transferReq.decision === "APPROVED" ? <Field id="dt-bed" label="Bed to move to" required full><select id="dt-bed" className="ctl" value={bed} onChange={(e) => setBed(e.target.value)}><option value="">{beds.length ? "Choose a bed" : "Reading free beds…"}</option>{beds.map((b) => <option key={b.bed_id} value={b.bed_id}>{b.hall_name} · {b.block}-{b.room_no} · bed {b.bed}{b.room_type_label ? ` · ${b.room_type_label}` : ""}</option>)}</select></Field> : null}
          <Field id="dt-note" label={transferReq.decision === "APPROVED" ? "Note" : "Reason"} required={transferReq.decision !== "APPROVED"} full><textarea id="dt-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
