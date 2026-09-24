"use client";

/** mClinic — proto/part10.html: the waiting list, triage, the record a clinician opens (and the opening logged), the outcome. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import type { ClinicDesk, OpenVisit } from "@/lib/health";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

function when(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function Clinic({ d, number }: { d: ClinicDesk; number: string }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [who, setWho] = useState(number);
  const [presenting, setPresenting] = useState("");
  const [triage, setTriage] = useState("STANDARD");
  const [open, setOpen] = useState<OpenVisit | null>(null);
  const [outcome, setOutcome] = useState({ outcome: "", referredTo: "", note: "", fitness: "" });
  const t = d.tiles;

  async function send(path: string, method: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      return j;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="Clinical notes never leave this module">
        Registry sees a fitness status; the student 360 view shows an alert flag and nothing more. Every read of a patient record is logged against the clinician who opened it, and the patient can see the log.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      <Tiles items={[
        ["Encounters today", String(t.encounters_today), null, "Walk-in and booked"],
        ["Awaiting triage", String(t.waiting), t.waiting ? "var(--red-ink)" : null, t.waiting ? `Longest wait ${t.longest_wait_min} min` : "Nobody waiting"],
        ["Referrals this month", String(t.referrals_month), null, "To the Teaching Hospital and others"],
        ["Fitness recorded", String(t.fitness_recorded), null, `${t.booked_today} booked for today`],
      ]} />
      <div className="grid grid--2">
        <Panel title="Patient arrives" right="A walk-in, or the appointment they booked">
          <PBody>
            <div className="grid grid--3">
              <Field id="cl-who" label="Number" hint="Matriculation or admission number"><input id="cl-who" className="ctl tnum" value={who} onChange={(e) => setWho(e.target.value)} autoComplete="off" /></Field>
              <Field id="cl-pres" label="Presenting complaint"><input id="cl-pres" className="ctl" value={presenting} onChange={(e) => setPresenting(e.target.value)} autoComplete="off" /></Field>
              <Field id="cl-tri" label="Triage"><select id="cl-tri" className="ctl" value={triage} onChange={(e) => setTriage(e.target.value)}><option value="URGENT">Urgent</option><option value="STANDARD">Standard</option><option value="ROUTINE">Routine</option></select></Field>
            </div>
            <div className="row">
              <Btn kind="primary" disabled={busy || !who.trim()} onClick={async () => { const j = await send("/api/bff/api/v1/health/visits", "POST", { number: who, presenting, triage }, `Patient ${who} arrived at the clinic`); if (j) { setSaid("On the waiting list"); setPresenting(""); router.refresh(); } }}>Add to the waiting list</Btn>
              <Btn kind="ghost" disabled={busy} onClick={() => queryNav(`/clinic?number=${encodeURIComponent(who)}`)}>Look the patient up</Btn>
            </div>
            {d.patron === null && number ? <Note kind="bad" title={`Nobody carries the number ${number}`}>The matriculation or admission number, as issued.</Note> : d.patron ? <Note kind="info" title={`${d.patron.name} · ${d.patron.number}`}>{d.patron.programme}</Note> : null}
          </PBody>
        </Panel>
        <Panel title="Booked" right={`${d.booked.length} for today and tomorrow`}>
          {d.booked.length ? (
            <DTable cols={["Time", "Patient", "Reason", "|num"]} rows={d.booked.map((b) => [<span className="tnum" key="t">{day(b.preferred_at, false)} {when(b.preferred_at)}</span>, <Two key="p" a={b.patient} b={b.number} />, <span key="r">{b.reason}</span>, <Btn kind="ghost" key="a" disabled={busy} onClick={async () => { const j = await send("/api/bff/api/v1/health/visits", "POST", { studentId: b.student_id, presenting: b.reason, triage: "STANDARD", appointmentId: b.id }, `Booked patient ${b.number} arrived`); if (j) { setSaid("Arrived, on the waiting list"); router.refresh(); } }}>Arrived</Btn>])} />
          ) : <PBody><div className="sub2">No appointment booked for today or tomorrow.</div></PBody>}
        </Panel>
      </div>
      <Panel title="Waiting list" right="University Health Services">
        {d.waiting.length ? (
          <DTable cols={["Arrived|mid", "Patient", "Presenting complaint", "Triage|mid", "Action|num"]} rows={d.waiting.map((w) => [
            <span className="tnum" key="a">{when(w.arrived_at)}</span>,
            <Two key="p" a={w.patient} b={w.number} />,
            <span key="c">{w.presenting}</span>,
            <Pil key="t" kind={w.triage === "URGENT" ? "bad" : w.triage === "STANDARD" ? "info" : "ok"}>{w.triage.charAt(0) + w.triage.slice(1).toLowerCase()}</Pil>,
            <Btn key="o" kind={w.triage === "URGENT" ? "urgent" : "primary"} disabled={busy} onClick={async () => { const j = await send(`/api/bff/api/v1/health/visits/${w.id}/open`, "POST", {}, `Opened the record of ${w.number}`); if (j) { setOpen(j as unknown as OpenVisit); setOutcome({ outcome: "", referredTo: "", note: "", fitness: "" }); } }}>{w.state === "IN_CONSULTATION" ? `Open · ${w.clinician ?? ""}` : w.triage === "URGENT" ? "See now" : "Open"}</Btn>,
          ])} />
        ) : <PBody><div className="sub2">Nobody is waiting.</div></PBody>}
      </Panel>
      <Panel title="Concluded today" right={`${d.concluded.length}`}>
        {d.concluded.length ? (
          <DTable cols={["Time|mid", "Patient", "Presenting", "Outcome", "Clinician|num"]} rows={d.concluded.map((c) => [<span className="tnum" key="t">{when(c.concluded_at)}</span>, <Two key="p" a={c.patient} b={c.number} />, <span key="c">{c.presenting}</span>, <span key="o">{c.outcome}{c.referred_to ? <div className="sub2">Referred to {c.referred_to}</div> : null}</span>, <span className="sub2" key="w">{c.clinician ?? "—"}</span>])} />
        ) : <PBody><div className="sub2">Nothing concluded yet today.</div></PBody>}
      </Panel>
      <Note kind="info" title="Pharmacy stock is not on the portal">The prototype drew a stock alert table; no dispensing record exists in this module yet, so nothing is shown as if it did.</Note>

      {open ? (
        <Modal title={`${open.patient} · ${open.number}`} sub={`${open.programme}${open.sex ? ` · ${open.sex === "F" ? "female" : "male"}` : ""}${open.date_of_birth ? ` · born ${day(open.date_of_birth)}` : ""} · opened in your name, on the log`} onClose={() => setOpen(null)}
          foot={<><Btn kind="ghost" onClick={() => setOpen(null)}>Leave open</Btn><span className="grow" /><Btn kind="go" disabled={busy || !outcome.outcome.trim()} onClick={async () => { const j = await send(`/api/bff/api/v1/health/visits/${open.id}/conclude`, "POST", { outcome: outcome.outcome, referredTo: outcome.referredTo || null, note: outcome.note || null, fitness: outcome.fitness || null }, `Visit of ${open.number} concluded`); if (j) { setOpen(null); setSaid("Concluded"); router.refresh(); } }}>Conclude the visit</Btn></>}>
          <KvGrid cls="grid--3" pairs={[
            ["Presenting", open.presenting], ["Triage", open.triage], ["Arrived", when(open.arrived_at)],
            ["Blood group", open.profile?.consented_at && !open.profile.restricted_at ? open.profile.blood_group ?? "—" : "Not consented"],
            ["Genotype", open.profile?.consented_at && !open.profile.restricted_at ? open.profile.genotype ?? "—" : "Not consented"],
            ["Allergies", open.profile?.consented_at && !open.profile.restricted_at ? open.profile.allergies ?? "None recorded" : "Not consented"],
          ]} />
          {open.history.length ? (
            <div className="mt-3">
              <div className="eyebrow">Earlier visits</div>
              {open.history.map((x) => <div key={x.id} style={{ padding: "var(--s-2) 0", borderTop: "1px solid var(--line-2)" }}><b>{day(x.arrived_at)}</b> · {x.presenting} → {x.outcome}{x.referred_to ? ` (referred to ${x.referred_to})` : ""}{x.notes ? <div className="sub2" style={{ whiteSpace: "pre-wrap" }}>{x.notes}</div> : null}</div>)}
            </div>
          ) : null}
          <Field id="ov-out" label="Outcome" hint="What the patient sees on their record."><input id="ov-out" className="ctl" value={outcome.outcome} onChange={(e) => setOutcome({ ...outcome, outcome: e.target.value })} autoComplete="off" /></Field>
          <div className="grid grid--2">
            <Field id="ov-ref" label="Referred to" hint="If referred."><input id="ov-ref" className="ctl" value={outcome.referredTo} onChange={(e) => setOutcome({ ...outcome, referredTo: e.target.value })} autoComplete="off" /></Field>
            <Field id="ov-fit" label="Fitness" hint="Only if this visit decides it."><select id="ov-fit" className="ctl" value={outcome.fitness} onChange={(e) => setOutcome({ ...outcome, fitness: e.target.value })}><option value="">Unchanged</option><option value="FIT">Fit</option><option value="FIT_WITH_CONDITIONS">Fit, with conditions</option><option value="UNFIT">Unfit</option></select></Field>
          </div>
          <Field id="ov-note" label="Clinical note" hint="Never leaves the clinic."><textarea id="ov-note" className="ctl" rows={4} value={outcome.note} onChange={(e) => setOutcome({ ...outcome, note: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
