"use client";

/** Accountability (V290): who occupies or holds every bed of the session — student, staff or named person; general, special,
 *  Student Union or Security; paying, paid or no charge — and the room board beneath it with capacity, occupied, reserved,
 *  available and the derived status of every room. No occupied room is invisible here. Exported with S/N first, names A–Z. */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { FEE_STATUS, ROOM_STATUS, dayOf, naira, pct, type AccountabilityRow, type RoomBoardRow, type RoomCategory } from "@/lib/hostel";

export interface AccountabilityData { session: string; rows: AccountabilityRow[]; board: RoomBoardRow[]; halls: { code: string; name: string }[]; categories: RoomCategory[] }
export interface AccFilters { hall: string; category: string; feeStatus: string }

export function Accountability({ data, filters, session: s, sessions }: { data: AccountabilityData; filters: AccFilters; session: string; sessions: string[] }) {
  const queryNav = useQueryNav();
  const go = (next: Partial<AccFilters>, session = s) => {
    const f = { ...filters, ...next };
    const q = new URLSearchParams({ session });
    if (f.hall) q.set("hall", f.hall); if (f.category) q.set("category", f.category); if (f.feeStatus) q.set("feeStatus", f.feeStatus);
    queryNav(`/hostel/accountability?${q.toString()}`);
  };
  const rows = [...data.rows].sort((a, b) => a.occupant.localeCompare(b.occupant));
  const board = data.board.filter((r) => (!filters.hall || r.hall_code === filters.hall) && (!filters.category || r.category === filters.category));
  const cap = board.reduce((a, r) => a + r.capacity - r.out_of_service, 0), occ = board.reduce((a, r) => a + r.occupied, 0), res = board.reduce((a, r) => a + r.reserved, 0), av = board.reduce((a, r) => a + r.available, 0);
  const HEAD = ["S/N", "Hostel", "Block", "Room", "Capacity", "Bed", "Occupant", "Student/Staff ID", "Kind", "Category", "Allocation type", "Session", "Semester", "Fee status", "Amount", "Payment status", "Start date", "End date", "Status", "Allocated by", "Reason"];
  const body = () => rows.map((r, i) => [i + 1, r.hall_name, r.block, r.room_no, r.capacity, r.bed_label ?? "", r.occupant, r.occupant_number ?? "", r.occupant_kind, r.category_label, r.allocation_type, r.session, r.semester ?? "", FEE_STATUS[r.fee_status]?.[0] ?? r.fee_status, Number(r.fee_amount), r.payment_status, r.start_on ?? "", r.end_on ?? "", r.state, r.allocated_by ?? "", r.reason ?? ""]);
  async function excel() { const blob = await brandedXlsx("Hostel Occupancy Accountability", HEAD, body(), { sheetName: "Occupants", serial: docSerial("HST"), sub: s }); downloadBlob(blob, `hostel-accountability-${s.replace("/", "-")}.xlsx`); }
  const pdf = () => brandedPrint("Hostel Occupancy Accountability", s, HEAD, body());
  const BHEAD = ["S/N", "Hostel", "Block", "Floor", "Room", "Category", "Capacity", "Occupied", "Reserved", "Available", "Occupancy %", "Status", "Fee"];
  const bbody = () => board.map((r, i) => [i + 1, r.hall_name, r.block, r.floor, r.room_no, r.category_label, r.capacity, r.occupied, r.reserved, r.available, pct(r.occupied, r.capacity - r.out_of_service), r.status, r.fee_status === "NO_CHARGE" ? "No charge" : Number(r.fee ?? 0)]);
  async function boardExcel() { const blob = await brandedXlsx("Hostel Room Utilisation", BHEAD, bbody(), { sheetName: "Rooms", serial: docSerial("HST"), sub: s }); downloadBlob(blob, `hostel-rooms-${s.replace("/", "-")}.xlsx`); }

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/hostel?session=${encodeURIComponent(s)}`}>Accommodation</Link><span>›</span><strong>Accountability</strong></div>
      <PageHead description={`${s}. Every bed held or occupied.`}
        actions={<>
          <Field id="ac-session" label="Session"><select id="ac-session" className="ctl" value={s} onChange={(e) => go({}, e.target.value)}>{(sessions.includes(s) ? sessions : [s, ...sessions]).map((x) => <option key={x} value={x}>{x}</option>)}</select></Field>
          <Field id="ac-hall" label="Hostel"><select id="ac-hall" className="ctl" value={filters.hall} onChange={(e) => go({ hall: e.target.value })}><option value="">Every hostel</option>{data.halls.map((h) => <option key={h.code} value={h.code}>{h.name}</option>)}</select></Field>
          <Field id="ac-cat" label="Category"><select id="ac-cat" className="ctl" value={filters.category} onChange={(e) => go({ category: e.target.value })}><option value="">Every category</option>{data.categories.map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}</select></Field>
          <Field id="ac-fee" label="Fee status"><select id="ac-fee" className="ctl" value={filters.feeStatus} onChange={(e) => go({ feeStatus: e.target.value })}><option value="">Any</option><option value="PAID">Paid</option><option value="PAYABLE">Outstanding</option><option value="NO_CHARGE">No charge</option></select></Field>
          <Btn kind="ghost" onClick={() => void excel()} disabled={!rows.length}>Excel</Btn><Btn kind="ghost" onClick={pdf} disabled={!rows.length}>PDF</Btn>
        </>} />
      <Tiles items={[["OCCUPANTS", rows.length, null, `${rows.filter((r) => r.state === "CHECKED_IN").length} checked in`], ["CAPACITY", cap, null, `${board.length} rooms in service`], ["OCCUPIED", occ, "var(--green-ink)", `${pct(occ, cap)}% occupancy`], ["RESERVED", res, "var(--amber-ink)", "Held, confirmed or accepted"], ["AVAILABLE", av, null, `${board.filter((r) => r.status === "FULL").length} rooms full`]]} cls="grid--5" />

      <Panel title="Occupants" right="Sorted by name · every category, every fee status">
        {rows.length === 0 ? <PBody><Note kind="info" title="No records found">Nobody holds or occupies a bed of {s}{filters.hall || filters.category || filters.feeStatus ? " under these filters" : ""}.</Note></PBody> : (
          <DTable cols={["S/N|mid", "Occupant", "Room", "Category", "Allocation", "Fee|num", "Payment|mid", "Stay|mid", "Status|mid", "Allocated by"]}
            texts={rows.map((r) => `${r.occupant} ${r.occupant_number ?? ""} ${r.room_no} ${r.hall_name}`)}
            rows={rows.map((r, i) => [i + 1, <span key="o"><b>{r.occupant}</b><span className="sub2 blk tnum">{r.occupant_number ?? r.occupant_kind}</span></span>, <span key="r">{r.hall_name} · {r.block}-{r.room_no} {r.bed_label ?? ""}<span className="sub2 blk">capacity {r.capacity}</span></span>,
              <Pil kind={r.category === "GENERAL" ? "grey" : "info"} key="c">{r.category_label}</Pil>, <span className="sub2" key="a">{r.allocation_type}</span>, <span className="tnum" key="f">{r.fee_status === "NO_CHARGE" ? "₦0" : naira(r.fee_amount)}</span>,
              <Pil kind={FEE_STATUS[r.fee_status]?.[1] ?? "grey"} key="p">{r.payment_status}</Pil>, <span className="tnum sub2" key="s">{dayOf(r.start_on)} – {dayOf(r.end_on)}</span>, <Pil kind={r.state === "CHECKED_IN" ? "ok" : r.state === "HELD" ? "warn" : "info"} key="st">{r.state.replace(/_/g, " ")}</Pil>, <span className="sub2" key="b">{r.allocated_by ?? "—"}</span>])} />
        )}
      </Panel>

      <Panel title="Room utilisation" right={<Btn kind="ghost" size="sm" onClick={() => void boardExcel()} disabled={!board.length}>Excel</Btn>}>
        {board.length === 0 ? <PBody><div className="sub2">No room on the inventory.</div></PBody> : (
          <DTable cols={["Hostel", "Room|mid", "Category", "Capacity|mid", "Occupied|mid", "Reserved|mid", "Available|mid", "Occupancy|mid", "Status|mid", "Fee|num"]}
            rows={board.map((r) => [r.hall_name, <b className="tnum" key="n">{r.block}-{r.room_no}</b>, r.category_label, r.capacity, r.occupied, r.reserved, r.available, <span className="tnum" key="p">{pct(r.occupied, r.capacity - r.out_of_service)}%</span>, <Pil kind={ROOM_STATUS[r.status]?.[1] ?? "grey"} key="s">{ROOM_STATUS[r.status]?.[0] ?? r.status}</Pil>, <span className="tnum" key="f">{r.fee_status === "NO_CHARGE" ? "No charge" : naira(r.fee)}</span>])} />
        )}
      </Panel>
    </>
  );
}
