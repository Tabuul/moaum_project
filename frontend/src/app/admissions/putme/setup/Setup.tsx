"use client";

/** The examination's setup (V260): the event itself; the CBT centres with their rooms and numbered workstations
 *  (a workstation switched off is a seat nobody is given); the days, the slots and the centres this examination
 *  uses; and the programmes screened by examination, which the admission settings name. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { EXAM_STATE, STRATEGY, callPutme, clock, dayOf, type Centre, type Overview, type Room } from "@/lib/putme";

const OFFICERS = ["academic", "registrar", "dregistrar", "super"];
interface Workstation { id: string; number: number; label: string; operational: boolean }

export function Setup({ view, office }: { view: Overview; office: string | null }) {
  const router = useRouter();
  const s = view.session;
  const x = view.exam;
  const may = !!office && OFFICERS.includes(office);
  const [busy, setBusy] = useState<string | null>(null);
  const [exam, setExam] = useState({
    name: x?.name ?? `Post-UTME Examination ${s}`, startsOn: x?.starts_on ?? "", endsOn: x?.ends_on ?? "", checkinMinutes: x?.checkin_minutes ?? 30, durationMinutes: x?.duration_minutes ?? 120, bufferMinutes: x?.buffer_minutes ?? 30,
    registrationDeadline: x?.registration_deadline ?? "", strategy: x?.strategy ?? "PROGRAMME", keepProgramme: x?.keep_programme ?? true, instructions: x?.instructions ?? "", venueInstructions: x?.venue_instructions ?? "", contact: x?.contact ?? "",
  });
  const [centreForm, setCentreForm] = useState<{ code: string; name: string; location: string; address: string; contactPerson: string; contactInfo: string; state: string } | null>(null);
  const [roomForm, setRoomForm] = useState<{ centreId: string; code: string; name: string; capacity: number; workstations: number; state: string } | null>(null);
  const [ws, setWs] = useState<{ room: Room; list: Workstation[] } | null>(null);
  const [days, setDays] = useState<string[]>((view.days ?? []).filter((d) => d.active).map((d) => String(d.held_on).slice(0, 10)));
  const [newDay, setNewDay] = useState("");
  const [slots, setSlots] = useState<{ code: string; startsAt: string; endsAt: string }[]>((view.slots ?? []).filter((z) => z.active).map((z) => ({ code: z.code, startsAt: clock(z.starts_at), endsAt: clock(z.ends_at) })));
  const [chosen, setChosen] = useState<string[]>(view.examCentres ?? []);
  const locked = !!x && ["SCHEDULED", "ONGOING", "COMPLETED", "CANCELLED"].includes(x.state);

  async function run<T>(key: string, p: Promise<{ ok: true; data: T } | { ok: false; problem: import("@/lib/api").Problem }>, done: string) {
    setBusy(key);
    try { const r = await p; if (!r.ok) { notifyProblem(r.problem); return null; } notify(done); router.refresh(); return r.data; } finally { setBusy(null); }
  }
  const saveExam = () => run("exam", callPutme(s, "PUT", "/exam", { ...exam, startsOn: exam.startsOn || null, endsOn: exam.endsOn || null, registrationDeadline: exam.registrationDeadline || null, instructions: exam.instructions || null, venueInstructions: exam.venueInstructions || null, contact: exam.contact || null }, `Save the Post-UTME examination for ${s}`), x ? "Examination saved" : "Examination created");
  const saveCentre = async () => { if (!centreForm) return; if (await run("centre", callPutme(s, "POST", "/centres", centreForm, `Save CBT centre ${centreForm.code}`), "Centre saved")) setCentreForm(null); };
  const saveRoom = async () => { if (!roomForm) return; if (await run("room", callPutme(s, "POST", `/centres/${roomForm.centreId}/rooms`, roomForm, `Save CBT room ${roomForm.code}`), "Room saved, workstations numbered")) setRoomForm(null); };
  const openWs = async (room: Room) => { const r = await callPutme<Workstation[]>(s, "GET", `/rooms/${room.id}/workstations`, undefined, "Read the room's workstations"); if (!r.ok) { notifyProblem(r.problem); return; } setWs({ room, list: r.data }); };
  const flipWs = async (w: Workstation) => { const r = await callPutme<Workstation>(s, "PUT", `/workstations/${w.id}`, { operational: !w.operational }, `${w.operational ? "Switch off" : "Switch on"} workstation ${w.label}`); if (!r.ok) { notifyProblem(r.problem); return; } setWs((cur) => cur ? { ...cur, list: cur.list.map((z) => (z.id === w.id ? r.data : z)) } : cur); };
  const saveDays = () => run("days", callPutme(s, "PUT", "/exam/days", { dates: days }, `Name the examination days for ${s}`), "Days saved");
  const saveSlots = () => run("slots", callPutme(s, "PUT", "/exam/slots", { slots }, `Name the examination slots for ${s}`), "Slots saved");
  const saveCentres = () => run("centres", callPutme(s, "PUT", "/exam/centres", { ids: chosen }, `Name the examination centres for ${s}`), "Centres saved");

  const num = (v: string, d: number) => (Number.isFinite(Number(v)) && v !== "" ? Number(v) : d);

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/admissions/putme?session=${encodeURIComponent(s)}`}>Post-UTME CBT</Link><span>›</span><strong>Setup</strong></div>
      <PageHead title="Examination setup" description={`${s}. The examination, its centres and rooms, its days and slots, and the programmes it screens. Rooms, days and slots multiply into the places the batches fill.`}
        actions={<>{x ? <Pil kind={EXAM_STATE[x.state]?.[1] ?? "grey"}>{EXAM_STATE[x.state]?.[0] ?? x.state}</Pil> : null}<LinkBtn kind="secondary" href={`/admissions/putme?session=${encodeURIComponent(s)}`}>Back to the desk</LinkBtn></>} />
      {locked ? <Note kind="info" title="The schedule is published">Places cannot be changed under a published schedule. Reopen the examination for scheduling from the desk to change its days, slots or centres; a single batch is postponed from its own page.</Note> : null}
      {!may ? <Note kind="info" title="You are reading this setup">The Academic Office and the Registry change it.</Note> : null}

      <Panel title="The examination" right={x ? `Created for ${s}` : "Not yet created"}>
        <PBody>
          <div className="grid grid--3">
            <Field id="ex-name" label="Name" required><input id="ex-name" className="ctl" value={exam.name} onChange={(e) => setExam({ ...exam, name: e.target.value })} disabled={!may} /></Field>
            <Field id="ex-from" label="First day"><input id="ex-from" type="date" className="ctl" value={exam.startsOn} onChange={(e) => setExam({ ...exam, startsOn: e.target.value })} disabled={!may} /></Field>
            <Field id="ex-to" label="Last day"><input id="ex-to" type="date" className="ctl" value={exam.endsOn} onChange={(e) => setExam({ ...exam, endsOn: e.target.value })} disabled={!may} /></Field>
            <Field id="ex-ci" label="Report before (minutes)" hint="The reporting time on the slip is the batch's start less this"><input id="ex-ci" type="number" min={0} max={240} className="ctl" value={exam.checkinMinutes} onChange={(e) => setExam({ ...exam, checkinMinutes: num(e.target.value, 30) })} disabled={!may} /></Field>
            <Field id="ex-du" label="Sitting (minutes)"><input id="ex-du" type="number" min={10} max={600} className="ctl" value={exam.durationMinutes} onChange={(e) => setExam({ ...exam, durationMinutes: num(e.target.value, 120) })} disabled={!may} /></Field>
            <Field id="ex-bu" label="Buffer between batches (minutes)"><input id="ex-bu" type="number" min={0} max={240} className="ctl" value={exam.bufferMinutes} onChange={(e) => setExam({ ...exam, bufferMinutes: num(e.target.value, 30) })} disabled={!may} /></Field>
            <Field id="ex-rd" label="Registration deadline"><input id="ex-rd" type="date" className="ctl" value={exam.registrationDeadline} onChange={(e) => setExam({ ...exam, registrationDeadline: e.target.value })} disabled={!may} /></Field>
            <Field id="ex-st" label="Batching strategy"><select id="ex-st" className="ctl" value={exam.strategy} onChange={(e) => setExam({ ...exam, strategy: e.target.value })} disabled={!may}>{Object.entries(STRATEGY).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
            <Field id="ex-kp" label="Keep a programme together"><select id="ex-kp" className="ctl" value={exam.keepProgramme ? "1" : "0"} onChange={(e) => setExam({ ...exam, keepProgramme: e.target.value === "1" })} disabled={!may}><option value="1">Yes — a programme is not split across batches where it fits</option><option value="0">No — fill each place in order</option></select></Field>
            <Field id="ex-ct" label="Enquiries contact" hint="Printed on the slip"><input id="ex-ct" className="ctl" value={exam.contact} onChange={(e) => setExam({ ...exam, contact: e.target.value })} disabled={!may} /></Field>
          </div>
          <Field id="ex-in" label="Examination instructions" hint="Printed on every slip and shown on the portal" full><textarea id="ex-in" className="ctl" rows={4} value={exam.instructions} onChange={(e) => setExam({ ...exam, instructions: e.target.value })} disabled={!may} /></Field>
          <Field id="ex-vi" label="Venue instructions" hint="Where to report, what to bring to the centre" full><textarea id="ex-vi" className="ctl" rows={2} value={exam.venueInstructions} onChange={(e) => setExam({ ...exam, venueInstructions: e.target.value })} disabled={!may} /></Field>
          {may ? <div className="row"><Btn kind="primary" onClick={() => void saveExam()} disabled={busy === "exam" || !exam.name.trim()}>{x ? "Save the examination" : "Create the examination"}</Btn></div> : null}
        </PBody>
      </Panel>

      <Panel title="Programmes screened by examination" right={<Link className="lnk" href="/admissions/settings">Named under Admission Settings</Link>}>
        {view.examProgrammes.length ? <DTable cols={["Code|mid", "Programme"]} rows={view.examProgrammes.map((p) => [<span key="c" className="tnum">{p.programme_code}</span>, p.name])} texts={view.examProgrammes.map((p) => `${p.programme_code} ${p.name}`)} /> : <PBody><div className="sub2">No programme is named as screened by the Post-UTME examination for {s}. Nobody is eligible until one is.</div></PBody>}
      </Panel>

      <Panel title="CBT centres and rooms" right={may ? <Btn kind="secondary" onClick={() => setCentreForm({ code: "", name: "", location: "", address: "", contactPerson: "", contactInfo: "", state: "ACTIVE" })}>Add a centre</Btn> : `${view.centres.length} centre(s)`}>
        <PBody>
          {view.centres.length ? view.centres.map((c: Centre) => (
            <div key={c.id} className="card" style={{ marginBottom: "var(--s-3)" }}>
              <div className="card__head">
                <div className="grow"><b>{c.name}</b> <span className="sub2 tnum">{c.code}</span>{c.location ? <span className="sub2"> · {c.location}</span> : null} <Pil kind={c.state === "ACTIVE" ? "ok" : "grey"}>{c.state === "ACTIVE" ? "Active" : "Inactive"}</Pil></div>
                {may ? <span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setCentreForm({ code: c.code, name: c.name, location: c.location ?? "", address: c.address ?? "", contactPerson: c.contact_person ?? "", contactInfo: c.contact_info ?? "", state: c.state })}>Edit</Btn><Btn kind="secondary" onClick={() => setRoomForm({ centreId: c.id, code: "", name: "", capacity: 50, workstations: 50, state: "ACTIVE" })}>Add a room</Btn></span> : null}
              </div>
              {c.rooms.length ? <DTable cols={["Room", "Code|mid", "Capacity|num", "Workstations|num", "Operational|num", "State|mid", "|num"]} rows={c.rooms.map((r) => [r.name, <span key="c" className="tnum sub2">{r.code}</span>, <span key="k" className="tnum">{r.capacity}</span>, <span key="w" className="tnum">{r.workstations}</span>, <span key="o" className="tnum" style={{ color: r.workstations && r.operational_workstations < r.workstations ? "var(--red-ink)" : undefined }}>{r.operational_workstations}</span>, <Pil key="s" kind={r.state === "ACTIVE" ? "ok" : "grey"}>{r.state === "ACTIVE" ? "Active" : "Inactive"}</Pil>, <span key="a" className="row row--inline row--tight"><Btn kind="ghost" onClick={() => void openWs(r)}>Workstations</Btn>{may ? <Btn kind="ghost" onClick={() => setRoomForm({ centreId: c.id, code: r.code, name: r.name, capacity: r.capacity, workstations: r.workstations, state: r.state })}>Edit</Btn> : null}</span>])} /> : <PBody><div className="sub2">No room yet.</div></PBody>}
            </div>
          )) : <div className="sub2">No CBT centre is registered. A centre has rooms; a room has a capacity and numbered workstations.</div>}
        </PBody>
      </Panel>

      {x ? (
        <div className="grid grid--3">
          <Panel title="Centres this examination uses" right={`${chosen.length} chosen`}>
            <PBody>
              {view.centres.filter((c) => c.state === "ACTIVE").map((c) => (
                <label key={c.id} className="row row--tight" style={{ gap: 8, marginBottom: 6 }}><input type="checkbox" checked={chosen.includes(c.id)} disabled={!may || locked} onChange={(e) => setChosen(e.target.checked ? [...chosen, c.id] : chosen.filter((i) => i !== c.id))} /> <span>{c.name} <span className="sub2">· {c.rooms.filter((r) => r.state === "ACTIVE").length} room(s), {c.rooms.filter((r) => r.state === "ACTIVE").reduce((a, r) => a + (r.operational_workstations || r.capacity), 0)} seats</span></span></label>
              ))}
              {may && !locked ? <Btn kind="primary" onClick={() => void saveCentres()} disabled={busy === "centres"}>Save centres</Btn> : null}
            </PBody>
          </Panel>
          <Panel title="Examination days" right={`${days.length} day(s)`}>
            <PBody>
              {days.map((d) => <div key={d} className="row row--tight" style={{ justifyContent: "space-between", marginBottom: 4 }}><span className="tnum">{dayOf(d)}</span>{may && !locked ? <Btn kind="ghost" onClick={() => setDays(days.filter((z) => z !== d))}>Remove</Btn> : null}</div>)}
              {may && !locked ? <div className="row row--tight" style={{ alignItems: "flex-end" }}><Field id="ex-day" label="Add a day"><input id="ex-day" type="date" className="ctl" value={newDay} onChange={(e) => setNewDay(e.target.value)} /></Field><Btn kind="secondary" onClick={() => { if (newDay && !days.includes(newDay)) setDays([...days, newDay].sort()); setNewDay(""); }} disabled={!newDay}>Add</Btn><Btn kind="primary" onClick={() => void saveDays()} disabled={busy === "days"}>Save days</Btn></div> : null}
            </PBody>
          </Panel>
          <Panel title="Time slots" right={`${slots.length} slot(s) a day`}>
            <PBody>
              {slots.map((z, i) => (
                <div key={i} className="row row--tight" style={{ alignItems: "flex-end", marginBottom: 4 }}>
                  <Field id={`sl-c-${i}`} label="Code"><input id={`sl-c-${i}`} className="ctl" value={z.code} onChange={(e) => setSlots(slots.map((q, j) => (j === i ? { ...q, code: e.target.value.toUpperCase() } : q)))} disabled={!may || locked} style={{ width: 70 }} /></Field>
                  <Field id={`sl-a-${i}`} label="From"><input id={`sl-a-${i}`} type="time" className="ctl" value={z.startsAt} onChange={(e) => setSlots(slots.map((q, j) => (j === i ? { ...q, startsAt: e.target.value } : q)))} disabled={!may || locked} /></Field>
                  <Field id={`sl-b-${i}`} label="To"><input id={`sl-b-${i}`} type="time" className="ctl" value={z.endsAt} onChange={(e) => setSlots(slots.map((q, j) => (j === i ? { ...q, endsAt: e.target.value } : q)))} disabled={!may || locked} /></Field>
                  {may && !locked ? <Btn kind="ghost" onClick={() => setSlots(slots.filter((_, j) => j !== i))}>Remove</Btn> : null}
                </div>
              ))}
              {may && !locked ? <div className="row row--tight"><Btn kind="secondary" onClick={() => { const n = slots.length + 1; const start = 8 + (n - 1) * Math.ceil(((exam.durationMinutes + exam.bufferMinutes) || 150) / 60); setSlots([...slots, { code: `S${n}`, startsAt: `${String(Math.min(start, 22)).padStart(2, "0")}:00`, endsAt: `${String(Math.min(start + Math.ceil(exam.durationMinutes / 60), 23)).padStart(2, "0")}:00` }]); }}>Add a slot</Btn><Btn kind="primary" onClick={() => void saveSlots()} disabled={busy === "slots" || slots.some((z) => !z.code || !z.startsAt || !z.endsAt)}>Save slots</Btn></div> : null}
            </PBody>
          </Panel>
        </div>
      ) : null}

      {x && view.capacity ? (
        <Panel title="Places" right={`${view.capacity.length} place(s) · ${view.capacity.reduce((a, c) => a + c.capacity, 0)} seats`}>
          {view.capacity.length ? <DTable cols={["Day", "Slot|mid", "Centre", "Room", "Seats|num", "Assigned|num"]} rows={view.capacity.map((c) => [dayOf(c.held_on), <span key="s" className="tnum">{c.slot} · {clock(c.starts_at)}–{clock(c.ends_at)}</span>, c.centre, c.room, <span key="k" className="tnum">{c.capacity}</span>, <span key="a" className="tnum">{c.assigned}</span>])} texts={view.capacity.map((c) => `${c.held_on} ${c.slot} ${c.centre} ${c.room}`)} /> : <PBody><div className="sub2">Days × slots × rooms of the chosen centres: none yet.</div></PBody>}
        </Panel>
      ) : null}

      {centreForm ? (
        <Modal title={centreForm.code && view.centres.some((c) => c.code === centreForm.code) ? `Centre ${centreForm.code}` : "A new CBT centre"} onClose={() => setCentreForm(null)} foot={<><Btn kind="ghost" onClick={() => setCentreForm(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveCentre()} disabled={busy === "centre" || !centreForm.code.trim() || !centreForm.name.trim()}>Save</Btn></>}>
          <div className="grid grid--2">
            <Field id="cf-code" label="Code" required><input id="cf-code" className="ctl" value={centreForm.code} onChange={(e) => setCentreForm({ ...centreForm, code: e.target.value.toUpperCase() })} maxLength={12} /></Field>
            <Field id="cf-state" label="State"><select id="cf-state" className="ctl" value={centreForm.state} onChange={(e) => setCentreForm({ ...centreForm, state: e.target.value })}><option value="ACTIVE">Active</option><option value="INACTIVE">Inactive</option></select></Field>
            <Field id="cf-name" label="Name" required full><input id="cf-name" className="ctl" value={centreForm.name} onChange={(e) => setCentreForm({ ...centreForm, name: e.target.value })} /></Field>
            <Field id="cf-loc" label="Location"><input id="cf-loc" className="ctl" value={centreForm.location} onChange={(e) => setCentreForm({ ...centreForm, location: e.target.value })} /></Field>
            <Field id="cf-addr" label="Address"><input id="cf-addr" className="ctl" value={centreForm.address} onChange={(e) => setCentreForm({ ...centreForm, address: e.target.value })} /></Field>
            <Field id="cf-cp" label="Contact person"><input id="cf-cp" className="ctl" value={centreForm.contactPerson} onChange={(e) => setCentreForm({ ...centreForm, contactPerson: e.target.value })} /></Field>
            <Field id="cf-ci" label="Contact phone or email"><input id="cf-ci" className="ctl" value={centreForm.contactInfo} onChange={(e) => setCentreForm({ ...centreForm, contactInfo: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
      {roomForm ? (
        <Modal title="A room" sub="Its workstations are numbered when it is saved" onClose={() => setRoomForm(null)} foot={<><Btn kind="ghost" onClick={() => setRoomForm(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveRoom()} disabled={busy === "room" || !roomForm.code.trim() || !roomForm.name.trim() || roomForm.capacity < 1}>Save</Btn></>}>
          <div className="grid grid--2">
            <Field id="rf-code" label="Code" required><input id="rf-code" className="ctl" value={roomForm.code} onChange={(e) => setRoomForm({ ...roomForm, code: e.target.value.toUpperCase() })} maxLength={12} /></Field>
            <Field id="rf-name" label="Name" required><input id="rf-name" className="ctl" value={roomForm.name} onChange={(e) => setRoomForm({ ...roomForm, name: e.target.value })} /></Field>
            <Field id="rf-cap" label="Capacity (seats)"><input id="rf-cap" type="number" min={1} max={2000} className="ctl" value={roomForm.capacity} onChange={(e) => setRoomForm({ ...roomForm, capacity: num(e.target.value, 1) })} /></Field>
            <Field id="rf-ws" label="Workstations" hint="Numbered Computer 001…; at most the capacity"><input id="rf-ws" type="number" min={0} max={2000} className="ctl" value={roomForm.workstations} onChange={(e) => setRoomForm({ ...roomForm, workstations: num(e.target.value, 0) })} /></Field>
            <Field id="rf-state" label="State"><select id="rf-state" className="ctl" value={roomForm.state} onChange={(e) => setRoomForm({ ...roomForm, state: e.target.value })}><option value="ACTIVE">Active</option><option value="INACTIVE">Inactive</option></select></Field>
          </div>
        </Modal>
      ) : null}
      {ws ? (
        <Modal title={`${ws.room.name} · workstations`} sub={`${ws.list.filter((w) => w.operational).length} of ${ws.list.length} operational`} wide onClose={() => setWs(null)} foot={<Btn kind="ghost" onClick={() => setWs(null)}>Close</Btn>}>
          <KvGrid cls="grid--4" pairs={[["Room", ws.room.name], ["Capacity", String(ws.room.capacity)], ["Workstations", String(ws.room.workstations)], ["Operational", String(ws.list.filter((w) => w.operational).length)]]} />
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginTop: "var(--s-3)" }}>
            {ws.list.map((w) => <button key={w.id} type="button" className={`btn btn--sm ${w.operational ? "btn--secondary" : "btn--ghost"}`} style={{ opacity: w.operational ? 1 : 0.55 }} disabled={!may} title={w.operational ? "Operational · click to switch off" : "Off · click to switch on"} onClick={() => void flipWs(w)}>{w.label}</button>)}
            {!ws.list.length ? <span className="sub2">The room states no workstations; its capacity seats candidates.</span> : null}
          </div>
        </Modal>
      ) : null}
    </>
  );
}
