"use client";

/** sHealth — proto/part8.html: book an appointment, the facts on your record with your consent, the visit history — outcomes, never the note (V032). */
import { useState } from "react";
import type { StudentHealth } from "@/lib/health";
import { Btn, KvGrid, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { onDay, useAct, when } from "../common";

const FITNESS: Record<string, string> = { PENDING: "Not yet recorded", FIT: "Fit", UNFIT: "Unfit", FIT_WITH_CONDITIONS: "Fit, with conditions" };

export function Health({ h }: { h: StudentHealth }) {
  const { act, busy, problem } = useAct();
  const [reason, setReason] = useState("");
  const [at, setAt] = useState("");
  const [blood, setBlood] = useState(h.profile?.blood_group ?? "");
  const [geno, setGeno] = useState(h.profile?.genotype ?? "");
  const [allergies, setAllergies] = useState(h.profile?.allergies ?? "");
  const [said, setSaid] = useState<string | null>(null);
  const booked = h.appointments.find((a) => a.state === "BOOKED");
  const p = h.profile;
  const consented = !!p?.consented_at && !p?.restricted_at;

  return (
    <>
      <Note kind="info" title="Only the clinic sees your medical notes">
        Registry and your department see a fitness status and nothing else. Every access to your record is logged and is shown to you below.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      <div className="grid grid--2">
        <Panel title="Book an appointment" right="University Health Services">
          <PBody>
            {booked ? (
              <Note kind="ok" title={`Booked for ${when(booked.preferred_at)}`} action={<Btn kind="ghost" disabled={busy !== null} onClick={async () => { if (await act("cancel", "POST", `/me/health/appointments/${booked.id}/cancel`, {}, "Appointment cancelled by the student")) setSaid("Appointment cancelled"); }}>Cancel</Btn>}>
                {booked.reason}. Walk-in triage runs 8am–4pm for urgent cases; come to the clinic behind the Sports Complex.
              </Note>
            ) : (
              <>
                <Field id="hl-reason" label="Reason for visit"><input id="hl-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="One line" autoComplete="off" /></Field>
                <Field id="hl-at" label="Preferred time"><input id="hl-at" className="ctl" type="datetime-local" value={at} onChange={(e) => setAt(e.target.value)} /></Field>
                <div><Btn kind="primary" disabled={busy !== null || !reason.trim() || !at} onClick={async () => { if (await act("book", "POST", "/me/health/appointments", { reason, preferredAt: new Date(at).toISOString() }, "Clinic appointment booked")) { setSaid("Appointment booked"); setReason(""); setAt(""); } }}>Book appointment</Btn></div>
                <div className="sub2">University Health Services, behind the Sports Complex. Walk-in triage runs 8am–4pm for urgent cases.</div>
              </>
            )}
          </PBody>
        </Panel>
        <Panel title="On your record" right="Visible to the treating clinician only">
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Blood group", consented ? p?.blood_group ?? "Not given" : "Not consented"],
              ["Genotype", consented ? p?.genotype ?? "Not given" : "Not consented"],
              ["Allergies", consented ? p?.allergies ?? "None recorded" : "Not consented"],
              ["Fitness", `${FITNESS[p?.fitness ?? "PENDING"]}${p?.fitness_on ? ` · ${onDay(p.fitness_on)}` : ""}`],
            ]} />
            <div className="grid grid--3">
              <Field id="hp-blood" label="Blood group"><select id="hp-blood" className="ctl" value={blood} onChange={(e) => setBlood(e.target.value)}><option value="">—</option>{["O+", "O-", "A+", "A-", "B+", "B-", "AB+", "AB-"].map((b) => <option key={b}>{b}</option>)}</select></Field>
              <Field id="hp-geno" label="Genotype"><select id="hp-geno" className="ctl" value={geno} onChange={(e) => setGeno(e.target.value)}><option value="">—</option>{["AA", "AS", "SS", "AC", "SC"].map((g) => <option key={g}>{g}</option>)}</select></Field>
              <Field id="hp-all" label="Allergies"><input id="hp-all" className="ctl" value={allergies} onChange={(e) => setAllergies(e.target.value)} autoComplete="off" /></Field>
            </div>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              <Btn kind="ghost" disabled={busy !== null} onClick={async () => { if (await act("consent", "PUT", "/me/health/consent", { bloodGroup: blood || null, genotype: geno || null, allergies: allergies || null }, "Health record consented by the student")) setSaid("Recorded with your consent"); }}>{consented ? "Update with my consent" : "Record with my consent"}</Btn>
              {consented ? <Btn kind="ghost" disabled={busy !== null} onClick={async () => { if (await act("restrict", "POST", "/me/health/restrict", {}, "Health record restricted by the student")) setSaid("Restricted — not deleted"); }}>Withdraw consent</Btn> : null}
            </div>
            <div className="sub2">Blood group and genotype are recorded with your consent. You can withdraw that consent at any time, and the record is then restricted rather than deleted.</div>
          </PBody>
        </Panel>
      </div>
      <Panel title="Visit history" right={`${h.visits.length}`}>
        {h.visits.length ? (
          <DTable cols={["Date", "Reason", "Outcome", "Clinician|num"]} rows={h.visits.map((v) => [
            <span className="tnum" key="d">{onDay(v.arrived_at)}</span>,
            <span key="r">{v.presenting}</span>,
            <span key="o">{v.state === "DONE" ? <>{v.outcome}{v.referred_to ? <div className="sub2">Referred to {v.referred_to}</div> : null}</> : <Pil kind="info">{v.state === "WAITING" ? "Waiting" : "In consultation"}</Pil>}</span>,
            <span className="sub2" key="c">{v.clinician ?? "—"}</span>,
          ])} />
        ) : <PBody><div className="sub2">No visit on your record.</div></PBody>}
      </Panel>
      <Panel title="Who opened your record" right="Every access, logged">
        {h.access.length ? (
          <DTable cols={["When", "Who", "Office", "What"]} rows={h.access.map((a, i) => [<span className="tnum sub2" key={`w${i}`}>{when(a.at)}</span>, <span key={`o${i}`}>{a.who ?? "—"}</span>, <span className="sub2" key={`f${i}`}>{a.office}</span>, <span className="sub2" key={`t${i}`}>{a.what}</span>])} />
        ) : <PBody><div className="sub2">Nobody has opened your record.</div></PBody>}
      </Panel>
    </>
  );
}
