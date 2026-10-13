"use client";

/**
 * V433: the Quickteller (Interswitch PAYDirect) door on the Gateways screen — its state against its own rhythm, who calls
 * it, the addresses it is kept to, and the silence watch that tells the Directorate of ICT and the Bursary once per silence.
 */
import { useState } from "react";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { Btn, Note, PBody, Panel, Pil, Tiles } from "@/components/proto/ui";
import { when, type PaydirectDoor as Door } from "@/lib/bursary";

type Send = (path: string, body: unknown, reason: string, method?: string) => Promise<Record<string, unknown> | null>;

/** what the door's state means */
const STATE: Record<string, [string, "ok" | "bad" | "warn" | "grey", string]> = {
  NEVER: ["Never called", "grey", "No validation or payment notification has reached the door yet."],
  OK: ["Within its rhythm", "ok", "The door is hearing from Interswitch as usual."],
  QUIET: ["Quiet", "warn", "Longer than usual since the last call, but too few calls in the fortnight before it to judge by; not reported."],
  SILENT: ["Silent", "bad", "Quiet for longer than its own rhythm allows: the Directorate of ICT and the Bursary are told once per silence."],
};

function hoursWord(h: number): string {
  if (!Number.isFinite(h)) return "—";
  if (h >= 48) return `${Math.round(h / 24)} days`;
  return `${Math.round(h * 10) / 10} h`;
}

export function PayDirectDoor({ door, mayConfigure, mayWatch, busy, send }: { door: Door; mayConfigure: boolean; mayWatch: boolean; busy: boolean; send: Send }) {
  const [add, setAdd] = useState({ address: "", label: "" });
  const [hours, setHours] = useState(String(door.silence_hours));
  const [checked, setChecked] = useState<number | null>(null);
  const [label, kind, meaning] = STATE[door.state] ?? [door.state, "grey", ""];
  const hoursOk = /^[0-9]{1,3}$/.test(hours) && Number(hours) >= 1 && Number(hours) <= 168;
  return (
    <Panel title="The Quickteller door" right={<Pil kind={kind}>{label}</Pil>}>
      <PBody>
        <Tiles items={[
          ["Last validation", door.last_validation_at ? when(door.last_validation_at) : "never", null, "Quickteller asking about a reference"],
          ["Last notification", door.last_notification_at ? when(door.last_notification_at) : "never", null, "A payment reported to the portal"],
          ["Quiet for", door.last_call_at ? hoursWord(Number(door.quiet_hours)) : "—", door.state === "SILENT" ? "var(--red-ink)" : null,
            door.last_call_at ? `Reported past ${hoursWord(Number(door.threshold_hours))}: the longer of ${door.silence_hours} h and 1.5 × the longest quiet spell of the last fortnight (${hoursWord(Number(door.longest_gap_hours))} over ${door.calls_14d} calls)` : "Nothing to measure yet"],
          ["Calls, 7 days", String(door.calls_7d), null, `${door.calls_today} today · ${door.refused_7d} refused by the address list`],
        ]} />
        <div className="sub2">{meaning}{door.last_alert_at ? ` Last reported ${when(door.last_alert_at)}.` : ""}</div>
        <Note kind="info" title="How a silence is judged">
          The door is silent when nothing has reached it for longer than the hours set here, or than one and a half times the longest quiet spell among its calls in
          the fortnight before the last one, whichever is longer. A door with fewer than twenty calls in that fortnight has no rhythm to judge by and is not reported.
          The Directorate of ICT and the Bursary are told once per silence, by e-mail, SMS and on the portal; the message names any call the door itself refused.
        </Note>
        <div className="row">
          {mayConfigure ? (
            <>
              <label className="row"><input type="checkbox" checked={door.watch_enabled} disabled={busy}
                onChange={(e) => void send("/paydirect/door", { watch: e.target.checked }, e.target.checked ? "Quickteller door watch switched on" : "Quickteller door watch switched off", "PUT")} /> Watch the door</label>
              <Field id="pdd-hours" label="Least silence reported, hours"><input id="pdd-hours" className="ctl tnum" value={hours} onChange={(e) => setHours(e.target.value)} /></Field>
              <Btn kind="primary" size="sm" disabled={busy || !hoursOk || Number(hours) === door.silence_hours}
                onClick={() => void send("/paydirect/door", { silenceHours: Number(hours) }, `Quickteller door: a silence reported past ${hours} hours`, "PUT")}>Save</Btn>
            </>
          ) : null}
          {mayWatch ? <Btn kind="ghost" size="sm" disabled={busy} onClick={async () => { const j = await send("/paydirect/door/watch", {}, "Quickteller door checked now"); if (j) setChecked(Number(j.told)); }}>Check now</Btn> : null}
        </div>
        {checked !== null ? <div className="sub2">{checked > 0 ? `Silent: ${checked} message${checked === 1 ? "" : "s"} queued to the Directorate of ICT and the Bursary.` : "Nothing to report: the door is within its rhythm, or this silence has already been reported."}</div> : null}

        <div className="row mt-2">
          <b>Kept to these addresses</b>
          {door.restrict_addresses ? <Pil kind="ok">answering the list only</Pil> : <Pil kind="grey">answering everyone</Pil>}
        </div>
        <div className="sub2">
          The validation door needs no credential, so anyone may ask it the payer and the amount behind a reference. Listed here, Interswitch&rsquo;s live addresses are
          the only ones the door answers once the switch is on. The switch is refused while no listed address has called the door in the last seven days, so it is never
          switched on blind: compare the addresses seen below with the list first.
        </div>
        {door.addresses.length ? (
          <DTable cols={["Address", "Label", "Added|mid", "|mid"]} rows={door.addresses.map((a) => [
            <span key="a" className="tnum">{a.address}</span>,
            a.label ?? "—",
            `${when(a.added_at)}${a.added_by_name ? " by " + a.added_by_name : ""}`,
            mayConfigure ? <Btn key="r" kind="ghost" size="sm" disabled={busy} onClick={() => void send("/paydirect/door/addresses/remove", { address: a.address }, `Quickteller door: ${a.address} removed from the list`)}>Remove</Btn> : "",
          ])} />
        ) : <div className="sub2">None listed.</div>}
        {mayConfigure ? (
          <div className="row">
            <Field id="pdd-address" label="Address, or a range such as 41.223.145.0/24"><input id="pdd-address" className="ctl tnum" value={add.address} onChange={(e) => setAdd({ ...add, address: e.target.value })} /></Field>
            <Field id="pdd-label" label="Label"><input id="pdd-label" className="ctl" placeholder="Interswitch live" value={add.label} onChange={(e) => setAdd({ ...add, label: e.target.value })} /></Field>
            <Btn kind="primary" size="sm" disabled={busy || !add.address.trim()} onClick={async () => { const j = await send("/paydirect/door/addresses", { address: add.address.trim(), label: add.label.trim() }, `Quickteller door: ${add.address.trim()} listed`); if (j) setAdd({ address: "", label: "" }); }}>Add</Btn>
            <label className="row"><input type="checkbox" checked={door.restrict_addresses} disabled={busy}
              onChange={(e) => void send("/paydirect/door", { restrict: e.target.checked }, e.target.checked ? "Quickteller door kept to its address list" : "Quickteller door opened to every address", "PUT")} /> Answer only the listed addresses</label>
          </div>
        ) : null}

        <div className="row mt-2"><b>Who called in the last seven days</b></div>
        {door.seen.length ? (
          <DTable cols={["Address", "Calls|num", "Refused|num", "Last call|mid", "Listed|mid"]} rows={door.seen.map((s) => [
            <span key="a" className="tnum">{s.address}</span>,
            String(s.calls),
            String(s.refused),
            when(s.last_at),
            s.listed ? <Pil key="l" kind="ok">listed</Pil> : <Pil key="l" kind="grey">not listed</Pil>,
          ])} />
        ) : <div className="sub2">Nobody has called since the counting began.</div>}
      </PBody>
    </Panel>
  );
}
