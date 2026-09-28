"use client";

/** Special allocations (V290): the rooms that are not for general selection — special / reserved, Student Union, Security and
 *  any category the Dean adds — who occupies them, what they pay or that no charge applies, who allocated and why; the Dean
 *  allocates a bed here to a student, a member of staff or a named person. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { FEE_STATUS, HOSTEL_OFFICERS, callHostel, dayOf, naira, type AccountabilityRow, type AllocatableBed, type RoomBoardRow, type RoomCategory } from "@/lib/hostel";

export interface SpecialData { session: string; rows: AccountabilityRow[]; rooms: RoomBoardRow[]; categories: RoomCategory[] }

export function Special({ data, session: s, sessions, office, beds }: { data: SpecialData; session: string; sessions: string[]; office: string | null; beds: AllocatableBed[] }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const may = !!office && HOSTEL_OFFICERS.includes(office);
  const [s1, s2] = s.split("/");
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [f, setF] = useState({ category: "SPECIAL", bedId: "", who: "student", studentNumber: "", occupantName: "", reason: "", startOn: "", endOn: "" });
  const cats = data.categories.filter((c) => !c.general_selection);
  const choices = beds.filter((b) => b.category === f.category);
  const chosen = choices.find((b) => b.bed_id === f.bedId) ?? null;

  async function allocate() {
    setBusy(true);
    try {
      const r = await callHostel<AccountabilityRow>("POST", `/hostel/sessions/${s1}/${s2}/allocate-special`, {
        bedId: f.bedId, category: f.category, studentNumber: f.who === "student" ? f.studentNumber.trim() : null, occupantName: f.who === "other" ? f.occupantName.trim() : null,
        reason: f.reason.trim(), startOn: f.startOn || null, endOn: f.endOn || null,
      }, `Special allocation: ${f.category} room for ${f.who === "student" ? f.studentNumber : f.occupantName}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${r.data.occupant} allocated ${r.data.hall_name} ${r.data.block}-${r.data.room_no} · ${FEE_STATUS[r.data.fee_status]?.[0] ?? r.data.fee_status}`);
      setOpen(false); setF({ ...f, bedId: "", studentNumber: "", occupantName: "", reason: "" }); router.refresh();
    } finally { setBusy(false); }
  }

  const byCat = (code: string) => data.rows.filter((r) => r.category === code).length;
  const HEAD = ["S/N", "Occupant", "Number", "Kind", "Hostel", "Block", "Room", "Bed", "Category", "Session", "Semester", "Fee status", "Amount", "Payment", "Start", "End", "Status", "Allocated by", "Reason"];
  const sorted = [...data.rows].sort((a, b) => a.occupant.localeCompare(b.occupant));
  const body = () => sorted.map((r, i) => [i + 1, r.occupant, r.occupant_number ?? "", r.occupant_kind, r.hall_name, r.block, r.room_no, r.bed_label ?? "", r.category_label, r.session, r.semester ?? "", FEE_STATUS[r.fee_status]?.[0] ?? r.fee_status, Number(r.fee_amount), r.payment_status, r.start_on ?? "", r.end_on ?? "", r.state, r.allocated_by ?? "", r.reason ?? ""]);
  async function excel() { const blob = await brandedXlsx("Hostel Special Allocations", HEAD, body(), { sheetName: "Special", serial: docSerial("HST"), sub: s }); downloadBlob(blob, `hostel-special-allocations-${s.replace("/", "-")}.xlsx`); }
  const pdf = () => brandedPrint("Hostel Special Allocations", s, HEAD, body());

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/hostel?session=${encodeURIComponent(s)}`}>Accommodation</Link><span>›</span><strong>Special allocations</strong></div>
      <PageHead title="Special allocations" description={`${s}. Rooms that are never chosen by students: reserved for particular people, the Student Union, Security. Free does not mean untracked — every occupant is here.`}
        actions={<>
          <Field id="sp-session" label="Session"><select id="sp-session" className="ctl" value={s} onChange={(e) => queryNav(`/hostel/special?session=${encodeURIComponent(e.target.value)}`)}>{(sessions.includes(s) ? sessions : [s, ...sessions]).map((x) => <option key={x} value={x}>{x}</option>)}</select></Field>
          <Btn kind="ghost" onClick={() => void excel()} disabled={!data.rows.length}>Excel</Btn><Btn kind="ghost" onClick={pdf} disabled={!data.rows.length}>PDF</Btn>
          {may ? <Btn kind="primary" onClick={() => setOpen(true)}>Allocate a special room</Btn> : null}
        </>} />
      <Tiles items={[["SPECIAL / RESERVED", byCat("SPECIAL"), null, "Payable at the Bursar's rule"], ["STUDENT UNION", byCat("STUDENT_UNION"), "var(--green-ink)", "No charge, on the record"], ["SECURITY", byCat("SECURITY"), "var(--green-ink)", "No charge, on the record"], ["PROTECTED ROOMS", data.rooms.length, "var(--chrome)", `${data.rooms.reduce((a, r) => a + r.available, 0)} beds free for the Dean to allocate`]]} />

      <Panel title="Occupants of the protected rooms" right="Sorted by name">
        {data.rows.length === 0 ? <PBody><Note kind="info" title="No special allocation this session">Allocate a bed of a special, Student Union or Security room above; the room must carry that category on the inventory first.</Note></PBody> : (
          <DTable cols={["S/N|mid", "Occupant", "Room", "Category", "Fee|num", "Payment|mid", "Stay|mid", "Status|mid", "Allocated by", "Reason"]}
            texts={sorted.map((r) => `${r.occupant} ${r.occupant_number ?? ""} ${r.room_no} ${r.category_label}`)}
            rows={sorted.map((r, i) => [i + 1, <span key="o"><b>{r.occupant}</b><span className="sub2 blk tnum">{r.occupant_number ?? r.occupant_kind}</span></span>, <span key="r">{r.hall_name} · {r.block}-{r.room_no} {r.bed_label ?? ""}</span>, <Pil kind="info" key="c">{r.category_label}</Pil>,
              <span className="tnum" key="f">{r.fee_status === "NO_CHARGE" ? "₦0 · no charge" : naira(r.fee_amount)}</span>, <Pil kind={FEE_STATUS[r.fee_status]?.[1] ?? "grey"} key="p">{r.payment_status}</Pil>,
              <span className="tnum sub2" key="s">{dayOf(r.start_on)} – {dayOf(r.end_on)}</span>, <Pil kind={r.state === "CHECKED_IN" ? "ok" : "info"} key="st">{r.state.replace(/_/g, " ")}</Pil>, <span className="sub2" key="b">{r.allocated_by ?? "—"}</span>, <span className="sub2" key="w">{r.reason ?? ""}</span>])} />
        )}
      </Panel>

      <Panel title="The protected rooms" right="Category says what a room is for; status says its condition">
        {data.rooms.length === 0 ? <PBody><div className="sub2">No room carries a category other than General. Set a room&rsquo;s category on the inventory.</div></PBody> : (
          <DTable cols={["Hostel", "Room|mid", "Category", "Capacity|mid", "Occupied|mid", "Reserved|mid", "Available|mid", "Status|mid", "Fee|num"]}
            rows={data.rooms.map((r) => [r.hall_name, <b className="tnum" key="n">{r.block}-{r.room_no}</b>, r.category_label, r.capacity, r.occupied, r.reserved, r.available, <Pil kind={r.status === "FULL" ? "bad" : r.status === "SPECIAL_RESERVED" ? "info" : r.status === "AVAILABLE" || r.status === "PARTIALLY_OCCUPIED" ? "ok" : "grey"} key="s">{r.status.replace(/_/g, " ")}</Pil>, <span className="tnum" key="f">{r.fee_status === "NO_CHARGE" ? "No charge" : naira(r.fee)}</span>])} />
        )}
      </Panel>

      {open ? (
        <Modal title="Allocate a special room" sub={`${s} · the fee follows the room's category and the Bursar's rules`} onClose={() => setOpen(false)} wide
          foot={<><Btn kind="ghost" onClick={() => setOpen(false)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={busy || !f.bedId || !f.reason.trim() || (f.who === "student" ? !f.studentNumber.trim() : !f.occupantName.trim())} onClick={() => void allocate()}>{busy ? "Allocating…" : "Allocate"}</Btn></>}>
          <div className="grid grid--2 rfgrid">
            <Field id="sp-cat" label="Category"><select id="sp-cat" className="ctl" value={f.category} onChange={(e) => setF({ ...f, category: e.target.value, bedId: "" })}>{cats.map((c) => <option key={c.code} value={c.code}>{c.label}{c.chargeable ? "" : " · no charge"}</option>)}</select></Field>
            <Field id="sp-bed" label="Bed" hint={choices.length ? `${choices.length} free bed${choices.length === 1 ? "" : "s"} in ${f.category.toLowerCase().replace(/_/g, " ")} rooms` : "No free bed of this category: set a room's category on the inventory first"}>
              <select id="sp-bed" className="ctl" value={f.bedId} onChange={(e) => setF({ ...f, bedId: e.target.value })}><option value="">— choose —</option>{choices.map((b) => <option key={b.bed_id} value={b.bed_id}>{b.hall_name} · {b.block}-{b.room_no} · {b.bed_label}</option>)}</select>
            </Field>
            <Field id="sp-who" label="Occupant"><select id="sp-who" className="ctl" value={f.who} onChange={(e) => setF({ ...f, who: e.target.value })}><option value="student">A student (by matriculation or admission number)</option><option value="other">A member of staff or another named person</option></select></Field>
            {f.who === "student" ? <Field id="sp-no" label="Student number"><input id="sp-no" className="ctl tnum" value={f.studentNumber} onChange={(e) => setF({ ...f, studentNumber: e.target.value })} placeholder="MOAU/SCI/26/0001" /></Field>
              : <Field id="sp-name" label="Occupant's name"><input id="sp-name" className="ctl" value={f.occupantName} onChange={(e) => setF({ ...f, occupantName: e.target.value })} placeholder="Officer's full name" /></Field>}
            <Field id="sp-from" label="Start date" hint="Blank: the session's stay"><input id="sp-from" type="date" className="ctl" value={f.startOn} onChange={(e) => setF({ ...f, startOn: e.target.value })} /></Field>
            <Field id="sp-to" label="End date"><input id="sp-to" type="date" className="ctl" value={f.endOn} onChange={(e) => setF({ ...f, endOn: e.target.value })} /></Field>
            <Field id="sp-why" label="Reason, as it will read in the record" full><input id="sp-why" className="ctl" value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} /></Field>
          </div>
          {chosen ? <Note kind={chosen.fee_status === "NO_CHARGE" ? "ok" : "info"} title={chosen.fee_status === "NO_CHARGE" ? "No hostel charge" : `Hostel fee ${naira(chosen.fee)} · payable`}>{chosen.fee_status === "NO_CHARGE" ? "An institutional allocation: nothing is charged and no payment is expected, but the occupant, the room and the dates are recorded like every other stay." : "The occupant pays the hostel fee through the Bursary; the allocation stands as payable until it is confirmed."}</Note> : null}
        </Modal>
      ) : null}
    </>
  );
}
