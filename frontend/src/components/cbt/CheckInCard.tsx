"use client";
/** V375: what an invigilator sees when they scan a candidate's CBT slip — the candidate's photograph (from the record, never from the
 *  slip), name, number, level and seat, where they stand, and a button to check them in. The server judges the slip's code, whether
 *  the scanner may check this candidate in, and the check-in itself; this page only shows it. */
import { useEffect, useState } from "react";
import { Btn, LinkBtn, Note, Pil } from "@/components/proto/ui";
import { cbtSend } from "./CbtExam";
import type { BoardRow } from "./InvigilatorBoard";

export interface CheckIn {
  exam: { id: string; reference: string; title: string; course_code: string; require_check_in: boolean; late_entry_minutes: number | null };
  candidateId: string; token: string; seated: boolean; canCheckIn: boolean; mine?: boolean;
  sitting?: { id: string; label: string; venue: string; starts_at: string; ends_at: string; seat_no: number };
  candidate: Partial<BoardRow> & { surname: string; other_names: string; number: string; level?: number | null };
}

const hhmm = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" }) : "—");
const STATE: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  NOT_COME: ["Not checked in", "grey"], CHECKED_IN: ["Checked in", "ok"], ADMITTED: ["Admitted late", "info"], ABSENT: ["Marked absent", "bad"],
  WRITING: ["Writing", "info"], DISCONNECTED: ["Writing, not heard from", "warn"], TIME_UP: ["Time up", "warn"], SUBMITTED: ["Submitted", "ok"],
  TIME_EXPIRED: ["Time expired", "warn"], TERMINATED: ["Terminated", "bad"],
};

export function CheckInCard({ initial }: { initial: CheckIn }) {
  const [row, setRow] = useState(initial.candidate);
  const [busy, setBusy] = useState(false);
  const c = row;
  const s = initial.sitting;
  // the photograph from the record, fetched (not left to an <img> error, which can fire before the page is live); null = none on record
  const [photo, setPhoto] = useState<string | null | undefined>(undefined);
  const photoUrl = s ? `/api/bff/api/v1/cbt/sittings/${s.id}/candidates/${initial.candidateId}/photo` : null;
  useEffect(() => {
    if (!photoUrl) return;
    let gone = false;
    let url: string | null = null;
    fetch(photoUrl).then(async (r) => {
      if (gone) return;
      if (!r.ok) { setPhoto(null); return; }
      url = URL.createObjectURL(await r.blob());
      setPhoto(url);
    }).catch(() => { if (!gone) setPhoto(null); });
    return () => { gone = true; if (url) URL.revokeObjectURL(url); };
  }, [photoUrl]);
  const state = String(c.state ?? "NOT_COME");

  async function checkIn() {
    if (!s) return;
    setBusy(true);
    try {
      const j = await cbtSend(`/sittings/${s.id}/candidates/${initial.candidateId}/check-in`, "POST", { method: "SCAN", token: initial.token }, `${c.surname}, ${c.other_names} checked in to ${s.label}`);
      const rows = j ? (j.rows as BoardRow[]) : null;
      const mine = rows?.find((r) => r.candidate_id === initial.candidateId);
      if (mine) setRow(mine);
    } finally { setBusy(false); }
  }

  return (
    <div style={{ maxWidth: 560 }}>
      <div className="row row--inline" style={{ gap: 16, alignItems: "flex-start", flexWrap: "wrap" }}>
        {photo ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={photo} alt={`Photograph of ${c.surname}, ${c.other_names} on the record`} style={{ width: 150, height: 180, objectFit: "cover", borderRadius: 8, border: "1px solid var(--line, #d0d5dd)" }} />
        ) : (
          <div style={{ width: 150, height: 180, borderRadius: 8, border: "1px dashed var(--line, #d0d5dd)", display: "grid", placeItems: "center", textAlign: "center", padding: 8 }} className="sub2">
            {photo === undefined && photoUrl ? "Loading the photograph…" : "No photograph on record — check another identity document"}
          </div>
        )}
        <div style={{ display: "grid", gap: 4, minWidth: 0, flex: 1 }}>
          <b style={{ fontSize: 20 }}>{c.surname.toUpperCase()}, {c.other_names}</b>
          <span className="tnum">{c.number}{c.level ? ` · ${c.level} level` : ""}</span>
          {c.programme ? <span className="sub2">{c.programme}</span> : null}
          <span><b className="tnum">{initial.exam.course_code}</b> {initial.exam.title}</span>
          {s ? <span>{s.label} · {s.venue} · {hhmm(s.starts_at)} to {hhmm(s.ends_at)}</span> : null}
          {s ? <span style={{ fontSize: 28, fontWeight: 700 }} className="tnum">Seat {s.seat_no}</span> : null}
          <span><Pil kind={(STATE[state] ?? STATE.NOT_COME)[1]}>{(STATE[state] ?? STATE.NOT_COME)[0]}</Pil>{c.checked_in_at ? <span className="sub2"> at {hhmm(c.checked_in_at)}</span> : null}</span>
        </div>
      </div>

      {!initial.seated ? <Note kind="bad" title="Not seated in any sitting">The candidate has no seat in this examination&rsquo;s sittings. Send them to the examination office.</Note> : null}
      {initial.seated && !initial.canCheckIn ? <Note kind="info" title={`Seated in ${s?.label ?? "another sitting"}`}>You invigilate another sitting of this examination; this candidate belongs to {s?.label} at {s?.venue}. Send them there.</Note> : null}
      {state === "ABSENT" ? <Note kind="bad" title="Marked absent">The candidate was marked absent from this sitting. If that was wrong, undo the mark on the board; if they came late, admit them there.</Note> : null}

      <div className="row row--inline row--tight mt-3" style={{ flexWrap: "wrap" }}>
        {initial.canCheckIn && state === "NOT_COME" ? <Btn kind="primary" disabled={busy} onClick={() => void checkIn()}>{busy ? "Checking in…" : "The face matches — check in"}</Btn> : null}
        {s ? <LinkBtn kind="secondary" href={`/cbt/invigilate/${s.id}`}>Open the sitting&rsquo;s board</LinkBtn> : null}
      </div>
      {initial.canCheckIn && state === "NOT_COME" ? <div className="sub2 mt-2">Compare the face with the photograph before checking in. A candidate who does not match is not checked in: record an identity incident on the board.</div> : null}
    </div>
  );
}

