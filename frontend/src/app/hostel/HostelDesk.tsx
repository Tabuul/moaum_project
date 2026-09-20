"use client";

/** tHostel — proto/part46.html: the inventory, the draw from a published seed, the hold window that runs on its own. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { CATEGORIES, type HostelDeskData } from "@/lib/hostel";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

function when(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short" }) + ", " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function HostelDesk({ d, sessions, actingOffice }: { d: HostelDeskData; sessions: string[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["services", "housing", "bursar", "registrar", "admin", "super"].includes(actingOffice ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [fee, setFee] = useState(d.setting ? String(d.setting.fee) : "");
  const [hold, setHold] = useState(d.setting ? String(d.setting.hold_hours) : "72");
  const [close, setClose] = useState(d.setting?.applications_close ?? "");
  const [seed, setSeed] = useState("");
  const [hall, setHall] = useState({ code: "", name: "", sex: "" });
  const [room, setRoom] = useState({ hall: d.halls[0]?.code ?? "", block: "", roomNo: "", beds: "4" });
  const c = d.counts;
  const drawn = !!d.setting?.drawn_at;
  const ballot = Math.max(0, c.beds - c.priority);
  const contested = Math.max(0, c.applications - c.priority);
  const odds = contested ? Math.min(100, Math.round((100 * ballot) / contested)) : null;

  async function send(path: string, method: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j ?? { status: r.status, title: r.statusText });
        return null;
      }
      notify(reason);
      router.refresh();
      return j;
    } finally {
      setBusy(false);
    }
  }
  const sess = d.session.replace("/", "/");

  return (
    <>
      <RoleLine allowed={["services", "housing", "bursar"]} actingOffice={actingOffice} canAct={may}
        action="Allocating hostel places and rooms" />
      <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, alignItems: "flex-end", flexWrap: "wrap" }}>
        <div className="field" style={{ minWidth: 160 }}><label htmlFor="hd-s">Session</label>
          <select id="hd-s" className="ctl" value={d.session} onChange={(e) => router.push(`/hostel?session=${encodeURIComponent(e.target.value)}`)}>
            {(sessions.includes(d.session) ? sessions : [d.session, ...sessions]).map((s) => <option key={s} value={s}>{s}</option>)}
          </select></div>
      </div></div>
      <Note kind="info" title="Allocation is where discretion does the most damage, so it is designed out">
        Priority categories are filled first, by rule and by name. What is left is drawn by ballot from a <b>published seed</b>, and the order is a function of the seed and the applicants, and of nothing else. When an allocation lapses unpaid, the bed does not return to this office: it goes to the next name on the same list.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      <Tiles items={[
        ["Bed spaces", c.beds.toLocaleString(), null, `${c.out_of_service} out of service, excluded from the draw`],
        ["Applications", c.applications.toLocaleString(), null, `For ${c.beds.toLocaleString()} beds`],
        ["Taken by priority", String(c.priority), null, "Filled before the ballot is drawn"],
        ["Ballot odds", odds === null ? "—" : `${odds}%`, odds !== null && odds < 50 ? "var(--red-ink)" : null, contested ? `${ballot} beds, ${contested} applicants` : "Nobody in the ballot yet"],
      ]} />
      {odds !== null && odds < 100 ? (
        <Note kind="bad" title="The odds are published, because a student who knows them can act on them">
          After the priority categories are filled, {ballot} beds remain for {contested} applicants — about {odds}%. The system cannot create beds and should not pretend otherwise; a student told now finds lodgings now.
        </Note>
      ) : null}

      <div className="grid grid--2">
        <Panel title={`The session — ${d.session}`} right={d.setting ? `Fee ${money(Number(d.setting.fee))} · hold ${d.setting.hold_hours} h` : "Not yet stated"}>
          <PBody>
            <div className="grid grid--3">
              <Field id="hd-fee" label="Accommodation fee"><input id="hd-fee" className="ctl tnum" value={fee} onChange={(e) => setFee(e.target.value)} disabled={!may || drawn} /></Field>
              <Field id="hd-hold" label="Hold, hours"><input id="hd-hold" className="ctl tnum" value={hold} onChange={(e) => setHold(e.target.value)} disabled={!may || drawn} /></Field>
              <Field id="hd-close" label="Applications close"><input id="hd-close" className="ctl" type="date" value={close} onChange={(e) => setClose(e.target.value)} disabled={!may || drawn} /></Field>
            </div>
            <div><Btn kind="primary" disabled={!may || busy || drawn || !fee} onClick={async () => { if (await send(`/api/bff/api/v1/hostel/sessions/${sess}/setting`, "PUT", { fee: Number(fee), holdHours: Number(hold) || 72, applicationsClose: close || null }, `Accommodation for ${d.session} stated`)) setSaid("The session is stated"); }}>{d.setting ? "Restate" : "State the session"}</Btn></div>
          </PBody>
        </Panel>
        <Panel title="The draw" right={d.setting?.seed ? <span className="sub2">Seed <span className="tnum">{d.setting.seed}</span> · {when(d.setting.drawn_at)}</span> : "Not yet run"}>
          <PBody>
            <div className="sub2">The seed is published with the result. Anyone holding it can reproduce this order exactly — which is what makes it a ballot rather than a list somebody wrote. Fix the seed and publish it <b>before</b> the draw, not after.</div>
            {drawn ? (
              <Note kind="ok" title="The draw has been run">{c.allocated + c.confirmed} allocated, {c.reserves} reserves, {c.lapsed} lapsed so far. A draw is run once; the order it produced is the record.</Note>
            ) : (
              <>
                <Field id="hd-seed" label="Published seed" hint="At least six characters, published to applicants before you press the button."><input id="hd-seed" className="ctl tnum" value={seed} onChange={(e) => setSeed(e.target.value)} disabled={!may} /></Field>
                <div><Btn kind="primary" disabled={!may || busy || seed.trim().length < 6 || !d.setting} onClick={async () => { const j = await send(`/api/bff/api/v1/hostel/sessions/${sess}/draw`, "POST", { seed: seed.trim() }, `Hostel draw for ${d.session} from seed ${seed.trim()}`); if (j) setSaid(`Drawn: ${j.allocated} allocated (${j.priority} by priority), ${j.unsuccessful} reserves`); }}>Run the draw</Btn></div>
              </>
            )}
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              <Btn kind="ghost" disabled={!may || busy || !drawn} onClick={async () => { const j = await send(`/api/bff/api/v1/hostel/sessions/${sess}/lapse`, "POST", {}, `Hostel holds lapsed for ${d.session}`); if (j) setSaid(`${j.lapsed} hold${j.lapsed === 1 ? "" : "s"} lapsed and passed to the next name`); }}>Lapse expired holds now</Btn>
              <span className="sub2">The hold runs whether or not anybody is watching; this applies what has already expired.</span>
            </div>
          </PBody>
        </Panel>
      </div>

      <Panel title="The draw, in order" right={`${d.draw.length} application${d.draw.length === 1 ? "" : "s"}`}>
        {d.draw.length === 0 ? <PBody><div className="sub2">No application for {d.session} yet.</div></PBody> : (
          <DTable cols={["Position|mid", "Matriculation number", "Candidate", "Category", "Hall requested", "Bed", "Hold|mid", "Outcome|num"]}
            rows={d.draw.map((r) => [
              <b className="tnum" key="p">{r.draw_position ?? "—"}</b>,
              <span className="tnum sub2" key="n">{r.number}</span>,
              <span key="c">{r.name}</span>,
              <span className="sub2" key="k">{CATEGORIES.find((x) => x[0] === r.category)?.[1] ?? r.category}</span>,
              <span className="sub2" key="h">{r.hall_requested ?? "Any"}</span>,
              <span className="sub2" key="b">{r.hall_name ? `${r.hall_name} ${r.block}-${r.room_no} · ${r.bed}` : "—"}</span>,
              <span className="tnum sub2" key="w">{r.confirmed_at ? "Paid" : r.lapsed_at ? "Lapsed" : r.held_until ? when(r.held_until) : "—"}</span>,
              r.state === "CONFIRMED" ? <Pil kind="ok" key="o">Confirmed</Pil> : r.state === "ALLOCATED" ? <Pil kind="info" key="o">{r.basis === "PRIORITY" ? "Priority" : r.basis === "RESERVE" ? "Reserve called" : "Bed allocated"}</Pil> : r.state === "UNSUCCESSFUL" ? <Pil kind="grey" key="o">Reserve</Pil> : r.state === "LAPSED" ? <Pil kind="bad" key="o">Lapsed</Pil> : <Pil kind="grey" key="o">Applied</Pil>,
            ])}
            texts={d.draw.map((r) => `${r.number} ${r.name} ${r.state}`)} />
        )}
      </Panel>

      <div className="grid grid--2">
        <Panel title="Inventory" right="A record, not a spreadsheet">
          {d.halls.length ? (
            <DTable cols={["Hall", "Beds|mid", "Rooms|mid", "Out|mid"]} rows={d.halls.map((h) => [<span key="h"><strong>{h.name}</strong><div className="sub2">{h.code}{h.sex ? ` · ${h.sex === "F" ? "female" : "male"}` : " · either"}</div></span>, <span className="tnum" key="b">{h.beds}</span>, <span className="tnum sub2" key="r">{h.rooms}</span>, h.out_of_service ? <b className="tnum" key="o" style={{ color: "var(--red-ink)" }}>{h.out_of_service}</b> : <span className="sub2" key="o">—</span>])} />
          ) : <PBody><div className="sub2">No hall on the register. Add one below; the draw allocates only what is recorded.</div></PBody>}
          {may ? (
            <PBody>
              <div className="grid grid--3">
                <Field id="hh-code" label="Hall code"><input id="hh-code" className="ctl" value={hall.code} onChange={(e) => setHall({ ...hall, code: e.target.value })} placeholder="AKP" /></Field>
                <Field id="hh-name" label="Name"><input id="hh-name" className="ctl" value={hall.name} onChange={(e) => setHall({ ...hall, name: e.target.value })} /></Field>
                <Field id="hh-sex" label="For"><select id="hh-sex" className="ctl" value={hall.sex} onChange={(e) => setHall({ ...hall, sex: e.target.value })}><option value="">Either</option><option value="F">Female</option><option value="M">Male</option></select></Field>
              </div>
              <div><Btn kind="ghost" disabled={busy || !hall.code || !hall.name} onClick={async () => { if (await send("/api/bff/api/v1/hostel/halls", "PUT", hall, `Hall ${hall.code} recorded`)) { setSaid(`Hall ${hall.code.toUpperCase()} recorded`); setHall({ code: "", name: "", sex: "" }); } }}>Record the hall</Btn></div>
              <div className="grid grid--4">
                <Field id="hr-hall" label="Hall"><select id="hr-hall" className="ctl" value={room.hall} onChange={(e) => setRoom({ ...room, hall: e.target.value })}>{d.halls.map((h) => <option key={h.code} value={h.code}>{h.name}</option>)}</select></Field>
                <Field id="hr-block" label="Block"><input id="hr-block" className="ctl" value={room.block} onChange={(e) => setRoom({ ...room, block: e.target.value })} /></Field>
                <Field id="hr-no" label="Room"><input id="hr-no" className="ctl" value={room.roomNo} onChange={(e) => setRoom({ ...room, roomNo: e.target.value })} /></Field>
                <Field id="hr-beds" label="Beds"><input id="hr-beds" className="ctl tnum" value={room.beds} onChange={(e) => setRoom({ ...room, beds: e.target.value })} /></Field>
              </div>
              <div><Btn kind="ghost" disabled={busy || !room.hall || !room.block || !room.roomNo} onClick={async () => { if (await send("/api/bff/api/v1/hostel/rooms", "PUT", { ...room, beds: Number(room.beds) || 1 }, `Room ${room.hall} ${room.block}-${room.roomNo} recorded`)) { setSaid("Room recorded"); setRoom({ ...room, roomNo: "" }); } }}>Record the room</Btn></div>
            </PBody>
          ) : null}
        </Panel>
        <Panel title="Maintenance requests" right={`${d.maintenance.filter((m) => m.state === "RAISED" || m.state === "ASSIGNED").length} open`}>
          {d.maintenance.length ? (
            <DTable cols={["Room", "Issue", "Raised", "State|num"]} rows={d.maintenance.map((m) => [
              <Two key="r" a={`${m.hall_name} ${m.block}-${m.room_no}`} b={`${m.raised_by_name} · ${m.number}`} />,
              <span key="i">{m.issue}{m.note ? <div className="sub2">{m.note}</div> : null}</span>,
              <span className="sub2 tnum" key="w">{when(m.raised_at)}</span>,
              <span key="s">{m.state === "FIXED" || m.state === "CLOSED" ? <Pil kind="ok">{m.state.charAt(0) + m.state.slice(1).toLowerCase()}</Pil> : may ? <>
                {m.state === "RAISED" ? <Btn kind="ghost" disabled={busy} onClick={() => void send(`/api/bff/api/v1/hostel/maintenance/${m.id}`, "POST", { state: "ASSIGNED" }, `Maintenance ${m.issue} assigned`)}>Assign</Btn> : null}{" "}
                <Btn kind="go" disabled={busy} onClick={() => void send(`/api/bff/api/v1/hostel/maintenance/${m.id}`, "POST", { state: "FIXED" }, `Maintenance ${m.issue} fixed`)}>Fixed</Btn>
              </> : <Pil kind="info">{m.state.charAt(0) + m.state.slice(1).toLowerCase()}</Pil>}</span>,
            ])} />
          ) : <PBody><div className="sub2">Nothing raised.</div></PBody>}
        </Panel>
      </div>
    </>
  );
}
