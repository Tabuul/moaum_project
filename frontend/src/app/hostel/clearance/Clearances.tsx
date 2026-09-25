"use client";

/** Checkout and clearance (V261): every clearance of the session with what is outstanding, names A–Z; the checkouts requested
 *  and awaiting inspection; the transfer requests; the maintenance queue assigned, fixed and closed. Each row opens the allocation. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { CLEAR_STATE, MAINT_CATS, TRANSFER_STATE, callHostel, dayOf, naira, whenAt, type BedRow, type ClearanceRow, type Maintenance, type TransferReq } from "@/lib/hostel";

const OFFICERS = ["services", "housing", "registrar", "admin", "super"];

export function Clearances({ rows, checkouts, transfers, maintenance, session: s, state, q: q0, tab, office }: { rows: ClearanceRow[]; checkouts: BedRow[]; transfers: TransferReq[]; maintenance: Maintenance[]; session: string; state: string; q: string; tab: string; office: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const may = !!office && OFFICERS.includes(office);
  const [q, setQ] = useState(q0);
  const [m, setM] = useState<{ id: string; state: string; note: string; assignedTo: string; priority: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const go = (next: { state?: string; q?: string; tab?: string }) => { const qs = new URLSearchParams(); qs.set("session", s); const f = { state, q: q0, tab, ...next }; for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/hostel/clearance?${qs}`); };
  const sorted = [...rows].sort((a, b) => a.student_name.localeCompare(b.student_name));

  async function saveMaint() {
    if (!m) return;
    setBusy(true);
    try {
      const r = await callHostel("POST", `/hostel/maintenance/${m.id}/update`, { state: m.state, note: m.note || null, assignedTo: m.assignedTo || null, priority: m.priority }, `Maintenance request ${m.state.toLowerCase()}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify("Request updated"); setM(null); router.refresh();
    } finally { setBusy(false); }
  }

  const HEAD = ["S/N", "Clearance Reference", "Student ID", "Student Name", "Hostel", "Room", "Bed", "Clearance Status", "Outstanding Items", "Charges Due", "Checkout Date", "Clearance Date"];
  const body = () => sorted.map((r, i) => [i + 1, r.reference, r.student_number, r.student_name, r.hall_name, `${r.block}-${r.room_no}`, r.bed_label ?? "", CLEAR_STATE[r.state]?.[0] ?? r.state, r.outstanding_items ?? "", Number(r.charges_due), r.checked_out_at ? dayOf(r.checked_out_at) : r.checkout_on ? dayOf(r.checkout_on) : "", r.completed_at ? dayOf(r.completed_at) : ""]);
  async function excel() { const blob = await brandedXlsx("Hostel Clearance", HEAD, body(), { sheetName: "Clearance", serial: docSerial("HST"), sub: `${s}${state ? ` · ${state.toLowerCase()}` : ""}` }); downloadBlob(blob, `hostel-clearance-${s.replace("/", "-")}.xlsx`); }
  const CHEAD = ["S/N", "Student ID", "Student Name", "Programme", "Hostel", "Block", "Room", "Bed", "Checkout Requested"];
  const cbody = () => [...checkouts].sort((a, b) => (a.student_name ?? "").localeCompare(b.student_name ?? "")).map((r, i) => [i + 1, r.student_number ?? "", r.student_name ?? "", r.programme ?? "", r.hall_name, r.block, r.room_no, r.bed_label, r.end_on ? dayOf(r.end_on) : ""]);
  async function checkoutExcel() { const blob = await brandedXlsx("Hostel Checkout Requests", CHEAD, cbody(), { sheetName: "Checkouts", serial: docSerial("HST"), sub: s }); downloadBlob(blob, `hostel-checkouts-${s.replace("/", "-")}.xlsx`); }
  const THEAD = ["S/N", "Student ID", "Student Name", "Current Hostel", "Room", "Requested Hostel", "Requested Type", "Reason", "Status", "Submitted", "Decided"];
  const tbody = () => [...transfers].sort((a, b) => (a.student_name ?? "").localeCompare(b.student_name ?? "")).map((t, i) => [i + 1, t.student_number ?? "", t.student_name ?? "", t.hall_name ?? "", `${t.block ?? ""}-${t.room_no ?? ""}`, t.requested_hall_name ?? "Any", t.requested_type_label ?? "Any", t.reason, TRANSFER_STATE[t.state]?.[0] ?? t.state, dayOf(t.submitted_at), t.decided_at ? dayOf(t.decided_at) : ""]);
  async function transferExcel() { const blob = await brandedXlsx("Hostel Transfer Requests", THEAD, tbody(), { sheetName: "Transfers", serial: docSerial("HST"), sub: s }); downloadBlob(blob, `hostel-transfers-${s.replace("/", "-")}.xlsx`); }

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/hostel?session=${encodeURIComponent(s)}`}>Accommodation</Link><span>›</span><strong>Checkout &amp; clearance</strong></div>
      <PageHead title="Checkout and clearance" description={`${s}. ${rows.filter((r) => r.state === "PENDING").length} clearance(s) in progress · ${checkouts.length} checkout(s) requested · ${transfers.filter((t) => ["SUBMITTED", "UNDER_REVIEW"].includes(t.state)).length} transfer request(s) waiting · ${maintenance.filter((x) => ["RAISED", "ASSIGNED"].includes(x.state)).length} maintenance request(s) open.`}
        actions={<>
          {tab === "clearances" ? <><Btn kind="secondary" onClick={() => void excel()} disabled={!rows.length}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Hostel Clearance", s, HEAD, body(), docSerial("HST"))} disabled={!rows.length}>PDF</Btn></> : null}
          {tab === "checkouts" ? <><Btn kind="secondary" onClick={() => void checkoutExcel()} disabled={!checkouts.length}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Hostel Checkout Requests", s, CHEAD, cbody(), docSerial("HST"))} disabled={!checkouts.length}>PDF</Btn></> : null}
          {tab === "transfers" ? <><Btn kind="secondary" onClick={() => void transferExcel()} disabled={!transfers.length}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Hostel Transfer Requests", s, THEAD, tbody(), docSerial("HST"))} disabled={!transfers.length}>PDF</Btn></> : null}
          <LinkBtn kind="ghost" href={`/hostel?session=${encodeURIComponent(s)}`}>Back to the desk</LinkBtn>
        </>} />
      <Tabs value={tab} onChange={(t) => go({ tab: t })} items={[{ id: "clearances", label: `Clearances (${rows.length})` }, { id: "checkouts", label: `Checkout requests (${checkouts.length})` }, { id: "transfers", label: `Transfer requests (${transfers.length})` }, { id: "maintenance", label: `Maintenance (${maintenance.filter((x) => ["RAISED", "ASSIGNED"].includes(x.state)).length})` }]} />

      {tab === "clearances" ? (
        <>
          <div className="scope">
            <div className="scope__f"><Field id="cl-state" label="Status"><select id="cl-state" className="ctl" value={state} onChange={(e) => go({ state: e.target.value })}><option value="">Every clearance</option><option value="PENDING">Pending</option><option value="CLEARED">Cleared</option><option value="NOT_CLEARED">Not cleared</option></select></Field></div>
            <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}><Field id="cl-q" label="Search"><input id="cl-q" className="ctl" placeholder="Name, student ID or reference" value={q} onChange={(e) => setQ(e.target.value)} /></Field><Btn kind="secondary" type="submit">Search</Btn></form>
          </div>
          <Panel title={`${rows.length} clearance(s)`} right="Names A–Z">
            {sorted.length ? <DTable pageSize={0} cols={["S/N|num", "Reference|mid", "Student", "Hostel · room", "Bed|mid", "Status|mid", "Outstanding", "Charges|num", "Checkout|mid", "Cleared|mid", "|num"]} rows={sorted.map((r, i) => [
              <span key="sn" className="tnum sub2">{i + 1}</span>, <span key="r" className="tnum">{r.reference}</span>,
              <span key="s"><strong>{r.student_name}</strong><div className="sub2 tnum">{r.student_number}</div></span>, <span key="h">{r.hall_name}<div className="sub2">{r.block}-{r.room_no}</div></span>, <span key="b" className="tnum">{r.bed_label ?? "—"}</span>,
              <Pil key="st" kind={CLEAR_STATE[r.state]?.[1] ?? "grey"}>{CLEAR_STATE[r.state]?.[0] ?? r.state}</Pil>, <span key="o" className="sub2">{r.outstanding ? `${r.outstanding}: ${r.outstanding_items}` : "None"}</span>,
              <span key="c" className="tnum">{Number(r.charges_due) ? naira(r.charges_due) : "—"}</span>, <span key="co" className="tnum sub2">{r.checked_out_at ? dayOf(r.checked_out_at) : r.checkout_on ? `asked ${dayOf(r.checkout_on)}` : "—"}</span>, <span key="cd" className="tnum sub2">{r.completed_at ? dayOf(r.completed_at) : "—"}</span>,
              <LinkBtn key="op" href={`/hostel/allocations/${r.allocation_id}?session=${encodeURIComponent(s)}`} size="sm" kind={r.state === "PENDING" ? "primary" : "ghost"}>{r.state === "PENDING" ? "Clear" : "Open"}</LinkBtn>,
            ])} texts={sorted.map((r) => `${r.student_name} ${r.student_number} ${r.reference} ${r.hall_name}`)} /> : <PBody><div className="sub2">No clearance record for {s}{state ? ` in that state` : ""}. A clearance starts at the checkout inspection.</div></PBody>}
          </Panel>
        </>
      ) : tab === "checkouts" ? (
        <Panel title={`${checkouts.length} checkout request(s) awaiting inspection`} right="Names A–Z">
          {checkouts.length ? <DTable pageSize={0} cols={["S/N|num", "Student", "Programme", "Hostel · room", "Bed|mid", "Requested for|mid", "|num"]} rows={[...checkouts].sort((a, b) => (a.student_name ?? "").localeCompare(b.student_name ?? "")).map((r, i) => [
            <span key="sn" className="tnum sub2">{i + 1}</span>, <span key="s"><strong>{r.student_name}</strong><div className="sub2 tnum">{r.student_number}</div></span>, <span key="p" className="sub2">{r.programme ?? "—"}</span>,
            <span key="h">{r.hall_name}<div className="sub2">{r.block}-{r.room_no}</div></span>, <span key="b" className="tnum">{r.bed_label}</span>, <span key="d" className="tnum sub2">{r.end_on ? dayOf(r.end_on) : "—"}</span>,
            <LinkBtn key="op" href={`/hostel/allocations/${r.allocation_id}?session=${encodeURIComponent(s)}`} size="sm" kind="primary">Inspect</LinkBtn>,
          ])} /> : <PBody><div className="sub2">Nobody has asked to check out.</div></PBody>}
        </Panel>
      ) : tab === "transfers" ? (
        <Panel title={`${transfers.length} transfer request(s)`} right="Decided from the allocation">
          {transfers.length ? <DTable pageSize={0} cols={["S/N|num", "Student", "Now", "Asked for", "Reason", "Status|mid", "Submitted|mid", "|num"]} rows={[...transfers].sort((a, b) => (a.student_name ?? "").localeCompare(b.student_name ?? "")).map((t, i) => [
            <span key="sn" className="tnum sub2">{i + 1}</span>, <span key="s"><strong>{t.student_name}</strong><div className="sub2 tnum">{t.student_number}</div></span>, <span key="n">{t.hall_name}<div className="sub2">{t.block}-{t.room_no} · {t.bed_label}</div></span>,
            <span key="a">{t.requested_hall_name ?? "Any hall"}{t.requested_type_label ? ` · ${t.requested_type_label}` : ""}</span>, <span key="r" className="sub2">{t.reason}</span>,
            <Pil key="st" kind={TRANSFER_STATE[t.state]?.[1] ?? "grey"}>{TRANSFER_STATE[t.state]?.[0] ?? t.state}</Pil>, <span key="d" className="tnum sub2">{dayOf(t.submitted_at)}</span>,
            <LinkBtn key="op" href={`/hostel/allocations/${t.allocation_id}?session=${encodeURIComponent(s)}`} size="sm" kind={["SUBMITTED", "UNDER_REVIEW"].includes(t.state) ? "primary" : "ghost"}>{["SUBMITTED", "UNDER_REVIEW"].includes(t.state) ? "Decide" : "Open"}</LinkBtn>,
          ])} /> : <PBody><div className="sub2">No transfer request.</div></PBody>}
        </Panel>
      ) : (
        <Panel title="Maintenance and complaints" right="Urgent first">
          {maintenance.length ? <DTable pageSize={0} cols={["Priority|mid", "Issue", "Room", "Raised by", "Raised|mid", "Assigned to", "Status|mid", "|num"]} rows={maintenance.map((x) => [
            <Pil key="p" kind={x.priority === "URGENT" ? "bad" : x.priority === "HIGH" ? "warn" : "grey"}>{(x.priority ?? "NORMAL").toLowerCase()}</Pil>,
            <span key="i">{x.issue}<div className="sub2">{MAINT_CATS.find((c) => c[0] === x.category)?.[1] ?? x.category}{x.note ? ` · ${x.note}` : ""}</div></span>,
            <span key="r">{x.hall_name}<div className="sub2">{x.block}-{x.room_no}</div></span>, <span key="b" className="sub2">{x.raised_by_name}<div className="tnum">{x.number}</div></span>, <span key="d" className="tnum sub2">{whenAt(x.raised_at)}</span>, <span key="as" className="sub2">{x.assigned_to ?? "—"}</span>,
            <Pil key="s" kind={x.state === "FIXED" || x.state === "CLOSED" ? "ok" : x.state === "ASSIGNED" ? "info" : "bad"}>{x.state.charAt(0) + x.state.slice(1).toLowerCase()}</Pil>,
            may ? <Btn key="u" kind="ghost" onClick={() => setM({ id: x.id, state: x.state === "RAISED" ? "ASSIGNED" : x.state === "ASSIGNED" ? "FIXED" : x.state, note: x.note ?? "", assignedTo: x.assigned_to ?? "", priority: x.priority ?? "NORMAL" })}>Update</Btn> : <span key="u" />,
          ])} /> : <PBody><div className="sub2">Nothing raised.</div></PBody>}
        </Panel>
      )}

      {m ? (
        <Modal title="Update the maintenance request" onClose={() => setM(null)} foot={<><Btn kind="ghost" onClick={() => setM(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveMaint()} disabled={busy}>Save</Btn></>}>
          <div className="grid grid--2">
            <Field id="mt-state" label="State"><select id="mt-state" className="ctl" value={m.state} onChange={(e) => setM({ ...m, state: e.target.value })}><option value="RAISED">Raised</option><option value="ASSIGNED">Assigned</option><option value="FIXED">Fixed</option><option value="CLOSED">Closed</option></select></Field>
            <Field id="mt-pri" label="Priority"><select id="mt-pri" className="ctl" value={m.priority} onChange={(e) => setM({ ...m, priority: e.target.value })}><option value="LOW">Low</option><option value="NORMAL">Normal</option><option value="HIGH">High</option><option value="URGENT">Urgent</option></select></Field>
            <Field id="mt-to" label="Assigned to" full><input id="mt-to" className="ctl" value={m.assignedTo} onChange={(e) => setM({ ...m, assignedTo: e.target.value })} placeholder="The artisan, the works unit, the contractor" /></Field>
            <Field id="mt-note" label="Note to the student" full><input id="mt-note" className="ctl" value={m.note} onChange={(e) => setM({ ...m, note: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
