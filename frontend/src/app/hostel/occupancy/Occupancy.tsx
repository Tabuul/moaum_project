"use client";

/** Occupancy (V261): the bed board of the session — every bed with its status and who holds it — or the students accommodated
 *  with where they stay; filtered by hostel, block, status, faculty, department, programme, level and gender; searched on the
 *  server; exported with S/N first and names A–Z. A room opens bed by bed; a bed opens the allocation. */
import { useEffect, useState } from "react";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, KvGrid, LinkBtn, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { ALLOC_STATE, OCCUPANCY, callHostel, dayOf, type BedRow } from "@/lib/hostel";
import type { OccFilters, OccList } from "./page";

interface RoomView { id: string; hall_name: string; block: string; floor: number; room_no: string; room_type_label: string | null; beds: number; state: string; state_reason: string | null; beds_: never; facilities: { facility_code: string; label: string; quantity: number }[]; assets: { tag: string; kind: string; condition: string }[]; maintenance: { id: string; issue: string; state: string; raised_at: string; raised_by_name: string }[]; history: { reference_no: string; session: string; state: string; bed: number; allocated_at: string; checked_in_at: string | null; checked_out_at: string | null; student_name: string; student_number: string }[] }

export function Occupancy({ list, filters, session: s, office }: { list: OccList; filters: OccFilters; session: string; office: string | null }) {
  const queryNav = useQueryNav();
  const [q, setQ] = useState(filters.q);
  const [room, setRoom] = useState<(RoomView & { beds_rows: BedRow[] }) | null>(null);
  const rows = list.rows;
  const students = filters.view === "students" || filters.view === "checkins" || filters.view === "checkouts";
  const pages = Math.max(1, Math.ceil(list.total / list.size));
  const go = (next: Partial<OccFilters>) => { const f = { ...filters, ...next, page: next.page ?? "", room: "" }; if (next.hall !== undefined) f.block = ""; if (next.fac !== undefined) { f.dept = ""; f.prog = ""; } if (next.dept !== undefined) f.prog = ""; const qs = new URLSearchParams(); qs.set("session", s); for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/hostel/occupancy?${qs}`); };
  const faculties = [...new Map(list.options.map((o) => [o.faculty_code, o.faculty])).entries()];
  const depts = [...new Map(list.options.filter((o) => !filters.fac || o.faculty_code === filters.fac).map((o) => [o.dept_code, o.department])).entries()];
  const progs = [...new Map(list.options.filter((o) => (!filters.fac || o.faculty_code === filters.fac) && (!filters.dept || o.dept_code === filters.dept)).map((o) => [o.programme_code, o.programme])).entries()];
  const scope = [filters.view === "students" ? "students accommodated" : filters.view === "checkins" ? "to check in" : filters.view === "checkouts" ? "checkout requested" : "every bed", list.halls.find((h) => h.code === filters.hall)?.name, filters.block ? `block ${filters.block}` : "", filters.status ? (OCCUPANCY[filters.status]?.[0] ?? ALLOC_STATE[filters.status]?.[0] ?? filters.status) : "", filters.fac, filters.dept, filters.prog, filters.level ? `${filters.level} Level` : "", filters.q ? `search “${filters.q}”` : ""].filter(Boolean).join(" · ");
  const counts = { occ: rows.filter((r) => r.occupancy === "OCCUPIED").length, res: rows.filter((r) => r.occupancy === "RESERVED").length, av: rows.filter((r) => r.occupancy === "AVAILABLE").length, mt: rows.filter((r) => r.occupancy === "MAINTENANCE").length };

  async function openRoom(id: string) {
    const r = await callHostel<RoomView & { beds: BedRow[] }>("GET", `/hostel/rooms/${id}?session=${encodeURIComponent(s)}`, undefined, "Open a room");
    if (!r.ok) { notifyProblem(r.problem); return; }
    const { beds, ...rest } = r.data;
    setRoom({ ...(rest as unknown as RoomView), beds_rows: beds as unknown as BedRow[] });
  }
  useEffect(() => {
    if (!filters.room) return;
    let live = true;
    (async () => {
      const r = await callHostel<RoomView & { beds: BedRow[] }>("GET", `/hostel/rooms/${filters.room}?session=${encodeURIComponent(s)}`, undefined, "Open a room");
      if (!live) return;
      if (!r.ok) { notifyProblem(r.problem); return; }
      const { beds, ...rest } = r.data;
      setRoom({ ...(rest as unknown as RoomView), beds_rows: beds as unknown as BedRow[] });
    })();
    return () => { live = false; };
  }, [filters.room, s]);

  const HEAD = students ? ["S/N", "Student ID", "Student Name", "Faculty", "Department", "Programme", "Level", "Gender", "Hostel", "Block", "Floor", "Room", "Bed", "Allocation Status", "Check-in Date", "Expected Checkout"]
    : ["S/N", "Hostel", "Block", "Floor", "Room", "Room Type", "Bed", "Bed Status", "Student ID", "Student Name", "Allocation Status"];
  const body = () => students
    ? [...rows].sort((a, b) => (a.student_name ?? "").localeCompare(b.student_name ?? "")).map((r, i) => [i + 1, r.student_number ?? "", r.student_name ?? "", r.faculty ?? "", r.department ?? "", r.programme ?? "", r.level ?? "", r.sex ?? "", r.hall_name, r.block, r.floor, r.room_no, r.bed_label, ALLOC_STATE[r.allocation_state ?? ""]?.[0] ?? r.allocation_state ?? "", r.checked_in_at ? dayOf(r.checked_in_at) : "", r.end_on ? dayOf(r.end_on) : ""])
    : rows.map((r, i) => [i + 1, r.hall_name, r.block, r.floor, r.room_no, r.room_type ?? "", r.bed_label, OCCUPANCY[r.occupancy]?.[0] ?? r.occupancy, r.student_number ?? "", r.student_name ?? "", ALLOC_STATE[r.allocation_state ?? ""]?.[0] ?? ""]);
  async function excel() { const blob = await brandedXlsx(students ? "Hostel Occupancy — Students" : "Hostel Bed Board", HEAD, body(), { sheetName: students ? "Occupancy" : "Beds", serial: docSerial("HST"), sub: `${s} · ${scope}` }); downloadBlob(blob, `hostel-${students ? "occupancy" : "beds"}-${s.replace("/", "-")}.xlsx`); }

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/hostel?session=${encodeURIComponent(s)}`}>Accommodation</Link><span>›</span><strong>Occupancy</strong></div>
      <PageHead title={students ? "Students accommodated" : "Bed board"} description={`${s} · ${scope}. ${list.total.toLocaleString()} ${students ? "student(s), names A–Z" : "bed(s)"}.`}
        actions={<>
          <Btn kind={students ? "ghost" : "secondary"} onClick={() => go({ view: "" })}>Beds</Btn>
          <Btn kind={filters.view === "students" ? "secondary" : "ghost"} onClick={() => go({ view: "students" })}>Students</Btn>
          <Btn kind={filters.view === "checkins" ? "secondary" : "ghost"} onClick={() => go({ view: "checkins" })}>To check in</Btn>
          <Btn kind={filters.view === "checkouts" ? "secondary" : "ghost"} onClick={() => go({ view: "checkouts" })}>Checkout requested</Btn>
          <Btn kind="secondary" onClick={() => void excel()} disabled={!rows.length}>Excel</Btn>
          <Btn kind="ghost" onClick={() => brandedPrint(students ? "Hostel Occupancy — Students" : "Hostel Bed Board", `${s} · ${scope}`, HEAD, body(), docSerial("HST"))} disabled={!rows.length}>PDF</Btn>
          <LinkBtn kind="ghost" href={`/hostel?session=${encodeURIComponent(s)}`}>Back to the desk</LinkBtn>
        </>} />
      {!students ? <Tiles items={[["Occupied", String(counts.occ), "var(--chrome)", "Checked in"], ["Reserved", String(counts.res), counts.res ? "var(--amber-ink)" : null, "Allocated, not checked in"], ["Available", String(counts.av), "var(--green-ink)", "Free"], ["Maintenance", String(counts.mt), counts.mt ? "var(--red-ink)" : null, "Not given"]]} cls="grid--4" /> : null}

      <div className="scope">
        <div className="scope__f"><Field id="oc-hall" label="Hostel"><select id="oc-hall" className="ctl" value={filters.hall} onChange={(e) => go({ hall: e.target.value })}><option value="">Every hostel</option>{list.halls.map((h) => <option key={h.code} value={h.code}>{h.name}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="oc-block" label="Block"><select id="oc-block" className="ctl" value={filters.block} onChange={(e) => go({ block: e.target.value })}><option value="">Every block</option>{list.blocks.filter((b) => !filters.hall || b.hall_code === filters.hall).map((b) => <option key={`${b.hall_code}${b.code}`} value={b.code}>{b.hall_code} · {b.code}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="oc-status" label="Status"><select id="oc-status" className="ctl" value={filters.status} onChange={(e) => go({ status: e.target.value })}><option value="">Any</option>{Object.entries(OCCUPANCY).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}<option value="HELD">Held (payment pending)</option><option value="CONFIRMED">Confirmed</option><option value="ACCEPTED">Accepted</option><option value="CHECKED_IN">Checked in</option></select></Field></div>
        <div className="scope__f"><Field id="oc-fac" label="Faculty"><select id="oc-fac" className="ctl" value={filters.fac} onChange={(e) => go({ fac: e.target.value })}><option value="">Every faculty</option>{faculties.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="oc-dept" label="Department"><select id="oc-dept" className="ctl" value={filters.dept} onChange={(e) => go({ dept: e.target.value })}><option value="">Every department</option>{depts.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="oc-prog" label="Programme"><select id="oc-prog" className="ctl" value={filters.prog} onChange={(e) => go({ prog: e.target.value })}><option value="">Every programme</option>{progs.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="oc-level" label="Level"><select id="oc-level" className="ctl" value={filters.level} onChange={(e) => go({ level: e.target.value })}><option value="">Any</option>{["100", "200", "300", "400", "500", "600", "700", "800", "900"].map((l) => <option key={l} value={l}>{l}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="oc-sex" label="Gender"><select id="oc-sex" className="ctl" value={filters.sex} onChange={(e) => go({ sex: e.target.value })}><option value="">Any</option><option value="F">Female</option><option value="M">Male</option></select></Field></div>
        <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}>
          <Field id="oc-q" label="Search"><input id="oc-q" className="ctl" placeholder="Name, student ID or room" value={q} onChange={(e) => setQ(e.target.value)} /></Field>
          <Btn kind="secondary" type="submit">Search</Btn>
        </form>
      </div>

      <Panel title={students ? `${list.total.toLocaleString()} student(s)` : `${list.total.toLocaleString()} bed(s)`} right={pages > 1 ? <span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => go({ page: String(list.page - 1) })} disabled={list.page <= 0}>Previous</Btn><span className="sub2">Page {list.page + 1} of {pages}</span><Btn kind="ghost" onClick={() => go({ page: String(list.page + 1) })} disabled={list.page + 1 >= pages}>Next</Btn></span> : students ? "Names A–Z" : "Hostel, block, room, bed"}>
        {rows.length ? students ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Programme", "Hostel · room", "Bed|mid", "Status|mid", "Checked in|mid", "Expected out|mid", "|num"]} rows={[...rows].sort((a, b) => (a.student_name ?? "").localeCompare(b.student_name ?? "")).map((r, i) => [
            <span key="sn" className="tnum sub2">{list.page * list.size + i + 1}</span>,
            <span key="s"><strong>{r.student_name}</strong><div className="sub2 tnum">{r.student_number} · {r.level} Level · {r.sex === "F" ? "Female" : r.sex === "M" ? "Male" : "—"}</div></span>,
            <span key="p">{r.programme ?? "—"}<div className="sub2">{r.department ?? "—"} · {r.faculty ?? "—"}</div></span>,
            <span key="h">{r.hall_name}<div className="sub2">Block {r.block} · floor {r.floor} · <button type="button" className="lnk" onClick={() => void openRoom(r.room_id)}>room {r.room_no}</button></div></span>,
            <span key="b" className="tnum">{r.bed_label}</span>,
            <Pil key="st" kind={ALLOC_STATE[r.allocation_state ?? ""]?.[1] ?? "grey"}>{ALLOC_STATE[r.allocation_state ?? ""]?.[0] ?? r.allocation_state}</Pil>,
            <span key="ci" className="tnum sub2">{r.checked_in_at ? dayOf(r.checked_in_at) : "—"}</span>, <span key="eo" className="tnum sub2">{r.end_on ? dayOf(r.end_on) : "—"}</span>,
            <LinkBtn key="o" href={`/hostel/allocations/${r.allocation_id}?session=${encodeURIComponent(s)}`} size="sm" kind={["CONFIRMED", "ACCEPTED"].includes(r.allocation_state ?? "") ? "primary" : "ghost"}>{["CONFIRMED", "ACCEPTED"].includes(r.allocation_state ?? "") ? "Check in" : "Open"}</LinkBtn>,
          ])} texts={rows.map((r) => `${r.student_name ?? ""} ${r.student_number ?? ""} ${r.hall_name} ${r.room_no}`)} />
        ) : (
          <DTable pageSize={0} cols={["S/N|num", "Hostel", "Block|mid", "Floor|mid", "Room|mid", "Bed|mid", "Status|mid", "Student", "Allocation|mid", "|num"]} rows={rows.map((r, i) => [
            <span key="sn" className="tnum sub2">{list.page * list.size + i + 1}</span>, <span key="h">{r.hall_name}</span>, <span key="b" className="tnum">{r.block}</span>, <span key="f" className="tnum">{r.floor}</span>,
            <button key="r" type="button" className="lnk b600 tnum" onClick={() => void openRoom(r.room_id)}>{r.room_no}</button>, <span key="bd" className="tnum">{r.bed_label}</span>,
            <Pil key="st" kind={OCCUPANCY[r.occupancy]?.[1] ?? "grey"}>{OCCUPANCY[r.occupancy]?.[0] ?? r.occupancy}</Pil>,
            r.student_name ? <span key="s"><strong>{r.student_name}</strong><div className="sub2 tnum">{r.student_number} · {r.programme ?? ""}</div></span> : <span key="s" className="sub2">—</span>,
            r.allocation_state ? <Pil key="as" kind={ALLOC_STATE[r.allocation_state]?.[1] ?? "grey"}>{ALLOC_STATE[r.allocation_state]?.[0] ?? r.allocation_state}</Pil> : <span key="as" />,
            r.allocation_id ? <LinkBtn key="o" href={`/hostel/allocations/${r.allocation_id}?session=${encodeURIComponent(s)}`} size="sm">Open</LinkBtn> : <span key="o" />,
          ])} texts={rows.map((r) => `${r.hall_name} ${r.block} ${r.room_no} ${r.bed_label} ${r.student_name ?? ""} ${r.occupancy}`)} />
        ) : <PBody><div className="sub2">{students ? "Nobody matches these filters." : "There are currently no beds matching these filters."}</div></PBody>}
      </Panel>

      {room ? (
        <Modal title={`${room.hall_name} · Block ${room.block} · Room ${room.room_no}`} sub={`${room.room_type_label ?? ""} · capacity ${room.beds} · occupied ${room.beds_rows.filter((b) => b.occupancy === "OCCUPIED").length} · reserved ${room.beds_rows.filter((b) => b.occupancy === "RESERVED").length} · available ${room.beds_rows.filter((b) => b.occupancy === "AVAILABLE").length}`} wide onClose={() => setRoom(null)} foot={<Btn kind="ghost" onClick={() => setRoom(null)}>Close</Btn>}>
          <KvGrid cls="grid--4" pairs={[["Floor", String(room.floor)], ["State", <Pil key="s" kind={room.state === "AVAILABLE" ? "ok" : "bad"}>{room.state.toLowerCase()}</Pil>], ["Facilities", room.facilities.map((f) => `${f.label}${f.quantity > 1 ? ` ×${f.quantity}` : ""}`).join(", ") || "—"], ["Assets", room.assets.map((a) => `${a.tag} ${a.kind} (${a.condition.toLowerCase()})`).join(", ") || "—"]]} />
          <DTable cols={["Bed|mid", "Status|mid", "Student", "Allocation|mid", "|num"]} rows={room.beds_rows.map((b) => [
            <strong key="b" className="tnum">{b.bed_label}</strong>, <Pil key="s" kind={OCCUPANCY[b.occupancy]?.[1] ?? "grey"}>{OCCUPANCY[b.occupancy]?.[0] ?? b.occupancy}</Pil>,
            b.student_name ? <span key="st"><strong>{b.student_name}</strong><div className="sub2 tnum">{b.student_number} · {b.programme ?? ""} · {b.level ?? ""} Level</div></span> : <span key="st" className="sub2">Available</span>,
            b.allocation_state ? <Pil key="a" kind={ALLOC_STATE[b.allocation_state]?.[1] ?? "grey"}>{ALLOC_STATE[b.allocation_state]?.[0] ?? b.allocation_state}</Pil> : <span key="a" />,
            b.allocation_id ? <LinkBtn key="o" href={`/hostel/allocations/${b.allocation_id}?session=${encodeURIComponent(s)}`} size="sm">Open</LinkBtn> : <span key="o" />,
          ])} />
          {room.maintenance.filter((m) => ["RAISED", "ASSIGNED"].includes(m.state)).length ? <div className="sub2 mt-2">Open maintenance: {room.maintenance.filter((m) => ["RAISED", "ASSIGNED"].includes(m.state)).map((m) => `${m.issue} (${m.state.toLowerCase()}, ${m.raised_by_name})`).join("; ")}</div> : null}
          {room.history.length ? <div className="sub2 mt-2">Previous occupants: {room.history.filter((h) => h.session !== s || ["CHECKED_OUT", "TRANSFERRED", "CANCELLED", "DECLINED", "LAPSED"].includes(h.state)).slice(0, 12).map((h) => `${h.student_name} (${h.session}, bed ${h.bed}, ${h.state.toLowerCase()})`).join("; ") || "none"}</div> : null}
        </Modal>
      ) : null}
    </>
  );
}
