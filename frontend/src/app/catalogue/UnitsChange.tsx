"use client";

/** V464, V465: a change of units counted before it is saved, wherever units are changed — the units a programme takes a course
 *  at (from the review's report or the programme's structure), or the course's own (on its page). Registrations not yet
 *  examined follow; a closed session, or a class whose results are being worked on, keeps its units — each such class listed,
 *  with the sheet whose desk of entry raises a units correction through the amendment chain. */
import { useEffect, useState } from "react";
import Link from "next/link";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import type { CourseUnitsImpact, HeldClass, UnitsImpact } from "@/lib/catalogue";

const plural = (n: number, one: string, many = one + "s") => `${n.toLocaleString()} ${n === 1 ? one : many}`;
const unitsValue = (text: string) => (/^\d{1,2}$/.test(text.trim()) && Number(text) <= 12 ? Number(text) : null);

/** the classes a change leaves as they are, each with the sheet a units correction is raised on */
export function HeldClasses({ held, kept }: { held: HeldClass[]; kept: number }) {
  if (!kept) return null;
  return (
    <div className="sub2 mt-2">
      {`${plural(kept, "registration")} keep the units they were examined at (a closed session, or the class's results being worked on). `}
      {held.length ? <>To correct one of those classes, the course&rsquo;s lecturer or the Programme Examinations Officer raises a units correction on its sheet; it goes through the amendment chain to the Senate.</> : null}
      {held.length ? (
        <ul style={{ margin: "6px 0 0", paddingLeft: 18 }}>
          {held.map((h) => (
            <li key={`${h.course}-${h.session}-${h.semester}`}>
              <span className="tnum">{h.course} · {h.session}, semester {h.semester} · {plural(Number(h.registrations), "registration")}</span>
              {h.sheetId ? <> · <Link className="lnk" style={{ textDecoration: "underline" }} href={`/results/chain?sheet=${h.sheetId}`}>its sheet</Link></> : <> · closed session, no result sheet</>}
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

export interface UnitsTarget { course: string; courseUnits: number; programme: string; programmeName: string; level: number; units: number }

/** the units a programme takes a course at, at a level — counted, then saved (the binding's basis and track untouched) */
/** V471: `ticket` — the support ticket the change answers, put on its timeline */
export function UnitsChangeModal({ target, onClose, onSaved, ticket = "" }: { target: UnitsTarget; onClose: () => void; onSaved: () => void; ticket?: string }) {
  const [units, setUnits] = useState(String(target.units));
  const [impact, setImpact] = useState<UnitsImpact | null>(null);
  const [busy, setBusy] = useState(false);
  const value = unitsValue(units);

  // what the change would reach, counted as the number is typed
  useEffect(() => {
    if (value == null) return;
    let live = true;
    const t = setTimeout(async () => {
      const qs = new URLSearchParams({ programme: target.programme, course: target.course, level: String(target.level), units: String(value) });
      const r = await fetch(`/api/bff/api/v1/catalogue/structure/units-impact?${qs.toString()}`, { cache: "no-store" });
      const j = r.ok ? ((await r.json().catch(() => null)) as UnitsImpact | null) : null;
      if (live) setImpact(j);
    }, 250);
    return () => { live = false; clearTimeout(t); };
  }, [target.programme, target.course, target.level, value]);

  const set = (text: string) => { if (unitsValue(text) !== value) setImpact(null); setUnits(text); };
  const nothing = impact != null && value === impact.nowUnits && impact.follow === 0;

  async function save() {
    if (value == null) return;
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue/structure/units${ticket ? `?ticket=${encodeURIComponent(ticket)}` : ""}`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${ticket ? `Ticket ${ticket.toUpperCase()}: ` : ""}${target.course} units for ${target.programme} at ${target.level} level set to ${value}`) },
        body: JSON.stringify({ programme: target.programme, course: target.course, level: target.level, units: value }),
      });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) { notifyProblem(j ? (j as unknown as Parameters<typeof notifyProblem>[0]) : { status: r.status, title: r.statusText }); return; }
      const followed = Number(j?.followed ?? 0);
      notify(`${target.course} for ${target.programme}: ${plural(Number(j?.units ?? value), "unit")} · ${plural(followed, "registration")} followed`);
      onSaved();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title={`Units of ${target.course} for ${target.programme}`} sub={`${target.programmeName} · ${target.level} level · the course carries ${target.courseUnits}`} onClose={onClose}
      foot={<><Btn kind="primary" disabled={busy || value == null || !impact || nothing} onClick={() => void save()}>{busy ? "Saving…" : "Save"}</Btn><Btn kind="ghost" onClick={onClose}>Cancel</Btn></>}>
      <div className="row row--inline row--tight" style={{ alignItems: "flex-end" }}>
        <Field id="ue-units" label="Units this programme takes it at" hint="0 to 12; the course's own number takes the course's units">
          <input id="ue-units" className="ctl tnum" inputMode="numeric" style={{ width: 90 }} value={units} onChange={(e) => set(e.target.value)} /></Field>
        {value !== target.courseUnits ? <Btn kind="ghost" size="sm" onClick={() => set(String(target.courseUnits))}>Use the course&rsquo;s {target.courseUnits}</Btn> : null}
      </div>
      <div className="sub2" aria-live="polite">
        {value == null ? "Give a number from 0 to 12."
          : !impact ? "Counting what this reaches…"
          : nothing ? `${target.programme} takes it at ${value} already; nothing would change.`
          : <>{target.programme} takes it at <b className="tnum">{impact.nowUnits}</b> now, <b className="tnum">{impact.newUnits}</b> after. <b className="tnum">{impact.follow.toLocaleString()}</b> {impact.follow === 1 ? "registration" : "registrations"} not yet examined will follow.</>}
      </div>
      {impact && !nothing ? <HeldClasses held={impact.held ?? []} kept={impact.kept} /> : null}
    </Modal>
  );
}

/** the course's own units, as typed on its edit form: what the change would reach before it is saved */
export function CourseUnitsImpactNote({ code, units }: { code: string; units: string }) {
  const value = unitsValue(units);
  const [impact, setImpact] = useState<{ for: number; data: CourseUnitsImpact | null } | null>(null);
  useEffect(() => {
    if (value == null) return;
    let live = true;
    const t = setTimeout(async () => {
      const r = await fetch(`/api/bff/api/v1/catalogue/courses/${encodeURIComponent(code)}/units-impact?units=${value}`, { cache: "no-store" });
      const j = r.ok ? ((await r.json().catch(() => null)) as CourseUnitsImpact | null) : null;
      if (live) setImpact({ for: value, data: j });
    }, 250);
    return () => { live = false; clearTimeout(t); };
  }, [code, value]);

  if (value == null) return null;
  const i = impact && impact.for === value ? impact.data : null;
  if (!i) return <div className="sub2" aria-live="polite">{impact && impact.for === value ? "" : "Counting what this reaches…"}</div>;
  if (value === i.nowUnits) return null;
  return (
    <div className="sub2" aria-live="polite">
      <b className="tnum">{i.follow.toLocaleString()}</b> {i.follow === 1 ? "registration" : "registrations"} not yet examined will follow at <b className="tnum">{i.newUnits}</b>.
      {i.pinned ? <> {plural(i.pinned, "programme binding")} of other departments keep <b className="tnum">{i.nowUnits}</b>, changed on their own Programme Structure: {i.pinnedProgrammes.map((p) => `${p.programme} (${p.level})`).join(", ")}.</> : null}
      <HeldClasses held={i.held ?? []} kept={i.kept} />
    </div>
  );
}
