"use client";

/** sHostel — proto/part8.html: the allocation, the maintenance requests, the history — from the draw, the hold and the fee (V030). */
import { useState } from "react";
import { CATEGORIES, type StudentHostel } from "@/lib/hostel";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, onDay, useAct, when } from "../common";

export function Hostel({ h }: { h: StudentHostel }) {
  const { act, busy, problem } = useAct();
  const v = h.view;
  const [hall, setHall] = useState("");
  const [category, setCategory] = useState("NONE");
  const [note, setNote] = useState("");
  const [issue, setIssue] = useState("");
  const [reference, setReference] = useState<{ reference: string; amount: number } | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const open = v.open === true;
  const state = v.state ?? null;
  const [now] = useState(() => Date.now());
  const holdLeft = v.held_until ? Math.max(0, Math.round((new Date(v.held_until).getTime() - now) / 36e5)) : null;
  const confirmed = state === "CONFIRMED";
  const allocated = state === "ALLOCATED" && !v.lapsed_at;

  async function apply() {
    const r = await act("apply", "POST", "/me/hostel/apply", { session: h.session, hall: hall || null, category, note: note || null }, "Hostel application");
    if (r) setSaid("Your application is in. The draw is run by Student Services from a published seed; you will see your position here.");
  }
  async function pay() {
    const r = await act("pay", "POST", "/me/hostel/fee-reference", { session: h.session }, "Accommodation fee reference");
    if (r) setReference({ reference: String(r.reference), amount: Number(r.amount) });
  }
  async function raise() {
    const r = await act("raise", "POST", "/me/hostel/maintenance", { session: h.session, issue }, "Maintenance request");
    if (r) { setIssue(""); setSaid("The request is with Student Services; it is listed below with its state."); }
  }

  return (
    <>
      {v.fee === null || v.fee === undefined ? (
        <Note kind="info" title={`Accommodation for ${h.session} is not open yet`}>Student Services states the accommodation fee, the hold window and the closing date before applications open. Nothing here is a guess: until it is stated, there is nothing to apply for.</Note>
      ) : confirmed ? (
        <Note kind="ok" title="Bed space confirmed">{v.hall_name}, Block {v.block}, Room {v.room_no}, bed {v.bed} of {v.beds}. Confirmed {when(v.confirmed_at)} after payment. Check in at the porter&rsquo;s lodge with your identity card.</Note>
      ) : allocated ? (
        <Note kind="bad" title={`A bed is held for you — ${holdLeft} hour${holdLeft === 1 ? "" : "s"} to pay`} action={<Btn kind="urgent" disabled={busy !== null} onClick={() => void pay()}>Pay {naira(v.fee)} now</Btn>}>
          {v.hall_name}, Block {v.block}, Room {v.room_no}, bed {v.bed}. The hold runs to {when(v.held_until)} whether anybody is watching; unpaid, the bed goes to the next name on the draw, not back to the office. Generate the reference and pay it at the bank or by card; the Bursary&rsquo;s confirmation is what makes the bed yours.
        </Note>
      ) : state === "LAPSED" ? (
        <Note kind="bad" title="Your hold lapsed">The bed held for you was not paid for within {v.hold_hours} hours and went to the next name on the draw. Ask Student Services whether a lapsed bed is free.</Note>
      ) : state === "UNSUCCESSFUL" ? (
        <Note kind="info" title={`Reserve ${v.draw_position ?? ""} on the draw`}>Every bed was taken before your position came up. Reserves are called in draw order when a hold lapses unpaid — you will see a bed appear here with its own hold window if one does.</Note>
      ) : state === "APPLIED" ? (
        <Note kind="info" title="Applied — the draw has not been run">{v.category && v.category !== "NONE" ? `You applied under a priority category (${CATEGORIES.find((c) => c[0] === v.category)?.[1] ?? v.category}), which is filled first, by rule and by name.` : "Priority categories are filled first; the rest is drawn by ballot from a seed published before the draw, so the order is nobody's to arrange."} Applications {v.applications_close ? `close ${onDay(v.applications_close)}` : "close when the draw is run"}.</Note>
      ) : !open ? (
        <Note kind="info" title="Applications are closed">{v.drawn_at ? `The draw for ${h.session} was run on ${onDay(v.drawn_at)} from seed ${v.seed}.` : `Applications for ${h.session} closed ${onDay(v.applications_close)}.`} You did not apply.</Note>
      ) : (
        <Note kind="info" title={`Apply for a bed — ${naira(v.fee)} for the session`}>Priority categories are filled first, by rule and by name. What is left is drawn by ballot from a published seed; a bed is then held for {v.hold_hours} hours for payment, and lapses to the next name if it is not paid.</Note>
      )}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title="Done">{said}</Note> : null}
      {reference ? (
        <Note kind="info" title={`Pay ${naira(reference.amount)} against ${reference.reference}`} action={<LinkBtn kind="primary" href="/student/fees">Fees &amp; payments</LinkBtn>}>
          The reference is on your Fees page with the card option and the bank details. Confirmed, it makes the bed yours; the hold clock keeps running until then.
        </Note>
      ) : null}

      {open && !state ? (
        <Panel title="Apply for accommodation" right={h.session}>
          <PBody>
            <div className="grid grid--2">
              <Field id="hs-hall" label="Hall preferred" hint="A preference, not a promise: the draw fills it if a bed is free when your position comes up.">
                <select id="hs-hall" className="ctl" value={hall} onChange={(e) => setHall(e.target.value)}>
                  <option value="">Any hall</option>
                  {h.halls.map((x) => <option key={x.code} value={x.code}>{x.name}{x.sex ? ` (${x.sex === "F" ? "female" : "male"})` : ""} · {x.beds} beds</option>)}
                </select>
              </Field>
              <Field id="hs-cat" label="Priority category" hint="Verified by Student Services against its rule; a false claim is refused before the draw.">
                <select id="hs-cat" className="ctl" value={category} onChange={(e) => setCategory(e.target.value)}>
                  {CATEGORIES.map(([c, l]) => <option key={c} value={c}>{l}</option>)}
                </select>
              </Field>
            </div>
            {category !== "NONE" ? (
              <Field id="hs-note" label="What the category rests on" hint="The letter, the condition, the team — one line; the office checks it.">
                <input id="hs-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} autoComplete="off" />
              </Field>
            ) : null}
            <div><Btn kind="primary" disabled={busy !== null || (category !== "NONE" && !note.trim())} onClick={() => void apply()}>Apply</Btn></div>
          </PBody>
        </Panel>
      ) : null}

      {state && (allocated || confirmed) ? (
        <div className="grid grid--2">
          <Panel title="Your allocation">
            <PBody>
              <KvGrid cls="grid--2" pairs={[
                ["Hall", v.hall_name ?? "—"], ["Block & room", `${v.block ?? "—"} · ${v.room_no ?? "—"}`], ["Bed", `${v.bed ?? "—"} of ${v.beds ?? "—"}`],
                ["Session", h.session], ["Fee", confirmed ? `${naira(v.fee)} — paid` : `${naira(v.fee)} — ${holdLeft} h left on the hold`],
                ["Basis", v.basis === "PRIORITY" ? "Priority category" : v.basis === "RESERVE" ? `Reserve, position ${v.draw_position}` : `Ballot, position ${v.draw_position}`],
              ]} />
              {!confirmed ? <div className="mt-1"><Btn kind="primary" disabled={busy !== null} onClick={() => void pay()}>Generate the payment reference</Btn></div> : null}
            </PBody>
          </Panel>
          <Panel title="Maintenance requests" right="Raised by anyone in the room">
            {h.maintenance.length ? (
              <DTable cols={["Issue", "Raised", "Status|num"]} rows={h.maintenance.map((m) => [<span key="i">{m.issue}{m.note ? <div className="sub2">{m.note}</div> : null}</span>, <span className="sub2 tnum" key="r">{onDay(m.raised_at)}</span>, <Pil key="s" kind={m.state === "FIXED" || m.state === "CLOSED" ? "ok" : m.state === "ASSIGNED" ? "info" : "bad"}>{m.state.charAt(0) + m.state.slice(1).toLowerCase()}</Pil>])} />
            ) : <PBody><div className="sub2">{confirmed ? "Nothing raised for this room yet." : "Requests are raised from a confirmed room."}</div></PBody>}
            {confirmed ? (
              <PBody>
                <Field id="hs-issue" label="Raise a request" hint="One line: what is wrong.">
                  <input id="hs-issue" className="ctl" value={issue} onChange={(e) => setIssue(e.target.value)} autoComplete="off" />
                </Field>
                <div><Btn kind="ghost" disabled={busy !== null || !issue.trim()} onClick={() => void raise()}>Send to Student Services</Btn></div>
              </PBody>
            ) : null}
          </Panel>
        </div>
      ) : null}

      <Panel title="Allocation history" right={h.history.length ? `${h.history.length} session${h.history.length === 1 ? "" : "s"}` : "none yet"}>
        {h.history.length ? (
          <DTable cols={["Session|mid", "Hall", "Room|mid", "Outcome|num"]} rows={h.history.map((x) => [
            <span className="tnum" key="s">{x.session}</span>,
            <span key="h">{x.hall_name ?? "—"}</span>,
            <span className="tnum" key="r">{x.block && x.room_no ? `${x.block}-${x.room_no}${x.bed ? ` · bed ${x.bed}` : ""}` : "—"}</span>,
            x.state === "CONFIRMED" ? <Pil kind="ok" key="o">{x.session === h.session ? "Current" : "Cleared at check-out"}</Pil> : x.state === "UNSUCCESSFUL" ? <span className="sub2" key="o">Not allocated — ballot unsuccessful</span> : x.state === "LAPSED" ? <Pil kind="bad" key="o">Lapsed unpaid</Pil> : <Pil kind="info" key="o">{x.state.charAt(0) + x.state.slice(1).toLowerCase()}</Pil>,
          ])} />
        ) : <PBody><div className="sub2">No application on your record yet.</div></PBody>}
      </Panel>
    </>
  );
}
