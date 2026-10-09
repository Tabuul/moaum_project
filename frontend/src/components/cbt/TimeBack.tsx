"use client";
/** V376: an incident's time given back — the minutes the office chooses, added as extra time to every candidate whose attempt was
 *  running when it happened and still runs, each grant naming the incident. Once only; a candidate who has finished is not reopened.
 *  The office decides; the server applies it. */
import { useEffect, useState } from "react";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { cbtSend } from "./CbtExam";
import { INCIDENT_WORD } from "./IncidentForm";
import type { Incident } from "./InvigilatorBoard";

interface Who { candidate_id: string; seat_no: number; number: string; surname: string; other_names: string; still_writing: boolean; attempt_status: string; extra_minutes: number | null }

export function TimeBack({ sittingId, incident, onDone, onClose }: { sittingId: string; incident: Incident; onDone: (board: Record<string, unknown>) => void; onClose: () => void }) {
  const [who, setWho] = useState<Who[] | null>(null);
  const [minutes, setMinutes] = useState(String(incident.minutes_lost ?? ""));
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let gone = false;
    fetch(`/api/bff/api/v1/cbt/sittings/${sittingId}/incidents/${incident.id}/time-back`).then(async (r) => {
      if (!gone && r.ok) setWho(((await r.json()) as { candidates: Who[] }).candidates);
    }).catch(() => { /* the list stays empty */ });
    return () => { gone = true; };
  }, [sittingId, incident.id]);
  const writing = who?.filter((w) => w.still_writing) ?? [];

  async function give() {
    setBusy(true);
    try {
      const j = await cbtSend(`/sittings/${sittingId}/incidents/${incident.id}/time-back`, "POST", { minutes: Number(minutes) },
        `${minutes} minutes given back for ${(INCIDENT_WORD[incident.kind] ?? incident.kind).toLowerCase()} to ${writing.length} candidate${writing.length === 1 ? "" : "s"}`);
      if (j) onDone(j);
    } finally { setBusy(false); }
  }

  return (
    <Modal title="Give the time back" sub={`${INCIDENT_WORD[incident.kind] ?? incident.kind} at ${new Date(incident.occurred_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })} — ${incident.detail}`} wide onClose={onClose}
      foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={onClose}>Back</Btn>
        <Btn kind="primary" disabled={busy || !writing.length || !Number(minutes) || Number(minutes) > 600} onClick={() => void give()}>{busy ? "Giving…" : `Give ${minutes || "…"} minutes to ${writing.length}`}</Btn></span>}>
      <p className="sub2">The minutes are added to the extra time of every candidate {incident.candidate_id ? "named in the incident" : "of the sitting"} whose attempt was running when it happened and still runs, with the incident named as the reason. It is done once. A candidate who has finished since is not reopened; their result can be reviewed with the incident on record.</p>
      <Field id="tb-min" label="Minutes to give back" hint={incident.minutes_lost ? `${incident.minutes_lost} minutes were recorded as lost` : "1 to 600"}>
        <input id="tb-min" className="ctl tnum" inputMode="numeric" style={{ maxWidth: 110 }} value={minutes} onChange={(e) => setMinutes(e.target.value.replace(/[^0-9]/g, ""))} />
      </Field>
      {who === null ? <div className="sub2">Reading who was writing…</div> : who.length ? (
        <DTable pageSize={50} cols={["Seat|num", "Candidate", "Now|mid", "Extra time|num"]} rows={who.map((w) => [
          <b key="s" className="tnum">{w.seat_no}</b>,
          <span key="c">{w.surname.toUpperCase()}, {w.other_names}<div className="sub2 tnum">{w.number}</div></span>,
          w.still_writing ? <Pil key="n" kind="info">Writing — gets the time</Pil> : <Pil key="n" kind="grey">Finished since</Pil>,
          <span key="x" className="tnum">{w.extra_minutes ? `${w.extra_minutes} min` : "—"}</span>,
        ])} />
      ) : <Note kind="info" title="Nobody was writing then">No candidate&rsquo;s attempt was running when this happened.</Note>}
    </Modal>
  );
}
