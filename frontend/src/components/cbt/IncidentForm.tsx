"use client";
/** V375: an incident recorded in a sitting as it happens — for the whole hall (power, network) or for one candidate (illness, suspected
 *  malpractice, identity) — with when it happened and, for an outage, the minutes lost. Kept with the sitting; the candidate's own
 *  attempt is linked by the server. Once the report is filed, only the office adds one. */
import { useState } from "react";
import { Btn } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { cbtSend } from "./CbtExam";

export const INCIDENT_WORD: Record<string, string> = {
  POWER: "Power lost", NETWORK: "Network lost", EQUIPMENT: "Equipment fault", MALPRACTICE: "Suspected malpractice", ILLNESS: "Illness",
  DISTURBANCE: "Disturbance", IDENTITY: "Question of identity", OTHER: "Other",
};

export function IncidentForm({ sittingId, candidate, onDone, onClose }: {
  sittingId: string; candidate?: { id: string; name: string } | null; onDone: (board: Record<string, unknown>) => void; onClose: () => void;
}) {
  const [kind, setKind] = useState(candidate ? "ILLNESS" : "POWER");
  const [detail, setDetail] = useState("");
  const [minutes, setMinutes] = useState("");
  const [at, setAt] = useState("");
  const [busy, setBusy] = useState(false);
  const outage = kind === "POWER" || kind === "NETWORK" || kind === "EQUIPMENT";

  async function save() {
    setBusy(true);
    try {
      let occurredAt: string | null = null;
      if (at) { const d = new Date(); const [h, m] = at.split(":").map(Number); d.setHours(h, m, 0, 0); occurredAt = d.toISOString(); }
      const j = await cbtSend(`/sittings/${sittingId}/incidents`, "POST",
        { candidateId: candidate?.id ?? null, kind, detail: detail.trim(), minutesLost: outage && minutes ? Number(minutes) : null, occurredAt },
        `${INCIDENT_WORD[kind]} recorded${candidate ? ` for ${candidate.name}` : ""}`);
      if (j) onDone(j);
    } finally { setBusy(false); }
  }

  return (
    <Modal title={candidate ? `Record an incident · ${candidate.name}` : "Record an incident in the hall"} sub="Kept with the sitting and its report" onClose={onClose}
      foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={onClose}>Back</Btn><Btn kind="primary" disabled={busy || !detail.trim()} onClick={() => void save()}>{busy ? "Recording…" : "Record"}</Btn></span>}>
      <Field id="inc-kind" label="What happened"><select id="inc-kind" className="ctl" value={kind} onChange={(e) => setKind(e.target.value)}>{Object.entries(INCIDENT_WORD).map(([k, w]) => <option key={k} value={k}>{w}</option>)}</select></Field>
      <Field id="inc-detail" label="Say what happened" required hint="As you would write it in the sitting's report"><textarea id="inc-detail" className="ctl" rows={3} value={detail} onChange={(e) => setDetail(e.target.value)} /></Field>
      <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
        <Field id="inc-at" label="When" hint="Empty for now"><input id="inc-at" type="time" className="ctl" value={at} onChange={(e) => setAt(e.target.value)} /></Field>
        {outage ? <Field id="inc-min" label="Minutes lost" hint="For the whole hall"><input id="inc-min" className="ctl tnum" inputMode="numeric" style={{ maxWidth: 110 }} value={minutes} onChange={(e) => setMinutes(e.target.value.replace(/[^0-9]/g, ""))} /></Field> : null}
      </div>
      {outage ? <div className="sub2">Recording an outage changes no clock; the examination office gives time back as extra time.</div> : null}
    </Modal>
  );
}
