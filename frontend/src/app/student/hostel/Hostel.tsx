"use client";

/** sHostel (V030 + V261): the student's whole stay — the window and eligibility, the application with its preferences and
 *  roommate request, the review, the allocation held and paid, accepted under the rules or declined, the letter, the
 *  roommates, maintenance, a transfer request, checkout, the clearance and its certificate, and the history. */
import { useState } from "react";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { ALLOC_STATE, APP_STATE, CATEGORIES, CLEAR_STATE, MAINT_CATS, REVIEW, TRANSFER_STATE, dayOf, longDay, whenAt, type StudentHostelFull } from "@/lib/hostel";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, Steps } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { naira, onDay, useAct, when } from "../common";

export function Hostel({ h }: { h: StudentHostelFull }) {
  const { act, busy, problem } = useAct();
  const queryNav = useQueryNav();
  const v = h.view;
  const [form, setForm] = useState({ hall: "", category: "NONE", note: "", roomType: "", block: "", specialNeed: "", roommateNumber: "", roommateNote: "" });
  const [issue, setIssue] = useState({ category: "OTHER", priority: "NORMAL", issue: "" });
  const [reference, setReference] = useState<{ reference: string; amount: number } | null>(null);
  const [ask, setAsk] = useState<"decline" | "withdraw" | "transfer" | "checkout" | "rules" | null>(null);
  const [reason, setReason] = useState("");
  const [transfer, setTransfer] = useState({ hall: "", roomType: "" });
  const [checkoutOn, setCheckoutOn] = useState("");
  const [agreed, setAgreed] = useState(false);
  const [now] = useState(() => Date.now());

  const open = v.open === true;
  const appState = v.state ?? null;
  const al = v.allocation_state ?? null;
  const live = !!v.allocation_id && !!al && !["LAPSED", "DECLINED", "CANCELLED", "TRANSFERRED", "CHECKED_OUT"].includes(al);
  const holdLeft = v.held_until ? Math.max(0, Math.round((new Date(v.held_until).getTime() - now) / 36e5)) : null;
  const inRoom = al === "CHECKED_IN";
  const needsRules = !!v.rules && al === "CONFIRMED";
  const place = live ? `${v.hall_name}, Block ${v.block}${v.floor ? `, floor ${v.floor}` : ""}, Room ${v.room_no}, ${v.bed_label ?? `bed ${v.bed}`}` : "";

  async function apply() {
    const r = await act("apply", "POST", "/me/hostel/apply-full", { session: h.session, hall: form.hall || null, category: form.category, note: form.note || null, roomType: form.roomType || null, block: form.block || null, specialNeed: form.specialNeed || null, roommateNumber: form.roommateNumber || null, roommateNote: form.roommateNote || null }, "Hostel application", "Hostel application submitted successfully.");
    if (r) queryNav(`/student/hostel?session=${encodeURIComponent(h.session)}`);
  }
  async function pay() {
    const r = await act("pay", "POST", "/me/hostel/fee-reference", { session: h.session }, "Accommodation fee reference", "");
    if (r) setReference({ reference: String(r.reference), amount: Number(r.amount) });
  }
  async function accept() {
    const r = await act("accept", "POST", "/me/hostel/accept", { session: h.session, rulesVersion: v.rules_version ?? null }, "Hostel allocation accepted", "Hostel allocation accepted successfully.");
    if (r) { setAsk(null); queryNav(`/student/hostel?session=${encodeURIComponent(h.session)}`); }
  }
  async function decline() {
    const r = await act("decline", "POST", "/me/hostel/decline", { session: h.session, reason }, "Hostel allocation declined", "Allocation declined; the bed is released.");
    if (r) { setAsk(null); setReason(""); queryNav(`/student/hostel?session=${encodeURIComponent(h.session)}`); }
  }
  async function withdraw() {
    const r = await act("withdraw", "POST", "/me/hostel/withdraw", { session: h.session, reason }, "Hostel application withdrawn", "Application withdrawn.");
    if (r) { setAsk(null); setReason(""); queryNav(`/student/hostel?session=${encodeURIComponent(h.session)}`); }
  }
  async function requestTransfer() {
    const r = await act("transfer", "POST", "/me/hostel/transfer", { session: h.session, hall: transfer.hall || null, roomType: transfer.roomType || null, reason }, "Room transfer requested", "Transfer request submitted.");
    if (r) { setAsk(null); setReason(""); queryNav(`/student/hostel?session=${encodeURIComponent(h.session)}`); }
  }
  async function requestCheckout() {
    const r = await act("checkout", "POST", "/me/hostel/checkout", { session: h.session, on: checkoutOn || null, reason: reason || null }, "Checkout requested", "Checkout requested; the desk will inspect the room.");
    if (r) { setAsk(null); setReason(""); queryNav(`/student/hostel?session=${encodeURIComponent(h.session)}`); }
  }
  async function raise() {
    const r = await act("raise", "POST", "/me/hostel/maintenance-full", { session: h.session, ...issue }, "Maintenance request", "Maintenance request sent to the housing desk.");
    if (r) { setIssue({ category: "OTHER", priority: "NORMAL", issue: "" }); queryNav(`/student/hostel?session=${encodeURIComponent(h.session)}`); }
  }

  const stepState = (k: number) => {
    const at = !appState ? 0 : ["APPLIED", "UNSUCCESSFUL", "REJECTED"].includes(appState) ? 1 : al === "HELD" ? 2 : al === "CONFIRMED" ? 3 : al === "ACCEPTED" ? 4 : al === "CHECKED_IN" ? (v.clearance_state ? 6 : 5) : al === "CHECKED_OUT" ? 7 : 1;
    return k < at ? "done" : k === at ? "now" : "todo";
  };

  return (
    <>
      <div className="row row--tight" style={{ justifyContent: "space-between", alignItems: "flex-end" }}>
        <div className="sub2">Session</div>
        <Field id="hs-session" label=""><select id="hs-session" className="ctl" value={h.session} onChange={(e) => queryNav(`/student/hostel?session=${encodeURIComponent(e.target.value)}`)}>{(h.sessions.includes(h.session) ? h.sessions : [h.session, ...h.sessions]).map((s) => <option key={s} value={s}>{s}</option>)}</select></Field>
      </div>

      {v.fee === null || v.fee === undefined ? (
        <Note kind="info" title={`Accommodation for ${h.session} is not open yet`}>The housing desk states the accommodation fee, the window and the rules before applications open. You do not currently have a hostel allocation for this academic session.</Note>
      ) : inRoom ? (
        <Note kind="ok" title={`You are checked in — ${place}`} action={<span className="row row--inline row--tight"><a href={`/student/hostel/letter?session=${encodeURIComponent(h.session)}`} target="_blank" rel="noopener" className="btn btn--ghost btn--sm">Allocation letter (PDF)</a>{!v.checkout_requested_at ? <Btn kind="secondary" onClick={() => setAsk("checkout")}>Request checkout</Btn> : null}{!v.transfer_state || ["REJECTED", "COMPLETED", "CANCELLED"].includes(v.transfer_state) ? <Btn kind="ghost" onClick={() => setAsk("transfer")}>Request a transfer</Btn> : null}</span>}>
          Checked in {when(v.checked_in_at)}{v.end_on ? ` · stay to ${onDay(v.end_on)}` : ""}. {v.checkout_requested_at ? `Checkout requested for ${onDay(v.checkout_on)}; the desk inspects the room, then clears you.` : "Report a fault below; a transfer or a checkout is asked for from here."}
        </Note>
      ) : al === "ACCEPTED" ? (
        <Note kind="ok" title={`Allocation accepted — check in at the porter's lodge`} action={<a href={`/student/hostel/letter?session=${encodeURIComponent(h.session)}`} target="_blank" rel="noopener" className="btn btn--primary btn--sm">Allocation letter (PDF)</a>}>
          {place}. Bring the letter and your identity card; the porter records your check-in and the condition of the room.
        </Note>
      ) : al === "CONFIRMED" ? (
        <Note kind="info" title="Fee confirmed — accept your allocation" action={<span className="row row--inline row--tight"><Btn kind="primary" onClick={() => (needsRules ? setAsk("rules") : void accept())} disabled={busy !== null}>Accept allocation</Btn><Btn kind="ghost" onClick={() => setAsk("decline")}>Decline</Btn></span>}>
          {place}. {needsRules ? `The hostel rules (version ${v.rules_version}) are acknowledged once when you accept.` : "Accepting confirms you will take the bed; declining releases it to the next name."}
        </Note>
      ) : al === "HELD" ? (
        <Note kind="bad" title={`A bed is held for you — ${holdLeft} hour${holdLeft === 1 ? "" : "s"} to pay`} action={<span className="row row--inline row--tight"><Btn kind="urgent" disabled={busy !== null} onClick={() => void pay()}>Pay {naira(v.fee)} now</Btn><Btn kind="ghost" onClick={() => setAsk("decline")}>Decline</Btn></span>}>
          {place}. The hold runs to {when(v.held_until)} whether anybody is watching; unpaid, the bed goes to the next name on the list. Generate the reference and pay it at the bank or by card; the Bursary&rsquo;s confirmation makes the bed yours.
        </Note>
      ) : al === "CHECKED_OUT" || v.clearance_state === "CLEARED" ? (
        <Note kind="ok" title="Checked out and cleared" action={<a href={`/student/hostel/clearance?session=${encodeURIComponent(h.session)}`} target="_blank" rel="noopener" className="btn btn--primary btn--sm">Clearance certificate (PDF)</a>}>Your stay for {h.session} is closed with clearance {v.clearance_ref}.</Note>
      ) : appState === "LAPSED" ? (
        <Note kind="bad" title="Your hold lapsed">The bed held for you was not paid for within {v.hold_hours} hours and went to the next name on the list. Ask the housing desk whether a bed is free.</Note>
      ) : appState === "UNSUCCESSFUL" ? (
        <Note kind="info" title={`Waiting list${v.draw_position ? ` — position ${v.draw_position}` : ""}`}>Your hostel application is currently on the waiting list. Beds are offered in list order when one becomes free; you will see a bed appear here with its own hold window if one does.</Note>
      ) : appState === "REJECTED" ? (
        <Note kind="bad" title="Your application was not approved">{v.review_note ?? "The housing desk did not approve the application."}</Note>
      ) : appState === "APPLIED" ? (
        <Note kind="info" title={v.review === "CORRECTION" ? "The housing desk asks for a correction" : v.requires_review && !v.review ? "Applied — under review" : "Applied — allocation not yet made"} action={<Btn kind="ghost" onClick={() => setAsk("withdraw")}>Withdraw</Btn>}>
          {v.review === "CORRECTION" ? `${v.review_note ?? ""} Withdraw and apply again with the correction.` : v.category && v.category !== "NONE" ? `You applied under a priority category (${CATEGORIES.find((c) => c[0] === v.category)?.[1] ?? v.category}), which is filled first, by rule and by name.` : "Allocation follows when the window closes; preferences are not a promise of a particular hall or room."} Applications {v.applications_close ? `close ${onDay(v.applications_close)}` : "close when the allocation is made"}.
        </Note>
      ) : !open ? (
        <Note kind="info" title="Applications are closed">{v.drawn_at ? `The allocation for ${h.session} was made on ${onDay(v.drawn_at)}.` : v.window_state === "DRAFT" ? "The window is not yet open." : v.applications_open && new Date(v.applications_open).getTime() > now ? `Applications open ${onDay(v.applications_open)}.` : `Applications for ${h.session} closed ${onDay(v.applications_close)}.`} You did not apply.</Note>
      ) : v.eligible === false ? (
        <Note kind="bad" title="You are not eligible to apply this session">{v.eligibility_why}</Note>
      ) : (
        <Note kind="info" title={`Apply for a bed — ${naira(v.fee)} for the session`}>You are eligible. {v.allocation_method === "BALLOT" ? "Priority categories are filled first; the rest is drawn by ballot from a published seed." : "Beds are allocated by the University's stated policy."} A bed is then held for {v.hold_hours} hours for payment. Applications {v.applications_close ? `close ${onDay(v.applications_close)}` : "close when the allocation is made"}.</Note>
      )}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {reference ? (
        <Note kind="info" title={`Pay ${naira(reference.amount)} against ${reference.reference}`} action={<LinkBtn kind="primary" href="/student/fees">Fees &amp; payments</LinkBtn>}>
          The reference is on your Fees page with the card option and the bank details. Confirmed, it makes the bed yours; the hold clock keeps running until then.
        </Note>
      ) : null}
      {v.damage_due ? <Note kind="bad" title={`A damage charge of ${naira(v.damage_due)} stands against you`}>Pay the reference on your Fees page; hostel clearance completes when it is settled or waived.</Note> : null}

      {appState || live ? (
        <Steps list={[
          [stepState(1), "Applied", v.application_ref ?? ""], [stepState(2), "Allocated", v.allocation_ref ?? "A bed held"], [stepState(3), "Fee paid", v.confirmed_at ? onDay(v.confirmed_at) : `${naira(v.fee)}`],
          [stepState(4), "Accepted", v.accepted_at ? onDay(v.accepted_at) : "Under the rules"], [stepState(5), "Checked in", v.checked_in_at ? onDay(v.checked_in_at) : "At the lodge"], [stepState(6), "Checkout", v.checkout_on ? onDay(v.checkout_on) : "Inspection"], [stepState(7), "Cleared", v.clearance_ref ?? "Certificate"],
        ]} />
      ) : null}

      {open && !appState ? (
        <Panel title="Apply for accommodation" right={h.session}>
          <PBody>
            <div className="grid grid--2">
              <Field id="hs-hall" label="Hall preferred" hint="A preference, not a promise: the allocation fills it if a bed is free when your turn comes.">
                <select id="hs-hall" className="ctl" value={form.hall} onChange={(e) => setForm({ ...form, hall: e.target.value })}>
                  <option value="">Any hall</option>
                  {h.halls.map((x) => <option key={x.code} value={x.code}>{x.name}{x.sex ? ` (${x.sex === "F" ? "female" : "male"})` : ""}{x.campus ? ` · ${x.campus}` : ""} · {x.free ?? 0} of {x.beds ?? 0} beds free</option>)}
                </select>
              </Field>
              <Field id="hs-type" label="Room type preferred">
                <select id="hs-type" className="ctl" value={form.roomType} onChange={(e) => setForm({ ...form, roomType: e.target.value })}>
                  <option value="">Any</option>{h.roomTypes.map((t) => <option key={t.code} value={t.code}>{t.label} · {t.beds} bed{t.beds === 1 ? "" : "s"}</option>)}
                </select>
              </Field>
              <Field id="hs-block" label="Block preferred" hint="The block's code, if you have one"><input id="hs-block" className="ctl" value={form.block} onChange={(e) => setForm({ ...form, block: e.target.value.toUpperCase() })} maxLength={12} /></Field>
              <Field id="hs-cat" label="Priority category" hint="Verified against its rule; a false claim is refused before the allocation.">
                <select id="hs-cat" className="ctl" value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>{CATEGORIES.map(([c, l]) => <option key={c} value={c}>{l}</option>)}</select>
              </Field>
              {form.category !== "NONE" ? <Field id="hs-note" label="What the category rests on" hint="The letter, the condition, the team — one line; the office checks it." full><input id="hs-note" className="ctl" value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} autoComplete="off" /></Field> : null}
              <Field id="hs-special" label="Special or medical accommodation need" hint="A ground-floor room, accessibility, a medical need — say what" full><input id="hs-special" className="ctl" value={form.specialNeed} onChange={(e) => setForm({ ...form, specialNeed: e.target.value })} /></Field>
              <Field id="hs-rm" label="Preferred roommate (matriculation number)" hint="Both must be eligible and of the same hall restriction; not guaranteed"><input id="hs-rm" className="ctl" value={form.roommateNumber} onChange={(e) => setForm({ ...form, roommateNumber: e.target.value })} autoComplete="off" /></Field>
              <Field id="hs-rmn" label="Roommate note"><input id="hs-rmn" className="ctl" value={form.roommateNote} onChange={(e) => setForm({ ...form, roommateNote: e.target.value })} /></Field>
            </div>
            <div className="sub2 mt-1">Your student information (name, faculty, department, programme, level and sex) is read from your record and cannot be edited here.</div>
            <div className="mt-2"><Btn kind="primary" disabled={busy !== null || (form.category !== "NONE" && !form.note.trim())} onClick={() => void apply()}>Submit application</Btn></div>
          </PBody>
        </Panel>
      ) : null}

      {live ? (
        <div className="grid grid--2">
          <Panel title="My allocation" right={<Pil kind={ALLOC_STATE[al ?? ""]?.[1] ?? "grey"}>{ALLOC_STATE[al ?? ""]?.[0] ?? al}</Pil>}>
            <PBody>
              <KvGrid cls="grid--2" pairs={[
                ["Reference", <span key="r" className="tnum">{v.allocation_ref}</span>], ["Session", h.session],
                ["Hall", `${v.hall_name ?? "—"}${v.hall_campus ? ` · ${v.hall_campus}` : ""}`], ["Block · floor", `${v.block ?? "—"}${v.floor ? ` · floor ${v.floor}` : ""}`],
                ["Room", `${v.room_no ?? "—"}${v.room_type ? ` · ${v.room_type}` : ""}`], ["Bed", v.bed_label ?? `Bed ${v.bed ?? "—"}`],
                ["Fee", v.confirmed_at ? `${naira(v.fee)} — paid ${onDay(v.confirmed_at)}` : `${naira(v.fee)} — ${holdLeft} h left on the hold`],
                ["Basis", v.basis === "PRIORITY" ? "Priority" : v.basis === "RESERVE" ? `From the waiting list, position ${v.draw_position}` : `Ballot, position ${v.draw_position}`],
                ["Stay", `${dayOf(v.start_on)} – ${dayOf(v.end_on)}`], ["Check-in", v.checked_in_at ? when(v.checked_in_at) : "Not yet"],
              ]} />
              {v.hall_location ? <div className="sub2 mt-1">{v.hall_location}</div> : null}
              <div className="row row--tight mt-2">
                {al === "HELD" ? <Btn kind="primary" disabled={busy !== null} onClick={() => void pay()}>Generate the payment reference</Btn> : null}
                {al !== "HELD" ? <a href={`/student/hostel/letter?session=${encodeURIComponent(h.session)}`} target="_blank" rel="noopener" className="btn btn--secondary btn--sm">Allocation letter (PDF)</a> : null}
              </div>
            </PBody>
          </Panel>
          <Panel title="Roommates" right={h.roommates.length ? `${h.roommates.length} in the room` : "Nobody else yet"}>
            {h.roommates.length ? <DTable cols={["Bed|mid", "Name", "Number", "Programme"]} rows={h.roommates.map((r) => [<span key="b" className="tnum">{r.bed ?? "—"}</span>, r.name, <span key="n" className="tnum sub2">{r.number}</span>, <span key="p" className="sub2">{r.programme ?? "—"}</span>])} /> : <PBody><div className="sub2">The other beds in {v.room_no ? `room ${v.room_no}` : "the room"} are not yet taken.</div></PBody>}
          </Panel>
        </div>
      ) : null}

      {live && al !== "HELD" ? (
        <Panel title="Maintenance and complaints" right="Raised from your room">
          {h.maintenance.length ? (
            <DTable cols={["Issue", "Category|mid", "Raised|mid", "Status|num"]} rows={h.maintenance.map((m) => [<span key="i">{m.issue}{m.note ? <div className="sub2">{m.note}</div> : null}</span>, <span key="c" className="sub2">{MAINT_CATS.find((c) => c[0] === m.category)?.[1] ?? m.category}</span>, <span className="sub2 tnum" key="r">{onDay(m.raised_at)}</span>, <Pil key="s" kind={m.state === "FIXED" || m.state === "CLOSED" ? "ok" : m.state === "ASSIGNED" ? "info" : "bad"}>{m.state.charAt(0) + m.state.slice(1).toLowerCase()}</Pil>])} />
          ) : <PBody><div className="sub2">Nothing raised for this room yet.</div></PBody>}
          <PBody>
            <div className="grid grid--3">
              <Field id="hs-mc" label="What kind of fault"><select id="hs-mc" className="ctl" value={issue.category} onChange={(e) => setIssue({ ...issue, category: e.target.value })}>{MAINT_CATS.map(([c, l]) => <option key={c} value={c}>{l}</option>)}</select></Field>
              <Field id="hs-mp" label="Urgency"><select id="hs-mp" className="ctl" value={issue.priority} onChange={(e) => setIssue({ ...issue, priority: e.target.value })}><option value="LOW">Low</option><option value="NORMAL">Normal</option><option value="HIGH">High</option><option value="URGENT">Urgent</option></select></Field>
              <Field id="hs-issue" label="What is wrong" hint="One line"><input id="hs-issue" className="ctl" value={issue.issue} onChange={(e) => setIssue({ ...issue, issue: e.target.value })} autoComplete="off" /></Field>
            </div>
            <div><Btn kind="ghost" disabled={busy !== null || !issue.issue.trim()} onClick={() => void raise()}>Send to the housing desk</Btn></div>
          </PBody>
        </Panel>
      ) : null}

      {h.transfers.length ? (
        <Panel title="Transfer requests">
          <DTable cols={["Asked for", "Reason", "Submitted|mid", "Status|mid", "Decision"]} rows={h.transfers.map((t) => [<span key="a">{t.requested_hall ?? "Any hall"}{t.requested_type ? ` · ${t.requested_type}` : ""}</span>, t.reason, <span key="s" className="tnum sub2">{dayOf(t.submitted_at)}</span>, <Pil key="st" kind={TRANSFER_STATE[t.state]?.[1] ?? "grey"}>{TRANSFER_STATE[t.state]?.[0] ?? t.state}</Pil>, <span key="d" className="sub2">{t.decision_note ?? ""}</span>])} />
        </Panel>
      ) : null}

      {h.clearanceItems.length ? (
        <Panel title={`Hostel clearance ${v.clearance_ref ?? ""}`} right={<Pil kind={CLEAR_STATE[v.clearance_state ?? "PENDING"]?.[1] ?? "grey"}>{CLEAR_STATE[v.clearance_state ?? "PENDING"]?.[0] ?? v.clearance_state}</Pil>}>
          <DTable cols={["Requirement", "Status|mid", "Decided|mid", "Remarks"]} rows={h.clearanceItems.map((i) => [i.label, <Pil key="s" kind={CLEAR_STATE[i.state]?.[1] ?? "grey"}>{CLEAR_STATE[i.state]?.[0] ?? i.state}</Pil>, <span key="d" className="tnum sub2">{i.decided_at ? dayOf(i.decided_at) : "—"}</span>, <span key="r" className="sub2">{i.remarks ?? ""}</span>])} />
          {h.charges.length ? <PBody><div className="sub2">Damage charges: {h.charges.map((c) => `${c.description} ${naira(c.charge)}${c.waived_at ? " (waived)" : c.settled_at ? " (settled)" : c.reference ? ` — pay ${c.reference}` : ""}`).join("; ")}</div></PBody> : null}
        </Panel>
      ) : live && inRoom ? <Note kind="info" title="No clearance record">Your hostel checkout/clearance process has not yet started. Request a checkout when you are ready to leave.</Note> : null}

      {v.rules ? (
        <Panel title="Hostel rules and regulations" right={`Version ${v.rules_version}${v.rules_accepted ? ` · acknowledged` : ""}`}>
          <PBody><div style={{ whiteSpace: "pre-wrap" }}>{v.rules}</div></PBody>
        </Panel>
      ) : null}

      <Panel title="Accommodation history" right={h.history.length ? `${h.history.length} record${h.history.length === 1 ? "" : "s"}` : "none yet"}>
        {h.history.length ? (
          <DTable cols={["Session|mid", "Hostel", "Room|mid", "Bed|mid", "Allocated|mid", "Checkout|mid", "Status|num"]} rows={h.history.map((x, i) => [
            <span className="tnum" key="s">{x.session}</span>, <span key="h">{x.hall_name ?? "—"}</span>,
            <span className="tnum" key="r">{x.block && x.room_no ? `${x.block}-${x.room_no}` : "—"}</span>, <span className="tnum" key="b">{x.bed_label ?? "—"}</span>,
            <span className="tnum sub2" key="a">{x.allocated_at ? dayOf(x.allocated_at) : "—"}</span>, <span className="tnum sub2" key="c">{x.checked_out_at ? dayOf(x.checked_out_at) : "—"}</span>,
            x.allocation_state ? <Pil key={`o${i}`} kind={ALLOC_STATE[x.allocation_state]?.[1] ?? "grey"}>{ALLOC_STATE[x.allocation_state]?.[0] ?? x.allocation_state}</Pil> : <Pil key={`o${i}`} kind={APP_STATE[x.application_state]?.[1] ?? "grey"}>{APP_STATE[x.application_state]?.[0] ?? x.application_state}</Pil>,
          ])} />
        ) : <PBody><div className="sub2">No application on your record yet.</div></PBody>}
      </Panel>

      {h.events.length ? (
        <Panel title="Trail" right="Every step kept">
          <DTable cols={["When|mid", "What", "Note"]} rows={h.events.map((e) => [<span key="w" className="tnum sub2">{whenAt(e.at)}</span>, <span key="a">{e.action.replace(/_/g, " ").toLowerCase()}{e.to_value ? <span className="sub2"> · {e.to_value}</span> : null}</span>, <span key="n" className="sub2">{e.note ?? ""}</span>])} pageSize={10} />
        </Panel>
      ) : null}

      {ask === "rules" ? (
        <Modal title="Hostel rules and regulations" sub={`Version ${v.rules_version} — acknowledged once`} wide onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Not now</Btn><Btn kind="primary" onClick={() => void accept()} disabled={!agreed || busy !== null}>Accept the allocation</Btn></>}>
          <div style={{ whiteSpace: "pre-wrap", maxHeight: 360, overflow: "auto" }}>{v.rules}</div>
          <label className="row row--tight mt-2" style={{ gap: 8 }}><input type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} /> I have read the hostel rules and regulations and will abide by them.</label>
        </Modal>
      ) : ask === "decline" || ask === "withdraw" ? (
        <Modal title={ask === "decline" ? "Decline the allocation" : "Withdraw the application"} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="urgent" onClick={() => void (ask === "decline" ? decline() : withdraw())} disabled={busy !== null || !reason.trim()}>{ask === "decline" ? "Decline and release the bed" : "Withdraw"}</Btn></>}>
          <p>{ask === "decline" ? "The bed is released to the next name on the list. A declined allocation is kept on your record; any refund of a paid fee is a Bursary decision." : "The application leaves the list. You may apply again while the window is open."}</p>
          <Field id="hs-reason" label="Reason" required full><textarea id="hs-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : ask === "transfer" ? (
        <Modal title="Request a room transfer" onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void requestTransfer()} disabled={busy !== null || !reason.trim()}>Submit</Btn></>}>
          <p>Your current allocation stands until the housing desk approves and moves you; nothing changes before then.</p>
          <div className="grid grid--2">
            <Field id="tr-hall" label="Hall requested"><select id="tr-hall" className="ctl" value={transfer.hall} onChange={(e) => setTransfer({ ...transfer, hall: e.target.value })}><option value="">Any hall</option>{h.halls.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
            <Field id="tr-type" label="Room type requested"><select id="tr-type" className="ctl" value={transfer.roomType} onChange={(e) => setTransfer({ ...transfer, roomType: e.target.value })}><option value="">Any</option>{h.roomTypes.map((t) => <option key={t.code} value={t.code}>{t.label}</option>)}</select></Field>
          </div>
          <Field id="tr-reason" label="Reason" required full><textarea id="tr-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : ask === "checkout" ? (
        <Modal title="Request checkout" onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void requestCheckout()} disabled={busy !== null}>Request checkout</Btn></>}>
          <p>{place}. The housing desk inspects the room, the bed, the furniture and the keys, then completes your clearance; the bed is released when it is complete.</p>
          <div className="grid grid--2">
            <Field id="co-on" label="Intended checkout date"><input id="co-on" type="date" className="ctl" value={checkoutOn} onChange={(e) => setCheckoutOn(e.target.value)} /></Field>
            <Field id="co-reason" label="Reason"><input id="co-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
          </div>
        </Modal>
      ) : null}
      <div className="sub2">Need help? <Link className="lnk" href="/student/support">Help &amp; requests</Link> · the housing desk answers from there.</div>
    </>
  );
}
