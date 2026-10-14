"use client";

/**
 * Amendments of a published result (V358), on the sheet's chain: each correction of one student's published mark with its
 * reason, where it stands in the chain and who took each step. The desk of entry raises one (the course's lecturer, or the
 * Programme Examinations Officer on the lecturer's behalf); each desk approves or refuses it at its own stage; the Registrar
 * applies it on the Senate minute — a new version of the mark, the original kept. The person who raised it may withdraw it.
 * The server decides who may do each; the buttons only follow it. V422: a candidate on the published sheet's roll with no
 * mark on it (registered after publication, or migrated without the result) gets a late result the same way — chosen from
 * the roll's candidates with no mark, applied on the Senate minute as the first mark. V465: when a programme's students on the
 * class carry units its structure no longer says, and the class's results are worked on (so a change of units does not reach
 * it), the desk of entry raises a units correction for that programme the same way — applied on the minute to their
 * registrations.
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
  id: string; ref: string; kind?: "AMEND" | "LATE" | "UNITS"; student_id: string | null; number: string | null; name: string | null; query_ref: string | null;
  was_ca: number | null; was_exam: number | null; was_outcome: string | null; ca: number | null; exam: number | null; outcome: string;
  reason: string; stage: string; raised_by_name: string | null; raised_office: string | null; raised_at: string;
  senate_minute: string | null; applied_at: string | null; closed_reason: string | null;
  decisions: { kind: string; from: string | null; to: string; office: string | null; comment: string | null; at: string; by: string | null }[];
  programme_code?: string | null; programme_name?: string | null; units?: number | null; was_units?: number | null; applied_count?: number | null;
}

/** V465: the class by programme — students on it, the units they carry, what the programme's structure says now */
interface ClassUnit { programme: string; name: string | null; students: number; carried: number[]; takes: number[]; examined: boolean; openRef: string | null }
const unitsOf = (n: number | null | undefined) => (n == null ? "—" : `${n} unit${n === 1 ? "" : "s"}`);

/** V422: a candidate on the roll with no mark on the sheet — a late result is for them */
interface LateCandidate { student_id: string; number: string; surname: string; other_names: string; programme_code: string }

const markOf = (outcome: string | null, ca: number | null, exam: number | null) =>
  outcome == null ? "no mark" : outcome === "GRADED" ? `${ca ?? "—"} + ${exam ?? "—"} = ${(ca ?? 0) + (exam ?? 0)}` : outcome.toLowerCase();
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
  const [late, setLate] = useState<LateCandidate[]>([]);
  const [classUnits, setClassUnits] = useState<ClassUnit[]>([]);
  const [unitsRaise, setUnitsRaise] = useState<{ u: ClassUnit; units: string; reason: string } | null>(null);
  useEffect(() => {
    let live = true;
    void fetch(`/api/bff/api/v1/results/sheets/${sheetId}/amendments`, { cache: "no-store" }).then(async (r) => { if (live && r.ok) setRows(await r.json()); });
    return () => { live = false; };
  }, [sheetId]);
  // V422: the roll's candidates with no mark on the published sheet, read again after each change
  useEffect(() => {
    let live = true;
    if (published) void fetch(`/api/bff/api/v1/results/sheets/${sheetId}/late-candidates`, { cache: "no-store" }).then(async (r) => { if (live && r.ok) setLate(await r.json()); });
    return () => { live = false; };
  }, [sheetId, published, rows]);
  // V465: the class's programmes and their units, read again after each change
  useEffect(() => {
    let live = true;
    void fetch(`/api/bff/api/v1/results/sheets/${sheetId}/units`, { cache: "no-store" }).then(async (r) => { if (live && r.ok) setClassUnits(await r.json()); });
    return () => { live = false; };
  }, [sheetId, rows]);

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
  const entryDesk = !!actingOffice && ENTRY_DESKS.includes(actingOffice);
  // V465: programmes whose students on an examined class carry units their structure no longer says
  const unitsOff = classUnits.filter((u) => u.examined && (u.carried.length !== 1 || u.takes.length !== 1 || u.carried[0] !== u.takes[0]));
  if (!published && !(rows && rows.length) && !unitsOff.length) return null;
  const examMax = 100 - caMax;
  const r = raise;
  const wrong = r && r.outcome === "GRADED" && (r.ca === "" || r.exam === "" || Number(r.ca) > caMax || Number(r.exam) > examMax || Number(r.ca) < 0 || Number(r.exam) < 0);
  const chosen = r ? marks.find((m) => m.studentId === r.studentId) : undefined;
  const chosenLate = r ? late.find((c) => c.student_id === r.studentId) : undefined;

  return (
    <Panel title={published ? "Amendments of the published result" : "Amendments of this class"} right={mayRaise ? <Btn kind="primary" onClick={() => setRaise({ studentId: "", outcome: "GRADED", ca: "", exam: "", reason: "" })}>Raise an amendment or a late result</Btn> : null}>
      <PBody>
        <p className="sub2">A published mark changes only by an amendment, approved by each desk and applied on the Senate minute; the original is kept. A candidate on the roll with no mark on the sheet gets a late result the same way.</p>
        {published && late.length ? (
          <Note kind="bad" title={`${late.length} candidate${late.length === 1 ? "" : "s"} on the roll with no mark on this sheet`}>
            {`${late.slice(0, 6).map((c) => c.number).join(", ")}${late.length > 6 ? ` and ${late.length - 6} more` : ""}: no result, never an F. ${mayRaise ? "Raise a late result for each, with the mark and the reason." : "The course's lecturer, or the Programme Examinations Officer, raises a late result for each."}`}
          </Note>
        ) : null}
        {unitsOff.length ? (
          <Note kind="info" title="Units on this class differ from the programme's structure">
            <span className="sub2">The class&rsquo;s results are worked on, so a change of units does not reach it; a units correction for the programme goes through the chain, as a mark does.</span>
            <DTable noPrint pageSize={0} cols={["Programme", "Students|mid", "They carry|mid", "Its structure says|mid", "|mid"]} rows={unitsOff.map((u) => [
              <span key="p"><b className="tnum">{u.programme}</b>{u.name ? <span className="sub2" style={{ display: "block" }}>{u.name}</span> : null}</span>,
              <span key="n" className="tnum">{u.students}</span>, <span key="c" className="tnum">{u.carried.join(", ")}</span>, <b key="t" className="tnum">{u.takes.join(", ")}</b>,
              u.openRef ? <span key="x" className="sub2">{`${u.openRef} open`}</span>
                : entryDesk ? <Btn key="x" kind="primary" disabled={busy} onClick={() => setUnitsRaise({ u, units: u.takes.length === 1 ? String(u.takes[0]) : "", reason: "" })}>Raise a units correction</Btn>
                : <span key="x" className="sub2">The desk of entry raises it</span>,
            ])} />
          </Note>
        ) : null}
        {!rows ? <p className="sub2">Loading…</p> : !rows.length ? <p className="sub2">No amendment of this sheet.</p> : (
          <DTable noPrint pageSize={0} cols={["Amendment", "Student", "Published", "Corrected to", "Reason", "Stands", "|mid"]} rows={rows.map((a) => {
            const open = !["APPLIED", "REFUSED", "WITHDRAWN"].includes(a.stage);
            const mine = open && !!actingOffice && (STAGE_DESKS[a.stage] ?? []).includes(actingOffice);
            const last = a.decisions[a.decisions.length - 1];
            return [
              <span key="r"><b className="tnum">{a.ref}</b>{a.kind === "LATE" ? <Pil kind="info">Late result</Pil> : a.kind === "UNITS" ? <Pil kind="info">Units</Pil> : null}<span className="sub2" style={{ display: "block" }}>{`${a.raised_by_name ?? "—"} (${roleLabel(a.raised_office)}), ${day(a.raised_at)}`}</span>
                {a.query_ref ? <span className="sub2" style={{ display: "block" }}>{`From query ${a.query_ref}`}</span> : null}</span>,
              a.kind === "UNITS"
                ? <span key="s">{`Students of ${a.programme_code}`}<span className="sub2" style={{ display: "block" }}>{a.programme_name ?? ""}</span></span>
                : <span key="s">{a.name}<span className="sub2 tnum" style={{ display: "block" }}>{a.number}</span></span>,
              <span key="w" className="tnum">{a.kind === "UNITS" ? unitsOf(a.was_units) : markOf(a.was_outcome, a.was_ca, a.was_exam)}</span>,
              <b key="n" className="tnum">{a.kind === "UNITS" ? <>{unitsOf(a.units)}{a.applied_count != null ? <span className="sub2" style={{ display: "block", fontWeight: 400 }}>{`${a.applied_count} registration${a.applied_count === 1 ? "" : "s"} changed`}</span> : null}</> : markOf(a.outcome, a.ca, a.exam)}</b>,
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
        <Modal title={`${chosenLate ? "Raise a late result" : "Raise an amendment"} — ${courseCode}`} sub={chosenLate ? "A candidate on the roll with no mark on the published sheet: the first mark, through the chain" : "One student's published mark, corrected through the chain"} onClose={() => setRaise(null)}
          foot={<><Btn kind="ghost" onClick={() => setRaise(null)}>Cancel</Btn><span className="grow" />
            <Btn kind="primary" disabled={busy || !r.studentId || r.reason.trim().length < 10 || !!wrong} onClick={async () => {
              const ok = await post(`/sheets/${sheetId}/amendments`, { studentId: r.studentId, outcome: r.outcome, ca: r.outcome === "GRADED" ? Number(r.ca) : null,
                exam: r.outcome === "GRADED" ? Number(r.exam) : null, reason: r.reason.trim() }, `${courseCode}: ${chosenLate ? "a late result" : "an amendment"} raised`);
              if (ok) setRaise(null);
            }}>{busy ? "Raising…" : "Raise it"}</Btn></>}>
          <Field id="am-st" label="Student" required><select id="am-st" className="ctl" value={r.studentId} onChange={(e) => setRaise({ ...r, studentId: e.target.value })}>
            <option value="">— Choose —</option>
            <optgroup label="On the published sheet: an amendment">{marks.map((m) => <option key={m.studentId} value={m.studentId}>{`${m.number} — ${m.surname}, ${m.otherNames}`}</option>)}</optgroup>
            {late.length ? <optgroup label="On the roll, no mark: a late result">{late.map((c) => <option key={c.student_id} value={c.student_id}>{`${c.number} — ${c.surname}, ${c.other_names}`}</option>)}</optgroup> : null}</select></Field>
          {chosenLate ? <p className="sub2">No mark on the published sheet. A late result is applied on the Senate minute as the candidate&rsquo;s first mark.</p> : null}
          {chosen ? <p className="sub2">{`Published: ${chosen.outcome === "GRADED" || chosen.outcome == null ? `CA ${chosen.ca ?? "—"}, examination ${chosen.exam ?? "—"}` : chosen.outcome}`}</p> : null}
          <div className="grid grid--3">
            <Field id="am-o" label="Outcome"><select id="am-o" className="ctl" value={r.outcome} onChange={(e) => setRaise({ ...r, outcome: e.target.value })}>{OUTCOMES.map((o) => <option key={o}>{o}</option>)}</select></Field>
            {r.outcome === "GRADED" ? <>
              <Field id="am-ca" label={`CA (0–${caMax})`}><input id="am-ca" className="ctl tnum" inputMode="numeric" value={r.ca} onChange={(e) => setRaise({ ...r, ca: e.target.value })} /></Field>
              <Field id="am-ex" label={`Examination (0–${examMax})`}><input id="am-ex" className="ctl tnum" inputMode="numeric" value={r.exam} onChange={(e) => setRaise({ ...r, exam: e.target.value })} /></Field>
            </> : null}
          </div>
          <Field id="am-why" label="Why" required hint={chosenLate ? "In words Senate can read: why the candidate was not on the sheet, and where the mark comes from" : "In words Senate can read: the query and what was found"}>
            <textarea id="am-why" className="ctl" rows={3} maxLength={2000} value={r.reason} onChange={(e) => setRaise({ ...r, reason: e.target.value })} /></Field>
          {wrong ? <Note kind="bad" title="Marks outside the course's split">{`This course assesses ${caMax} and examines ${examMax}.`}</Note> : null}
        </Modal>
      ) : null}
      {unitsRaise ? (() => {
        const n = /^\d{1,2}$/.test(unitsRaise.units.trim()) && Number(unitsRaise.units) <= 12 ? Number(unitsRaise.units) : null;
        return (
          <Modal title={`Raise a units correction — ${courseCode}`} sub={`Students of ${unitsRaise.u.programme} on this class: ${unitsRaise.u.students}, carrying ${unitsRaise.u.carried.join(", ")}`} onClose={() => setUnitsRaise(null)}
            foot={<><Btn kind="ghost" onClick={() => setUnitsRaise(null)}>Cancel</Btn><span className="grow" />
              <Btn kind="primary" disabled={busy || n == null || unitsRaise.reason.trim().length < 10} onClick={async () => {
                const ok = await post(`/sheets/${sheetId}/units-amendments`, { programme: unitsRaise.u.programme, units: n, reason: unitsRaise.reason.trim() },
                  `${courseCode}: a units correction raised for ${unitsRaise.u.programme}`);
                if (ok) setUnitsRaise(null);
              }}>{busy ? "Raising…" : "Raise it"}</Btn></>}>
            <p className="sub2">{`${unitsRaise.u.programme}'s structure says ${unitsRaise.u.takes.join(", ")}. Applied on the Senate minute, the programme's students on this class carry the corrected units, their grade point average reads them, and each is told by e-mail.`}</p>
            <Field id="ua-units" label="Corrected units" required hint="0 to 12"><input id="ua-units" className="ctl tnum" inputMode="numeric" style={{ width: 90 }} value={unitsRaise.units} onChange={(e) => setUnitsRaise({ ...unitsRaise, units: e.target.value })} /></Field>
            <Field id="ua-why" label="Why" required hint="In words Senate can read: what the programme takes the course at, and why this class carried another number">
              <textarea id="ua-why" className="ctl" rows={3} maxLength={2000} value={unitsRaise.reason} onChange={(e) => setUnitsRaise({ ...unitsRaise, reason: e.target.value })} /></Field>
          </Modal>
        );
      })() : null}
      {act ? (
        <Modal title={act.kind === "minute" ? `Apply ${act.a.ref} on the Senate minute` : act.kind === "refuse" ? `Refuse ${act.a.ref}` : act.kind === "withdraw" ? `Withdraw ${act.a.ref}` : `Approve ${act.a.ref}`}
          sub={act.a.kind === "UNITS" ? `Students of ${act.a.programme_code} on this class: ${unitsOf(act.a.was_units)} → ${unitsOf(act.a.units)}`
            : `${act.a.name}: ${markOf(act.a.was_outcome, act.a.was_ca, act.a.was_exam)} → ${markOf(act.a.outcome, act.a.ca, act.a.exam)}`} onClose={() => setAct(null)}
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
