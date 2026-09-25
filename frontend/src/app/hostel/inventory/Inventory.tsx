"use client";

/** The hostel inventory (V261): every hostel with its kind, gender, campus and state; its blocks and floors; every room with
 *  its type, capacity, occupancy and state; the beds numbered from the room; facilities and assets; rooms generated in a
 *  run; a hall, block, room or bed closed with the reason and the occupants it affects named. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { CONDITIONS, callHostel, pct, type Asset, type HallFull, type InventoryData, type RoomRow } from "@/lib/hostel";

const OFFICERS = ["services", "housing", "registrar", "admin", "super"];
type HallForm = { code: string; name: string; sex: string; kind: string; campus: string; location: string; description: string };
type RoomForm = { hall: string; block: string; roomNo: string; beds: string; floor: string; roomType: string; sex: string; state: string; note: string };
type GenForm = { hall: string; block: string; floor: string; from: string; to: string; beds: string; roomType: string; prefix: string };
type AssetForm = { tag: string; kind: string; hall: string; roomId: string; quantity: string; condition: string; acquiredOn: string; value: string; note: string };
type CloseForm = { kind: string; id: string; label: string; state: string; reason: string };

export function Inventory({ data, session: s, office }: { data: InventoryData; session: string; office: string | null }) {
  const router = useRouter();
  const may = !!office && OFFICERS.includes(office);
  const [hall, setHall] = useState("");
  const [busy, setBusy] = useState(false);
  const [hallForm, setHallForm] = useState<HallForm | null>(null);
  const [blockForm, setBlockForm] = useState<{ hall: string; code: string; name: string; floors: string } | null>(null);
  const [roomForm, setRoomForm] = useState<RoomForm | null>(null);
  const [gen, setGen] = useState<GenForm | null>(null);
  const [assetForm, setAssetForm] = useState<AssetForm | null>(null);
  const [closing, setClosing] = useState<CloseForm | null>(null);
  const [affected, setAffected] = useState<{ student_name: string; student_number: string; reference_no: string; allocation_id: string; hall_name: string; block: string; room_no: string; bed_label: string | null }[] | null>(null);
  const [facRoom, setFacRoom] = useState<{ room: RoomRow; items: Record<string, number> } | null>(null);
  const rooms = data.rooms.filter((r) => !hall || r.hall_code === hall);
  const totals = { beds: rooms.reduce((a, r) => a + r.beds - r.out_of_service, 0), occ: rooms.reduce((a, r) => a + r.occupied, 0), res: rooms.reduce((a, r) => a + r.reserved, 0), avail: rooms.reduce((a, r) => a + r.available, 0), maint: rooms.reduce((a, r) => a + r.maintenance, 0) };

  async function run<T>(p: Promise<{ ok: true; data: T } | { ok: false; problem: import("@/lib/api").Problem }>, done: string): Promise<T | null> {
    setBusy(true);
    try { const r = await p; if (!r.ok) { notifyProblem(r.problem); return null; } notify(done); router.refresh(); return r.data; } finally { setBusy(false); }
  }
  const saveHall = async () => { if (!hallForm) return; if (await run(callHostel("PUT", "/hostel/halls-full", hallForm, `Save hostel ${hallForm.code}`), "Hostel saved")) setHallForm(null); };
  const saveBlock = async () => { if (!blockForm) return; if (await run(callHostel("PUT", "/hostel/blocks", { ...blockForm, floors: Number(blockForm.floors) || 1 }, `Save block ${blockForm.code}`), "Block saved")) setBlockForm(null); };
  const saveRoom = async () => { if (!roomForm) return; if (await run(callHostel("PUT", "/hostel/rooms-full", { ...roomForm, beds: Number(roomForm.beds), floor: Number(roomForm.floor) || 0, roomType: roomForm.roomType || null, sex: roomForm.sex || null, note: roomForm.note || null }, `Save room ${roomForm.block}-${roomForm.roomNo}`), "Room saved; beds numbered")) setRoomForm(null); };
  const generate = async () => { if (!gen) return; const r = await run<{ generated: number }>(callHostel("POST", "/hostel/rooms/generate", { ...gen, floor: Number(gen.floor) || 0, from: Number(gen.from), to: Number(gen.to), beds: Number(gen.beds), roomType: gen.roomType || null, prefix: gen.prefix || null }, `Generate rooms ${gen.from}–${gen.to} in ${gen.hall} ${gen.block}`), "Rooms generated"); if (r) setGen(null); };
  const saveAsset = async () => { if (!assetForm) return; if (await run(callHostel("PUT", "/hostel/assets", { ...assetForm, roomId: assetForm.roomId || null, quantity: Number(assetForm.quantity) || 1, acquiredOn: assetForm.acquiredOn || null, value: assetForm.value ? Number(assetForm.value) : null, note: assetForm.note || null }, `Save asset ${assetForm.tag}`), "Asset saved")) setAssetForm(null); };
  const close = async () => {
    if (!closing) return;
    const r = await run<{ affected: number; occupants: typeof affected }>(callHostel("POST", `/hostel/close?session=${encodeURIComponent(s)}`, { kind: closing.kind, id: closing.id, state: closing.state, reason: closing.reason || null }, `${closing.state} ${closing.kind.toLowerCase()} ${closing.label}: ${closing.reason}`), `${closing.label} is now ${closing.state.toLowerCase()}`);
    if (r) { setClosing(null); setAffected(r.affected ? r.occupants : null); }
  };
  const saveFacilities = async () => { if (!facRoom) return; if (await run(callHostel("PUT", `/hostel/rooms/${facRoom.room.id}/facilities`, { items: Object.entries(facRoom.items).filter(([, q]) => q > 0).map(([code, quantity]) => ({ code, quantity })) }, `Facilities of room ${facRoom.room.room_no}`), "Facilities saved")) setFacRoom(null); };

  const HEAD = ["S/N", "Hostel", "Block", "Floor", "Room", "Room Type", "Capacity", "Occupied", "Reserved", "Available", "Maintenance", "Status"];
  const body = () => rooms.map((r, i) => [i + 1, r.hall_name, r.block, r.floor, r.room_no, r.room_type_label ?? r.room_type ?? "", r.beds, r.occupied, r.reserved, r.available, r.maintenance, r.state]);
  async function excel() { const blob = await brandedXlsx("Hostel Inventory", HEAD, body(), { sheetName: "Rooms", serial: docSerial("HST"), sub: `${s}${hall ? ` · ${data.halls.find((h) => h.code === hall)?.name}` : ""}` }); downloadBlob(blob, `hostel-inventory-${s.replace("/", "-")}.xlsx`); }
  const BHEAD = ["S/N", "Hostel", "Block", "Room", "Bed", "Status"];
  async function bedsExcel() {
    const r = await callHostel<{ rows: { hall_name: string; block: string; room_no: string; bed_label: string; occupancy: string }[] }>("GET", `/hostel/sessions/${s.replace("/", "/")}/occupancy?size=5000${hall ? `&hall=${encodeURIComponent(hall)}` : ""}`, undefined, "Bed inventory export");
    if (!r.ok) { notifyProblem(r.problem); return; }
    const blob = await brandedXlsx("Hostel Bed Inventory", BHEAD, r.data.rows.map((b, i) => [i + 1, b.hall_name, b.block, b.room_no, b.bed_label, b.occupancy]), { sheetName: "Beds", serial: docSerial("HST"), sub: s });
    downloadBlob(blob, `hostel-beds-${s.replace("/", "-")}.xlsx`);
  }
  const emptyHall = (): HallForm => ({ code: "", name: "", sex: "", kind: "UNDERGRADUATE", campus: "", location: "", description: "" });
  const editHall = (h: HallFull): HallForm => ({ code: h.code, name: h.name, sex: h.sex ?? "", kind: h.kind, campus: h.campus ?? "", location: h.location ?? "", description: h.description ?? "" });
  const editRoom = (r: RoomRow): RoomForm => ({ hall: r.hall_code, block: r.block, roomNo: r.room_no, beds: String(r.beds), floor: String(r.floor), roomType: r.room_type ?? "", sex: r.sex ?? "", state: r.state, note: r.note ?? "" });
  const emptyAsset = (): AssetForm => ({ tag: "", kind: "", hall: hall || data.halls[0]?.code || "", roomId: "", quantity: "1", condition: "GOOD", acquiredOn: "", value: "", note: "" });

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/hostel?session=${encodeURIComponent(s)}`}>Accommodation</Link><span>›</span><strong>Inventory</strong></div>
      <PageHead title="Hostel inventory" description={`${data.halls.length} hostel(s), ${data.blocks.length} block(s), ${data.rooms.length} room(s). Beds are numbered from each room's capacity; a bed under maintenance is a bed nobody is given.`}
        actions={<>
          <Field id="inv-hall" label="Hostel"><select id="inv-hall" className="ctl" value={hall} onChange={(e) => setHall(e.target.value)}><option value="">Every hostel</option>{data.halls.map((h) => <option key={h.code} value={h.code}>{h.name}</option>)}</select></Field>
          {may ? <><Btn kind="primary" onClick={() => setHallForm(emptyHall())}>Add a hostel</Btn><Btn kind="secondary" onClick={() => setBlockForm({ hall: hall || data.halls[0]?.code || "", code: "", name: "", floors: "1" })} disabled={!data.halls.length}>Add a block</Btn><Btn kind="secondary" onClick={() => setRoomForm({ hall: hall || data.halls[0]?.code || "", block: "", roomNo: "", beds: "4", floor: "0", roomType: "", sex: "", state: "AVAILABLE", note: "" })} disabled={!data.halls.length}>Add a room</Btn><Btn kind="secondary" onClick={() => setGen({ hall: hall || data.halls[0]?.code || "", block: "", floor: "0", from: "1", to: "20", beds: "4", roomType: "", prefix: "" })} disabled={!data.halls.length}>Generate rooms</Btn></> : null}
          <Btn kind="ghost" onClick={() => void excel()} disabled={!rooms.length}>Excel</Btn>
          <Btn kind="ghost" onClick={() => brandedPrint("Hostel Inventory", s, HEAD, body(), docSerial("HST"))} disabled={!rooms.length}>PDF</Btn>
          <Btn kind="ghost" onClick={() => void bedsExcel()} disabled={!rooms.length}>Bed list (Excel)</Btn>
          <LinkBtn kind="ghost" href={`/hostel?session=${encodeURIComponent(s)}`}>Back to the desk</LinkBtn>
        </>} />

      <Tiles items={[
        ["Beds", String(totals.beds), null, `${rooms.length} room(s)`], ["Occupied", String(totals.occ), "var(--chrome)", `${pct(totals.occ + totals.res, totals.beds)}% with reserved`],
        ["Reserved", String(totals.res), totals.res ? "var(--amber-ink)" : null, "Allocated, not checked in"], ["Available", String(totals.avail), "var(--green-ink)", "Free to allocate"], ["Maintenance", String(totals.maint), totals.maint ? "var(--red-ink)" : null, "Not given to anyone"],
      ]} cls="grid--5" />

      {affected ? (
        <Note kind="bad" title={`${affected.length} occupant(s) are affected by the closure`} action={<Btn kind="ghost" onClick={() => setAffected(null)}>Dismiss</Btn>}>
          {affected.map((a) => <span className="blk" key={a.allocation_id}><Link className="lnk" href={`/hostel/allocations/${a.allocation_id}?session=${encodeURIComponent(s)}`}>{a.student_name}</Link> · {a.student_number} · {a.hall_name} {a.block}-{a.room_no} {a.bed_label ?? ""} — transfer them from their allocation page and tell them</span>)}
        </Note>
      ) : null}

      <Panel title="Hostels" right={`${data.halls.length}`}>
        {data.halls.length ? <DTable cols={["Hostel", "Code|mid", "Type|mid", "Gender|mid", "Campus", "Blocks|num", "Rooms|num", "State|mid", "|num"]} rows={data.halls.map((h) => [
          <span key="n"><strong>{h.name}</strong>{h.location ? <div className="sub2">{h.location}</div> : null}</span>, <span key="c" className="tnum sub2">{h.code}</span>, <span key="k" className="sub2">{data.kinds.find((k) => k.code === h.kind)?.label ?? h.kind}</span>,
          <span key="x" className="sub2">{h.sex === "F" ? "Female" : h.sex === "M" ? "Male" : "Mixed"}</span>, <span key="ca" className="sub2">{h.campus ?? "—"}</span>,
          <span key="b" className="tnum">{data.blocks.filter((b) => b.hall_code === h.code).length}</span>, <span key="r" className="tnum">{data.rooms.filter((r) => r.hall_code === h.code).length}</span>,
          <Pil key="st" kind={h.state === "ACTIVE" ? "ok" : "bad"} title={h.state_reason ?? undefined}>{h.state === "ACTIVE" ? "Active" : "Closed"}</Pil>,
          <span key="a" className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setHall(h.code)}>Rooms</Btn>{may ? <><Btn kind="ghost" onClick={() => setHallForm(editHall(h))}>Edit</Btn><Btn kind="ghost" onClick={() => setClosing({ kind: "HALL", id: h.code, label: h.name, state: h.state === "ACTIVE" ? "CLOSED" : "ACTIVE", reason: "" })}>{h.state === "ACTIVE" ? "Close" : "Reopen"}</Btn></> : null}</span>,
        ])} /> : <PBody><div className="sub2">No hostel on the record yet.</div></PBody>}
      </Panel>

      {data.blocks.filter((b) => !hall || b.hall_code === hall).length ? (
        <Panel title="Blocks and floors" right="Each block's rooms, floor by floor">
          <DTable cols={["Hostel", "Block", "Floors|num", "Rooms|num", "Beds|num", "Occupied|num", "State|mid", "|num"]} rows={data.blocks.filter((b) => !hall || b.hall_code === hall).map((b) => {
            const rs = data.rooms.filter((r) => r.block_id === b.id);
            return [data.halls.find((h) => h.code === b.hall_code)?.name ?? b.hall_code, <strong key="c">{b.name} <span className="sub2 tnum">{b.code}</span></strong>, <span key="f" className="tnum">{b.floors}</span>, <span key="r" className="tnum">{rs.length}</span>,
              <span key="bd" className="tnum">{rs.reduce((a, r) => a + r.beds - r.out_of_service, 0)}</span>, <span key="o" className="tnum">{rs.reduce((a, r) => a + r.occupied + r.reserved, 0)}</span>,
              <Pil key="st" kind={b.state === "ACTIVE" ? "ok" : "bad"} title={b.state_reason ?? undefined}>{b.state === "ACTIVE" ? "Active" : "Closed"}</Pil>,
              may ? <span key="a" className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setBlockForm({ hall: b.hall_code, code: b.code, name: b.name, floors: String(b.floors) })}>Edit</Btn><Btn kind="ghost" onClick={() => setClosing({ kind: "BLOCK", id: b.id, label: `${b.hall_code} ${b.name}`, state: b.state === "ACTIVE" ? "CLOSED" : "ACTIVE", reason: "" })}>{b.state === "ACTIVE" ? "Close" : "Reopen"}</Btn></span> : <span key="a" />];
          })} />
        </Panel>
      ) : null}

      <Panel title="Rooms" right={`${rooms.length} room(s)`}>
        {rooms.length ? <DTable pageSize={50} cols={["S/N|num", "Hostel", "Block|mid", "Floor|mid", "Room|mid", "Type", "Capacity|num", "Occupied|num", "Available|num", "Maintenance|num", "State|mid", "|num"]} rows={rooms.map((r, i) => [
          <span key="sn" className="tnum sub2">{i + 1}</span>, <span key="h" className="sub2">{r.hall_name}</span>, <span key="b" className="tnum">{r.block}</span>, <span key="f" className="tnum">{r.floor}</span>,
          <Link key="r" className="lnk b600 tnum" href={`/hostel/occupancy?session=${encodeURIComponent(s)}&room=${r.id}`}>{r.room_no}</Link>,
          <span key="t">{r.room_type_label ?? r.room_type ?? "—"}{r.sex ? <span className="sub2"> · {r.sex === "F" ? "female" : "male"}</span> : null}{r.facilities ? <div className="sub2">{r.facilities}</div> : null}</span>,
          <span key="c" className="tnum">{r.beds}</span>, <span key="o" className="tnum">{r.occupied + r.reserved}</span>, <span key="a" className="tnum">{r.available}</span>, <span key="m" className="tnum">{r.maintenance}</span>,
          <Pil key="st" kind={r.state === "AVAILABLE" ? "ok" : r.state === "RESERVED" ? "warn" : "bad"} title={r.state_reason ?? undefined}>{r.state.charAt(0) + r.state.slice(1).toLowerCase()}</Pil>,
          may ? <span key="ac" className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setRoomForm(editRoom(r))}>Edit</Btn><Btn kind="ghost" onClick={() => setFacRoom({ room: r, items: Object.fromEntries(data.facilities.map((f) => [f.code, 0])) })}>Facilities</Btn><Btn kind="ghost" onClick={() => setClosing({ kind: "ROOM", id: r.id, label: `${r.hall_name} ${r.block}-${r.room_no}`, state: r.state === "AVAILABLE" ? "MAINTENANCE" : "AVAILABLE", reason: "" })}>{r.state === "AVAILABLE" ? "Close" : "Reopen"}</Btn></span> : <span key="ac" />,
        ])} texts={rooms.map((r) => `${r.hall_name} ${r.block} ${r.room_no} ${r.room_type_label ?? ""} ${r.state}`)} /> : <PBody><div className="sub2">No room {hall ? "in this hostel" : "on the record"} yet.</div></PBody>}
      </Panel>

      <Panel title="Assets" right={may ? <Btn kind="secondary" onClick={() => setAssetForm(emptyAsset())} disabled={!data.halls.length}>Add an asset</Btn> : `${data.assets.length}`}>
        {data.assets.filter((a) => !hall || a.hall_code === hall).length ? <DTable pageSize={50} cols={["Tag|mid", "Asset", "Hostel", "Room|mid", "Qty|num", "Condition|mid", "Acquired|mid", "Value|num", "State|mid", "|num"]} rows={data.assets.filter((a) => !hall || a.hall_code === hall).map((a) => [
          <span key="t" className="tnum">{a.tag}</span>, a.kind, <span key="h" className="sub2">{a.hall_name}</span>, <span key="r" className="tnum sub2">{a.room_no ? `${a.block}-${a.room_no}` : "—"}</span>, <span key="q" className="tnum">{a.quantity}</span>,
          <Pil key="c" kind={["NEW", "GOOD"].includes(a.condition) ? "ok" : a.condition === "FAIR" ? "warn" : "bad"}>{a.condition.replace("_", " ").toLowerCase()}</Pil>, <span key="d" className="tnum sub2">{a.acquired_on ?? "—"}</span>,
          <span key="v" className="tnum">{a.value ? `₦${Number(a.value).toLocaleString()}` : "—"}</span>, <span key="s" className="sub2">{a.state.toLowerCase()}</span>,
          may ? <Btn key="e" kind="ghost" onClick={() => setAssetForm({ tag: a.tag, kind: a.kind, hall: a.hall_code, roomId: a.room_id ?? "", quantity: String(a.quantity), condition: a.condition, acquiredOn: a.acquired_on ?? "", value: a.value ? String(a.value) : "", note: a.note ?? "" })}>Edit</Btn> : <span key="e" />,
        ])} texts={data.assets.map((a) => `${a.tag} ${a.kind} ${a.hall_name}`)} /> : <PBody><div className="sub2">No asset recorded{hall ? " for this hostel" : ""}.</div></PBody>}
      </Panel>

      {hallForm ? (
        <Modal title={hallForm.code && data.halls.some((h) => h.code === hallForm.code) ? `Hostel ${hallForm.code}` : "A new hostel"} onClose={() => setHallForm(null)} foot={<><Btn kind="ghost" onClick={() => setHallForm(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveHall()} disabled={busy || !hallForm.code.trim() || !hallForm.name.trim()}>Save</Btn></>}>
          <div className="grid grid--2">
            <Field id="hf-code" label="Code" required hint="Two to eight letters or digits"><input id="hf-code" className="ctl" value={hallForm.code} onChange={(e) => setHallForm({ ...hallForm, code: e.target.value.toUpperCase() })} maxLength={8} /></Field>
            <Field id="hf-kind" label="Type"><select id="hf-kind" className="ctl" value={hallForm.kind} onChange={(e) => setHallForm({ ...hallForm, kind: e.target.value })}>{data.kinds.map((k) => <option key={k.code} value={k.code}>{k.label}</option>)}</select></Field>
            <Field id="hf-name" label="Name" required full><input id="hf-name" className="ctl" value={hallForm.name} onChange={(e) => setHallForm({ ...hallForm, name: e.target.value })} /></Field>
            <Field id="hf-sex" label="Gender"><select id="hf-sex" className="ctl" value={hallForm.sex} onChange={(e) => setHallForm({ ...hallForm, sex: e.target.value })}><option value="">Mixed / either</option><option value="F">Female</option><option value="M">Male</option></select></Field>
            <Field id="hf-campus" label="Campus"><input id="hf-campus" className="ctl" value={hallForm.campus} onChange={(e) => setHallForm({ ...hallForm, campus: e.target.value })} /></Field>
            <Field id="hf-loc" label="Location" full><input id="hf-loc" className="ctl" value={hallForm.location} onChange={(e) => setHallForm({ ...hallForm, location: e.target.value })} /></Field>
            <Field id="hf-desc" label="Description" full><textarea id="hf-desc" className="ctl" rows={2} value={hallForm.description} onChange={(e) => setHallForm({ ...hallForm, description: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
      {blockForm ? (
        <Modal title="A block" onClose={() => setBlockForm(null)} foot={<><Btn kind="ghost" onClick={() => setBlockForm(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveBlock()} disabled={busy || !blockForm.code.trim()}>Save</Btn></>}>
          <div className="grid grid--2">
            <Field id="bf-hall" label="Hostel"><select id="bf-hall" className="ctl" value={blockForm.hall} onChange={(e) => setBlockForm({ ...blockForm, hall: e.target.value })}>{data.halls.map((h) => <option key={h.code} value={h.code}>{h.name}</option>)}</select></Field>
            <Field id="bf-code" label="Block code" required><input id="bf-code" className="ctl" value={blockForm.code} onChange={(e) => setBlockForm({ ...blockForm, code: e.target.value.toUpperCase() })} maxLength={12} /></Field>
            <Field id="bf-name" label="Name"><input id="bf-name" className="ctl" value={blockForm.name} onChange={(e) => setBlockForm({ ...blockForm, name: e.target.value })} placeholder={`Block ${blockForm.code || "A"}`} /></Field>
            <Field id="bf-floors" label="Floors"><input id="bf-floors" type="number" min={1} max={30} className="ctl" value={blockForm.floors} onChange={(e) => setBlockForm({ ...blockForm, floors: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
      {roomForm ? (
        <Modal title="A room" sub="Its beds are numbered from the capacity when it is saved" onClose={() => setRoomForm(null)} foot={<><Btn kind="ghost" onClick={() => setRoomForm(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveRoom()} disabled={busy || !roomForm.block.trim() || !roomForm.roomNo.trim() || !Number(roomForm.beds)}>Save</Btn></>}>
          <div className="grid grid--3">
            <Field id="rf-hall" label="Hostel"><select id="rf-hall" className="ctl" value={roomForm.hall} onChange={(e) => setRoomForm({ ...roomForm, hall: e.target.value })}>{data.halls.map((h) => <option key={h.code} value={h.code}>{h.name}</option>)}</select></Field>
            <Field id="rf-block" label="Block" required><input id="rf-block" className="ctl" value={roomForm.block} onChange={(e) => setRoomForm({ ...roomForm, block: e.target.value.toUpperCase() })} list="rf-blocks" /><datalist id="rf-blocks">{data.blocks.filter((b) => b.hall_code === roomForm.hall).map((b) => <option key={b.id} value={b.code} />)}</datalist></Field>
            <Field id="rf-floor" label="Floor" hint="0 is the ground floor"><input id="rf-floor" type="number" min={0} max={30} className="ctl" value={roomForm.floor} onChange={(e) => setRoomForm({ ...roomForm, floor: e.target.value })} /></Field>
            <Field id="rf-no" label="Room number" required><input id="rf-no" className="ctl" value={roomForm.roomNo} onChange={(e) => setRoomForm({ ...roomForm, roomNo: e.target.value })} /></Field>
            <Field id="rf-beds" label="Capacity (beds)" required><input id="rf-beds" type="number" min={1} max={12} className="ctl" value={roomForm.beds} onChange={(e) => setRoomForm({ ...roomForm, beds: e.target.value })} /></Field>
            <Field id="rf-type" label="Room type"><select id="rf-type" className="ctl" value={roomForm.roomType} onChange={(e) => setRoomForm({ ...roomForm, roomType: e.target.value })}><option value="">From the capacity</option>{data.roomTypes.map((t) => <option key={t.code} value={t.code}>{t.label}</option>)}</select></Field>
            <Field id="rf-sex" label="Gender restriction" hint="Blank follows the hostel"><select id="rf-sex" className="ctl" value={roomForm.sex} onChange={(e) => setRoomForm({ ...roomForm, sex: e.target.value })}><option value="">As the hostel</option><option value="F">Female</option><option value="M">Male</option></select></Field>
            <Field id="rf-state" label="State"><select id="rf-state" className="ctl" value={roomForm.state} onChange={(e) => setRoomForm({ ...roomForm, state: e.target.value })}><option value="AVAILABLE">Available</option><option value="MAINTENANCE">Maintenance</option><option value="CLOSED">Closed</option><option value="RESERVED">Reserved</option></select></Field>
            <Field id="rf-note" label="Note"><input id="rf-note" className="ctl" value={roomForm.note} onChange={(e) => setRoomForm({ ...roomForm, note: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
      {gen ? (
        <Modal title="Generate rooms" sub="A run of rooms in one block, each with its beds" onClose={() => setGen(null)} foot={<><Btn kind="ghost" onClick={() => setGen(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void generate()} disabled={busy || !gen.block.trim() || !Number(gen.beds)}>Generate</Btn></>}>
          <div className="grid grid--3">
            <Field id="g-hall" label="Hostel"><select id="g-hall" className="ctl" value={gen.hall} onChange={(e) => setGen({ ...gen, hall: e.target.value })}>{data.halls.map((h) => <option key={h.code} value={h.code}>{h.name}</option>)}</select></Field>
            <Field id="g-block" label="Block" required><input id="g-block" className="ctl" value={gen.block} onChange={(e) => setGen({ ...gen, block: e.target.value.toUpperCase() })} /></Field>
            <Field id="g-floor" label="Floor"><input id="g-floor" type="number" min={0} className="ctl" value={gen.floor} onChange={(e) => setGen({ ...gen, floor: e.target.value })} /></Field>
            <Field id="g-prefix" label="Number prefix" hint="e.g. A- gives A-1, A-2 …"><input id="g-prefix" className="ctl" value={gen.prefix} onChange={(e) => setGen({ ...gen, prefix: e.target.value })} /></Field>
            <Field id="g-from" label="From number"><input id="g-from" type="number" min={1} className="ctl" value={gen.from} onChange={(e) => setGen({ ...gen, from: e.target.value })} /></Field>
            <Field id="g-to" label="To number"><input id="g-to" type="number" min={1} className="ctl" value={gen.to} onChange={(e) => setGen({ ...gen, to: e.target.value })} /></Field>
            <Field id="g-beds" label="Beds per room"><input id="g-beds" type="number" min={1} max={12} className="ctl" value={gen.beds} onChange={(e) => setGen({ ...gen, beds: e.target.value })} /></Field>
            <Field id="g-type" label="Room type"><select id="g-type" className="ctl" value={gen.roomType} onChange={(e) => setGen({ ...gen, roomType: e.target.value })}><option value="">From the capacity</option>{data.roomTypes.map((t) => <option key={t.code} value={t.code}>{t.label}</option>)}</select></Field>
          </div>
        </Modal>
      ) : null}
      {assetForm ? (
        <Modal title="An asset" onClose={() => setAssetForm(null)} foot={<><Btn kind="ghost" onClick={() => setAssetForm(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveAsset()} disabled={busy || !assetForm.tag.trim() || !assetForm.kind.trim()}>Save</Btn></>}>
          <div className="grid grid--3">
            <Field id="af-tag" label="Asset tag" required><input id="af-tag" className="ctl" value={assetForm.tag} onChange={(e) => setAssetForm({ ...assetForm, tag: e.target.value.toUpperCase() })} /></Field>
            <Field id="af-kind" label="Asset type" required><input id="af-kind" className="ctl" value={assetForm.kind} onChange={(e) => setAssetForm({ ...assetForm, kind: e.target.value })} list="af-kinds" placeholder="Mattress, wardrobe, fan…" /><datalist id="af-kinds">{data.facilities.map((f) => <option key={f.code} value={f.label} />)}</datalist></Field>
            <Field id="af-hall" label="Hostel"><select id="af-hall" className="ctl" value={assetForm.hall} onChange={(e) => setAssetForm({ ...assetForm, hall: e.target.value, roomId: "" })}>{data.halls.map((h) => <option key={h.code} value={h.code}>{h.name}</option>)}</select></Field>
            <Field id="af-room" label="Room"><select id="af-room" className="ctl" value={assetForm.roomId} onChange={(e) => setAssetForm({ ...assetForm, roomId: e.target.value })}><option value="">Not in a room</option>{data.rooms.filter((r) => r.hall_code === assetForm.hall).map((r) => <option key={r.id} value={r.id}>{r.block}-{r.room_no}</option>)}</select></Field>
            <Field id="af-qty" label="Quantity"><input id="af-qty" type="number" min={1} className="ctl" value={assetForm.quantity} onChange={(e) => setAssetForm({ ...assetForm, quantity: e.target.value })} /></Field>
            <Field id="af-cond" label="Condition"><select id="af-cond" className="ctl" value={assetForm.condition} onChange={(e) => setAssetForm({ ...assetForm, condition: e.target.value })}>{CONDITIONS.map((c) => <option key={c} value={c}>{c.replace("_", " ").toLowerCase()}</option>)}</select></Field>
            <Field id="af-acq" label="Date acquired"><input id="af-acq" type="date" className="ctl" value={assetForm.acquiredOn} onChange={(e) => setAssetForm({ ...assetForm, acquiredOn: e.target.value })} /></Field>
            <Field id="af-val" label="Value (₦)"><input id="af-val" type="number" min={0} className="ctl" value={assetForm.value} onChange={(e) => setAssetForm({ ...assetForm, value: e.target.value })} /></Field>
            <Field id="af-note" label="Note"><input id="af-note" className="ctl" value={assetForm.note} onChange={(e) => setAssetForm({ ...assetForm, note: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
      {closing ? (
        <Modal title={`${closing.state === "ACTIVE" || closing.state === "AVAILABLE" ? "Reopen" : "Close"} ${closing.label}`} onClose={() => setClosing(null)} foot={<><Btn kind="ghost" onClick={() => setClosing(null)}>Cancel</Btn><Btn kind={closing.state === "ACTIVE" || closing.state === "AVAILABLE" ? "primary" : "urgent"} onClick={() => void close()} disabled={busy || (!["ACTIVE", "AVAILABLE"].includes(closing.state) && !closing.reason.trim())}>Confirm</Btn></>}>
          {["ACTIVE", "AVAILABLE"].includes(closing.state) ? <p>It becomes available for allocation again.</p> : <><p>No new allocation is made to it. Occupants keep their record; they are named so the desk can transfer them.</p>
            {closing.kind === "ROOM" ? <Field id="cl-state" label="State"><select id="cl-state" className="ctl" value={closing.state} onChange={(e) => setClosing({ ...closing, state: e.target.value })}><option value="MAINTENANCE">Maintenance</option><option value="CLOSED">Closed</option><option value="RESERVED">Reserved</option></select></Field> : null}
            <Field id="cl-reason" label="Reason" required full><textarea id="cl-reason" className="ctl" rows={3} value={closing.reason} onChange={(e) => setClosing({ ...closing, reason: e.target.value })} placeholder="Maintenance, renovation, safety, emergency…" /></Field></>}
        </Modal>
      ) : null}
      {facRoom ? (
        <Modal title={`Facilities of room ${facRoom.room.block}-${facRoom.room.room_no}`} onClose={() => setFacRoom(null)} foot={<><Btn kind="ghost" onClick={() => setFacRoom(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveFacilities()} disabled={busy}>Save</Btn></>}>
          <div className="grid grid--3">{data.facilities.map((f) => <Field key={f.code} id={`fc-${f.code}`} label={f.label}><input id={`fc-${f.code}`} type="number" min={0} max={100} className="ctl" value={facRoom.items[f.code] ?? 0} onChange={(e) => setFacRoom({ ...facRoom, items: { ...facRoom.items, [f.code]: Number(e.target.value) || 0 } })} /></Field>)}</div>
          <div className="sub2">Quantity 0 removes the facility from the room. {facRoom.room.facilities ? `Now: ${facRoom.room.facilities}` : ""}</div>
        </Modal>
      ) : null}
    </>
  );
}
