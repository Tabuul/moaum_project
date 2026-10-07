"use client";

/**
 * Amendments of a published result (V358), on the sheet's chain: each correction of one student's published mark with its
 * reason, where it stands in the chain and who took each step. The desk of entry raises one (the course's lecturer, or the
 * Programme Examinations Officer on the lecturer's behalf); each desk approves or refuses it at its own stage; the Registrar
 * applies it on the Senate minute — a new version of the mark, the original kept. The person who raised it may withdraw it.
 * The server decides who may do each; the buttons only follow it.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { roleLabel } from "@/lib/offices";
import { STAGE_LABEL, type Mark } from "@/lib/results";

/** the desk of each stage — the server's rule (assessment.stage_offices = Sheets.DESK) */
const STAGE_DESKS: Record<string, string[]> = {
  VERIFICATION: ["exams"], DEPT_BOARD: ["hod"], FACULTY_SCRUTINY: ["facultyexams"], FACULTY_COMPILATION: ["facultyofficer"],
  FACULTY_BOARD: ["dean"], RECORDS: ["records"], SENATE: ["registrar", "dregistrar"],
};
const ENTRY_DESKS = ["lecturer", "gst", "eps", "exams"];
const OUTCOMES = ["GRADED", "ABSENT", "WITHHELD", "INCOMPLETE", "MALPRACTICE", "EXEMPTED"];

export interface Amendment {
  id: string; ref: string; student_id: string; number: string; name: string; query_ref: string | null;
  was_ca: number | null; was_exam: number | null; was_outcome: string; ca: number | null; exam: number | null; outcome: string;
  reason: string; stage: string; raised_by_name: string | null; raised_office: string | null; raised_at: string;
  senate_minute: string | null; applied_at: string | null; closed_reason: string | null;
  decisions: { kind: string; from: string | null; to: string; office: string | null; comment: string | null; at: string; by: string | null }[];
}

const markOf = (outcome: string, ca: number | null, exam: number | null) =>
  outcome === "GRADED" ? `${ca ?? "—"} + ${exam ?? "—"} = ${(ca ?? 0) + (exam ?? 0)}` : outcome.toLowerCase();
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

function stagePil(stage: string) {
  if (stage === "APPLIED") return <Pil kind="ok">Applied</Pil>;
  if (stage === "REFUSED") return <Pil kind="bad">Refused</Pil>;
  if (stage === "WITHDRAWN") return <Pil kind="grey">Withdrawn</Pil>;
  return <Pil kind="info">{`At ${STAGE_LABEL[stage]?.[0] ?? stage.toLowerCase().replace(/_/g, " ")}`}</Pil>;
}

export function Amendments({ sheetId, courseCode, caMax, published, actingOffice, marks }: {
  sheetId: string; courseCode: string; caMax: number; published: boolean; actingOffice: string | null; marks: Mark[];
}) {
  const router = useRouter();
  const [rows, setRows] = useState<Amendment[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [raise, setRaise] = useState<{ studentId: string; outcome: string; ca: string; exam: string; reason: string } | null>(null);
  const [act, setAct] = useState<{ a: Amendment; kind: "approve" | "minute" | "refuse" | "withdraw"; text: string } | null>(null);
  useEffect(() => {
    let live = true;
    void fetch(`/api/bff/api/v1/results/sheets/${sheetId}/amendments`, { cache: "no-store" }).then(async (r) => { if (live && r.ok) setRows(await r.json()); });
    return () => { live = false; };
  }, [sheetId]);

  async function post(path: string, body: unknown, reason: string) {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/results${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) { notifyProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return false; }
      setRows(await r.json()); notify(reason); router.refresh();
      return true;
    } finally { setBusy(false); }
  }

  const mayRaise = published && !!actingOffice && ENTRY_DESKS.includes(actingOffice);
  if (!published && !(rows && rows.length)) return null;
  const examMax = 100 - caMax;
  const r = raise;
  const wrong = r && r.outcome === "GRADED" && (r.ca === "" || r.exam === "" || Number(r.ca) > caMax || Number(r.exam) > examMax || Number(r.ca) < 0 || Number(r.exam) < 0);
  const chosen = r ? marks.find((m) => m.studentId === r.studentId) : undefined;

  return (
    <Panel title="Amendments of the published result" right={mayRaise ? <Btn kind="primary" onClick={() => setRaise({ studentId: "", outcome: "GRADED", ca: "", exam: "", reason: "" })}>Raise an amendment</Btn> : null}>
      <PBody>
        <p className="sub2">A published mark changes only by an amendment: raised with its reason, approved by each desk in turn, applied by the Registrar on the Senate minute as a new version of the mark — the original kept, the student told.</p>
        {!rows ? <p className="sub2">Loading…</p> : !rows.length ? <p className="sub2">No amendment of this sheet.</p> : (
          <DTable noPrint pageSize={0} cols={["Amendment", "Student", "Published", "Corrected to", "Reason", "Stands", "|mid"]} rows={rows.map((a) => {
            const open = !["APPLIED", "REFUSED", "WITHDRAWN"].includes(a.stage);
            const mine = open && !!actingOffice && (STAGE_DESKS[a.stage] ?? []).includes(actingOffice);
            const last = a.decisions[a.decisions.length - 1];
            return [
              <span key="r"><b className="tnum">{a.ref}</b><span className="sub2" style={{ display: "block" }}>{`${a.raised_by_name ?? "—"} (${roleLabel(a.raised_office)}), ${day(a.raised_at)}`}</span>
                {a.query_ref ? <span className="sub2" style={{ display: "block" }}>{`From query ${a.query_ref}`}</span> : null}</span>,
              <span key="s">{a.name}<span className="sub2 tnum" style={{ display: "block" }}>{a.number}</span></span>,
              <span key="w" className="tnum">{markOf(a.was_outcome, a.was_ca, a.was_exam)}</span>,
              <b key="n" className="tnum">{markOf(a.outcome, a.ca, a.exam)}</b>,
              <span key="why" className="sub2">{a.reason}</span>,
              <span key="st">{stagePil(a.stage)}
                <span className="sub2" style={{ display: "block" }}>{a.stage === "APPLIED" ? `Minute ${a.senate_minute}, ${day(a.applied_at)}` : a.closed_reason ? a.closed_reason
                  : last ? `Last: ${last.by ?? roleLabel(last.office)}, ${day(last.at)}` : ""}</span></span>,
              <span key="x" className="row" style={{ gap: 4, flexWrap: "wrap" }}>
                {mine ? <Btn kind="go" disabled={busy} onClick={() => setAct({ a, kind: a.stage === "SENATE" ? "minute" : "approve", text: "" })}>{a.stage === "SENATE" ? "Apply on the minute" : "Approve"}</Btn> : null}
                {mine ? <Btn kind="urgent" disabled={busy} onClick={() => setAct({ a, kind: "refuse", text: "" })}>Refuse</Btn> : null}
                {open && actingOffice && ENTRY_DESKS.includes(actingOffice) ? <Btn kind="ghost" disabled={busy} onClick={() => setAct({ a, kind: "withdraw", text: "" })}>Withdraw</Btn> : null}
              </span>,
            ];
          })} />
        )}
      </PBody>
      {r ? (
        <Modal title={`Raise an amendment — ${courseCode}`} sub="One student's published mark, corrected through the chain" onClose={() => setRaise(null)}
          foot={<><Btn kind="ghost" onClick={() => setRaise(null)}>Cancel</Btn><span className="grow" />
            <Btn kind="primary" disabled={busy || !r.studentId || r.reason.trim().length < 10 || !!wrong} onClick={async () => {
              const ok = await post(`/sheets/${sheetId}/amendments`, { studentId: r.studentId, outcome: r.outcome, ca: r.outcome === "GRADED" ? Number(r.ca) : null,
                exam: r.outcome === "GRADED" ? Number(r.exam) : null, reason: r.reason.trim() }, `${courseCode}: an amendment raised`);
              if (ok) setRaise(null);
            }}>{busy ? "Raising…" : "Raise it"}</Btn></>}>
          <Field id="am-st" label="Student" required><select id="am-st" className="ctl" value={r.studentId} onChange={(e) => setRaise({ ...r, studentId: e.target.value })}>
            <option value="">— Choose —</option>{marks.map((m) => <option key={m.studentId} value={m.studentId}>{`${m.number} — ${m.surname}, ${m.otherNames}`}</option>)}</select></Field>
          {chosen ? <p className="sub2">{`Published: ${chosen.outcome === "GRADED" || chosen.outcome == null ? `CA ${chosen.ca ?? "—"}, examination ${chosen.exam ?? "—"}` : chosen.outcome}`}</p> : null}
          <div className="grid grid--3">
            <Field id="am-o" label="Outcome"><select id="am-o" className="ctl" value={r.outcome} onChange={(e) => setRaise({ ...r, outcome: e.target.value })}>{OUTCOMES.map((o) => <option key={o}>{o}</option>)}</select></Field>
            {r.outcome === "GRADED" ? <>
              <Field id="am-ca" label={`CA (0–${caMax})`}><input id="am-ca" className="ctl tnum" inputMode="numeric" value={r.ca} onChange={(e) => setRaise({ ...r, ca: e.target.value })} /></Field>
              <Field id="am-ex" label={`Examination (0–${examMax})`}><input id="am-ex" className="ctl tnum" inputMode="numeric" value={r.exam} onChange={(e) => setRaise({ ...r, exam: e.target.value })} /></Field>
            </> : null}
          </div>
          <Field id="am-why" label="Why" required hint="In words Senate can read — the query it answers, what was found. A result query answered “corrected” for this student is linked on its own.">
            <textarea id="am-why" className="ctl" rows={3} maxLength={2000} value={r.reason} onChange={(e) => setRaise({ ...r, reason: e.target.value })} /></Field>
          {wrong ? <Note kind="bad" title="Marks outside the course's split">{`This course assesses ${caMax} and examines ${examMax}.`}</Note> : null}
        </Modal>
      ) : null}
      {act ? (
        <Modal title={act.kind === "minute" ? `Apply ${act.a.ref} on the Senate minute` : act.kind === "refuse" ? `Refuse ${act.a.ref}` : act.kind === "withdraw" ? `Withdraw ${act.a.ref}` : `Approve ${act.a.ref}`}
          sub={`${act.a.name}: ${markOf(act.a.was_outcome, act.a.was_ca, act.a.was_exam)} → ${markOf(act.a.outcome, act.a.ca, act.a.exam)}`} onClose={() => setAct(null)}
          foot={<><Btn kind="ghost" onClick={() => setAct(null)}>Cancel</Btn><span className="grow" />
            <Btn kind={act.kind === "refuse" || act.kind === "withdraw" ? "urgent" : "go"} disabled={busy || ((act.kind === "minute" || act.kind === "refuse" || act.kind === "withdraw") && act.text.trim().length < (act.kind === "minute" ? 3 : 5))}
              onClick={async () => {
                const ok = act.kind === "refuse" ? await post(`/amendments/${act.a.id}/refuse`, { reason: act.text.trim() }, `${act.a.ref} refused`)
                  : act.kind === "withdraw" ? await post(`/amendments/${act.a.id}/withdraw`, { reason: act.text.trim() }, `${act.a.ref} withdrawn`)
                  : act.kind === "minute" ? await post(`/amendments/${act.a.id}/advance`, { minute: act.text.trim() }, `${act.a.ref} applied on ${act.text.trim()}`)
                  : await post(`/amendments/${act.a.id}/advance`, { comment: act.text.trim() || null }, `${act.a.ref} approved`);
                if (ok) setAct(null);
              }}>{act.kind === "minute" ? "Apply" : act.kind === "refuse" ? "Refuse it" : act.kind === "withdraw" ? "Withdraw it" : "Approve"}</Btn></>}>
          <p className="sub2">{act.a.reason}</p>
          <Field id="am-act" label={act.kind === "minute" ? "Senate minute" : act.kind === "approve" ? "Comment (optional)" : "Why"} required={act.kind !== "approve"}>
            <input id="am-act" className="ctl" value={act.text} onChange={(e) => setAct({ ...act, text: e.target.value })} placeholder={act.kind === "minute" ? "SEN/2026/…" : ""} autoComplete="off" /></Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
