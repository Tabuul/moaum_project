"use client";
/** Scripts from candidates not on the roll (V240): the lecturer holds the mark by matriculation number;
 *  the register releases it into the sheet when the candidate's registration is approved, or lapses it
 *  when the semester's late-registration date passes. Held marks are not on the roll, not graded and not
 *  on the broadsheet; this panel is where they wait, in view. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { OUTCOMES, type HeldScript } from "@/lib/results";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

/** the closing date has passed (a day's grace for time zones) */
const hasClosed = (iso: string | null) => !!iso && new Date(iso).getTime() < Date.now() - 86400000;
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const STATE: Record<string, ["ok" | "info" | "bad" | "grey", string]> = {
  HELD: ["info", "Held — waiting on registration"], RELEASED: ["ok", "Released into the sheet"], LAPSED: ["bad", "Lapsed — not registered in time"], WITHDRAWN: ["grey", "Withdrawn"],
};

export function HeldScripts({ sheetId, courseCode, caMax, items, own, closesOn }: {
  sheetId: string; courseCode: string; caMax: number; items: HeldScript[]; own: boolean; closesOn: string | null;
}) {
  const router = useRouter();
  const examMax = 100 - caMax;
  const [f, setF] = useState({ number: "", ca: "", exam: "", outcome: "GRADED", note: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const held = items.filter((h) => h.state === "HELD").length;
  const closed = hasClosed(closesOn);
  const caOver = f.ca !== "" && Number(f.ca) > caMax;
  const exOver = f.exam !== "" && Number(f.exam) > examMax;
  const graded = f.outcome === "GRADED";
  const canHold = own && !closed && f.number.trim() !== "" && (!graded || (f.ca !== "" && f.exam !== "" && !caOver && !exOver));

  async function call(path: string, method: "POST" | "DELETE", body: unknown, reason: string): Promise<boolean> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/results/sheets/${sheetId}/held${path}`, {
        method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: method === "DELETE" ? undefined : JSON.stringify(body),
      });
      if (!r.ok) { setErr((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally {
      setBusy(false);
    }
  }

  async function hold() {
    const ok = await call("", "POST", {
      number: f.number.trim(), ca: graded && f.ca !== "" ? Number(f.ca) : null, exam: graded && f.exam !== "" ? Number(f.exam) : null,
      outcome: f.outcome, note: f.note.trim() || null,
    }, `${courseCode}: script held for ${f.number.trim().toUpperCase()}`);
    if (ok) setF({ number: "", ca: "", exam: "", outcome: "GRADED", note: "" });
  }

  return (
    <Panel title="Scripts from candidates not on the roll" right={held ? `${held} held · released when the candidate registers` : "None held"}>
      <PBody>
        <div className="sub2" style={{ marginBottom: 8 }}>
          A candidate who sat the paper without registering the course is not on the roll, so the sheet has no row for them. Hold the script here by matriculation number: the mark waits, not graded and not on the broadsheet, and the register releases it into this sheet the moment the candidate pays, registers the course and the registration is approved.
          {closesOn ? <> Late registration for this semester closes on <b>{day(closesOn)}</b>; a script not released by then lapses and never grades.</> : <> The Registry has not set a late-registration closing date for this semester on the calendar; until it does, held scripts do not lapse.</>}
        </div>
        {err ? <ProblemNotice problem={err} /> : null}
        {own ? closed ? (
          <Note kind="bad" title="Late registration has closed for this semester">No more scripts can be held for {courseCode}. A script still held has lapsed; the Registry can move the date on the calendar if Senate extends it.</Note>
        ) : (
          <div style={{ display: "flex", gap: 8, alignItems: "flex-end", flexWrap: "wrap", marginBottom: 10 }}>
            <div className="field" style={{ flex: "1 1 200px" }}><label htmlFor="hs-num">Matriculation number</label>
              <input id="hs-num" className="ctl tnum" value={f.number} onChange={(e) => setF({ ...f, number: e.target.value.toUpperCase() })} placeholder="BSU/SC/CMP/23/70049" autoComplete="off" /></div>
            <div className="field" style={{ width: 110 }}><label htmlFor="hs-out">Outcome</label>
              <select id="hs-out" className="ctl" value={f.outcome} onChange={(e) => setF({ ...f, outcome: e.target.value, ...(e.target.value !== "GRADED" ? { ca: "", exam: "" } : {}) })}>
                {OUTCOMES.map((o) => <option key={o} value={o}>{o === "GRADED" ? "Graded" : o.charAt(0) + o.slice(1).toLowerCase()}</option>)}
              </select></div>
            <div className="field" style={{ width: 96 }}><label htmlFor="hs-ca">CA — {caMax}</label>
              <input id="hs-ca" className="ctl tnum" inputMode="numeric" value={f.ca} disabled={!graded} style={caOver ? { borderColor: "var(--red-ink)", color: "var(--red-ink)", fontWeight: 700 } : undefined} onChange={(e) => setF({ ...f, ca: e.target.value.replace(/[^0-9]/g, "") })} />
              {caOver ? <div style={{ color: "var(--red-ink)", fontSize: 11 }}>More than {caMax}</div> : null}</div>
            <div className="field" style={{ width: 96 }}><label htmlFor="hs-ex">Exam — {examMax}</label>
              <input id="hs-ex" className="ctl tnum" inputMode="numeric" value={f.exam} disabled={!graded} style={exOver ? { borderColor: "var(--red-ink)", color: "var(--red-ink)", fontWeight: 700 } : undefined} onChange={(e) => setF({ ...f, exam: e.target.value.replace(/[^0-9]/g, "") })} />
              {exOver ? <div style={{ color: "var(--red-ink)", fontSize: 11 }}>More than {examMax}</div> : null}</div>
            <div className="field" style={{ flex: "2 1 220px" }}><label htmlFor="hs-note">Note (optional)</label>
              <input id="hs-note" className="ctl" value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} placeholder="e.g. script no. 47, sat in LT 2" autoComplete="off" /></div>
            <Btn kind="primary" disabled={busy || !canHold} onClick={() => void hold()}>{busy ? "Holding…" : "Hold the script"}</Btn>
          </div>
        ) : null}
        {items.length ? (
          <DTable cols={["Matriculation number", "Name", "Programme", "CA|mid", "Exam|mid", "Outcome|mid", "Standing", "Entered", "|num"]} rows={items.map((h) => [
            <span className="tnum" key="n">{h.number}</span>,
            <strong key="nm">{h.surname}, {h.otherNames}</strong>,
            <span className="sub2" key="p">{h.programmeName} · {h.level}</span>,
            <span className="tnum" key="c">{h.ca ?? "—"}</span>,
            <span className="tnum" key="e">{h.exam ?? "—"}</span>,
            <span className="sub2" key="o">{h.outcome === "GRADED" ? "Graded" : h.outcome.charAt(0) + h.outcome.slice(1).toLowerCase()}</span>,
            <span key="s"><Pil kind={STATE[h.state]?.[0] ?? "grey"}>{STATE[h.state]?.[1] ?? h.state}</Pil>{h.state === "RELEASED" ? <div className="sub2">{day(h.releasedAt)}</div> : h.state === "LAPSED" ? <div className="sub2">{day(h.lapsedAt)}</div> : null}{h.note ? <div className="sub2">{h.note}</div> : null}</span>,
            <span className="sub2" key="w">{h.enteredBy ?? "—"}<div>{day(h.enteredAt)}</div></span>,
            own && h.state === "HELD" ? <Btn key="x" kind="ghost" disabled={busy} onClick={() => { if (window.confirm(`Withdraw the held script for ${h.number}? Hold it again if the mark was right.`)) void call(`/${h.id}`, "DELETE", null, `${courseCode}: held script for ${h.number} withdrawn`); }}>Withdraw</Btn> : <span key="x" />,
          ])} texts={items.map((h) => `${h.number} ${h.surname} ${h.otherNames} ${h.state}`)} />
        ) : <div className="sub2">No script is held for {courseCode}.</div>}
      </PBody>
    </Panel>
  );
}
