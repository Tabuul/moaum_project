"use client";
/** PHYSICAL SCREENING (V337): the School's screening of accepted postgraduate applicants. The session's policy — whether they
 *  are screened, where, from when, the instructions and the documents to bring — and the desk: every accepted applicant of
 *  the session with where their screening stands. A decision is recorded on the application itself (Details), where CLEARED
 *  admits the applicant to the register and opens school fees. Departments never screen. */
import { useCallback, useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface ScreeningRow {
  id: string; application_no: string; state: string; surname: string; other_names: string; email: string; phone: string | null;
  programme_name: string; pg_award: string | null; department_name: string; faculty_name: string;
  required: boolean; screening_state: string | null; venue: string | null; scheduled_for: string | null; decided_at: string | null;
  reason: string | null; missing_documents: string[] | null; admission_no: string | null; matric_no: string | null;
}
interface Policy { session: string; required: boolean; venue: string | null; starts_on: string | null; ends_on: string | null; instructions: string | null; required_documents: string[] }

export const SCREENING: Record<string, { kind: "ok" | "bad" | "warn" | "info" | "grey"; label: string }> = {
  PENDING: { kind: "grey", label: "Awaiting screening" },
  SCHEDULED: { kind: "info", label: "Scheduled" },
  IN_PROGRESS: { kind: "info", label: "In progress" },
  CLEARED: { kind: "ok", label: "Cleared" },
  NOT_CLEARED: { kind: "bad", label: "Not cleared" },
  CORRECTION_REQUIRED: { kind: "warn", label: "Correction required" },
};
export const when = (v: string | null | undefined) => (v ? new Date(v).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const day = (v: string | null | undefined) => (v ? new Date(v).toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }) : "—");

/** the desk and the session's policy, read together */
async function readDesk(session: string, sy: string, ey: string) {
  return Promise.all([
    fetch(`/api/bff/api/v1/pg/screening?session=${encodeURIComponent(session)}`, { cache: "no-store" }).then((r) => (r.ok ? r.json() : null)).catch(() => null),
    fetch(`/api/bff/api/v1/pg/sessions/${sy}/${ey}/screening-policy`, { cache: "no-store" }).then((r) => (r.ok ? r.json() : null)).catch(() => null),
  ]);
}

export function ScreeningDesk({ session, mayWritePolicy, onOpen }: { session: string; mayWritePolicy: boolean; onOpen: (id: string) => void }) {
  const [rows, setRows] = useState<ScreeningRow[] | null>(null);
  const [counts, setCounts] = useState<Record<string, number>>({});
  const [policy, setPolicy] = useState<Policy | null>(null);
  const [stated, setStated] = useState(false);
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [draft, setDraft] = useState({ required: true, venue: "", startsOn: "", endsOn: "", instructions: "", docs: "" });
  const [sy, ey] = session.split("/");

  const take = useCallback((d: { rows?: ScreeningRow[]; counts?: Record<string, number> } | null, p: { stated?: boolean; policy?: Policy | null } | null) => {
    setRows(d && Array.isArray(d.rows) ? d.rows : []);
    setCounts(d && d.counts ? d.counts : {});
    setStated(!!(p && p.stated));
    setPolicy(p && p.policy ? p.policy : null);
  }, []);
  const load = useCallback(async () => {
    const [d, p] = await readDesk(session, sy, ey);
    take(d, p);
  }, [session, sy, ey, take]);

  useEffect(() => {
    let live = true;
    readDesk(session, sy, ey).then(([d, p]) => { if (live) take(d, p); });
    return () => { live = false; };
  }, [session, sy, ey, take]);

  function edit() {
    setDraft({
      required: policy ? policy.required : true, venue: policy?.venue ?? "", startsOn: policy?.starts_on ?? "", endsOn: policy?.ends_on ?? "",
      instructions: policy?.instructions ?? "", docs: (policy?.required_documents ?? ["First degree certificate", "Academic transcript", "NYSC certificate", "O’Level result", "Birth certificate / declaration of age", "Passport photograph"]).join("\n"),
    });
    setEditing(true);
  }

  async function save() {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/sessions/${sy}/${ey}/screening-policy`, {
        method: "PUT",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Postgraduate screening policy for ${session}`) },
        body: JSON.stringify({ required: draft.required, venue: draft.venue, startsOn: draft.startsOn, endsOn: draft.endsOn, instructions: draft.instructions,
          requiredDocuments: draft.docs.split("\n").map((x) => x.trim()).filter(Boolean) }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(`Screening policy for ${session} saved`);
      setEditing(false);
      await load();
    } finally { setBusy(false); }
  }

  async function exportRows() {
    if (!rows?.length) return;
    const headers = ["S/N", "Application number", "Applicant", "Programme", "Department", "Faculty", "Screening", "Venue", "Scheduled for", "Decided", "Reason", "Admission number"];
    const body = rows.map((r, i) => [i + 1, r.application_no, `${r.surname}, ${r.other_names}`, r.programme_name, r.department_name, r.faculty_name,
      SCREENING[r.screening_state ?? ""]?.label ?? (r.required ? "Awaiting screening" : "Not required"), r.venue ?? "", r.scheduled_for ? when(r.scheduled_for) : "",
      r.decided_at ? when(r.decided_at) : "", r.reason ?? "", r.admission_no ?? ""]);
    const blob = await brandedXlsx("Postgraduate physical screening", headers, body, { sheetName: "Screening", serial: docSerial("PGSCR"), sub: session });
    downloadBlob(blob, `postgraduate-screening-${session.replace("/", "-")}.xlsx`);
  }

  return (
    <>
      <Panel title={`PHYSICAL SCREENING · ${session}`} right={mayWritePolicy && !editing ? <Btn kind="secondary" size="sm" onClick={edit}>{stated ? "Change the screening policy" : "Set the screening policy"}</Btn> : null}>
        <PBody>
          {!editing ? (
            policy && policy.required ? (
              <div className="stack">
                <div className="sub2">Accepted applicants of {session} are screened in person{policy.venue ? <> at <b>{policy.venue}</b></> : null}{policy.starts_on ? <> from <b>{day(policy.starts_on)}</b></> : null}{policy.ends_on ? <> to <b>{day(policy.ends_on)}</b></> : null}. A cleared applicant is admitted to the register at once and pays school fees on the student portal.</div>
                {policy.instructions ? <div className="sub2" style={{ whiteSpace: "pre-wrap" }}>{policy.instructions}</div> : null}
                {policy.required_documents?.length ? <div className="sub2"><b>Documents to bring:</b> {policy.required_documents.join(" · ")}</div> : null}
              </div>
            ) : (
              <Note kind="info" title={stated ? "Screening is switched off for this session" : "No screening policy for this session"}>
                Accepted applicants are admitted to the register by the School without a physical screening. Set the policy to screen them; applicants who accepted before it was first set are not held.
              </Note>
            )
          ) : (
            <div className="stack">
              <label className="row row--inline"><input type="checkbox" checked={draft.required} onChange={(e) => setDraft({ ...draft, required: e.target.checked })} /> <span className="b600">Screen this session&rsquo;s accepted applicants before they are admitted</span></label>
              <div className="grid grid--3">
                <Field id="scr-venue" label="Venue"><input id="scr-venue" className="ctl" value={draft.venue} maxLength={300} onChange={(e) => setDraft({ ...draft, venue: e.target.value })} placeholder="e.g. Postgraduate School Hall" /></Field>
                <Field id="scr-from" label="From"><input id="scr-from" type="date" className="ctl" value={draft.startsOn} onChange={(e) => setDraft({ ...draft, startsOn: e.target.value })} /></Field>
                <Field id="scr-to" label="To"><input id="scr-to" type="date" className="ctl" value={draft.endsOn} onChange={(e) => setDraft({ ...draft, endsOn: e.target.value })} /></Field>
              </div>
              <Field id="scr-ins" label="Instructions" hint="What the applicant reads on the portal and in the email"><textarea id="scr-ins" className="ctl" rows={3} maxLength={4000} value={draft.instructions} onChange={(e) => setDraft({ ...draft, instructions: e.target.value })} /></Field>
              <Field id="scr-docs" label="Documents to bring" hint="One per line; the screening officer ticks them off"><textarea id="scr-docs" className="ctl" rows={5} value={draft.docs} onChange={(e) => setDraft({ ...draft, docs: e.target.value })} /></Field>
              <div className="row">
                <Btn kind="primary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save the policy"}</Btn>
                <Btn kind="ghost" disabled={busy} onClick={() => setEditing(false)}>Cancel</Btn>
              </div>
            </div>
          )}
        </PBody>
      </Panel>

      <Tiles items={[
        ["Awaiting screening", String(counts.PENDING ?? 0), counts.PENDING ? "var(--chrome)" : null, "accepted, not yet scheduled"],
        ["Scheduled", String((counts.SCHEDULED ?? 0) + (counts.IN_PROGRESS ?? 0)), null, "scheduled or in progress"],
        ["Correction required", String(counts.CORRECTION_REQUIRED ?? 0), counts.CORRECTION_REQUIRED ? "var(--amber-ink, var(--chrome))" : null, "told what to correct"],
        ["Cleared", String(counts.CLEARED ?? 0), counts.CLEARED ? "var(--green-ink)" : null, "on the register; school fees next"],
      ]} cls="grid--4" />

      <Panel title="Accepted applicants" right={<span className="row row--inline row--tight"><span className="sub2">{rows?.length ?? 0} applicant{rows?.length === 1 ? "" : "s"}</span>{rows?.length ? <Btn kind="ghost" size="sm" onClick={() => void exportRows()}>Download Excel</Btn> : null}</span>}>
        {rows === null ? <PBody><div className="sub2">Loading…</div></PBody> : rows.length ? (
          <DTable
            cols={["S/N|num", "Applicant", "Programme", "Screening|mid", "When and where", "|num"]}
            rows={rows.map((r, i) => {
              const s = SCREENING[r.screening_state ?? ""] ?? { kind: "grey" as const, label: r.required ? "Awaiting screening" : "Not required" };
              return [
                <span key="sn" className="tnum sub2">{i + 1}</span>,
                <Two key="n" a={`${r.surname}, ${r.other_names}`} b={r.application_no} />,
                <Two key="p" a={r.programme_name} b={r.department_name} />,
                <span key="s"><Pil kind={s.kind}>{s.label}</Pil>{r.reason && r.screening_state !== "CLEARED" ? <div className="sub2 mt-1">{r.reason}</div> : null}</span>,
                <span key="w" className="sub2">{r.scheduled_for ? when(r.scheduled_for) : "—"}{r.venue ? <div>{r.venue}</div> : null}</span>,
                <Btn kind="ghost" key="o" onClick={() => onOpen(r.id)}>Details</Btn>,
              ];
            })}
            texts={rows.map((r) => `${r.surname} ${r.other_names} ${r.application_no} ${r.programme_name} ${r.department_name} ${r.screening_state ?? ""}`)}
          />
        ) : <PBody><div className="sub2">No applicant of {session} has accepted an offer yet.</div></PBody>}
      </Panel>
    </>
  );
}
