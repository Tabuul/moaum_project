"use client";

/**
 * The JUPEB examination year on the Examination page (V355): registering the candidates with the Board — each record ready to send
 * or what is missing, the export with every fact the Board asks for and the photographs, the Board's stages, and a record changed
 * since it was sent flagged with what changed — and the examination timetable, uploaded from the Board's or entered, published to
 * the students. The server decides every stage and refuses a record not ready.
 */
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { day, jcall, readSheet, when } from "@/lib/jupeb";

interface Dated { starts_on: string; ends_on: string | null; deadline_on: string | null; title: string; deadline_note?: string | null }
interface BoardRow {
  application_id: string; application_no: string; name: string; class_name: string | null; combination_code: string | null; exam_no: string | null; stage: string;
  board_ref: string | null; sent_at: string | null; updated_at: string | null; note: string | null; problems: string[]; ready: boolean; changed: boolean; changed_facts: string[] | null;
}
interface Board { session: string; registration: Dated | null; alignment: Dated | null; penalty: Dated | null; rows: BoardRow[] }
interface Facts { surname: string; firstName: string; middleName: string | null; sex: string | null; dateOfBirth: string | null; nin: string | null; phone: string | null; email: string;
  stateOfOrigin: string | null; lga: string | null; combination: string | null; subjects: { code: string; prefix: string; title: string }[] }

const STAGE: Record<string, [string, "ok" | "warn" | "bad" | "grey" | "info"]> = {
  NOT_SENT: ["Not sent", "grey"], SENT: ["Sent", "info"], CONFIRMED: ["Confirmed", "ok"], CORRECTION_NEEDED: ["Correction needed", "bad"], CORRECTED: ["Correction sent", "info"],
  WITHDRAWN: ["Withdrawn", "grey"],
};
const FACT: Record<string, string> = { surname: "surname", firstName: "first name", middleName: "middle name", sex: "sex", dateOfBirth: "date of birth", nin: "NIN", phone: "phone",
  email: "email", stateOfOrigin: "state of origin", lga: "LGA", combination: "combination", subjects: "subjects" };
const range = (e: Dated) => (e.ends_on && e.ends_on !== e.starts_on ? `${day(e.starts_on)} – ${day(e.ends_on)}` : day(e.starts_on));

export function BoardPanel({ session, canWrite }: { session: string; canWrite: boolean }) {
  const [d, setD] = useState<Board | null>(null);
  /* opens on what is to act on, or on everyone when there is nothing to act on */
  const [chosen, setShow] = useState("");
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [ask, setAsk] = useState<{ stage: string; note: string; ref: string } | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    if (session) void jcall<Board>(`/api/v1/jupeb/office/board?session=${encodeURIComponent(session)}`).then((r) => { if (live) { if (r.ok) setD(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [session]);
  const toAct = (r: BoardRow) => (r.stage === "NOT_SENT" && r.ready) || r.changed || r.stage === "CORRECTION_NEEDED";
  const show = chosen || ((d?.rows ?? []).some(toAct) ? "ACTION" : "ALL");
  const rows = useMemo(() => (d?.rows ?? []).filter((r) => show === "ALL" || (show === "ACTION" ? (r.stage === "NOT_SENT" && r.ready) || r.changed || r.stage === "CORRECTION_NEEDED"
    : show === "MISSING" ? r.stage === "NOT_SENT" && !r.ready : r.stage === show)), [d, show]);
  if (!d) return null;
  const count = (f: (r: BoardRow) => boolean) => d.rows.filter(f).length;
  async function exportWhich(which: "ready" | "changed" | "sent") {
    const r = await jcall<{ application_no: string; stage: string; changed: boolean; facts: Facts; photo: string }[]>(`/api/v1/jupeb/office/board/export?session=${encodeURIComponent(d!.session)}&which=${which}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    if (!r.data.length) { notify("Nothing to export."); return; }
    const blob = await brandedXlsx(`JUPEB candidates for registration with the Board — ${d!.session}`,
      ["Application Number", "Surname", "First Name", "Middle Name", "Sex", "Date of Birth", "NIN", "Phone", "Email", "State of Origin", "LGA", "Combination",
        "Subject 1 (Board code)", "Subject 1", "Subject 2 (Board code)", "Subject 2", "Subject 3 (Board code)", "Subject 3", "Photograph file", "Stage"],
      r.data.map((x) => { const f = x.facts; const s = (i: number) => f.subjects[i]; return [x.application_no, f.surname, f.firstName, f.middleName ?? "", f.sex === "F" ? "Female" : f.sex === "M" ? "Male" : "",
        f.dateOfBirth ?? "", f.nin ?? "", f.phone ?? "", f.email, f.stateOfOrigin ?? "", f.lga ?? "", f.combination ?? "",
        s(0)?.code ?? "", s(0)?.title ?? "", s(1)?.code ?? "", s(1)?.title ?? "", s(2)?.code ?? "", s(2)?.title ?? "", x.photo, STAGE[x.stage]?.[0] ?? x.stage]; }),
      { sheetName: "Candidates", serial: docSerial("JUPEBBOARD"), meta: [["Session", d!.session], ["Records", which === "ready" ? "Ready, not yet sent" : which === "changed" ? "Changed since sent, or a correction asked" : "Every record sent"]] });
    downloadBlob(blob, `jupeb-board-${which}-${d!.session.replace("/", "-")}.xlsx`);
  }
  async function mark() {
    if (!ask) return;
    setBusy(true);
    try {
      const r = await jcall<Board & { marked: number }>("/api/v1/jupeb/office/board/mark", "POST", { session: d!.session, applicationIds: [...picked], stage: ask.stage, note: ask.note.trim() || null,
        boardRef: ask.ref.trim() || null }, `JUPEB Board: ${STAGE[ask.stage]?.[0] ?? ask.stage} (${picked.size})`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setD(r.data); setPicked(new Set()); setAsk(null); notify(`${r.data.marked} record${r.data.marked === 1 ? "" : "s"} marked ${STAGE[ask.stage]?.[0].toLowerCase()}.`);
    } finally { setBusy(false); }
  }
  const toggle = (id: string) => setPicked((p) => { const n = new Set(p); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  const allShown = rows.length > 0 && rows.every((r) => picked.has(r.application_id));
  return (
    <Panel title="Registration with the Board" right={<span className="row" style={{ flexWrap: "wrap" }}>
      <Btn kind="ghost" onClick={() => void exportWhich("ready")}>Export ready (Excel)</Btn>
      <a className="btn btn--ghost" href={`/api/bff/api/v1/jupeb/office/board/photos.zip?session=${encodeURIComponent(d.session)}&which=ready`}>Photographs (ZIP)</a>
      <Btn kind="ghost" onClick={() => void exportWhich("changed")}>Export changed</Btn>
    </span>}>
      <PBody>
        {d.registration ? <Note kind="info" title={`The Board's registration of candidates: ${range(d.registration)}`}>{[d.registration.deadline_note,
          d.alignment ? `Deletions and third-party data alignment by ${day(d.alignment.deadline_on ?? d.alignment.ends_on ?? d.alignment.starts_on)}` : null,
          d.penalty ? `After that, alignment costs ${d.penalty.title.replace(/^.*penalty of\s*/i, "")} until ${day(d.penalty.deadline_on ?? d.penalty.ends_on ?? d.penalty.starts_on)}` : null].filter(Boolean).join(". ") + "."}</Note> : null}
        <KvGrid cls="grid--4" pairs={[["Ready, not sent", count((r) => r.stage === "NOT_SENT" && r.ready)], ["Not ready", count((r) => r.stage === "NOT_SENT" && !r.ready)],
          ["Sent or confirmed", count((r) => ["SENT", "CONFIRMED", "CORRECTED"].includes(r.stage))], ["Changed since sent", count((r) => r.changed)]]} />
        <div className="row mt-2" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
          <select className="ctl" style={{ width: 260 }} aria-label="Show" value={show} onChange={(e) => { setShow(e.target.value); setPicked(new Set()); }}>
            <option value="ACTION">To act on (ready, changed, correction asked)</option><option value="MISSING">Not ready (something missing)</option>
            {Object.entries(STAGE).filter(([k]) => k !== "NOT_SENT").map(([k, [w]]) => <option key={k} value={k}>{w}</option>)}<option value="ALL">Everyone</option></select>
          {canWrite && picked.size ? <>
            <b>{picked.size} chosen</b>
            <Btn kind="secondary" onClick={() => setAsk({ stage: "SENT", note: "", ref: "" })}>Mark sent</Btn>
            <Btn kind="secondary" onClick={() => setAsk({ stage: "CONFIRMED", note: "", ref: "" })}>Confirmed by the Board</Btn>
            <Btn kind="secondary" onClick={() => setAsk({ stage: "CORRECTION_NEEDED", note: "", ref: "" })}>Correction asked</Btn>
            <Btn kind="secondary" onClick={() => setAsk({ stage: "CORRECTED", note: "", ref: "" })}>Correction sent</Btn>
            <Btn kind="ghost" onClick={() => setAsk({ stage: "WITHDRAWN", note: "", ref: "" })}>Withdrawn</Btn></> : null}
        </div>
        <DTable pageSize={25} cols={[...(canWrite ? ["|mid"] : []), "Application No", "Name", "Combination", "Stage", "What stands"]} texts={rows.map((r) => `${r.application_no} ${r.name}`)}
          rows={rows.map((r) => [...(canWrite ? [<input key="p" type="checkbox" aria-label={`Choose ${r.application_no}`} checked={picked.has(r.application_id)} onChange={() => toggle(r.application_id)} />] : []),
            <Link key="a" href={`/jupeb/applications/${r.application_id}`}>{r.application_no}</Link>, r.name, r.combination_code ?? "—",
            <span key="s"><Pil kind={STAGE[r.stage]?.[1] ?? "grey"}>{STAGE[r.stage]?.[0] ?? r.stage}</Pil>{r.sent_at ? <span className="sub2">{` ${when(r.updated_at ?? r.sent_at)}`}</span> : null}</span>,
            r.changed ? <span key="w" style={{ color: "var(--bad)" }}>{`Changed since sent: ${(r.changed_facts ?? []).map((f) => FACT[f] ?? f).join(", ")} — send the correction`}</span>
              : r.stage === "NOT_SENT" ? (r.ready ? "Ready to send" : r.problems.join(" · ")) : r.note ?? "—"])} />
        {canWrite && rows.length ? <label className="row mt-2" style={{ gap: "var(--s-1)" }}><input type="checkbox" checked={allShown} onChange={() => setPicked(allShown ? new Set() : new Set(rows.map((r) => r.application_id)))} /> Choose all {rows.length} shown</label> : null}
        <p className="sub2 mt-2">The export carries every fact the Board asks for and the photographs are named by application number; upload them on the Board&rsquo;s registration portal, then mark the records sent. What was sent is kept: a record changed after it (a name, a date of birth, a subject option) is flagged here until the correction is sent.</p>
      </PBody>
      {ask ? (
        <Modal title={`${STAGE[ask.stage]?.[0]} — ${picked.size} record${picked.size === 1 ? "" : "s"}`} onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || ((ask.stage === "CORRECTION_NEEDED" || ask.stage === "WITHDRAWN") && ask.note.trim().length < 3)} onClick={() => void mark()}>{busy ? "Saving…" : "Record it"}</Btn></>}>
          <p>{ask.stage === "SENT" || ask.stage === "CORRECTED" ? "The record as it stands now is kept as what was sent; only a record ready to send is accepted." : ask.stage === "CORRECTION_NEEDED" ? "Say what the Board asks to be corrected." : ask.stage === "WITHDRAWN" ? "Say why the candidate is withdrawn from the Board's registration." : "The Board has confirmed the registration."}</p>
          <Field id="bd-note" label={ask.stage === "CORRECTION_NEEDED" || ask.stage === "WITHDRAWN" ? "What and why" : "Note"} required={ask.stage === "CORRECTION_NEEDED" || ask.stage === "WITHDRAWN"}>
            <input id="bd-note" className="ctl" maxLength={500} value={ask.note} onChange={(e) => setAsk({ ...ask, note: e.target.value })} /></Field>
          <Field id="bd-ref" label="The Board's reference" hint="When the Board's portal gives one (not the examination number)"><input id="bd-ref" className="ctl" maxLength={60} value={ask.ref} onChange={(e) => setAsk({ ...ask, ref: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </Panel>
  );
}

interface Paper { id: string; subject_id: string; code: string; subject: string; board_subject_id: string | null; option_title: string | null; prefix: string | null; title: string; kind: string;
  sits_on: string; starts_at: string; ends_at: string; centre: string | null; note: string | null; candidates: number }
interface Exams { session: string; published: string | null; release: Dated | null; examinations: Dated | null; papers: Paper[]; subjects: { id: string; code: string; title: string; board_subject_id: string | null }[] }
interface PaperForm { id: string | null; subject: string; title: string; kind: string; sitsOn: string; startsAt: string; endsAt: string; centre: string; note: string }

export function ExamTimetablePanel({ session, canWrite }: { session: string; canWrite: boolean }) {
  const [d, setD] = useState<Exams | null>(null);
  const [form, setForm] = useState<PaperForm | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    if (session) void jcall<Exams>(`/api/v1/jupeb/office/exams?session=${encodeURIComponent(session)}`).then((r) => { if (live) { if (r.ok) setD(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [session]);
  if (!d) return null;
  const subjectKey = (p: { subject_id: string; board_subject_id: string | null }) => `${p.subject_id}|${p.board_subject_id ?? ""}`;
  async function upload(file: File) {
    setBusy(true);
    try {
      const sheet = await readSheet(file, { "subject": "subject", "subject code": "subject", "course": "subject", "paper": "paper", "paper title": "paper", "title": "paper",
        "kind": "kind", "mode": "kind", "type": "kind", "date": "date", "day": "date", "start": "start", "starts": "start", "start time": "start", "from": "start",
        "end": "end", "ends": "end", "end time": "end", "to": "end", "centre": "centre", "center": "centre", "venue": "centre", "note": "note", "remarks": "note" });
      const replace = d!.papers.length > 0 && window.confirm("Replace the papers already on the timetable? (Cancel adds these to them.)");
      const r = await jcall<Exams & { result: { added: number; refused: { row: number; reason: string }[] } }>("/api/v1/jupeb/office/exams/upload", "POST", { session: d!.session, rows: sheet, replace },
        `JUPEB examination timetable uploaded (${d!.session})`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setD(r.data);
      notify(`${r.data.result.added} paper${r.data.result.added === 1 ? "" : "s"} added${r.data.result.refused.length ? `; ${r.data.result.refused.length} row(s) not read: ${r.data.result.refused.slice(0, 3).map((x) => `row ${x.row}: ${x.reason}`).join(" ")}` : ""}.`);
    } finally { setBusy(false); }
  }
  async function save() {
    if (!form) return;
    const [subjectId, boardSubjectId] = form.subject.split("|");
    setBusy(true);
    try {
      const body = { session: d!.session, subjectId, boardSubjectId: boardSubjectId || null, title: form.title.trim(), kind: form.kind, sitsOn: form.sitsOn, startsAt: form.startsAt, endsAt: form.endsAt,
        centre: form.centre.trim() || null, note: form.note.trim() || null };
      const r = form.id ? await jcall<Exams>(`/api/v1/jupeb/office/exams/${form.id}`, "PUT", body, `JUPEB paper ${form.title}`) : await jcall<Exams>("/api/v1/jupeb/office/exams", "POST", body, `JUPEB paper ${form.title}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setD(r.data); setForm(null);
    } finally { setBusy(false); }
  }
  async function remove(p: Paper) {
    if (!window.confirm(`Remove ${p.title} on ${day(p.sits_on)}?`)) return;
    const r = await jcall<Exams>(`/api/v1/jupeb/office/exams/${p.id}/remove`, "POST", {}, `JUPEB paper removed: ${p.title}`);
    if (r.ok) setD(r.data); else notifyProblem(r.problem);
  }
  async function publish(on: boolean) {
    const r = await jcall<Exams>("/api/v1/jupeb/office/exams/publish", "POST", { session: d!.session, published: on }, on ? "JUPEB examination timetable published" : "JUPEB examination timetable held back");
    if (r.ok) { setD(r.data); notify(on ? "Published: the students see their papers, and those cleared print their admit cards." : "Held back from the students."); } else notifyProblem(r.problem);
  }
  async function excel() {
    downloadBlob(await brandedXlsx(`JUPEB examination timetable — ${d!.session}`, ["Date", "Start", "End", "Subject", "Paper", "Kind", "Centre", "Candidates", "Note"],
      d!.papers.map((p) => [p.sits_on, p.starts_at, p.ends_at, p.option_title ?? p.subject, p.title, p.kind, p.centre ?? "", p.candidates, p.note ?? ""]),
      { sheetName: "Timetable", serial: docSerial("JUPEBEXAM") }), `jupeb-examination-timetable-${d!.session.replace("/", "-")}.xlsx`);
  }
  return (
    <Panel title="Examination timetable" right={<span className="row" style={{ flexWrap: "wrap" }}>
      {d.published ? <Pil kind="ok">Published {day(d.published)}</Pil> : <Pil kind="grey">Not published</Pil>}
      {d.papers.length ? <Btn kind="ghost" onClick={() => void excel()}>Excel</Btn> : null}
      {canWrite ? <label className="btn btn--ghost" style={{ cursor: "pointer" }}>{busy ? "Reading…" : "Upload the Board's timetable"}<input type="file" accept=".xlsx,.xls,.csv" hidden onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ""; if (f) void upload(f); }} /></label> : null}
      {canWrite ? <Btn kind="secondary" onClick={() => setForm({ id: null, subject: "", title: "", kind: "CBT", sitsOn: d.examinations?.starts_on ?? "", startsAt: "09:00", endsAt: "11:00", centre: "", note: "" })}>Add a paper</Btn> : null}
      {canWrite ? (d.published ? <Btn kind="ghost" onClick={() => void publish(false)}>Hold back</Btn> : <Btn kind="primary" disabled={!d.papers.length} onClick={() => void publish(true)}>Publish to the students</Btn>) : null}
    </span>}>
      <PBody>
        {d.release ? <p className="sub2">{`The Board releases its examination timetable on ${day(d.release.starts_on)}${d.examinations ? `; the examinations run ${range(d.examinations)}` : ""}. Upload it as an Excel sheet (Subject, Paper, Kind, Date, Start, End, Centre, Note — the subject by its code, the Board's code such as J133, or a course prefix such as ECN, CRS or ISS for an option).`}</p> : null}
        {!d.papers.length ? <Note kind="info" title="No papers yet">The timetable appears here once the Board&rsquo;s is uploaded or its papers entered.</Note> : (
          <DTable pageSize={0} cols={["Date", "Time", "Subject", "Paper", "Kind", "Centre", "Candidates|num", ...(canWrite ? ["|mid"] : [])]}
            rows={d.papers.map((p) => [day(p.sits_on), `${p.starts_at}–${p.ends_at}`, p.option_title ?? p.subject, p.title, p.kind, p.centre ?? "—", p.candidates,
              ...(canWrite ? [<span key="a" className="row"><Btn kind="ghost" onClick={() => setForm({ id: p.id, subject: subjectKey(p), title: p.title, kind: p.kind, sitsOn: p.sits_on, startsAt: p.starts_at, endsAt: p.ends_at, centre: p.centre ?? "", note: p.note ?? "" })}>Edit</Btn>
                <Btn kind="ghost" onClick={() => void remove(p)}>Remove</Btn></span>] : [])])} />
        )}
        <p className="sub2 mt-2">Published, each student sees their own papers (of an either/or subject, the option they sit) and a student cleared to sit prints an admit card with a verification code.</p>
      </PBody>
      {form ? (
        <Modal wide title={form.id ? "Edit the paper" : "Add a paper"} onClose={() => setForm(null)}
          foot={<><Btn kind="ghost" onClick={() => setForm(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !form.subject || form.title.trim().length < 2 || !form.sitsOn || form.endsAt <= form.startsAt} onClick={() => void save()}>{busy ? "Saving…" : "Save"}</Btn></>}>
          <div className="grid grid--2">
            <Field id="ex-sub" label="Subject" required><select id="ex-sub" className="ctl" value={form.subject} onChange={(e) => setForm({ ...form, subject: e.target.value })}>
              <option value="">— Choose —</option>{d.subjects.map((s) => <option key={subjectKey({ subject_id: s.id, board_subject_id: s.board_subject_id })} value={subjectKey({ subject_id: s.id, board_subject_id: s.board_subject_id })}>{`${s.title} (${s.code})`}</option>)}</select></Field>
            <Field id="ex-title" label="Paper" required><input id="ex-title" className="ctl" maxLength={160} placeholder="Biology Paper I" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></Field>
            <Field id="ex-kind" label="Kind"><select id="ex-kind" className="ctl" value={form.kind} onChange={(e) => setForm({ ...form, kind: e.target.value })}>
              <option value="CBT">CBT</option><option value="PAPER">Written paper</option><option value="PRACTICAL">Practical</option><option value="ORAL">Oral</option></select></Field>
            <Field id="ex-day" label="Date" required><input id="ex-day" type="date" className="ctl" value={form.sitsOn} onChange={(e) => setForm({ ...form, sitsOn: e.target.value })} /></Field>
            <Field id="ex-st" label="Starts" required><input id="ex-st" type="time" className="ctl" value={form.startsAt} onChange={(e) => setForm({ ...form, startsAt: e.target.value })} /></Field>
            <Field id="ex-en" label="Ends" required error={form.endsAt <= form.startsAt ? "After it starts" : undefined}><input id="ex-en" type="time" className="ctl" value={form.endsAt} onChange={(e) => setForm({ ...form, endsAt: e.target.value })} /></Field>
            <Field id="ex-cen" label="Centre"><input id="ex-cen" className="ctl" maxLength={160} value={form.centre} onChange={(e) => setForm({ ...form, centre: e.target.value })} /></Field>
            <Field id="ex-note" label="Note"><input id="ex-note" className="ctl" maxLength={300} value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
    </Panel>
  );
}
